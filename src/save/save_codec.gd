extends RefCounted
class_name SaveCodec

const RunState = preload("res://src/save/run_state.gd")
const MetaState = preload("res://src/save/meta_state.gd")

const CURRENT_SCHEMA_VERSION := 1
const RUN_KIND := "run"
const META_KIND := "meta"

const RUN_FIELD_TYPES := {
	"data_version": TYPE_STRING,
	"seed": TYPE_INT,
	"current_biome_id": TYPE_STRING,
	"inventory": TYPE_DICTIONARY,
	"equipment": TYPE_DICTIONARY,
	"currency": TYPE_INT,
	"trade_stock": TYPE_DICTIONARY,
	"tails": TYPE_INT,
	"abilities": TYPE_ARRAY,
	"completed_dungeon_ids": TYPE_ARRAY,
	"completed_runtime_dungeon_ids": TYPE_ARRAY,
	"dungeon_runtime_state": TYPE_DICTIONARY,
	"teleport_states": TYPE_DICTIONARY,
	"repaired_teleports": TYPE_ARRAY,
	"crafting_unlocks": TYPE_ARRAY,
	"narrative_flags": TYPE_ARRAY,
	"narrative_event_counts": TYPE_DICTIONARY,
	"consumables": TYPE_DICTIONARY,
	"choice_history": TYPE_ARRAY,
	"choice_group_selections": TYPE_DICTIONARY,
	"target_survival": TYPE_DICTIONARY,
	"philosophy_marks": TYPE_ARRAY,
	"final_room_effects": TYPE_ARRAY,
	"acquisitions": TYPE_DICTIONARY
}

const META_FIELD_TYPES := {
	"run_count": TYPE_INT,
	"best_reached_biome_order": TYPE_INT,
	"discovered_records": TYPE_ARRAY,
	"unlocked_meta_flags": TYPE_ARRAY,
	"dialogue_memory_flags": TYPE_ARRAY,
	"meta_unlock_counters": TYPE_DICTIONARY
}

const REQUIRED_FIELDS := {
	RUN_KIND: ["seed"],
	META_KIND: ["run_count"]
}

static func encode_run(run_state) -> Dictionary:
	var snapshot := _snapshot_for(run_state, RUN_KIND)
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"kind": RUN_KIND,
		"run": RunState.from_dictionary(snapshot).to_dictionary()
	}

static func encode_meta(meta_state) -> Dictionary:
	var snapshot := _snapshot_for(meta_state, META_KIND)
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"kind": META_KIND,
		"meta": MetaState.from_dictionary(snapshot).to_dictionary()
	}

static func validate_run_snapshot(run_state) -> Dictionary:
	return _validate_snapshot(run_state, RUN_KIND, RUN_FIELD_TYPES)

static func validate_meta_snapshot(meta_state) -> Dictionary:
	return _validate_snapshot(meta_state, META_KIND, META_FIELD_TYPES)

static func decode_run(save_data: Dictionary) -> Dictionary:
	var result := _decode_payload(save_data, RUN_KIND, RUN_FIELD_TYPES)
	if not result.ok:
		return result
	var run_state = RunState.from_dictionary(result.state)
	return {"ok": true, "state": run_state.to_dictionary(), "run_state": run_state}

static func decode_meta(save_data: Dictionary) -> Dictionary:
	var result := _decode_payload(save_data, META_KIND, META_FIELD_TYPES)
	if not result.ok:
		return result
	var meta_state = MetaState.from_dictionary(result.state)
	return {"ok": true, "state": meta_state.to_dictionary(), "meta_state": meta_state}

static func _decode_payload(save_data: Dictionary, expected_kind: String, field_types: Dictionary) -> Dictionary:
	var envelope_result := _validate_envelope(save_data, expected_kind)
	if not envelope_result.ok:
		return envelope_result
	var migration_result := _migrate_payload(int(save_data.schema_version), expected_kind, save_data[expected_kind])
	if not migration_result.ok:
		return migration_result
	var payload: Dictionary = migration_result.state
	for field in field_types:
		if not payload.has(field):
			return _failure("Missing required %s field '%s'." % [expected_kind, field])
		if field_types[field] == TYPE_INT and _is_integer_value(payload[field]):
			payload[field] = int(payload[field])
		elif typeof(payload[field]) != field_types[field]:
			return _failure("Malformed %s field '%s'." % [expected_kind, field])
	return {"ok": true, "state": payload.duplicate(true)}

static func _validate_envelope(save_data: Dictionary, expected_kind: String) -> Dictionary:
	if not save_data.has("schema_version"):
		return _failure("Missing save schema version.")
	if not _is_integer_value(save_data.schema_version):
		return _failure("Malformed save schema version.")
	if save_data.schema_version > CURRENT_SCHEMA_VERSION:
		return _failure("Unsupported future save schema version %d." % save_data.schema_version)
	if save_data.schema_version < 1:
		return _failure("Unsupported save schema version %d." % save_data.schema_version)
	if not save_data.has("kind"):
		return _failure("Missing save kind.")
	if save_data.get("kind", "") != expected_kind:
		return _failure("Expected %s save." % expected_kind)
	if not save_data.has(expected_kind):
		return _failure("Missing %s payload." % expected_kind)
	if not (save_data[expected_kind] is Dictionary):
		return _failure("Malformed %s payload." % expected_kind)
	return {"ok": true}

static func _migrate_payload(schema_version: int, kind: String, payload: Dictionary) -> Dictionary:
	match schema_version:
		1:
			var migrated := payload.duplicate(true)
			var defaults := RunState.new().to_dictionary() if kind == RUN_KIND else MetaState.new().to_dictionary()
			for field in defaults:
				if not migrated.has(field) and not field in REQUIRED_FIELDS[kind]:
					migrated[field] = defaults[field]
			return {"ok": true, "state": migrated}
	return _failure("Unsupported save schema version %d." % schema_version)

static func _validate_snapshot(state, kind: String, field_types: Dictionary) -> Dictionary:
	var snapshot_result := _snapshot_result_for(state, kind)
	if not snapshot_result.ok:
		return snapshot_result
	var snapshot: Dictionary = snapshot_result.snapshot
	for required_field in REQUIRED_FIELDS[kind]:
		if not snapshot.has(required_field):
			return _failure("Missing required %s field '%s'." % [kind, required_field])
	for field in snapshot:
		if not field_types.has(field):
			continue
		if field_types[field] == TYPE_INT and _is_integer_value(snapshot[field]):
			continue
		if typeof(snapshot[field]) != field_types[field]:
			return _failure("Malformed %s field '%s'." % [kind, field])
	return {"ok": true, "snapshot": snapshot.duplicate(true)}

static func _snapshot_for(state, kind: String) -> Dictionary:
	var result := _snapshot_result_for(state, kind)
	if result.ok:
		return result.snapshot
	push_error(result.error)
	return {}

static func _snapshot_result_for(state, kind: String) -> Dictionary:
	if state is Dictionary:
		return {"ok": true, "snapshot": state.duplicate(true)}
	if state is Object and state.has_method("to_dictionary"):
		var snapshot = state.to_dictionary()
		if snapshot is Dictionary:
			return {"ok": true, "snapshot": snapshot.duplicate(true)}
	return _failure("Cannot encode malformed %s state." % kind)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _is_integer_value(value) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_equal_approx(value, floor(value))
