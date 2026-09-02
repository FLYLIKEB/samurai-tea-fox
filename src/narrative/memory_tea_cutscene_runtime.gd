extends RefCounted
class_name MemoryTeaCutsceneRuntime

const SNAPSHOT_SCHEMA_VERSION := 1
const DISCOVERY_RECORD_ID := "memory_tea"
const META_EVENT_TYPE := "discovery"
const COMPLETE_REASON_COMPLETED := "completed"
const COMPLETE_REASON_SKIPPED := "skipped"

signal cutscene_started(sequence: Dictionary)
signal cutscene_finished(event: Dictionary)
signal operation_failed(error: Dictionary)

var data_version := ""
var active_sequence := {}
var completed_memory_event_ids := {}

func configure(new_data_version := "") -> Dictionary:
	data_version = new_data_version
	active_sequence = {}
	completed_memory_event_ids = {}
	return {"ok": true}

func start_from_drink_completion(completion_result: Dictionary, run_state, meta_state = null) -> Dictionary:
	var memory_result := _memory_payload_from_completion(completion_result)
	if not memory_result.ok:
		return _fail_and_emit(memory_result)
	if not memory_result.has_memory:
		return {"ok": true, "started": false, "reason": "tea_has_no_memory"}
	var payload: Dictionary = memory_result.payload
	var event_id := String(payload.event_id)
	if _has_discovered_event(run_state, meta_state, event_id):
		return {"ok": true, "started": false, "reason": "memory_already_discovered", "event_id": event_id, "discovery_record_id": DISCOVERY_RECORD_ID}
	if not active_sequence.is_empty():
		return _fail_and_emit(_fail("cutscene_already_active", "A memory tea cutscene is already active."))
	active_sequence = _build_sequence(payload)
	cutscene_started.emit(active_sequence.duplicate(true))
	return {"ok": true, "started": true, "sequence": active_sequence.duplicate(true)}

func complete_current(run_state, meta_state = null) -> Dictionary:
	return _finish_current(COMPLETE_REASON_COMPLETED, run_state, meta_state)

func skip_current(run_state, meta_state = null) -> Dictionary:
	return _finish_current(COMPLETE_REASON_SKIPPED, run_state, meta_state)

func to_snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"active_sequence": active_sequence.duplicate(true),
		"completed_memory_event_ids": completed_memory_event_ids.duplicate(true)
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported memory tea cutscene snapshot schema version.")
	var raw_active = snapshot.get("active_sequence", {})
	if typeof(raw_active) != TYPE_DICTIONARY:
		return _fail("invalid_active_sequence", "Memory tea cutscene active_sequence must be a dictionary.")
	var raw_completed = snapshot.get("completed_memory_event_ids", {})
	if typeof(raw_completed) != TYPE_DICTIONARY:
		return _fail("invalid_completed_events", "Memory tea cutscene completed events must be a dictionary.")
	if not raw_active.is_empty():
		var sequence_result := _validate_sequence(raw_active)
		if not sequence_result.ok:
			return sequence_result
	active_sequence = raw_active.duplicate(true)
	completed_memory_event_ids = raw_completed.duplicate(true)
	data_version = String(snapshot.get("data_version", data_version))
	return {"ok": true}

func _memory_payload_from_completion(completion_result: Dictionary) -> Dictionary:
	if not bool(completion_result.get("ok", false)) or not bool(completion_result.get("consumed", false)):
		return _fail("invalid_drink_completion", "Memory cutscene detection requires a consumed tea completion.")
	var effect = completion_result.get("effect", {})
	if typeof(effect) != TYPE_DICTIONARY:
		return _fail("invalid_tea_effect", "Tea completion effect must be a dictionary.")
	var memory = effect.get("memory", {})
	if typeof(memory) != TYPE_DICTIONARY or not bool(memory.get("has_memory", false)):
		return {"ok": true, "has_memory": false}
	var event_id := String(memory.get("event_id", ""))
	if not _is_stable_id(event_id):
		return _fail("invalid_memory_event_id", "Memory tea event id must be a stable id: %s" % event_id)
	var tea_id := String(memory.get("tea_id", ""))
	if not _is_stable_id(tea_id):
		return _fail("invalid_memory_tea_id", "Memory tea id must be a stable id: %s" % tea_id)
	var strength := int(memory.get("strength", 0))
	if strength <= 0:
		return _fail("invalid_memory_strength", "Memory tea strength must be positive.")
	var evidence := String(memory.get("evidence", ""))
	if evidence.strip_edges().is_empty():
		return _fail("missing_memory_evidence", "Memory tea evidence must be non-empty.")
	return {"ok": true, "has_memory": true, "payload": {
		"event_id": event_id,
		"tea_id": tea_id,
		"tea_name": String(memory.get("tea_name", tea_id)),
		"strength": strength,
		"evidence": evidence
	}}

