extends RefCounted
class_name EndingRouteRuntime

const EVENT_PREFIX := "ending_"
const DEFAULT_ENDING_ID := "ending_solitary_road"
const ENDING_META_RECORD_TYPE := "ending"

signal endings_evaluated(event: Dictionary)
signal ending_recorded(event: Dictionary)
signal new_run_requested(event: Dictionary)

var data_version := ""
var ending_definitions := []

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Ending route runtime requires catalog event definitions.")
	var endings := []
	for event in catalog.get_definitions("events"):
		if typeof(event) == TYPE_DICTIONARY and String(event.get("id", "")).begins_with(EVENT_PREFIX) and event.has("ending_key"):
			var validation := _validate_ending(event)
			if not validation.ok:
				return validation
			endings.append(event.duplicate(true))
	if endings.is_empty():
		return _fail("missing_ending_routes", "Ending route runtime requires at least one ending event.")
	var runtime: EndingRouteRuntime = load("res://src/meta/ending_route_runtime.gd").new()
	runtime.data_version = String(catalog.get("data_version")) if catalog.has_method("get") else ""
	runtime.ending_definitions = endings
	return {"ok": true, "runtime": runtime}

func evaluate(run_state) -> Dictionary:
	var snapshot := _snapshot(run_state)
	var candidates := []
	for definition in ending_definitions:
		var result := _conditions_pass(definition, snapshot)
		if not result.ok:
			return result
		if result.passed:
			candidates.append(_ending_entry(definition, result.evidence))
	if candidates.is_empty() or not _has_exclusive_group(candidates, "primary"):
		var fallback := _definition_by_id(DEFAULT_ENDING_ID)
		if fallback.is_empty():
			return _fail("missing_default_ending", "Ending route runtime requires a default route.")
		candidates.append(_ending_entry(fallback, []))
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_group_rank := _group_rank(String(left.exclusive_group))
		var right_group_rank := _group_rank(String(right.exclusive_group))
		if left_group_rank != right_group_rank:
			return left_group_rank < right_group_rank
		if int(left.priority) == int(right.priority):
			return String(left.id) < String(right.id)
		return int(left.priority) > int(right.priority)
	)
	var selected := []
	var occupied_groups := {}
	for candidate in candidates:
		var group := String(candidate.exclusive_group)
		if group.is_empty():
			selected.append(candidate)
		elif not occupied_groups.has(group):
			occupied_groups[group] = true
			selected.append(candidate)
	var read_model := {
		"schema_version": 1,
		"data_version": data_version,
		"read_only": true,
		"ending_ids": selected.map(func(item): return item.id),
		"primary_ending_id": _primary_ending_id(selected),
		"endings": selected,
		"credits_hook": {"type": "show_credits", "ending_ids": selected.map(func(item): return item.id)},
		"new_run_hook": {"type": "request_new_run", "after": "credits", "reset_run_growth": true}
	}
	endings_evaluated.emit({"event_type": "endings_evaluated", "ending_ids": read_model.ending_ids})
	return {"ok": true, "read_model": read_model}

func record_to_meta(read_model: Dictionary, meta_state) -> Dictionary:
	if meta_state == null:
		return _fail("missing_meta_state", "Ending route runtime requires meta state for ending records.")
	if typeof(read_model) != TYPE_DICTIONARY or not read_model.has("ending_ids"):
		return _fail("invalid_ending_read_model", "Ending meta record requires an ending read model.")
	var record := {
		"type": ENDING_META_RECORD_TYPE,
		"ending_ids": _array_value(read_model.ending_ids),
		"primary_ending_id": String(read_model.get("primary_ending_id", "")),
		"data_version": String(read_model.get("data_version", data_version))
	}
	var existing := _meta_records(meta_state)
	var key := "%s|%s" % [record.primary_ending_id, ",".join(record.ending_ids)]
	for old in existing:
		if typeof(old) == TYPE_DICTIONARY and "%s|%s" % [String(old.get("primary_ending_id", "")), ",".join(_array_value(old.get("ending_ids", [])))] == key:
			return {"ok": true, "recorded": false, "record": old.duplicate(true), "read_model": read_model.duplicate(true)}
	existing.append(record)
	_set_meta_records(meta_state, existing)
	var event := {"event_type": "ending_recorded", "record": record.duplicate(true)}
	ending_recorded.emit(event.duplicate(true))
	return {"ok": true, "recorded": true, "record": record, "read_model": read_model.duplicate(true)}

