extends RefCounted
class_name AssetCatalog

const DEFAULT_MANIFEST_PATH := "res://assets/asset-manifest.json"
const STABLE_ID_PATTERN := "^[a-z][a-z0-9_]*$"

var definitions: Dictionary = {}
var _asset_id_by_path: Dictionary = {}

func load_manifest(path := DEFAULT_MANIFEST_PATH) -> Dictionary:
	definitions.clear()
	_asset_id_by_path.clear()
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Missing asset manifest: %s" % path}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema_version") != 1:
		return {"ok": false, "error": "Invalid asset manifest: %s" % path}
	var assets = parsed.get("assets")
	if typeof(assets) != TYPE_ARRAY:
		return {"ok": false, "error": "Asset manifest assets must be an array: %s" % path}
	var id_pattern := RegEx.new()
	id_pattern.compile(STABLE_ID_PATTERN)
	var character_animation_ids: Dictionary = {}
	for definition in assets:
		if typeof(definition) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Asset manifest entry must be an object"}
		var asset_id = definition.get("id", "")
		var asset_path = definition.get("path", "")
		if typeof(asset_id) != TYPE_STRING or id_pattern.search(asset_id) == null:
			return {"ok": false, "error": "Invalid asset stable ID: %s" % asset_id}
		if definitions.has(asset_id):
			return {"ok": false, "error": "Duplicate asset stable ID: %s" % asset_id}
		if typeof(asset_path) != TYPE_STRING or not asset_path.begins_with("res://assets/"):
			return {"ok": false, "error": "Invalid asset path for %s" % asset_id}
		if definition.get("placeholder", true):
			return {"ok": false, "error": "Runtime placeholder is forbidden: %s" % asset_id}
		if not _texture_exists(asset_path):
			return {"ok": false, "error": "Missing asset file for %s: %s" % [asset_id, asset_path]}
		if _asset_id_by_path.has(asset_path):
			return {"ok": false, "error": "Duplicate asset path: %s" % asset_path}
		_asset_id_by_path[asset_path] = asset_id
		var character_id := String(definition.get("character_id", ""))
		var animation_id := String(definition.get("animation_id", ""))
		if not character_id.is_empty() or not animation_id.is_empty():
			if character_id.is_empty() or animation_id.is_empty():
				return {"ok": false, "error": "Character animation metadata is incomplete for %s" % asset_id}
			var animation_key := "%s:%s" % [character_id, animation_id]
			if character_animation_ids.has(animation_key):
				return {"ok": false, "error": "Duplicate character animation metadata: %s" % animation_key}
			character_animation_ids[animation_key] = asset_id
		definitions[asset_id] = definition.duplicate(true)
	return {"ok": true}

func has(id: String) -> bool:
	return definitions.has(id)

func definition_for(id: String) -> Dictionary:
	return definitions.get(id, {}).duplicate(true)

func path_for(id: String) -> String:
	return definitions.get(id, {}).get("path", "")

func id_for_path(path: String) -> String:
	var normalized := _normalize_asset_path(path)
	if normalized.is_empty():
		return ""
	return String(_asset_id_by_path.get(normalized, ""))

func path_for_reference(reference: String) -> String:
	if definitions.has(reference):
		return path_for(reference)
	return _normalize_asset_path(reference)

func id_for_reference(reference: String) -> String:
	if definitions.has(reference):
		return reference
	return id_for_path(reference)

func character_animation_id(character_id: String, animation_id: String) -> String:
	for asset_id in definitions:
		var definition: Dictionary = definitions[asset_id]
		if (
			String(definition.get("character_id", "")) == character_id
			and String(definition.get("animation_id", "")) == animation_id
		):
			return String(asset_id)
	return ""

func load_texture(id: String) -> Texture2D:
	var path := path_for(id)
	if path.is_empty():
		return null
	return load_texture_reference(path)

func load_texture_reference(reference: String) -> Texture2D:
	var path := path_for_reference(reference)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func audit_references(references: Array) -> Dictionary:
	var used := {}
	var missing := []
	for reference in references:
		var asset_id := id_for_reference(String(reference))
		if asset_id.is_empty():
			missing.append(String(reference))
		else:
			used[asset_id] = true
	var unused := []
	for asset_id in definitions.keys():
		if not used.has(asset_id):
			unused.append(asset_id)
	unused.sort()
	return {
		"used_asset_ids": used.keys(),
		"missing_references": missing,
		"unused_asset_ids": unused
	}

func _normalize_asset_path(path: String) -> String:
	if path.begins_with("res://assets/"):
		return path
	if path.begins_with("assets/"):
		return "res://%s" % path
	return ""

func _texture_exists(path: String) -> bool:
	return ResourceLoader.exists(path, "Texture2D") or FileAccess.file_exists(path)
