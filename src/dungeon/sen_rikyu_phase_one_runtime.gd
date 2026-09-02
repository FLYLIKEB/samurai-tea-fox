extends RefCounted
class_name SenRikyuPhaseOneRuntime

const GameCommand = preload("res://src/core/commands/game_command.gd")
const NarrativeConditionResolver = preload("res://src/narrative/narrative_condition_resolver.gd")

const EVENT_ID := "sen_rikyu_phase_1_last_tea"
const SPEAKER_CHARACTER_ID := "CHR-5"
const HIDDEN_NAME := "???"
const REVEALED_NAME := "센리큐"
const STATE_IDLE := "idle"
const STATE_ACTIVE := "active"
const STATE_TRANSITIONED := "transitioned_to_phase_2"
const COMMAND_SHARE_LAST_TEA := "share_last_tea"
const COMMAND_REFUSE_LAST_TEA := "refuse_last_tea"
const OUTCOME_SHARED_TEA := "shared_last_tea"
const OUTCOME_REFUSED_TEA := "refused_last_tea"
const PHASE_2_ID := "sen_rikyu_phase_2"

signal name_revealed(event: Dictionary)
signal dialogue_branch_selected(event: Dictionary)
signal phase_transition_requested(command: Dictionary)

var data_version := ""
var event_definition := {}
var _tea_service = null
var _condition_resolver := NarrativeConditionResolver.new()
var _state := _empty_state()

static func from_catalog(catalog, tea_service = null) -> Dictionary:
	if catalog == null or not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Sen Rikyu Phase 1 requires a catalog with final encounter event data.")
	var event = catalog.find_by_id("events", EVENT_ID)
	if typeof(event) != TYPE_DICTIONARY or event.is_empty():
		return _fail("missing_phase_one_event", "Missing Sen Rikyu Phase 1 event data: %s" % EVENT_ID)
	if catalog.has_method("character_has_meta_memory") and not bool(catalog.character_has_meta_memory(SPEAKER_CHARACTER_ID)):
		return _fail("sen_rikyu_meta_memory_forbidden", "Sen Rikyu Phase 1 speaker must be allowed to read meta memory.")
	var runtime: SenRikyuPhaseOneRuntime = load("res://src/dungeon/sen_rikyu_phase_one_runtime.gd").new()
	var configured := runtime.configure(event, tea_service, String(catalog.get("data_version")) if catalog.has_method("get") else "")
	if not configured.ok:
		return configured
	return {"ok": true, "runtime": runtime}

func configure(new_event_definition: Dictionary, tea_service = null, new_data_version := "") -> Dictionary:
	var validation := _validate_event_definition(new_event_definition)
	if not validation.ok:
		return validation
	if tea_service != null:
		var service_validation := _validate_tea_service(tea_service)
		if not service_validation.ok:
			return service_validation
	event_definition = new_event_definition.duplicate(true)
	_tea_service = tea_service
	data_version = new_data_version
	_state = _empty_state()
	return {"ok": true, "projection": to_projection()}

func start(run_state = null, meta_state = null) -> Dictionary:
	if event_definition.is_empty():
		return _fail("not_configured", "Sen Rikyu Phase 1 is not configured.")
	if String(_state.lifecycle_state) != STATE_IDLE:
		return _fail("phase_one_already_started", "Sen Rikyu Phase 1 can only start once.")
	_state.lifecycle_state = STATE_ACTIVE
	_state.event_id = EVENT_ID
	_state.node_id = String(event_definition.start_node_id)
	var reveal_event := _name_reveal_event()
	_state.name_revealed = true
	name_revealed.emit(reveal_event.duplicate(true))
	return {
		"ok": true,
		"name_reveal_event": reveal_event,
		"read_model": _read_model_for_node(_state.node_id, run_state, meta_state).read_model,
		"projection": to_projection()
	}

