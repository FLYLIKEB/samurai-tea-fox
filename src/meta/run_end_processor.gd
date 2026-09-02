extends RefCounted
class_name RunEndProcessor

const CONDITION_EVENT_SEEN := "event_seen"
const CONDITION_CUMULATIVE_EVENT_COUNT_AT_LEAST := "cumulative_event_count_at_least"
const CONDITION_RUN_COUNT_AT_LEAST := "run_count_at_least"
const CONDITION_BEST_BIOME_ORDER_AT_LEAST := "best_biome_order_at_least"
const CONDITION_VALUE_AT_LEAST := "value_at_least"

const REWARD_UNLOCK_FLAG := "unlock_flag"
const REWARD_DIALOGUE_MEMORY_FLAG := "dialogue_memory_flag"
const REWARD_DISCOVERED_RECORD := "discovered_record"

const CONDITION_TYPES := [
	CONDITION_EVENT_SEEN,
	CONDITION_CUMULATIVE_EVENT_COUNT_AT_LEAST,
	CONDITION_RUN_COUNT_AT_LEAST,
	CONDITION_BEST_BIOME_ORDER_AT_LEAST,
	CONDITION_VALUE_AT_LEAST
]
const REWARD_KINDS := [REWARD_UNLOCK_FLAG, REWARD_DIALOGUE_MEMORY_FLAG, REWARD_DISCOVERED_RECORD]

func apply_run_end(meta_state: Dictionary, run_summary: Dictionary) -> Dictionary:
	var validation := _validate_previous_run_inputs(run_summary)
	if not validation.ok:
		return validation
	var next_meta := _prepare_next_meta(meta_state, run_summary)
	for flag in run_summary.get("earned_meta_flags", []):
		_append_unique(next_meta.unlocked_meta_flags, String(flag))
	return next_meta

func apply_run_end_with_unlocks(meta_state: Dictionary, run_summary: Dictionary, unlock_definitions: Array) -> Dictionary:
	var validation := _validate_previous_run_inputs(run_summary)
	if not validation.ok:
		return validation
	var next_meta := _prepare_next_meta(meta_state, run_summary)
	var events := _events_from_run_summary(run_summary)
	var allowed_counter_targets := _cumulative_counter_targets(unlock_definitions)
	if not allowed_counter_targets.ok:
		return allowed_counter_targets
	_apply_event_counters(next_meta, events, allowed_counter_targets.targets)

	var newly_unlocked: Array = []
	for definition in unlock_definitions:
		var definition_id := String(definition.get("id", ""))
		if next_meta.unlocked_meta_flags.has(definition_id):
			continue
		var condition_result_payload := _definition_condition(definition)
		if not condition_result_payload.ok:
			condition_result_payload["definition_id"] = definition_id
			return condition_result_payload
		var condition: Dictionary = condition_result_payload.condition
		var condition_result := _condition_passes(condition, next_meta, events)
		if not condition_result.ok:
			condition_result["definition_id"] = definition_id
			return condition_result
		if not condition_result.passed:
			continue
		var reward := _definition_reward(definition)
		var reward_result := _apply_reward(next_meta, definition_id, reward)
		if not reward_result.ok:
			reward_result["definition_id"] = definition_id
			return reward_result
		newly_unlocked.append({
			"id": definition_id,
			"reward_kind": reward.kind,
			"reward_target": reward.target,
			"reward_quantity": reward.quantity
		})

	return {"ok": true, "meta_state": next_meta, "unlocked": newly_unlocked}

func is_unlocked(meta_state: Dictionary, unlock_id: String) -> bool:
	return _array_value(meta_state.get("unlocked_meta_flags", [])).has(unlock_id)

func unlocked_ids(meta_state: Dictionary) -> Array:
	return _array_value(meta_state.get("unlocked_meta_flags", []))

