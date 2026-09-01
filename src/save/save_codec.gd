extends RefCounted
class_name SaveCodec

const RunState = preload("res://src/save/run_state.gd")

const CURRENT_SCHEMA_VERSION := 1

static func encode_run(run_state: Dictionary) -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"kind": "run",
		"run": run_state
	}

static func encode_meta(meta_state: Dictionary) -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"kind": "meta",
		"meta": meta_state
	}

static func decode_run(save_data: Dictionary) -> Dictionary:
	var result := _validate(save_data, "run")
	if not result.ok:
		return result
	return {"ok": true, "state": save_data.run, "run_state": RunState.from_dictionary(save_data.run)}

static func decode_meta(save_data: Dictionary) -> Dictionary:
	var result := _validate(save_data, "meta")
	if not result.ok:
		return result
	return {"ok": true, "state": save_data.meta}

static func _validate(save_data: Dictionary, expected_kind: String) -> Dictionary:
	if save_data.get("schema_version", -1) != CURRENT_SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported save schema version."}
	if save_data.get("kind", "") != expected_kind:
		return {"ok": false, "error": "Expected %s save." % expected_kind}
	if not save_data.has(expected_kind):
		return {"ok": false, "error": "Missing %s payload." % expected_kind}
	if not (save_data[expected_kind] is Dictionary):
		return {"ok": false, "error": "Malformed %s payload." % expected_kind}
	return {"ok": true}
