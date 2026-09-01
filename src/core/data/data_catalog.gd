extends RefCounted
class_name DataCatalog

const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")

const FILES := {
	"balance": "balance.json",
	"biomes": "biomes.json",
	"teas": "teas.json",
	"items": "items.json",
	"recipes": "recipes.json",
	"monsters": "monsters.json",
	"abilities": "abilities.json",
	"meta_unlocks": "meta_unlocks.json"
}

var data_version := ""
var sources: Dictionary = {}
var definitions: Dictionary = {}

func load_from_directory(directory: String) -> Dictionary:
	var validator := DataSchemaValidator.new()
	definitions.clear()
	sources.clear()
	data_version = ""

	for key in FILES.keys():
		var path := "%s/%s" % [directory, FILES[key]]
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "Missing generated data file: %s" % path}

		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		var validation := validator.validate_export_file(parsed, path)
		if not validation.ok:
			return validation

		if data_version == "":
			data_version = parsed.data_version
		elif data_version != parsed.data_version:
			return {"ok": false, "error": "Mismatched data_version in %s" % path}

		sources[key] = parsed.source
		definitions[key] = parsed.items

	return {"ok": true}

func get_definitions(key: String) -> Array:
	return definitions.get(key, [])

func find_by_id(key: String, id: String) -> Dictionary:
	for item in get_definitions(key):
		if item.get("id", "") == id:
			return item
	return {}

func find_balance_value(id: String, fallback := 0.0) -> float:
	var item := find_by_id("balance", id)
	if item.is_empty():
		return fallback
	return float(item.get("value", fallback))

