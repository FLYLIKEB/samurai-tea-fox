extends RefCounted
class_name SaveStore

const SaveCodec = preload("res://src/save/save_codec.gd")

const DEFAULT_RUN_PATH := "user://run.save.json"
const DEFAULT_META_PATH := "user://meta.save.json"
const RUN_INVALIDATION_KIND := "run_invalidation"

var run_path: String
var meta_path: String
var _replace_operation: Callable
var _remove_operation: Callable

func _init(
	run_save_path: String = DEFAULT_RUN_PATH,
	meta_save_path: String = DEFAULT_META_PATH,
	replace_operation: Callable = Callable(),
	remove_operation: Callable = Callable()
) -> void:
	run_path = run_save_path
	meta_path = meta_save_path
	_replace_operation = replace_operation
	_remove_operation = remove_operation

func save_run(run_state) -> Dictionary:
	var validation := SaveCodec.validate_run_snapshot(run_state)
	if not validation.ok:
		return validation
	var stale_result := _validate_not_stale(validation.snapshot)
	if not stale_result.ok:
		return stale_result
	return _write_envelope(run_path, SaveCodec.encode_run(validation.snapshot))

func save_meta(meta_state) -> Dictionary:
	var validation := SaveCodec.validate_meta_snapshot(meta_state)
	if not validation.ok:
		return validation
	return _write_envelope(meta_path, SaveCodec.encode_meta(validation.snapshot))

func load_run() -> Dictionary:
	var loaded := _read_envelope(run_path)
	if not loaded.ok:
		return loaded
	var decoded := SaveCodec.decode_run(loaded.envelope)
	if not decoded.ok:
		return decoded
	var stale_result := _validate_not_stale(decoded.state)
	if not stale_result.ok:
		return stale_result
	return decoded

func load_meta() -> Dictionary:
	var loaded := _read_envelope(meta_path)
	if not loaded.ok:
		return loaded
	return SaveCodec.decode_meta(loaded.envelope)

func invalidate_run(run_state = null) -> Dictionary:
	var candidate_epoch := 0
	if run_state != null:
		var validation := SaveCodec.validate_run_snapshot(run_state)
		if not validation.ok:
			return validation
		candidate_epoch = int(validation.snapshot.get("lifecycle_epoch", 0))
	else:
		var loaded := _read_envelope(run_path)
		if loaded.ok:
			var decoded := SaveCodec.decode_run(loaded.envelope)
			if not decoded.ok:
				return decoded
			candidate_epoch = int(decoded.state.get("lifecycle_epoch", 0))

	var marker_result := _load_invalidation_marker()
	var invalidated_epoch := candidate_epoch
	var marker_exists: bool = bool(marker_result.ok)
	if marker_exists:
		invalidated_epoch = maxi(candidate_epoch, int(marker_result.marker.invalidated_lifecycle_epoch))
	elif String(marker_result.get("reason", "")) != "missing_invalidation":
		return marker_result

	if not marker_exists or invalidated_epoch > int(marker_result.marker.invalidated_lifecycle_epoch):
		var marker := {
			"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION,
			"kind": RUN_INVALIDATION_KIND,
			"invalidated_lifecycle_epoch": invalidated_epoch
		}
		var write_result := _write_envelope(_invalidation_path(), marker)
		if not write_result.ok:
			return write_result
	var run_removed := false
	if FileAccess.file_exists(run_path):
		var current_run_result := _read_envelope(run_path)
		if not current_run_result.ok:
			return current_run_result
		var current_run := SaveCodec.decode_run(current_run_result.envelope)
		if not current_run.ok:
			return current_run
		var current_epoch := int(current_run.state.get("lifecycle_epoch", 0))
		if current_epoch > invalidated_epoch:
			return {
				"ok": true,
				"state": "stale_invalidation_ignored",
				"invalidated_lifecycle_epoch": invalidated_epoch,
				"current_lifecycle_epoch": current_epoch,
				"current_run_snapshot": current_run.state,
				"current_run_state": current_run.run_state,
				"run_removed": false,
				"preserved_newer_run": true
			}
		var remove_error := _remove(run_path)
		if remove_error != OK:
			return _failure("Could not remove invalidated run save '%s': %s." % [run_path, error_string(remove_error)], "remove_failed")
		run_removed = true
	return {
		"ok": true,
		"state": "run_invalidated",
		"invalidated_lifecycle_epoch": invalidated_epoch,
		"run_removed": run_removed,
		"preserved_newer_run": false
	}