func request_new_run_after_credits(read_model: Dictionary) -> Dictionary:
	if typeof(read_model) != TYPE_DICTIONARY or not read_model.has("new_run_hook"):
		return _fail("invalid_ending_read_model", "New run hook requires an ending read model.")
	var event := {"event_type": "ending_new_run_requested", "hook": _dictionary_value(read_model.new_run_hook), "ending_ids": _array_value(read_model.get("ending_ids", []))}
	new_run_requested.emit(event.duplicate(true))
	return {"ok": true, "event": event}

func _conditions_pass(definition: Dictionary, snapshot: Dictionary) -> Dictionary:
	var evidence := []
	for condition in _array_value(definition.get("ending_conditions", [])):
		if typeof(condition) != TYPE_DICTIONARY:
			return _fail("invalid_ending_condition", "Ending condition must be an object.")
		var check := _condition_pass(condition, snapshot)
		if not check.ok:
			return check
		if not check.passed:
			return {"ok": true, "passed": false, "evidence": evidence}
		evidence.append(check.evidence)
	return {"ok": true, "passed": true, "evidence": evidence}

func _condition_pass(condition: Dictionary, snapshot: Dictionary) -> Dictionary:
	var type := String(condition.get("type", ""))
	var id := String(condition.get("id", ""))
	match type:
		"run_flag":
			return _evidence(condition, _array_value(snapshot.get("narrative_flags", [])).has(id))
		"choice":
			return _evidence(condition, _array_value(snapshot.get("choice_history", [])).has(id))
		"target_survives":
			return _evidence(condition, bool(_dictionary_value(snapshot.get("target_survival", {})).get(id, false)))
		"philosophy_mark":
			return _evidence(condition, _array_value(snapshot.get("philosophy_marks", [])).has(id))
		"phase_victory_ability":
			return _evidence(condition, String(_dictionary_value(snapshot.get("sen_rikyu_phase3_victory", {})).get("selected_ability_id", "")) == id or _array_value(snapshot.get("narrative_flags", [])).has("sen_rikyu_phase3_ability_%s" % id))
		"core_tea_ware_collected":
			return _evidence(condition, _array_value(_dictionary_value(snapshot.get("core_tea_ware_collection", {})).get("collected_ids", [])).has(id))
		"memory_tea":
			return _evidence(condition, _array_value(snapshot.get("discovered_records", [])).has("memory_tea") or not _dictionary_value(snapshot.get("memory_tea_cutscene", {})).is_empty())
		_:
			return _fail("unsupported_ending_condition", "Unsupported ending condition type: %s" % type)

func _evidence(condition: Dictionary, passed: bool) -> Dictionary:
	return {"ok": true, "passed": passed, "evidence": {"type": String(condition.get("type", "")), "id": String(condition.get("id", "")), "passed": passed}}

func _ending_entry(definition: Dictionary, evidence: Array) -> Dictionary:
	return {"id": String(definition.id), "ending_key": String(definition.ending_key), "title": String(definition.name), "priority": int(definition.priority), "exclusive_group": String(definition.get("exclusive_group", "")), "conditions": _array_value(definition.get("ending_conditions", [])), "condition_evidence": evidence.duplicate(true), "event_id": String(definition.id), "start_node_id": String(definition.start_node_id)}

func _definition_by_id(id: String) -> Dictionary:
	for definition in ending_definitions:
		if String(definition.get("id", "")) == id:
			return definition
	return {}

func _has_exclusive_group(entries: Array, group: String) -> bool:
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("exclusive_group", "")) == group:
			return true
	return false

func _group_rank(group: String) -> int:
	if group == "primary":
		return 0
	if group.is_empty():
		return 1
	return 2

func _primary_ending_id(entries: Array) -> String:
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("exclusive_group", "")) == "primary":
			return String(entry.id)
	return String(entries[0].id) if not entries.is_empty() else ""

func _snapshot(state) -> Dictionary:
	if state == null:
		return {}
	if state is Dictionary:
		return state.duplicate(true)
	if state.has_method("to_dictionary"):
		return state.to_dictionary()
	return {}

func _meta_records(meta_state) -> Array:
	if meta_state == null:
		return []
	var value = meta_state.get("ending_records") if meta_state.has_method("get") else []
	return _array_value(value)

func _set_meta_records(meta_state, records: Array) -> void:
	if meta_state == null:
		return
	if meta_state is Dictionary:
		meta_state["ending_records"] = records
	else:
		meta_state.set("ending_records", records)

static func _validate_ending(event: Dictionary) -> Dictionary:
	for field in ["ending_key", "priority", "exclusive_group", "ending_conditions"]:
		if not event.has(field):
			return _fail("invalid_ending_route", "Ending event is missing field %s: %s" % [field, event.get("id", "")])
	if typeof(event.ending_conditions) != TYPE_ARRAY:
		return _fail("invalid_ending_route", "Ending conditions must be an array: %s" % event.id)
	return {"ok": true}

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
