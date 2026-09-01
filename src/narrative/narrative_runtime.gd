extends RefCounted
class_name NarrativeRuntime

const GameCommand = preload("res://src/core/commands/game_command.gd")
const NarrativeConditionResolver = preload("res://src/narrative/narrative_condition_resolver.gd")

const REPLAY_ONCE := "once"
const REPLAY_REPEAT := "repeat"
const RESULT_SET_RUN_FLAG := "set_run_flag"
const RESULT_GRANT_ITEM := "grant_item"
const RESULT_APPLY_CHOICE := "apply_choice"
const ALLOWED_RESULT_TYPES := [RESULT_SET_RUN_FLAG, RESULT_GRANT_ITEM, RESULT_APPLY_CHOICE]

var event_definitions: Dictionary = {}
var data_version := ""
var condition_resolver := NarrativeConditionResolver.new()

func from_catalog(catalog) -> Dictionary:
	if not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Catalog cannot provide narrative event definitions.")
	var items_available := _catalog_has_dataset(catalog, "items")
	var choices_available := _catalog_has_dataset(catalog, "choices")
	var item_ids: Dictionary = {}
	for item in catalog.get_definitions("items"):
		if typeof(item) == TYPE_DICTIONARY:
			item_ids[String(item.get("id", ""))] = true
	var choice_ids: Dictionary = {}
	for choice in catalog.get_definitions("choices"):
		if typeof(choice) == TYPE_DICTIONARY:
			choice_ids[String(choice.get("id", ""))] = true
	var definitions: Dictionary = {}
	for row in catalog.get_definitions("events"):
		var result := _event_definition_from_row(row, item_ids, items_available, choice_ids, choices_available)
		if not result.ok:
			return result
		if definitions.has(result.definition.id):
			return _fail("duplicate_event_id", "Narrative event id '%s' is duplicated." % result.definition.id)
		definitions[result.definition.id] = result.definition
	event_definitions = definitions
	var catalog_data_version = catalog.get("data_version") if catalog.has_method("get") else ""
	data_version = String(catalog_data_version)
	return {"ok": true, "runtime": self}

func _catalog_has_dataset(catalog, dataset: String) -> bool:
	if catalog.has_method("get"):
		var catalog_definitions = catalog.get("definitions")
		if typeof(catalog_definitions) == TYPE_DICTIONARY:
			return catalog_definitions.has(dataset)
	return not catalog.get_definitions(dataset).is_empty()

func can_start_event(event_id: String, run_state) -> Dictionary:
	if not event_definitions.has(event_id):
		return _fail("missing_event", "Narrative event '%s' is not defined." % event_id)
	var event: Dictionary = event_definitions[event_id]
	if String(event.replay_policy) == REPLAY_ONCE and _event_count(run_state, event_id) > 0:
		return _fail("event_already_completed", "Narrative event '%s' cannot repeat." % event_id)
	return {"ok": true}

func read_model_for_event(event_id: String, run_state, meta_state = null) -> Dictionary:
	var start_result := can_start_event(event_id, run_state)
	if not start_result.ok:
		return start_result
	return read_model_for_node(event_id, String(event_definitions[event_id].start_node_id), run_state, meta_state)

func read_model_for_node(event_id: String, node_id: String, run_state, meta_state = null) -> Dictionary:
	var node_result := _node_for_event(event_id, node_id)
	if not node_result.ok:
		return node_result
	var event: Dictionary = event_definitions[event_id]
	var node: Dictionary = node_result.node
	var run_query := _run_query(run_state)
	var meta_query := _meta_query(meta_state)
	var visible_options: Array = []
	for option in node.options:
		var visibility := _option_is_visible(option, run_query, meta_query)
		if not visibility.ok:
			return visibility
		if visibility.passed:
			visible_options.append({
				"id": option.id,
				"display_text": option.display_text,
				"next_node_id": option.next_node_id,
				"completes_event": bool(option.completes_event)
			})
	return {
		"ok": true,
		"read_model": {
			"event_id": event.id,
			"event_name": event.name,
			"node_id": node.id,
			"speaker_id": node.speaker_id,
			"text": node.text,
			"options": visible_options,
			"replay_policy": event.replay_policy
		}
	}

