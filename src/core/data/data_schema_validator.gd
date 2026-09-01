extends RefCounted
class_name DataSchemaValidator

func validate_export_file(value, path: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "%s is not a JSON object." % path}
	for key in ["schema_version", "data_version", "profile", "source", "content_hash", "items"]:
		if not value.has(key):
			return {"ok": false, "error": "%s is missing '%s'." % [path, key]}
	if int(value.schema_version) != 1:
		return {"ok": false, "error": "%s has unsupported schema_version '%s'." % [path, value.schema_version]}
	if typeof(value.data_version) != TYPE_STRING or value.data_version.is_empty():
		return {"ok": false, "error": "%s 'data_version' must be a non-empty string." % path}
	if typeof(value.profile) != TYPE_STRING or value.profile.is_empty():
		return {"ok": false, "error": "%s 'profile' must be a non-empty string." % path}
	if typeof(value.source) != TYPE_STRING or value.source.is_empty():
		return {"ok": false, "error": "%s 'source' must be a non-empty string." % path}
	if typeof(value.content_hash) != TYPE_STRING or value.content_hash.length() != 64:
		return {"ok": false, "error": "%s 'content_hash' must be a SHA-256 hex string." % path}
	var hash_pattern := RegEx.new()
	hash_pattern.compile("^[0-9a-f]{64}$")
	if hash_pattern.search(value.content_hash) == null:
		return {"ok": false, "error": "%s 'content_hash' must be a SHA-256 hex string." % path}
	if typeof(value.items) != TYPE_ARRAY:
		return {"ok": false, "error": "%s 'items' must be an array." % path}
	var ids: Dictionary = {}
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]*$")
	for item in value.items:
		if typeof(item) != TYPE_DICTIONARY:
			return {"ok": false, "error": "%s contains a non-object item." % path}
		if not item.has("id") or typeof(item.id) != TYPE_STRING or item.id.is_empty():
			return {"ok": false, "error": "%s contains an item without a stable id." % path}
		if id_pattern.search(item.id) == null:
			return {"ok": false, "error": "%s contains invalid stable id '%s'." % [path, item.id]}
		if ids.has(item.id):
			return {"ok": false, "error": "%s contains duplicate id '%s'." % [path, item.id]}
		ids[item.id] = true
	return {"ok": true}

func validate_catalog(definitions: Dictionary, dataset_rules: Dictionary) -> Dictionary:
	var ids_by_dataset: Dictionary = {}
	for dataset_name in definitions:
		var ids: Dictionary = {}
		for item in definitions[dataset_name]:
			ids[item.id] = true
		ids_by_dataset[dataset_name] = ids

	for dataset_name in definitions:
		var config: Dictionary = dataset_rules.get(dataset_name, {})
		var required_fields: Array = config.get("required_fields", ["id", "name", "status"])
		var relations: Dictionary = config.get("relations", {})
		for item in definitions[dataset_name]:
			for required_field in required_fields:
				if not item.has(required_field) or item[required_field] == null:
					return {"ok": false, "error": "%s item '%s' is missing required field '%s'." % [dataset_name, item.id, required_field]}
				if typeof(item[required_field]) == TYPE_STRING and item[required_field].is_empty():
					return {"ok": false, "error": "%s item '%s' is missing required field '%s'." % [dataset_name, item.id, required_field]}
			for field in relations:
				if not item.has(field) or item[field] == null:
					continue
				var relation_value = item[field]
				if typeof(relation_value) == TYPE_STRING and relation_value.is_empty():
					continue
				if typeof(relation_value) == TYPE_ARRAY and relation_value.is_empty():
					continue
				var target_dataset: String = relations[field]
				if not ids_by_dataset.has(target_dataset):
					return {"ok": false, "error": "%s item '%s' relation '%s' targets missing dataset '%s'." % [dataset_name, item.id, field, target_dataset]}
				var values: Array = relation_value if typeof(relation_value) == TYPE_ARRAY else [relation_value]
				for target_id in values:
					if not ids_by_dataset[target_dataset].has(target_id):
						return {"ok": false, "error": "%s item '%s' relation '%s' targets missing id '%s'." % [dataset_name, item.id, field, target_id]}
	if definitions.has("events"):
		var event_result := _validate_event_result_items(definitions.events, ids_by_dataset)
		if not event_result.ok:
			return event_result
	return {"ok": true}

func _validate_event_result_items(events: Array, ids_by_dataset: Dictionary) -> Dictionary:
	for event in events:
		var nodes = event.get("nodes", [])
		if typeof(nodes) != TYPE_ARRAY:
			continue
		for node in nodes:
			if typeof(node) != TYPE_DICTIONARY:
				continue
			var options = node.get("options", [])
			if typeof(options) != TYPE_ARRAY:
				continue
			for option in options:
				if typeof(option) != TYPE_DICTIONARY:
					continue
				var results = option.get("results", [])
				if typeof(results) != TYPE_ARRAY:
					continue
				for result in results:
					if typeof(result) != TYPE_DICTIONARY or String(result.get("type", "")) != "grant_item":
						continue
					if not ids_by_dataset.has("items"):
						return {"ok": false, "error": "events item '%s' option '%s' grant_item targets missing dataset 'items'." % [event.get("id", ""), option.get("id", "")]}
					var result_id := String(result.get("id", ""))
					if not ids_by_dataset.items.has(result_id):
						return {"ok": false, "error": "events item '%s' option '%s' grant_item targets missing item id '%s'." % [event.get("id", ""), option.get("id", ""), result_id]}
	return {"ok": true}