func handle_command(command_id: String, payload := {}, run_state = null, meta_state = null, resources = null) -> Dictionary:
	if String(_state.lifecycle_state) != STATE_ACTIVE:
		return _fail("phase_one_not_active", "Sen Rikyu Phase 1 must be active before commands.")
	if not [COMMAND_SHARE_LAST_TEA, COMMAND_REFUSE_LAST_TEA].has(command_id):
		return _fail("invalid_phase_one_command", "Sen Rikyu Phase 1 only accepts last-tea share/refuse commands.")
	var option_result := _option_for_node(String(event_definition.start_node_id), command_id)
	if not option_result.ok:
		return option_result
	var before_run := _snapshot_run_state(run_state)
	var tea_result := _apply_tea_command(command_id, _dictionary_value(payload), resources)
	if not tea_result.ok:
		return tea_result
	_apply_results(option_result.option.results, run_state)
	var branch_result := _select_dialogue_branch(String(option_result.option.next_node_id), run_state, meta_state)
	if not branch_result.ok:
		_restore_run_state(run_state, before_run)
		return branch_result
	_apply_results(branch_result.branch.results, run_state)
	_record_event_completion(run_state)
	var transition_command := _phase_2_transition_command(command_id, branch_result.branch)
	_state.lifecycle_state = STATE_TRANSITIONED
	_state.node_id = String(option_result.option.next_node_id)
	_state.selected_command = command_id
	_state.dialogue_branch_id = String(branch_result.branch.id)
	_state.phase_2_command = transition_command.to_dictionary()
	var branch_event := _dialogue_branch_event(command_id, branch_result.branch)
	dialogue_branch_selected.emit(branch_event.duplicate(true))
	phase_transition_requested.emit(_state.phase_2_command.duplicate(true))
	return {
		"ok": true,
		"outcome_type": OUTCOME_SHARED_TEA if command_id == COMMAND_SHARE_LAST_TEA else OUTCOME_REFUSED_TEA,
		"consumed": bool(tea_result.get("consumed", false)),
		"combat_started": false,
		"dialogue_branch": branch_result.branch.duplicate(true),
		"dialogue_event": branch_event,
		"transition_command": transition_command,
		"projection": to_projection()
	}

func to_projection() -> Dictionary:
	var projection := _state.duplicate(true)
	projection["read_only"] = true
	projection["phase"] = "sen_rikyu_phase_1"
	projection["hidden_name"] = HIDDEN_NAME
	projection["revealed_name"] = REVEALED_NAME if bool(_state.get("name_revealed", false)) else HIDDEN_NAME
	projection["combat_started"] = false
	projection["phase_2_ready"] = String(_state.lifecycle_state) == STATE_TRANSITIONED
	return projection

func _apply_tea_command(command_id: String, payload: Dictionary, resources) -> Dictionary:
	if command_id == COMMAND_REFUSE_LAST_TEA:
		return {"ok": true, "consumed": false}
	if _tea_service == null:
		return _fail("missing_tea_service", "Sharing the last tea requires the configured tea service.")
	var slot := int(payload.get("slot", -1))
	if not _tea_service.has_prepared_tea(slot):
		return _fail("missing_prepared_tea", "Sharing the last tea requires a prepared tea slot.")
	var action: Dictionary = _tea_service.start_drinking(slot, {"event_id": EVENT_ID, "phase": "sen_rikyu_phase_1", "command": command_id})
	if not action.ok:
		return action
	var completion: Dictionary = _tea_service.complete_drinking(action.action, resources)
	if not completion.ok:
		return completion
	return completion

func _select_dialogue_branch(node_id: String, run_state, meta_state) -> Dictionary:
	var read_result := _read_model_for_node(node_id, run_state, meta_state)
	if not read_result.ok:
		return read_result
	var options: Array = read_result.read_model.options
	if options.is_empty():
		return _fail("missing_dialogue_branch", "Sen Rikyu Phase 1 requires at least one visible dialogue branch.")
	return _option_for_node(node_id, String(options[0].id)).merged({"branch": _option_for_node(node_id, String(options[0].id)).option})