func _write_envelope(path: String, envelope: Dictionary) -> Dictionary:
	var directory_result := _ensure_parent_directory(path)
	if not directory_result.ok:
		return directory_result
	var temporary_path := "%s.tmp" % path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("Could not open temporary save file '%s': %s." % [temporary_path, error_string(FileAccess.get_open_error())])
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_present(temporary_path)
		return _failure("Could not write temporary save file '%s': %s." % [temporary_path, error_string(write_error)])
	var replace_error := _replace(temporary_path, path)
	if replace_error != OK:
		_remove_if_present(temporary_path)
		return _failure("Could not replace save file '%s': %s." % [path, error_string(replace_error)])
	return {"ok": true}

func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Save file does not exist: '%s'." % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open save file '%s': %s." % [path, error_string(FileAccess.get_open_error())])
	var json_text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _failure("Could not read save file '%s': %s." % [path, error_string(read_error)])
	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK:
		return _failure("Corrupt JSON in save file '%s' at line %d: %s." % [path, json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _failure("Malformed save envelope in '%s'." % path)
	return {"ok": true, "envelope": json.data}

func _ensure_parent_directory(path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var parent := absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(parent):
		return {"ok": true}
	var make_error := DirAccess.make_dir_recursive_absolute(parent)
	if make_error != OK:
		return _failure("Could not create save directory '%s': %s." % [parent, error_string(make_error)])
	return {"ok": true}

func _replace(from_path: String, to_path: String) -> int:
	if _replace_operation.is_valid():
		return int(_replace_operation.call(from_path, to_path))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))

func _remove(path: String) -> int:
	if _remove_operation.is_valid():
		return int(_remove_operation.call(path))
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _validate_not_stale(run_snapshot: Dictionary) -> Dictionary:
	var marker_result := _load_invalidation_marker()
	if not marker_result.ok:
		if String(marker_result.get("reason", "")) == "missing_invalidation":
			return {"ok": true}
		return marker_result
	var run_epoch := int(run_snapshot.get("lifecycle_epoch", 0))
	var invalidated_epoch := int(marker_result.marker.invalidated_lifecycle_epoch)
	if run_epoch <= invalidated_epoch:
		return _failure(
			"Run save lifecycle epoch %d is not newer than invalidated epoch %d." % [run_epoch, invalidated_epoch],
			"stale_run_save"
		)
	return {"ok": true}

func _load_invalidation_marker() -> Dictionary:
	var path := _invalidation_path()
	if not FileAccess.file_exists(path):
		return _failure("Run invalidation marker does not exist: '%s'." % path, "missing_invalidation")
	var loaded := _read_envelope(path)
	if not loaded.ok:
		return loaded
	var marker: Dictionary = loaded.envelope
	if int(marker.get("schema_version", -1)) != SaveCodec.CURRENT_SCHEMA_VERSION:
		return _failure("Unsupported run invalidation marker schema.", "invalid_invalidation_marker")
	if String(marker.get("kind", "")) != RUN_INVALIDATION_KIND:
		return _failure("Malformed run invalidation marker kind.", "invalid_invalidation_marker")
	if not marker.has("invalidated_lifecycle_epoch") or typeof(marker.invalidated_lifecycle_epoch) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("Malformed run invalidation marker epoch.", "invalid_invalidation_marker")
	return {"ok": true, "marker": marker}

func _invalidation_path() -> String:
	return run_path + ".invalidated.json"

func _failure(message: String, reason := "save_error") -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