func unlocked_rewards(meta_state: Dictionary, unlock_definitions: Array) -> Array:
	var ids := unlocked_ids(meta_state)
	var rewards: Array = []
	for definition in unlock_definitions:
		if typeof(definition) != TYPE_DICTIONARY:
			continue
		var definition_id := String(definition.get("id", ""))
		if ids.has(definition_id):
			var reward := _definition_reward(definition)
			rewards.append({
				"id": definition_id,
				"reward_kind": reward.kind,
				"reward_target": reward.target,
				"reward_quantity": reward.quantity
			})
	return rewards

func _prepare_next_meta(meta_state: Dictionary, run_summary: Dictionary) -> Dictionary:
	var next_meta := meta_state.duplicate(true)
	if typeof(next_meta.get("discovered_records", [])) != TYPE_ARRAY:
		next_meta["discovered_records"] = []
	if typeof(next_meta.get("unlocked_meta_flags", [])) != TYPE_ARRAY:
		next_meta["unlocked_meta_flags"] = []
	if typeof(next_meta.get("dialogue_memory_flags", [])) != TYPE_ARRAY:
		next_meta["dialogue_memory_flags"] = []
	if typeof(next_meta.get("meta_unlock_counters", {})) != TYPE_DICTIONARY:
		next_meta["meta_unlock_counters"] = {}
	for field in ["past_choice_ids", "reached_place_ids", "death_record_ids"]:
		if typeof(next_meta.get(field, [])) != TYPE_ARRAY:
			next_meta[field] = []

	_append_ids(next_meta.past_choice_ids, run_summary.get("past_choice_ids", []))
	_append_ids(next_meta.past_choice_ids, run_summary.get("choice_history", []))
	_append_ids(next_meta.reached_place_ids, run_summary.get("reached_place_ids", []))
	_append_ids(next_meta.reached_place_ids, run_summary.get("reached_biome_ids", []))
	_append_stable_id(next_meta.reached_place_ids, run_summary.get("current_biome_id", ""))
	if bool(run_summary.get("final_tea_room_reached", false)):
		_append_unique(next_meta.reached_place_ids, "final_tea_room")
	_append_ids(next_meta.death_record_ids, run_summary.get("death_record_ids", []))
	_append_stable_id(next_meta.death_record_ids, run_summary.get("death_record_id", ""))

	next_meta["run_count"] = int(next_meta.get("run_count", 0)) + 1
	next_meta["best_reached_biome_order"] = max(
		int(next_meta.get("best_reached_biome_order", 0)),
		int(run_summary.get("best_reached_biome_order", 0))
	)
	return next_meta

func _definition_condition(definition: Dictionary) -> Dictionary:
	var threshold = definition.get("threshold", null)
	if threshold == null or not _is_non_negative_integer(threshold):
		return _failure("invalid_condition_threshold", "Meta unlock condition threshold must be a non-negative integer.")
	return {"ok": true, "condition": {
		"type": String(definition.get("condition_event", definition.get("condition_kind", definition.get("condition_type", "")))),
		"target": String(definition.get("condition_target", "")),
		"operator": String(definition.get("condition_operator", "equals")),
		"threshold": int(threshold)
	}}

func _definition_reward(definition: Dictionary) -> Dictionary:
	return {
		"kind": String(definition.get("reward_kind", definition.get("reward_type", ""))),
		"target": String(definition.get("reward_target", definition.get("id", ""))),
		"quantity": int(definition.get("reward_quantity", 1))
	}

func _condition_passes(condition: Dictionary, meta_state: Dictionary, events: Array) -> Dictionary:
	var condition_type := String(condition.type)
	if not CONDITION_TYPES.has(condition_type):
		return _failure("unknown_condition_type", "Unknown meta unlock condition type '%s'." % condition_type)
	if not ["equals", "at_least"].has(String(condition.operator)):
		return _failure("unknown_condition_operator", "Unknown meta unlock condition operator '%s'." % condition.operator)
	match condition_type:
		CONDITION_EVENT_SEEN:
			return {"ok": true, "passed": _compare(1 if _has_event(events, condition.target) else 0, condition)}
		CONDITION_CUMULATIVE_EVENT_COUNT_AT_LEAST:
			return {"ok": true, "passed": _compare(int(meta_state.meta_unlock_counters.get(_counter_key(condition.target), 0)), condition)}
		CONDITION_RUN_COUNT_AT_LEAST:
			return {"ok": true, "passed": _compare(int(meta_state.get("run_count", 0)), condition)}
		CONDITION_BEST_BIOME_ORDER_AT_LEAST:
			return {"ok": true, "passed": _compare(int(meta_state.get("best_reached_biome_order", 0)), condition)}
		CONDITION_VALUE_AT_LEAST:
			return {"ok": true, "passed": _compare(_max_event_value(events, condition.target), condition)}
	return {"ok": true, "passed": false}