func _read_model_for_node(node_id: String, run_state, meta_state) -> Dictionary:
	var node_result := _node(node_id)
	if not node_result.ok:
		return node_result
	var visible_options := []
	for option in node_result.node.options:
		var visible := _option_visible(option, run_state, meta_state)
		if not visible.ok:
			return visible
		if visible.passed:
			visible_options.append({
				"id": option.id,
				"display_text": option.display_text,
				"next_node_id": option.next_node_id,
				"completes_event": bool(option.completes_event)
			})
	return {"ok": true, "read_model": {
		"event_id": EVENT_ID,
		"event_name": String(event_definition.name),
		"node_id": node_result.node.id,
		"speaker_id": node_result.node.speaker_id,
		"speaker_name": REVEALED_NAME if bool(_state.get("name_revealed", false)) else HIDDEN_NAME,
		"text": node_result.node.text,
		"options": visible_options,
		"combat_enabled": false
	}}

func _option_visible(option: Dictionary, run_state, meta_state) -> Dictionary:
	var conditions = option.get("conditions", [])
	if typeof(conditions) != TYPE_ARRAY:
		return _fail("invalid_conditions", "Sen Rikyu Phase 1 dialogue conditions must be an array.")
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY:
			return _fail("invalid_condition", "Sen Rikyu Phase 1 dialogue condition must be an object.")
		var resolved := _condition_resolver.resolve(condition, _run_query(run_state), _meta_query(meta_state))
		if not resolved.ok:
			return resolved
		if not resolved.passed:
			return {"ok": true, "passed": false}
	return {"ok": true, "passed": true}

func _apply_results(results, run_state) -> void:
	if run_state == null or typeof(results) != TYPE_ARRAY:
		return
	for result in results:
		if typeof(result) != TYPE_DICTIONARY or String(result.get("type", "")) != "set_run_flag":
			continue
		_append_run_flag(run_state, String(result.get("id", "")))

func _append_run_flag(run_state, flag: String) -> void:
	if flag.is_empty():
		return
	if run_state is Dictionary:
		var flags: Array = _array_value(run_state.get("narrative_flags", []))
		if not flags.has(flag):
			flags.append(flag)
		run_state["narrative_flags"] = flags
	elif run_state.has_method("get") and run_state.has_method("set"):
		var flags: Array = _array_value(run_state.get("narrative_flags"))
		if not flags.has(flag):
			flags.append(flag)
		run_state.set("narrative_flags", flags)

func _record_event_completion(run_state) -> void:
	if run_state == null:
		return
	if run_state is Dictionary:
		var counts: Dictionary = _dictionary_value(run_state.get("narrative_event_counts", {}))
		counts[EVENT_ID] = int(counts.get(EVENT_ID, 0)) + 1
		run_state["narrative_event_counts"] = counts
	elif run_state.has_method("get") and run_state.has_method("set"):
		var counts: Dictionary = _dictionary_value(run_state.get("narrative_event_counts"))
		counts[EVENT_ID] = int(counts.get(EVENT_ID, 0)) + 1
		run_state.set("narrative_event_counts", counts)

func _phase_2_transition_command(command_id: String, branch: Dictionary) -> GameCommand:
	return GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {
		"event_id": EVENT_ID,
		"phase": "sen_rikyu_phase_1",
		"result": {"type": "start_phase", "id": PHASE_2_ID},
		"selected_command": command_id,
		"dialogue_branch_id": String(branch.id),
		"combat_started": false
	})

func _name_reveal_event() -> Dictionary:
	return {
		"event_type": "sen_rikyu_name_revealed",
		"event_id": EVENT_ID,
		"character_id": SPEAKER_CHARACTER_ID,
		"from_name": HIDDEN_NAME,
		"revealed_name": REVEALED_NAME,
		"combat_started": false
	}

func _dialogue_branch_event(command_id: String, branch: Dictionary) -> Dictionary:
	return {
		"event_type": "sen_rikyu_phase_one_dialogue_selected",
		"event_id": EVENT_ID,
		"command": command_id,
		"dialogue_branch_id": String(branch.id),
		"dialogue_key": String(branch.display_text),
		"phase_2_ready": true,
		"combat_started": false
	}

