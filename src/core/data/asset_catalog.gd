extends RefCounted
class_name AssetCatalog

const DEFAULT_MANIFEST_PATH := "res://assets/asset-manifest.json"
const STABLE_ID_PATTERN := "^[a-z][a-z0-9_]*$"

var definitions: Dictionary = {}

func load_manifest(path := DEFAULT_MANIFEST_PATH) -> Dictionary:
	definitions.clear()
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
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _texture_exists(path: String) -> bool:
	return ResourceLoader.exists(path, "Texture2D") or FileAccess.file_exists(path)
