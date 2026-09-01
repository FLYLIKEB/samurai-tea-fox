extends RefCounted
class_name SaveStore

const SaveCodec = preload("res://src/save/save_codec.gd")

const DEFAULT_RUN_PATH := "user://run.save.json"
const DEFAULT_META_PATH := "user://meta.save.json"

var run_path: String
var meta_path: String
var _replace_operation: Callable

func _init(
	run_save_path: String = DEFAULT_RUN_PATH,
	meta_save_path: String = DEFAULT_META_PATH,
	replace_operation: Callable = Callable()
) -> void:
	run_path = run_save_path
	meta_path = meta_save_path
	_replace_operation = replace_operation

func save_run(run_state) -> Dictionary:
	return _write_envelope(run_path, SaveCodec.encode_run(run_state))

func save_meta(meta_state) -> Dictionary:
	return _write_envelope(meta_path, SaveCodec.encode_meta(meta_state))

func load_run() -> Dictionary:
	var loaded := _read_envelope(run_path)
	if not loaded.ok:
		return loaded
	return SaveCodec.decode_run(loaded.envelope)

func load_meta() -> Dictionary:
	var loaded := _read_envelope(meta_path)
	if not loaded.ok:
		return loaded
	return SaveCodec.decode_meta(loaded.envelope)

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

func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
