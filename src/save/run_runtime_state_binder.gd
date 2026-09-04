extends RefCounted
class_name RunRuntimeStateBinder

const RunState = preload("res://src/save/run_state.gd")

const FIELD := "field"
const RUNTIME := "runtime"
const ACTIVE := "active"
const CLEAR_WHEN_EMPTY_KEY := "clear_when_empty_key"

func snapshot_to_run_state(target_state, entries: Array) -> Dictionary:
	if not target_state is RunState:
		return _fail("invalid_run_state", "Run runtime snapshots require a RunState.")
	for entry in entries:
		var normalized := _normalized_entry(entry)
		if not bool(normalized.get("ok", true)):
			return normalized
		if not bool(normalized.get(ACTIVE, true)):
			continue
		var runtime = normalized[RUNTIME]
		if runtime == null:
			continue
		if not runtime.has_method("to_snapshot"):
			return _fail("invalid_runtime_snapshot", "Runtime '%s' does not expose to_snapshot." % normalized[FIELD])
		var snapshot = runtime.to_snapshot()
		if typeof(snapshot) != TYPE_DICTIONARY:
			return _fail("invalid_runtime_snapshot", "Runtime '%s' returned a malformed snapshot." % normalized[FIELD])
		var value: Dictionary = snapshot.duplicate(true)
		var clear_key := String(normalized.get(CLEAR_WHEN_EMPTY_KEY, ""))
		if not clear_key.is_empty() and value.has(clear_key) and _is_empty_value(value[clear_key]):
			value = {}
		target_state.set(String(normalized[FIELD]), value)
	return {"ok": true, "run_state": target_state, "snapshot": target_state.to_dictionary()}

func hydrate_from_run_state(source_state, entries: Array) -> Dictionary:
	if not source_state is RunState:
		return _fail("invalid_run_state", "Run runtime hydrate requires a RunState.")
	var normalized_entries := []
	var before_snapshots := {}
	for entry in entries:
		var normalized := _normalized_entry(entry)
		if not bool(normalized.get("ok", true)):
			return normalized
		if not bool(normalized.get(ACTIVE, true)):
			continue
		var runtime = normalized[RUNTIME]
		if runtime == null:
			continue
		if not runtime.has_method("to_snapshot") or not runtime.has_method("load_snapshot"):
			return _fail("invalid_runtime_hydrate", "Runtime '%s' must expose to_snapshot and load_snapshot." % normalized[FIELD])
		var before = runtime.to_snapshot()
		if typeof(before) != TYPE_DICTIONARY:
			return _fail("invalid_runtime_snapshot", "Runtime '%s' returned a malformed rollback snapshot." % normalized[FIELD])
		normalized_entries.append(normalized)
		before_snapshots[String(normalized[FIELD])] = before.duplicate(true)

	var applied_fields := []
	for normalized in normalized_entries:
		var field := String(normalized[FIELD])
		var desired = source_state.get(field)
		if _is_empty_value(desired):
			continue
		var runtime = normalized[RUNTIME]
		var hydrate_result = runtime.load_snapshot(_dictionary_value(desired))
		if typeof(hydrate_result) != TYPE_DICTIONARY or not bool(hydrate_result.get("ok", false)):
			var rollback := _rollback(normalized_entries, before_snapshots)
			var failure := _normalize_failure(hydrate_result, "Runtime '%s' rejected its saved snapshot." % field)
			failure["rollback_ok"] = bool(rollback.get("ok", false))
			if not bool(rollback.get("ok", false)):
				failure["rollback_error"] = rollback.get("error", "")
				failure["rollback_reason"] = rollback.get("reason", "")
			failure["applied_fields"] = applied_fields.duplicate()
			return failure
		applied_fields.append(field)

	var sync_result := snapshot_to_run_state(source_state, entries)
	if not sync_result.ok:
		var rollback := _rollback(normalized_entries, before_snapshots)
		sync_result["rollback_ok"] = bool(rollback.get("ok", false))
		return sync_result
	return {"ok": true, "run_state": source_state, "snapshot": sync_result.snapshot}

func _rollback(entries: Array, before_snapshots: Dictionary) -> Dictionary:
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		var field := String(entry[FIELD])
		var runtime = entry[RUNTIME]
		if runtime == null or not before_snapshots.has(field):
			continue
		var result = runtime.load_snapshot(_dictionary_value(before_snapshots[field]))
		if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
			return _normalize_failure(result, "Runtime '%s' rollback failed." % field)
	return {"ok": true}

func _normalized_entry(entry) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _fail("invalid_runtime_entry", "Run runtime binder entry must be a dictionary.")
	var field := String(entry.get(FIELD, ""))
	if field.is_empty():
		return _fail("invalid_runtime_entry", "Run runtime binder entry requires a field.")
	if not entry.has(RUNTIME):
		return _fail("invalid_runtime_entry", "Run runtime binder entry '%s' requires a runtime." % field)
	return entry.duplicate(true)

func _normalize_failure(result, fallback_error: String) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		var failure: Dictionary = result.duplicate(true)
		failure["ok"] = false
		if not failure.has("reason"):
			failure["reason"] = "runtime_hydrate_failed"
		if not failure.has("error"):
			failure["error"] = fallback_error
		return failure
	return _fail("runtime_hydrate_failed", fallback_error)

func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

func _is_empty_value(value) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			return value.is_empty()
		TYPE_ARRAY:
			return value.is_empty()
		TYPE_NIL:
			return true
	return false

func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