func _build_sequence(payload: Dictionary) -> Dictionary:
	return {
		"sequence_id": "sequence_%s" % String(payload.event_id),
		"event_id": payload.event_id,
		"tea_id": payload.tea_id,
		"tea_name": payload.tea_name,
		"memory_strength": int(payload.strength),
		"memory_evidence": payload.evidence,
		"frames": [
			{"id": "steep", "text": "%s의 향이 오래된 기억을 불러온다." % String(payload.tea_name), "duration_seconds": 1.0},
			{"id": "memory", "text": String(payload.evidence), "duration_seconds": 2.0},
			{"id": "return", "text": "짧은 픽셀 기억이 心에 가라앉는다.", "duration_seconds": 1.0}
		]
	}

func _finish_current(reason: String, run_state, meta_state) -> Dictionary:
	if active_sequence.is_empty():
		return _fail_and_emit(_fail("no_active_cutscene", "No memory tea cutscene is active."))
	var event_id := String(active_sequence.event_id)
	var meta_event := {
		"type": META_EVENT_TYPE,
		"target": DISCOVERY_RECORD_ID,
		"event_id": event_id,
		"tea_id": String(active_sequence.tea_id),
		"memory_strength": int(active_sequence.memory_strength),
		"memory_evidence": String(active_sequence.memory_evidence),
		"completion_reason": reason
	}
	_record_discovery(run_state, meta_state, event_id)
	var finished := {
		"ok": true,
		"completed": reason == COMPLETE_REASON_COMPLETED,
		"skipped": reason == COMPLETE_REASON_SKIPPED,
		"sequence": active_sequence.duplicate(true),
		"discovery_record_id": DISCOVERY_RECORD_ID,
		"meta_events": [meta_event]
	}
	active_sequence = {}
	cutscene_finished.emit(finished.duplicate(true))
	return finished

func _has_discovered_event(run_state, meta_state, event_id: String) -> bool:
	if completed_memory_event_ids.has(event_id):
		return true
	if int(_run_event_counts(run_state).get(event_id, 0)) > 0:
		return true
	return false

func _record_discovery(run_state, meta_state, event_id: String) -> void:
	completed_memory_event_ids[event_id] = true
	_append_unique_to_run_array(run_state, "discovered_records", DISCOVERY_RECORD_ID)
	_append_unique_to_run_array(run_state, "discovered_records", event_id)
	var counts := _run_event_counts(run_state)
	counts[event_id] = max(1, int(counts.get(event_id, 0)))
	_set_run_event_counts(run_state, counts)
	if meta_state != null:
		_append_unique_to_meta_array(meta_state, "discovered_records", DISCOVERY_RECORD_ID)
		_append_unique_to_meta_array(meta_state, "discovered_records", event_id)

func _run_array(run_state, field: String) -> Array:
	if run_state == null:
		return []
	if run_state is Dictionary:
		var value = run_state.get(field, [])
		return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []
	var value = run_state.get(field) if run_state.has_method("get") else []
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func _run_event_counts(run_state) -> Dictionary:
	if run_state == null:
		return {}
	if run_state is Dictionary:
		var value = run_state.get("narrative_event_counts", {})
		return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
	var value = run_state.get("narrative_event_counts") if run_state.has_method("get") else {}
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func _set_run_event_counts(run_state, counts: Dictionary) -> void:
	if run_state == null:
		return
	if run_state is Dictionary:
		run_state["narrative_event_counts"] = counts.duplicate(true)
	else:
		run_state.narrative_event_counts = counts.duplicate(true)

func _meta_array(meta_state, field: String) -> Array:
	if meta_state == null:
		return []
	if meta_state is Dictionary:
		var value = meta_state.get(field, [])
		return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []
	var value = meta_state.get(field) if meta_state.has_method("get") else []
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func _append_unique_to_run_array(run_state, field: String, value: String) -> void:
	if run_state == null:
		return
	var values := _run_array(run_state, field)
	if not values.has(value):
		values.append(value)
	if run_state is Dictionary:
		run_state[field] = values
	else:
		run_state.set(field, values)

func _append_unique_to_meta_array(meta_state, field: String, value: String) -> void:
	if meta_state == null:
		return
	var values := _meta_array(meta_state, field)
	if not values.has(value):
		values.append(value)
	if meta_state is Dictionary:
		meta_state[field] = values
	else:
		meta_state.set(field, values)

func _array_contains(values: Array, value: String) -> bool:
	return values.has(value)

func _validate_sequence(sequence: Dictionary) -> Dictionary:
	for field in ["sequence_id", "event_id", "tea_id", "frames"]:
		if not sequence.has(field):
			return _fail("invalid_sequence", "Memory tea cutscene sequence is missing %s." % field)
	if not _is_stable_id(String(sequence.event_id)) or not _is_stable_id(String(sequence.tea_id)):
		return _fail("invalid_sequence", "Memory tea cutscene sequence has invalid stable ids.")
	if typeof(sequence.frames) != TYPE_ARRAY or sequence.frames.is_empty():
		return _fail("invalid_sequence", "Memory tea cutscene sequence frames must be non-empty.")
	return {"ok": true}

func _is_stable_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45
		if not allowed:
			return false
	return true

func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error