func _node(node_id: String) -> Dictionary:
	for node in _array_value(event_definition.get("nodes", [])):
		if typeof(node) == TYPE_DICTIONARY and String(node.get("id", "")) == node_id:
			return {"ok": true, "node": node}
	return _fail("missing_phase_one_node", "Sen Rikyu Phase 1 event is missing node: %s" % node_id)

func _option_for_node(node_id: String, option_id: String) -> Dictionary:
	var node_result := _node(node_id)
	if not node_result.ok:
		return node_result
	for option in _array_value(node_result.node.get("options", [])):
		if typeof(option) == TYPE_DICTIONARY and String(option.get("id", "")) == option_id:
			return {"ok": true, "option": option}
	return _fail("missing_phase_one_option", "Sen Rikyu Phase 1 event is missing option: %s" % option_id)

func _validate_event_definition(event: Dictionary) -> Dictionary:
	if String(event.get("id", "")) != EVENT_ID:
		return _fail("invalid_phase_one_event", "Sen Rikyu Phase 1 must use event id %s." % EVENT_ID)
	if String(event.get("start_node_id", "")) != "start":
		return _fail("invalid_phase_one_start", "Sen Rikyu Phase 1 requires a start node.")
	for required_option in [COMMAND_SHARE_LAST_TEA, COMMAND_REFUSE_LAST_TEA]:
		var option_result := _option_for_event(event, "start", required_option)
		if not option_result.ok:
			return option_result
		if String(option_result.option.get("next_node_id", "")).is_empty():
			return _fail("invalid_phase_one_branch", "Sen Rikyu Phase 1 command option must route to a dialogue node: %s" % required_option)
	return {"ok": true}

func _option_for_event(event: Dictionary, node_id: String, option_id: String) -> Dictionary:
	for node in _array_value(event.get("nodes", [])):
		if typeof(node) == TYPE_DICTIONARY and String(node.get("id", "")) == node_id:
			for option in _array_value(node.get("options", [])):
				if typeof(option) == TYPE_DICTIONARY and String(option.get("id", "")) == option_id:
					return {"ok": true, "option": option}
	return _fail("missing_phase_one_option", "Sen Rikyu Phase 1 event is missing option: %s" % option_id)

func _validate_tea_service(tea_service) -> Dictionary:
	for method in ["has_prepared_tea", "start_drinking", "complete_drinking"]:
		if not tea_service.has_method(method):
			return _fail("invalid_tea_service", "Sen Rikyu Phase 1 tea service is missing method: %s" % method)
	return {"ok": true}

func _run_query(run_state) -> Dictionary:
	var data := _snapshot_run_state(run_state)
	return {"flags": data.get("narrative_flags", []), "inventory": data.get("inventory", {}), "current_biome_id": String(data.get("current_biome_id", ""))}

func _meta_query(meta_state) -> Dictionary:
	var data := _snapshot_run_state(meta_state)
	return {
		"run_count": int(data.get("run_count", 0)),
		"unlocked_meta_flags": data.get("unlocked_meta_flags", []),
		"dialogue_memory_flags": data.get("dialogue_memory_flags", []),
		"past_choice_ids": data.get("past_choice_ids", []),
		"reached_place_ids": data.get("reached_place_ids", []),
		"death_record_ids": data.get("death_record_ids", [])
	}

func _snapshot_run_state(state) -> Dictionary:
	if state == null:
		return {}
	if state is Dictionary:
		return state.duplicate(true)
	if state.has_method("to_dictionary"):
		return state.to_dictionary()
	return {}

func _restore_run_state(run_state, snapshot: Dictionary) -> void:
	if run_state == null:
		return
	if run_state is Dictionary:
		run_state.clear()
		for key in snapshot.keys():
			run_state[key] = snapshot[key]
	elif run_state.has_method("load_snapshot"):
		run_state.load_snapshot(snapshot)
	elif run_state.has_method("set"):
		for key in snapshot.keys():
			run_state.set(String(key), snapshot[key])

static func _empty_state() -> Dictionary:
	return {"lifecycle_state": STATE_IDLE, "event_id": "", "node_id": "", "selected_command": "", "dialogue_branch_id": "", "name_revealed": false, "phase_2_command": {}}

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
