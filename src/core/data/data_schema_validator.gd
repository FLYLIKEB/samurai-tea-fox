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
			var item_result := _validate_item_contract(dataset_name, item)
			if not item_result.ok:
				return item_result
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
		var event_result := _validate_event_result_references(definitions.events, ids_by_dataset)
		if not event_result.ok:
			return event_result
	return {"ok": true}

func _validate_event_result_references(events: Array, ids_by_dataset: Dictionary) -> Dictionary:
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
					if typeof(result) != TYPE_DICTIONARY:
						continue
					var result_type := String(result.get("type", ""))
					if result_type == "apply_choice":
						if not ids_by_dataset.has("choices"):
							return {"ok": false, "error": "events item '%s' option '%s' apply_choice targets missing dataset 'choices'." % [event.get("id", ""), option.get("id", "")]}
						var choice_id := String(result.get("id", ""))
						if not ids_by_dataset.choices.has(choice_id):
							return {"ok": false, "error": "events item '%s' option '%s' apply_choice targets missing choice id '%s'." % [event.get("id", ""), option.get("id", ""), choice_id]}
						continue
					if result_type != "grant_item":
						continue
					if not ids_by_dataset.has("items"):
						return {"ok": false, "error": "events item '%s' option '%s' grant_item targets missing dataset 'items'." % [event.get("id", ""), option.get("id", "")]}
					var result_id := String(result.get("id", ""))
					if not ids_by_dataset.items.has(result_id):
						return {"ok": false, "error": "events item '%s' option '%s' grant_item targets missing item id '%s'." % [event.get("id", ""), option.get("id", ""), result_id]}
	return {"ok": true}

func _validate_item_contract(dataset_name: String, item: Dictionary) -> Dictionary:
	if dataset_name == "drops":
		return _validate_drop_contract(item)
	if dataset_name == "choices":
		return _validate_choice_contract(item)
	if dataset_name == "shops":
		return _validate_shop_contract(item)
	if dataset_name == "meta_unlocks":
		return _validate_meta_unlock_contract(item)
	if dataset_name != "items":
		return {"ok": true}
	if String(item.get("type", "")) != "다구" or String(item.get("equipment_slot", "")) != "다구":
		return {"ok": true}
	return _validate_attachment_stage_data(item)


func _validate_meta_unlock_contract(item: Dictionary) -> Dictionary:
	var condition_type := String(item.get("condition_event", ""))
	if not ["event_seen", "cumulative_event_count_at_least", "run_count_at_least", "best_biome_order_at_least", "value_at_least"].has(condition_type):
		return {"ok": false, "error": "meta_unlocks item '%s' has unknown condition_event '%s'." % [item.id, condition_type]}
	var reward_kind := String(item.get("reward_kind", ""))
	if not ["unlock_flag", "dialogue_memory_flag", "discovered_record"].has(reward_kind):
		return {"ok": false, "error": "meta_unlocks item '%s' has unknown reward_kind '%s'." % [item.id, reward_kind]}
	if String(item.get("condition_target", "")).is_empty():
		return {"ok": false, "error": "meta_unlocks item '%s' condition_target must be non-empty." % item.id}
	if String(item.get("reward_target", "")).is_empty():
		return {"ok": false, "error": "meta_unlocks item '%s' reward_target must be non-empty." % item.id}
	var threshold = item.get("threshold", 1)
	if typeof(threshold) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(threshold)) or float(threshold) != floor(float(threshold)) or int(threshold) < 0:
		return {"ok": false, "error": "meta_unlocks item '%s' threshold must be a non-negative integer." % item.id}
	var reward_quantity = item.get("reward_quantity", 1)
	if typeof(reward_quantity) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(reward_quantity)) or float(reward_quantity) != floor(float(reward_quantity)) or int(reward_quantity) <= 0:
		return {"ok": false, "error": "meta_unlocks item '%s' reward_quantity must be a positive integer." % item.id}
	return {"ok": true}

