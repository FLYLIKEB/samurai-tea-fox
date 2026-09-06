extends RefCounted
class_name RunStartEventSelector

const FIRST_RUN_HOOK_KEY := "dialogue.prologue.call_father"
const RETURN_FATHER_HOOK_PREFIX := "dialogue.run_return.father_"
const RETURN_TRIGGER_TIMING := "반복 런"

var candidates: Array = []

func configure(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Run-start event selection requires a data catalog.")
	candidates.clear()
	var canonical_candidates: Array = []
	var configured_candidates: Array = []
	for event in catalog.get_definitions("events"):
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var canonical := _candidate_from_source_lines(event)
		if not canonical.ok:
			return canonical
		if bool(canonical.get("found", false)):
			canonical_candidates.append(canonical.candidate)
		var config = event.get("run_start", {})
		if typeof(config) != TYPE_DICTIONARY or config.is_empty():
			continue
		var parsed := _candidate_from_event(event, config)
		if not parsed.ok:
			return parsed
		configured_candidates.append(parsed.candidate)
	for candidate in canonical_candidates:
		candidates.append(candidate)
	for candidate in configured_candidates:
		if not _range_is_owned_by_canonical(candidate, canonical_candidates):
			candidates.append(candidate)
	if candidates.is_empty():
		return _fail("missing_run_start_events", "No narrative events declare run_start metadata.")
	candidates.sort_custom(_sort_candidates)
	return {"ok": true, "selector": self}

func _candidate_from_source_lines(event: Dictionary) -> Dictionary:
	var event_id := String(event.get("id", ""))
	if event_id.is_empty():
		return _fail("missing_event_id", "Run-start source event is missing an id.")
	var source_lines = event.get("source_lines", [])
	if typeof(source_lines) != TYPE_ARRAY:
		return {"ok": true, "found": false}
	for source_line in source_lines:
		if typeof(source_line) != TYPE_DICTIONARY:
			continue
		var hook_key := String(source_line.get("hook_key", ""))
		if hook_key == FIRST_RUN_HOOK_KEY:
			return {"ok": true, "found": true, "candidate": _source_candidate(event_id, 0, 0)}
		if (
			String(source_line.get("trigger_timing", "")) == RETURN_TRIGGER_TIMING
			and hook_key.begins_with(RETURN_FATHER_HOOK_PREFIX)
		):
			var run_range := _run_count_range(String(source_line.get("trigger_condition", "")))
			if not run_range.ok:
				return run_range
			return {"ok": true, "found": true, "candidate": _source_candidate(
				event_id,
				int(run_range.min_run_count),
				int(run_range.max_run_count)
			)}
	return {"ok": true, "found": false}

func _source_candidate(event_id: String, min_run_count: int, max_run_count: int) -> Dictionary:
	return {
		"event_id": event_id,
		"min_run_count": min_run_count,
		"max_run_count": max_run_count,
		"priority": 0,
		"presentation_kind": "dialogue",
		"father_physical_actor": false,
	}

func _run_count_range(condition: String) -> Dictionary:
	var min_run_count := 0
	var max_run_count := -1
	var found_bound := false
	for raw_clause in condition.replace(" ", "").split("&&"):
		var clause := String(raw_clause)
		if not clause.begins_with("meta.run_count"):
			return _fail("invalid_run_start_condition", "Unsupported canonical run-start condition '%s'." % condition)
		var comparison := clause.trim_prefix("meta.run_count")
		var operator := ""
		for candidate_operator in [">=", "<=", "==", ">", "<"]:
			if comparison.begins_with(candidate_operator):
				operator = candidate_operator
				break
		if operator.is_empty():
			return _fail("invalid_run_start_condition", "Canonical run-start condition '%s' has no supported comparison." % condition)
		var raw_value := comparison.trim_prefix(operator)
		if not raw_value.is_valid_int():
			return _fail("invalid_run_start_condition", "Canonical run-start condition '%s' has a non-integer bound." % condition)
		var value := int(raw_value)
		if value < 0:
			return _fail("invalid_run_start_condition", "Canonical run-start condition '%s' has a negative bound." % condition)
		found_bound = true
		match operator:
			">=": min_run_count = maxi(min_run_count, value)
			">": min_run_count = maxi(min_run_count, value + 1)
			"<=": max_run_count = value if max_run_count < 0 else mini(max_run_count, value)
			"<": max_run_count = value - 1 if max_run_count < 0 else mini(max_run_count, value - 1)
			"==":
				min_run_count = maxi(min_run_count, value)
				max_run_count = value if max_run_count < 0 else mini(max_run_count, value)
	if not found_bound or (max_run_count >= 0 and max_run_count < min_run_count):
		return _fail("invalid_run_start_condition", "Canonical run-start condition '%s' resolves to an invalid range." % condition)
	return {"ok": true, "min_run_count": min_run_count, "max_run_count": max_run_count}

func _range_is_owned_by_canonical(candidate: Dictionary, canonical_candidates: Array) -> bool:
	for canonical in canonical_candidates:
		if (
			int(candidate.min_run_count) == int(canonical.min_run_count)
			and int(candidate.max_run_count) == int(canonical.max_run_count)
		):
			return true
	return false

func select_event(run_state, meta_state := {}, force_first_run := false) -> Dictionary:
	var meta := _meta_query(meta_state)
	var run_count := 0 if force_first_run else int(meta.get("run_count", 0))
	for candidate in candidates:
		if not _run_count_matches(candidate, run_count):
			continue
		if _event_count(run_state, String(candidate.event_id)) > 0:
			continue
		var result: Dictionary = candidate.duplicate(true)
		result["ok"] = true
		result["meta_run_count"] = run_count
		return result
	return _fail("no_start_event_candidate", "No run-start narrative event matched the current meta state.")

func _candidate_from_event(event: Dictionary, config: Dictionary) -> Dictionary:
	var event_id := String(event.get("id", ""))
	if event_id.is_empty():
		return _fail("missing_event_id", "Run-start event candidate is missing an id.")
	var min_run_count: Dictionary = _optional_non_negative_int(config, "min_run_count", 0)
	if not min_run_count.ok:
		return min_run_count
	var max_run_count: Dictionary = _optional_non_negative_int(config, "max_run_count", -1)
	if not max_run_count.ok:
		return max_run_count
	var priority: Dictionary = _optional_non_negative_int(config, "priority", 999)
	if not priority.ok:
		return priority
	if int(max_run_count.value) >= 0 and int(max_run_count.value) < int(min_run_count.value):
		return _fail("invalid_run_start_range", "Run-start event '%s' has max_run_count lower than min_run_count." % event_id)
	return {"ok": true, "candidate": {
		"event_id": event_id,
		"min_run_count": int(min_run_count.value),
		"max_run_count": int(max_run_count.value),
		"priority": int(priority.value),
		"presentation_kind": String(config.get("presentation_kind", "dialogue")),
		"father_physical_actor": bool(config.get("father_physical_actor", false))
	}}

func _optional_non_negative_int(config: Dictionary, key: String, fallback: int) -> Dictionary:
	if not config.has(key) or config.get(key) == null:
		return {"ok": true, "value": fallback}
	var value = config.get(key)
	if typeof(value) == TYPE_INT and int(value) >= 0:
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))) and float(value) >= 0.0:
		return {"ok": true, "value": int(value)}
	return _fail("invalid_run_start_metadata", "Run-start metadata '%s' must be a non-negative integer." % key)

func _run_count_matches(candidate: Dictionary, run_count: int) -> bool:
	if run_count < int(candidate.min_run_count):
		return false
	var max_run_count := int(candidate.max_run_count)
	return max_run_count < 0 or run_count <= max_run_count

func _sort_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_min := int(left.min_run_count)
	var right_min := int(right.min_run_count)
	if left_min != right_min:
		return left_min > right_min
	return int(left.priority) < int(right.priority)

func _meta_query(meta_state) -> Dictionary:
	if meta_state == null:
		return {}
	if meta_state is Dictionary:
		return meta_state
	if meta_state.has_method("to_dictionary"):
		return meta_state.to_dictionary()
	return {}

func _event_count(run_state, event_id: String) -> int:
	if run_state == null:
		return 0
	var data: Dictionary = {}
	if run_state is Dictionary:
		data = run_state
	elif run_state.has_method("to_dictionary"):
		data = run_state.to_dictionary()
	return int(data.get("narrative_event_counts", {}).get(event_id, 0))

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
