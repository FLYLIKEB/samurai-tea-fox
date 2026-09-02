extends RefCounted
class_name TailState

const SOURCE_RUN_START := "run_start"
const SOURCE_CHOICE := "choice"
const SOURCE_EVENT := "event"
const SOURCE_SYSTEM := "system"
const PATH_HUMANITY := "humanity"
const PATH_YOKAI_NATURE := "yokai_nature"
const PATH_HARMONY := "harmony"
const VALID_PATH_FLAGS := [PATH_HUMANITY, PATH_YOKAI_NATURE, PATH_HARMONY]
const VALID_SOURCE_KINDS := [SOURCE_CHOICE, SOURCE_EVENT, SOURCE_SYSTEM, SOURCE_RUN_START]

var stage := 1
var tail_count := 1
var path_flags: Array[String] = []
var transition_history: Array = []

func _init(values := {}) -> void:
	var snapshot := values if typeof(values) == TYPE_DICTIONARY else {}
	stage = maxi(1, int(snapshot.get("stage", snapshot.get("tail_count", 1))))
	tail_count = stage
	path_flags = _string_array(snapshot.get("path_flags", []))
	transition_history = _history_array(snapshot.get("transition_history", []))
	if transition_history.is_empty():
		transition_history.append(_transition_record(SOURCE_RUN_START, SOURCE_RUN_START, "RUN_START", 1, []))
		if stage > 1:
			transition_history.append(_transition_record(SOURCE_SYSTEM, "state_initialization", "", stage, []))

static func from_dictionary(data: Dictionary) -> Dictionary:
	var validation := validate_dictionary(data)
	if not validation.ok:
		return validation
	return {"ok": true, "tail_state": load("res://src/player/tail_state.gd").new(data)}

static func default_dictionary() -> Dictionary:
	return load("res://src/player/tail_state.gd").new().to_dictionary()

static func from_tail_count(count: int) -> TailState:
	var normalized_count := maxi(1, count)
	var history := [_transition_record(SOURCE_RUN_START, SOURCE_RUN_START, "RUN_START", 1, [])]
	if normalized_count > 1:
		history.append(_transition_record(SOURCE_SYSTEM, "legacy_tail_count", "", normalized_count, []))
	return load("res://src/player/tail_state.gd").new({
		"stage": normalized_count,
		"tail_count": normalized_count,
		"transition_history": history
	})

