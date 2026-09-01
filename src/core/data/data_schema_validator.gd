extends RefCounted
class_name DataSchemaValidator

func validate_export_file(value, path: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "%s is not a JSON object." % path}
	for key in ["data_version", "source", "items"]:
		if not value.has(key):
			return {"ok": false, "error": "%s is missing '%s'." % [path, key]}
	if typeof(value.items) != TYPE_ARRAY:
		return {"ok": false, "error": "%s 'items' must be an array." % path}
	for item in value.items:
		if typeof(item) != TYPE_DICTIONARY:
			return {"ok": false, "error": "%s contains a non-object item." % path}
		if not item.has("id"):
			return {"ok": false, "error": "%s contains an item without id." % path}
	return {"ok": true}