func select_option(event_id: String, node_id: String, option_id: String, run_state, meta_state = null, choice_runtime = null, choice_context := {}) -> Dictionary:
	var start_result := can_start_event(event_id, run_state)
	if not start_result.ok:
		return start_result
	var node_result := _node_for_event(event_id, node_id)
	if not node_result.ok:
		return node_result
	var run_query := _run_query(run_state)
	var meta_query := _meta_query(meta_state)
	for option in node_result.node.options:
		if String(option.id) != option_id:
			continue
		var visibility := _option_is_visible(option, run_query, meta_query)
		if not visibility.ok:
			return visibility
		if not visibility.passed:
			return _fail("option_condition_failed", "Narrative option '%s' is not available." % option_id)
		var preflight := _preflight_choice_results(option, run_state, choice_runtime, choice_context)
		if not preflight.ok:
			return preflight
		var commands := _commands_for_results(event_id, node_id, option)
		var complete := bool(option.completes_event)
		if complete:
			_record_event_completion(run_state, event_id)
		var result := {
			"ok": true,
			"commands": commands,
			"next_node_id": option.next_node_id,
			"complete": complete
		}
		if not complete and not String(option.next_node_id).is_empty():
			var next_model := read_model_for_node(event_id, String(option.next_node_id), run_state, meta_state)
			if not next_model.ok:
				return next_model
			result["read_model"] = next_model.read_model
		return result
	return _fail("missing_option", "Narrative option '%s' is not defined on node '%s'." % [option_id, node_id])

func _preflight_choice_results(option: Dictionary, run_state, choice_runtime, choice_context: Dictionary) -> Dictionary:
	for result in option.results:
		if String(result.get("type", "")) != RESULT_APPLY_CHOICE:
			continue
		if choice_runtime == null or not choice_runtime.has_method("can_apply"):
			return _fail("missing_choice_runtime", "Narrative option '%s' requires a choice runtime before completion." % option.id)
		var availability: Dictionary = choice_runtime.can_apply(String(result.get("id", "")), run_state, choice_context)
		if not availability.ok:
			return availability
	return {"ok": true}

func _event_definition_from_row(row: Dictionary, item_ids: Dictionary, items_available: bool, choice_ids: Dictionary, choices_available: bool) -> Dictionary:
	var replay_policy := String(row.get("replay_policy", ""))
	if not [REPLAY_ONCE, REPLAY_REPEAT].has(replay_policy):
		return _fail("invalid_replay_policy", "Narrative event '%s' has invalid replay_policy '%s'." % [row.get("id", ""), replay_policy])
	var nodes_result := _nodes_from_row(row, item_ids, items_available, choice_ids, choices_available)
	if not nodes_result.ok:
		return nodes_result
	var start_node_id := String(row.get("start_node_id", ""))
	if not nodes_result.nodes.has(start_node_id):
		return _fail("missing_start_node", "Narrative event '%s' references missing start node '%s'." % [row.get("id", ""), start_node_id])
	var completion_result := _validate_reachable_completion(String(row.id), start_node_id, nodes_result.nodes)
	if not completion_result.ok:
		return completion_result
	return {"ok": true, "definition": {
		"id": String(row.id),
		"name": String(row.name),
		"status": String(row.status),
		"replay_policy": replay_policy,
		"start_node_id": start_node_id,
		"nodes": nodes_result.nodes
	}}

func _nodes_from_row(row: Dictionary, item_ids: Dictionary, items_available: bool, choice_ids: Dictionary, choices_available: bool) -> Dictionary:
	var raw_nodes = row.get("nodes", [])
	if typeof(raw_nodes) != TYPE_ARRAY:
		return _fail("invalid_nodes", "Narrative event '%s' nodes must be an array." % row.get("id", ""))
	var nodes: Dictionary = {}
	var event_option_ids: Dictionary = {}
	for raw_node in raw_nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			return _fail("invalid_node", "Narrative event '%s' contains a non-object node." % row.get("id", ""))
		var node_id := String(raw_node.get("id", ""))
		if node_id.is_empty():
			return _fail("missing_node_id", "Narrative event '%s' contains a node without an id." % row.get("id", ""))
		if nodes.has(node_id):
			return _fail("duplicate_node_id", "Narrative event '%s' contains duplicate node id '%s'." % [row.get("id", ""), node_id])
		var options_result := _options_from_node(row, raw_node, item_ids, items_available, choice_ids, choices_available)
		if not options_result.ok:
			return options_result
		for option in options_result.options:
			if event_option_ids.has(option.id):
				return _fail("duplicate_option_id", "Narrative event '%s' contains duplicate option id '%s'." % [row.get("id", ""), option.id])
			event_option_ids[option.id] = true
		nodes[node_id] = {
			"id": node_id,
			"speaker_id": String(raw_node.get("speaker_id", "")),
			"text": String(raw_node.get("text", "")),
			"options": options_result.options
		}
	for node_id in nodes:
		for option in nodes[node_id].options:
			var next_node_id := String(option.next_node_id)
			if not next_node_id.is_empty() and not nodes.has(next_node_id):
				return _fail("missing_next_node", "Narrative event '%s' option '%s' references missing node '%s'." % [row.get("id", ""), option.id, next_node_id])
	return {"ok": true, "nodes": nodes}