func _validate_shop_contract(item: Dictionary) -> Dictionary:
	if not item.has("item_id") and not item.has("tea_id"):
		return {"ok": false, "error": "shops item '%s' requires exactly one of item_id or tea_id." % item.id}
	var has_item := not String(item.get("item_id", "")).is_empty()
	var has_tea := not String(item.get("tea_id", "")).is_empty()
	if has_item == has_tea:
		return {"ok": false, "error": "shops item '%s' requires exactly one of item_id or tea_id." % item.id}
	if typeof(item.get("can_sell")) != TYPE_BOOL:
		return {"ok": false, "error": "shops item '%s' can_sell must be a boolean." % item.id}
	for field in ["buy_price", "sell_price", "stock_quantity", "min_progress_stage"]:
		var value = item.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)):
			return {"ok": false, "error": "shops item '%s' field '%s' must be an integer." % [item.id, field]}
	if int(item.buy_price) <= 0 or int(item.sell_price) <= 0:
		return {"ok": false, "error": "shops item '%s' prices must be positive." % item.id}
	if int(item.stock_quantity) < 0 or int(item.min_progress_stage) < 0:
		return {"ok": false, "error": "shops item '%s' stock and progress must be non-negative." % item.id}
	return {"ok": true}

func _validate_drop_contract(item: Dictionary) -> Dictionary:
	var has_item := not String(item.get("item_id", "")).is_empty()
	var has_tea := not String(item.get("tea_id", "")).is_empty()
	if has_item == has_tea:
		return {"ok": false, "error": "drops item '%s' requires exactly one of item_id or tea_id." % item.id}
	for field in ["min_quantity", "max_quantity"]:
		var value = item.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)):
			return {"ok": false, "error": "drops item '%s' field '%s' must be an integer." % [item.id, field]}
	var minimum := int(item.min_quantity)
	var maximum := int(item.max_quantity)
	if minimum <= 0 or maximum < minimum:
		return {"ok": false, "error": "drops item '%s' quantity range must be positive and ordered." % item.id}
	var chance = item.get("chance")
	if typeof(chance) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(chance)) or float(chance) < 0.0 or float(chance) > 1.0:
		return {"ok": false, "error": "drops item '%s' chance must be between zero and one." % item.id}
	return {"ok": true}

func _validate_choice_contract(item: Dictionary) -> Dictionary:
	for field in ["meta_record", "target_survives"]:
		if typeof(item.get(field)) != TYPE_BOOL:
			return {"ok": false, "error": "choices item '%s' field '%s' must be a boolean." % [item.id, field]}
	if typeof(item.get("philosophy_marks")) != TYPE_ARRAY:
		return {"ok": false, "error": "choices item '%s' philosophy_marks must be an array." % item.id}
	var run_flag := String(item.get("run_flag", ""))
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]*$")
	if id_pattern.search(run_flag) == null:
		return {"ok": false, "error": "choices item '%s' has invalid run_flag '%s'." % [item.id, run_flag]}
	return {"ok": true}

func _validate_attachment_stage_data(item: Dictionary) -> Dictionary:
	for field in ["attachment_stage_thresholds", "attachment_description_keys"]:
		if not item.has(field) or item[field] == null:
			return {"ok": false, "error": "items item '%s' is missing required field '%s'." % [item.id, field]}
		if typeof(item[field]) != TYPE_ARRAY or item[field].size() < 3:
			return {"ok": false, "error": "items item '%s' field '%s' must contain at least 3 stages." % [item.id, field]}
	var thresholds: Array = item.attachment_stage_thresholds
	var description_keys: Array = item.attachment_description_keys
	if description_keys.size() < thresholds.size():
		return {"ok": false, "error": "items item '%s' attachment_description_keys must cover every threshold." % item.id}
	var previous := -1
	for threshold in thresholds:
		if typeof(threshold) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(threshold)) or float(threshold) != floor(float(threshold)):
			return {"ok": false, "error": "items item '%s' attachment_stage_thresholds must contain integers." % item.id}
		var value := int(threshold)
		if value < 0 or value <= previous:
			return {"ok": false, "error": "items item '%s' attachment_stage_thresholds must be ascending non-negative integers." % item.id}
		previous = value
	for description_key in description_keys:
		if typeof(description_key) != TYPE_STRING or String(description_key).strip_edges().is_empty():
			return {"ok": false, "error": "items item '%s' attachment_description_keys must contain non-empty strings." % item.id}
	return {"ok": true}
