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
var schema_version := 0
var profile := ""
var sources: Dictionary = {}
var definitions: Dictionary = {}

func load_from_directory(directory: String) -> Dictionary:
	var validator := DataSchemaValidator.new()
	definitions.clear()
	sources.clear()
	data_version = ""
	schema_version = 0
	profile = ""

	var schema_path := "res://data/schemas/export_schema.json"
	var export_schema = JSON.parse_string(FileAccess.get_file_as_string(schema_path))
	if typeof(export_schema) != TYPE_DICTIONARY or typeof(export_schema.get("datasets")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid export schema: %s" % schema_path}

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
			schema_version = parsed.schema_version
			profile = parsed.profile
		elif data_version != parsed.data_version:
			return {"ok": false, "error": "Mismatched data_version in %s" % path}
		elif schema_version != parsed.schema_version:
			return {"ok": false, "error": "Mismatched schema_version in %s" % path}
		elif profile != parsed.profile:
			return {"ok": false, "error": "Mismatched profile in %s" % path}

		sources[key] = parsed.source
		definitions[key] = parsed.items

	return validator.validate_catalog(definitions, export_schema.datasets)

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