func _options_from_node(row: Dictionary, raw_node: Dictionary, item_ids: Dictionary, items_available: bool, choice_ids: Dictionary, choices_available: bool) -> Dictionary:
	var raw_options = raw_node.get("options", [])
	if typeof(raw_options) != TYPE_ARRAY:
		return _fail("invalid_options", "Narrative node '%s' options must be an array." % raw_node.get("id", ""))
	var options: Array = []
	var seen_option_ids: Dictionary = {}
	for raw_option in raw_options:
		if typeof(raw_option) != TYPE_DICTIONARY:
			return _fail("invalid_option", "Narrative node '%s' contains a non-object option." % raw_node.get("id", ""))
		var option_id := String(raw_option.get("id", ""))
		if option_id.is_empty():
			return _fail("missing_option_id", "Narrative node '%s' contains an option without an id." % raw_node.get("id", ""))
		if seen_option_ids.has(option_id):
			return _fail("duplicate_option_id", "Narrative node '%s' contains duplicate option id '%s'." % [raw_node.get("id", ""), option_id])
		seen_option_ids[option_id] = true
		var results = raw_option.get("results", [])
		if typeof(results) != TYPE_ARRAY:
			return _fail("invalid_results", "Narrative option '%s' results must be an array." % option_id)
		var results_result := _validate_results(row, raw_node, option_id, results, item_ids, items_available, choice_ids, choices_available)
		if not results_result.ok:
			return results_result
		options.append({
			"id": option_id,
			"display_text": String(raw_option.get("display_text", "")),
			"conditions": raw_option.get("conditions", []),
			"results": results,
			"next_node_id": String(raw_option.get("next_node_id", "")),
			"completes_event": bool(raw_option.get("completes_event", false))
		})
	return {"ok": true, "options": options}

func _validate_results(row: Dictionary, raw_node: Dictionary, option_id: String, results: Array, item_ids: Dictionary, items_available: bool, choice_ids: Dictionary, choices_available: bool) -> Dictionary:
	var choice_result_count := 0
	for result in results:
		if typeof(result) != TYPE_DICTIONARY:
			return _fail("invalid_result", "Narrative option '%s' contains a non-object result." % option_id)
		var result_type := String(result.get("type", ""))
		if not ALLOWED_RESULT_TYPES.has(result_type):
			return _fail("invalid_result_type", "Narrative option '%s' has invalid result type '%s'." % [option_id, result_type])
		var result_id := String(result.get("id", ""))
		if result_id.is_empty():
			return _fail("missing_result_id", "Narrative option '%s' result '%s' is missing id." % [option_id, result_type])
		if not _is_stable_id(result_id):
			return _fail("invalid_result_id", "Narrative option '%s' result '%s' has invalid stable id '%s'." % [option_id, result_type, result_id])
		if result_type == RESULT_GRANT_ITEM:
			if not items_available:
				return _fail("missing_items_dataset", "Narrative option '%s' grant_item requires catalog item definitions." % option_id)
			if not result.has("quantity"):
				return _fail("missing_result_quantity", "Narrative option '%s' grant_item result is missing quantity." % option_id)
			var quantity = result.quantity
			if not [TYPE_INT, TYPE_FLOAT].has(typeof(quantity)) or int(quantity) != float(quantity) or int(quantity) <= 0:
				return _fail("invalid_result_quantity", "Narrative option '%s' grant_item quantity must be a positive integer." % option_id)
			if not item_ids.has(result_id):
				return _fail("missing_result_item", "Narrative option '%s' grant_item targets missing item id '%s'." % [option_id, result_id])
		if result_type == RESULT_APPLY_CHOICE:
			choice_result_count += 1
			if choice_result_count > 1:
				return _fail("multiple_choice_results", "Narrative option '%s' cannot apply more than one choice." % option_id)
			if not choices_available:
				return _fail("missing_choices_dataset", "Narrative option '%s' apply_choice requires catalog choice definitions." % option_id)
			if not choice_ids.has(result_id):
				return _fail("missing_result_choice", "Narrative option '%s' apply_choice targets missing choice id '%s'." % [option_id, result_id])
	return {"ok": true}