func _apply_reward(meta_state: Dictionary, definition_id: String, reward: Dictionary) -> Dictionary:
	var reward_kind := String(reward.kind)
	if not REWARD_KINDS.has(reward_kind):
		return _failure("unknown_reward_type", "Unknown meta unlock reward kind '%s'." % reward_kind)
	var reward_target := String(reward.target)
	if reward_target.is_empty():
		reward_target = definition_id
	_append_unique(meta_state.unlocked_meta_flags, definition_id)
	match reward_kind:
		REWARD_UNLOCK_FLAG:
			_append_unique(meta_state.unlocked_meta_flags, reward_target)
		REWARD_DIALOGUE_MEMORY_FLAG:
			_append_unique(meta_state.dialogue_memory_flags, reward_target)
		REWARD_DISCOVERED_RECORD:
			_append_unique(meta_state.discovered_records, reward_target)
	return {"ok": true}

func _events_from_run_summary(run_summary: Dictionary) -> Array:
	var events: Array = []
	for key in ["events", "run_result_events", "discovery_events", "choice_events", "meta_events"]:
		var entries = run_summary.get(key, [])
		if typeof(entries) != TYPE_ARRAY:
			continue
		for entry in entries:
			if typeof(entry) == TYPE_DICTIONARY:
				events.append(entry.duplicate(true))

	if int(run_summary.get("best_reached_biome_order", 0)) > 0:
		events.append({"type": "biome_order_reached", "target": "best_reached_biome_order", "value": int(run_summary.best_reached_biome_order)})
	for biome_id in _array_value(run_summary.get("reached_biome_ids", [])):
		events.append({"type": "biome_reached", "target": String(biome_id), "value": 1})
	var current_biome_id := String(run_summary.get("current_biome_id", ""))
	if not current_biome_id.is_empty():
		events.append({"type": "biome_reached", "target": current_biome_id, "value": 1})
	if bool(run_summary.get("final_tea_room_reached", false)):
		events.append({"type": "final_tea_room_reached", "target": "final_tea_room", "value": 1})
	if int(run_summary.get("tail_stage", 0)) > 0:
		events.append({"type": "tail_stage_reached", "target": "tail_stage", "value": int(run_summary.tail_stage)})
	var tail_state = run_summary.get("tail_state", {})
	if typeof(tail_state) == TYPE_DICTIONARY:
		if int(tail_state.get("stage", 0)) > 0:
			events.append({"type": "tail_stage_reached", "target": "tail_stage", "value": int(tail_state.stage)})
		for flag in _array_value(tail_state.get("path_flags", [])):
			events.append({"type": "tail_path_flag", "target": String(flag), "value": 1})
	for record_id in _array_value(run_summary.get("discovered_records", [])):
		events.append({"type": "discovered_record", "target": String(record_id), "value": 1})
	for choice_id in _array_value(run_summary.get("choice_history", [])):
		events.append({"type": "choice", "target": String(choice_id), "value": 1})
	return events

