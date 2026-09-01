extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(result.ok, "generated Notion export files load")
	asserts.equal(catalog.data_version, "notion-2026-09-01", "data version is pinned")
	asserts.equal(int(catalog.find_balance_value("player_hp_max")), 100, "player HP max comes from balance data")
	asserts.equal(catalog.find_by_id("biomes", "common_region").name, "일반 지역", "common biome is present")

	var validator := DataSchemaValidator.new()
	var duplicate_result := validator.validate_export_file({
		"schema_version": 1,
		"data_version": "fixture-v1",
		"profile": "confirmed",
		"source": "collection://fixture",
		"content_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"items": [{"id": "same"}, {"id": "same"}]
	}, "fixture.json")
	asserts.false_value(duplicate_result.ok, "duplicate stable IDs are rejected before runtime use")
	if not duplicate_result.ok:
		asserts.true_value("duplicate id 'same'" in duplicate_result.error, "duplicate ID error names the conflicting stable ID")

	var legacy_result := validator.validate_export_file({
		"data_version": "fixture-v1",
		"source": "collection://fixture",
		"items": []
	}, "legacy.json")
	asserts.false_value(legacy_result.ok, "unversioned export files are rejected")
	if not legacy_result.ok:
		asserts.true_value("schema_version" in legacy_result.error, "schema version error is explicit")

	var relation_result := validator.validate_catalog({
		"items": [{"id": "wood"}],
		"recipes": [{"id": "broken_recipe", "result_item_id": "missing_item"}]
	}, {
		"items": {"required_fields": ["id"]},
		"recipes": {"required_fields": ["id"], "relations": {"result_item_id": "items"}}
	})
	asserts.false_value(relation_result.ok, "broken cross-dataset relations are rejected")
	if not relation_result.ok:
		asserts.true_value("broken_recipe" in relation_result.error, "relation error names the source item")
		asserts.true_value("missing_item" in relation_result.error, "relation error names the missing target")

	var required_result := validator.validate_catalog({
		"balance": [{"id": "player_hp_max", "name": "플레이어 HP 최대치", "status": "확정"}]
	}, {
		"balance": {"required_fields": ["id", "name", "status", "value"]}
	})
	asserts.false_value(required_result.ok, "dataset-specific required fields are enforced at runtime")
	if not required_result.ok:
		asserts.true_value("player_hp_max" in required_result.error, "required field error names the item")
		asserts.true_value("value" in required_result.error, "required field error names the field")