func _validate_reachable_completion(event_id: String, start_node_id: String, nodes: Dictionary) -> Dictionary:
	return _validate_node_completion_path(event_id, start_node_id, nodes, {})

func _validate_node_completion_path(event_id: String, node_id: String, nodes: Dictionary, visiting: Dictionary) -> Dictionary:
	if visiting.has(node_id):
		return _fail("dialogue_cycle", "Narrative event '%s' has a reachable cycle at node '%s'." % [event_id, node_id])
	var node: Dictionary = nodes[node_id]
	if node.options.is_empty():
		return _fail("non_terminating_dialogue_path", "Narrative event '%s' node '%s' has no completing option." % [event_id, node_id])
	var next_visiting := visiting.duplicate()
	next_visiting[node_id] = true
	for option in node.options:
		if bool(option.completes_event):
			continue
		var next_node_id := String(option.next_node_id)
		if next_node_id.is_empty():
			return _fail("non_terminating_dialogue_path", "Narrative event '%s' option '%s' neither completes nor advances." % [event_id, option.id])
		var path_result := _validate_node_completion_path(event_id, next_node_id, nodes, next_visiting)
		if not path_result.ok:
			return path_result
	return {"ok": true}

func _option_is_visible(option: Dictionary, run_query: Dictionary, meta_query: Dictionary) -> Dictionary:
	var conditions = option.get("conditions", [])
	if typeof(conditions) != TYPE_ARRAY:
		return _fail("invalid_conditions", "Narrative option '%s' conditions must be an array." % option.id)
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY:
			return _fail("invalid_condition", "Narrative option '%s' contains a non-object condition." % option.id)
		var condition_type := String(condition.get("type", ""))
		if condition_type.begins_with("meta_") and not condition_resolver.requires_meta(condition):
			return _fail("meta_boundary_violation", "Narrative condition type '%s' is not allowed to query meta state." % condition_type)
		var result := condition_resolver.resolve(condition, run_query, meta_query)
		if not result.ok:
			return result
		if not result.passed:
			return {"ok": true, "passed": false}
	return {"ok": true, "passed": true}

func _commands_for_results(event_id: String, node_id: String, option: Dictionary) -> Array:
	var commands: Array = []
	for result in option.results:
		commands.append(GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {
			"event_id": event_id,
			"node_id": node_id,
			"option_id": option.id,
			"result": result.duplicate(true)
		}))
	return commands

func _node_for_event(event_id: String, node_id: String) -> Dictionary:
	if not event_definitions.has(event_id):
		return _fail("missing_event", "Narrative event '%s' is not defined." % event_id)
	var event: Dictionary = event_definitions[event_id]
	if not event.nodes.has(node_id):
		return _fail("missing_node", "Narrative event '%s' does not define node '%s'." % [event_id, node_id])
	return {"ok": true, "node": event.nodes[node_id]}

func _run_query(run_state) -> Dictionary:
	if run_state == null:
		return {}
	var data: Dictionary = {}
	if run_state is Dictionary:
		data = run_state
	elif run_state.has_method("to_dictionary"):
		data = run_state.to_dictionary()
	return {
		"current_biome_id": String(data.get("current_biome_id", "")),
		"inventory": data.get("inventory", {}),
		"flags": data.get("narrative_flags", []),
		"event_counts": data.get("narrative_event_counts", {})
	}

func _meta_query(meta_state) -> Dictionary:
	if meta_state == null:
		return {}
	var data: Dictionary = {}
	if meta_state is Dictionary:
		data = meta_state
	elif meta_state.has_method("to_dictionary"):
		data = meta_state.to_dictionary()
	return {
		"run_count": int(data.get("run_count", 0)),
		"unlocked_meta_flags": data.get("unlocked_meta_flags", []),
		"dialogue_memory_flags": data.get("dialogue_memory_flags", [])
	}

func _event_count(run_state, event_id: String) -> int:
	var data := _run_query(run_state)
	return int(data.get("event_counts", {}).get(event_id, 0))

func _record_event_completion(run_state, event_id: String) -> void:
	if run_state == null:
		return
	if run_state is Dictionary:
		var counts: Dictionary = run_state.get("narrative_event_counts", {})
		counts[event_id] = int(counts.get(event_id, 0)) + 1
		run_state["narrative_event_counts"] = counts
		return
	var counts: Dictionary = run_state.get("narrative_event_counts") if run_state.has_method("get") else {}
	counts[event_id] = int(counts.get(event_id, 0)) + 1
	run_state.set("narrative_event_counts", counts)

func _is_stable_id(value: String) -> bool:
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]*$")
	return id_pattern.search(value) != null

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