func _cumulative_counter_targets(unlock_definitions: Array) -> Dictionary:
	var targets: Dictionary = {}
	for definition in unlock_definitions:
		if typeof(definition) != TYPE_DICTIONARY:
			return _failure("invalid_definition", "Meta unlock definition must be a dictionary.")
		var definition_id := String(definition.get("id", ""))
		if definition_id.is_empty():
			return _failure("missing_definition_id", "Meta unlock definition is missing id.")
		var condition_result_payload := _definition_condition(definition)
		if not condition_result_payload.ok:
			condition_result_payload["definition_id"] = definition_id
			return condition_result_payload
		var condition: Dictionary = condition_result_payload.condition
		if String(condition.type) == CONDITION_CUMULATIVE_EVENT_COUNT_AT_LEAST:
			var target := _counter_key(String(condition.target))
			if not target.is_empty():
				targets[target] = true
	return {"ok": true, "targets": targets}

func _apply_event_counters(meta_state: Dictionary, events: Array, allowed_counter_targets: Dictionary) -> void:
	var counted_this_run: Dictionary = {}
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var key := _counter_key(_event_key(event))
		if key.is_empty() or counted_this_run.has(key) or not allowed_counter_targets.has(key):
			continue
		counted_this_run[key] = true
		meta_state.meta_unlock_counters[key] = int(meta_state.meta_unlock_counters.get(key, 0)) + 1

func _has_event(events: Array, expected_key: String) -> bool:
	for event in events:
		if typeof(event) == TYPE_DICTIONARY and _event_key(event) == expected_key:
			return true
	return false

func _max_event_value(events: Array, expected_key: String) -> int:
	var highest := 0
	for event in events:
		if typeof(event) != TYPE_DICTIONARY or _event_key(event) != expected_key:
			continue
		highest = max(highest, int(event.get("value", 1)))
	return highest

func _event_key(event: Dictionary) -> String:
	var event_type := String(event.get("type", ""))
	var target := String(event.get("target", event.get("target_id", event.get("record_id", event.get("id", "")))))
	if event_type == "choice_meta_record_requested":
		event_type = "choice"
		target = String(event.get("choice_id", target))
	elif event_type == "discovery":
		event_type = "discovered_record"
	if event_type.is_empty():
		return target
	if target.is_empty():
		return event_type
	return "%s:%s" % [event_type, target]

func _compare(actual: int, condition: Dictionary) -> bool:
	if String(condition.operator) == "equals":
		return actual == int(condition.threshold)
	return actual >= int(condition.threshold)

func _counter_key(event_key: String) -> String:
	return event_key

func _validate_previous_run_inputs(run_summary: Dictionary) -> Dictionary:
	for field in ["past_choice_ids", "choice_history", "reached_place_ids", "reached_biome_ids", "death_record_ids"]:
		if run_summary.has(field):
			var result := _validate_stable_id_array(run_summary[field], field)
			if not result.ok:
				return result
	for field in ["current_biome_id", "death_record_id"]:
		if run_summary.has(field):
			var value = run_summary.get(field, "")
			if typeof(value) != TYPE_STRING or (not value.is_empty() and not _is_stable_id(value)):
				return _failure("invalid_run_summary_stable_id", "Run summary field '%s' must be a stable id." % field)
	return {"ok": true}

func _validate_stable_id_array(value, field: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("invalid_run_summary_stable_id_array", "Run summary field '%s' must be an array of stable ids." % field)
	for entry in value:
		if typeof(entry) != TYPE_STRING or not _is_stable_id(String(entry)):
			return _failure("invalid_run_summary_stable_id", "Run summary field '%s' contains a malformed stable id." % field)
	return {"ok": true}

func _is_stable_id(value: String) -> bool:
	if value.is_empty():
		return false
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]*$")
	return id_pattern.search(value) != null

func _is_non_negative_integer(value) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(float(value), floor(float(value))) and int(value) >= 0
	return false

func _append_unique(values: Array, id: String) -> void:
	if id.is_empty():
		return
	if not values.has(id):
		values.append(id)

func _append_ids(values: Array, ids) -> void:
	if typeof(ids) != TYPE_ARRAY:
		return
	for id in ids:
		_append_stable_id(values, id)

func _append_stable_id(values: Array, value) -> void:
	if typeof(value) != TYPE_STRING or not _is_stable_id(value):
		return
	_append_unique(values, value)

func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

func _failure(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