static func validate_dictionary(data: Dictionary) -> Dictionary:
	var raw_stage = data.get("stage", data.get("tail_count", 1))
	if not _is_positive_integer(raw_stage):
		return _fail("invalid_tail_stage", "Tail stage must be a positive integer.")
	var raw_tail_count = data.get("tail_count", raw_stage)
	if not _is_positive_integer(raw_tail_count):
		return _fail("invalid_tail_count", "Tail count must be a positive integer.")
	if int(raw_tail_count) != int(raw_stage):
		return _fail("tail_stage_count_mismatch", "Tail count must mirror tail stage for run-scoped growth.")
	var raw_flags = data.get("path_flags", [])
	if typeof(raw_flags) != TYPE_ARRAY:
		return _fail("invalid_tail_path_flags", "Tail path flags must be an array.")
	for flag in raw_flags:
		if typeof(flag) != TYPE_STRING or not VALID_PATH_FLAGS.has(String(flag)):
			return _fail("invalid_tail_path_flag", "Tail path flag '%s' is not supported." % str(flag))
	var raw_history = data.get("transition_history", [])
	if typeof(raw_history) != TYPE_ARRAY:
		return _fail("invalid_tail_history", "Tail transition history must be an array.")
	if raw_history.is_empty():
		return _fail("invalid_tail_history_start", "Tail transition history must start at run stage one.")
	var previous_stage := 0
	for index in raw_history.size():
		var entry = raw_history[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("invalid_tail_history", "Tail transition history entries must be dictionaries.")
		if not _is_positive_integer(entry.get("stage", 0)):
			return _fail("invalid_tail_history", "Tail transition history entry has an invalid stage.")
		var entry_stage := int(entry.stage)
		if not entry.has("path_flags") or typeof(entry.path_flags) != TYPE_ARRAY:
			return _fail("invalid_tail_history_path_flags", "Tail transition history path flags must be an array.")
		for history_flag in entry.path_flags:
			if typeof(history_flag) != TYPE_STRING or not VALID_PATH_FLAGS.has(String(history_flag)):
				return _fail("invalid_tail_history_path_flag", "Tail transition history path flag '%s' is not supported." % str(history_flag))
		var source_kind := String(entry.get("source_kind", ""))
		if not VALID_SOURCE_KINDS.has(source_kind):
			return _fail("invalid_tail_source_kind", "Tail source kind '%s' is not supported." % source_kind)
		if index == 0 and (source_kind != SOURCE_RUN_START or entry_stage != 1):
			return _fail("invalid_tail_history_start", "Tail transition history must start at run stage one.")
		if entry_stage < previous_stage:
			return _fail("tail_history_stage_regression", "Tail transition history stages must not move backward.")
		if entry_stage > int(raw_stage):
			return _fail("tail_history_stage_exceeds_current", "Tail transition history stage cannot exceed the current stage.")
		var source_id := String(entry.get("source_id", ""))
		if source_id.is_empty() or not _is_stable_source_id(source_id):
			return _fail("invalid_tail_source_id", "Tail source id '%s' is not stable." % source_id)
		var source_key := String(entry.get("source_key", ""))
		if not source_key.is_empty() and not _is_stable_source_key(source_key):
			return _fail("invalid_tail_source_key", "Tail source key '%s' is not stable." % source_key)
		previous_stage = entry_stage
	return {"ok": true}

func apply_choice_result(choice: Dictionary) -> Dictionary:
	return _apply_result(SOURCE_CHOICE, String(choice.get("id", "")), String(choice.get("choice_key", "")), choice)

func apply_event_result(event: Dictionary) -> Dictionary:
	var source_id := String(event.get("id", event.get("event_id", "")))
	var source_key := String(event.get("event_key", ""))
	return _apply_result(SOURCE_EVENT, source_id, source_key, event)

func apply_transition(source_kind: String, source_id: String, target_stage: int, new_path_flags := [], source_key := "") -> Dictionary:
	if not VALID_SOURCE_KINDS.has(source_kind):
		return _fail("invalid_tail_source_kind", "Tail source kind '%s' is not supported." % source_kind)
	if source_id.is_empty() or not _is_stable_source_id(source_id):
		return _fail("invalid_tail_source_id", "Tail source id '%s' is not stable." % source_id)
	if not String(source_key).is_empty() and not _is_stable_source_key(String(source_key)):
		return _fail("invalid_tail_source_key", "Tail source key '%s' is not stable." % String(source_key))
	if target_stage < 1:
		return _fail("invalid_tail_stage", "Tail stage must be a positive integer.")
	if target_stage < stage:
		return _fail("tail_stage_regression", "Tail stage cannot move backward from %d to %d." % [stage, target_stage])
	var normalized_flags_result := _normalized_path_flags(new_path_flags)
	if not normalized_flags_result.ok:
		return normalized_flags_result
	var added_flags: Array[String] = []
	for flag in normalized_flags_result.flags:
		if not path_flags.has(String(flag)):
			path_flags.append(String(flag))
			added_flags.append(String(flag))
	if target_stage == stage:
		var changed := not added_flags.is_empty()
		if changed:
			transition_history.append(_transition_record(source_kind, source_id, String(source_key), stage, added_flags))
		return {
			"ok": true,
			"advanced": false,
			"changed": changed,
			"stage": stage,
			"tail_count": tail_count,
			"path_flags": path_flags.duplicate()
		}
	stage = target_stage
	tail_count = target_stage
	transition_history.append(_transition_record(source_kind, source_id, String(source_key), stage, added_flags))
	return {
		"ok": true,
		"advanced": true,
		"changed": true,
		"stage": stage,
		"tail_count": tail_count,
		"path_flags": path_flags.duplicate()
	}

func can_use_ability(_ability_id: String, tail_requirement: int) -> bool:
	return tail_requirement <= tail_count

func candidate_ability_ids(ability_definitions: Dictionary) -> Array:
	var ids := []
	for ability_id in ability_definitions.keys():
		var definition = ability_definitions[ability_id]
		var requirement := int(definition.tail_requirement) if definition != null and definition.get("tail_requirement") != null else int(definition.get("tail_requirement", 0))
		if can_use_ability(String(ability_id), requirement):
			ids.append(String(ability_id))
	ids.sort()
	return ids

func projection() -> Dictionary:
	return {
		"stage": stage,
		"tail_count": tail_count,
		"path_flags": path_flags.duplicate(),
		"transition_history": transition_history.duplicate(true)
	}

func to_run_summary() -> Dictionary:
	return {
		"tail_stage": stage,
		"tail_state": to_dictionary(),
		"meta_events": [{"type": "tail_stage_reached", "target": "tail_stage", "value": stage}]
	}

func to_dictionary() -> Dictionary:
	return {
		"stage": stage,
		"tail_count": tail_count,
		"path_flags": path_flags.duplicate(),
		"transition_history": transition_history.duplicate(true)
	}

func _apply_result(source_kind: String, source_id: String, source_key: String, result: Dictionary) -> Dictionary:
	if not result.has("tail_stage") and not result.has("tail_path_flags") and not result.has("path_flags"):
		return {"ok": true, "advanced": false, "changed": false, "stage": stage, "tail_count": tail_count}
	var target_stage := int(result.get("tail_stage", stage))
	var flags = result.get("tail_path_flags", result.get("path_flags", []))
	return apply_transition(source_kind, source_id, target_stage, flags, source_key)

static func _transition_record(source_kind: String, source_id: String, source_key: String, record_stage: int, flags: Array) -> Dictionary:
	return {
		"source_kind": source_kind,
		"source_id": source_id,
		"source_key": source_key,
		"stage": record_stage,
		"path_flags": flags.duplicate()
	}

static func _normalized_path_flags(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _fail("invalid_tail_path_flags", "Tail path flags must be an array.")
	var flags: Array[String] = []
	for flag in value:
		if typeof(flag) != TYPE_STRING or not VALID_PATH_FLAGS.has(String(flag)):
			return _fail("invalid_tail_path_flag", "Tail path flag '%s' is not supported." % str(flag))
		_append_unique(flags, String(flag))
	return {"ok": true, "flags": flags}

static func _string_array(value) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		if typeof(item) == TYPE_STRING:
			output.append(String(item))
	return output

static func _history_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var output: Array = []
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item.duplicate(true)
		entry["stage"] = int(entry.get("stage", 1))
		entry["path_flags"] = _string_array(entry.get("path_flags", []))
		output.append(entry)
	return output

static func _append_unique(values: Array, value: String) -> void:
	if value.is_empty() or values.has(value):
		return
	values.append(value)

static func _is_positive_integer(value) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 1
	return typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))) and int(value) >= 1

static func _is_stable_source_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*$")
	return regex.search(value) != null

static func _is_stable_source_key(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Z][A-Z0-9_]*$")
	return regex.search(value) != null

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
