extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(result.ok, "generated Notion export files load: %s" % result.get("error", ""))
	asserts.equal(catalog.data_version, "notion-2026-09-01", "data version is pinned")
	asserts.equal(int(catalog.find_balance_value("player_hp_max")), 100, "player HP max comes from balance data")
	asserts.equal(catalog.find_by_id("biomes", "common_region").name, "일반 지역", "common biome is present")
	asserts.equal(catalog.find_by_id("events", "roadside_teahouse_intro").get("replay_policy", ""), "once", "narrative event definitions are present")
	asserts.equal(catalog.find_by_id("choices", "daimyo_relinquish_tea").get("choice_key", ""), "DAIMYO_RELINQUISH_TEA", "choice result definitions are present")

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

	var grant_without_items := validator.validate_catalog({
		"events": [_event_with_result({"type": "grant_item", "id": "tea_bowl", "quantity": 1})]
	}, {
		"events": {"required_fields": ["id"]}
	})
	asserts.false_value(grant_without_items.ok, "grant_item requires the items dataset in runtime catalog validation")
	if not grant_without_items.ok:
		asserts.true_value("items" in grant_without_items.error, "missing items dataset error names the dataset")

	var grant_missing_item := validator.validate_catalog({
		"items": [],
		"events": [_event_with_result({"type": "grant_item", "id": "tea_bowl", "quantity": 1})]
	}, {
		"items": {"required_fields": ["id"]},
		"events": {"required_fields": ["id"]}
	})
	asserts.false_value(grant_missing_item.ok, "grant_item result IDs must exist in runtime item definitions")
	if not grant_missing_item.ok:
		asserts.true_value("tea_bowl" in grant_missing_item.error, "missing grant item error names the result id")

	var flag_without_items := validator.validate_catalog({
		"events": [_event_with_result({"type": "set_run_flag", "id": "met_old_keeper"})]
	}, {
		"events": {"required_fields": ["id"]}
	})
	asserts.true_value(flag_without_items.ok, "set_run_flag-only events do not require items definitions")

	var choice_without_definitions := validator.validate_catalog({
		"events": [_event_with_result({"type": "apply_choice", "id": "missing_choice"})]
	}, {
		"events": {"required_fields": ["id"]}
	})
	asserts.false_value(choice_without_definitions.ok, "apply_choice requires the choices dataset")

	var invalid_choice := validator.validate_catalog({
		"choices": [{"id": "broken_choice", "name": "Broken", "status": "확정", "choice_key": "BROKEN_CHOICE"}]
	}, {
		"choices": {"required_fields": ["id", "name", "status", "choice_key", "run_flag", "display_text", "resolution", "meta_record", "target_survives", "philosophy_marks", "final_room_effect"]}
	})
	asserts.false_value(invalid_choice.ok, "choice definitions require the complete result contract")

	var short_attachment_description_result := validator.validate_catalog({
		"items": [{
			"id": "short_attachment_bowl",
			"name": "정붙음 부족 사발",
			"status": "테스트",
			"type": "다구",
			"equipment_slot": "다구",
			"attachment_stage_thresholds": [0, 3, 7, 12],
			"attachment_description_keys": [
				"items.short_attachment_bowl.attachment.stage_0",
				"items.short_attachment_bowl.attachment.stage_1",
				"items.short_attachment_bowl.attachment.stage_2"
			]
		}]
	}, {
		"items": {"required_fields": ["id", "name", "status"]}
	})
	asserts.false_value(short_attachment_description_result.ok, "attachment description keys must cover all thresholds")
	if not short_attachment_description_result.ok:
		asserts.true_value("short_attachment_bowl" in short_attachment_description_result.error, "attachment description error names the item")
		asserts.true_value("cover every threshold" in short_attachment_description_result.error, "attachment description error explains threshold coverage")

func _event_with_result(result: Dictionary) -> Dictionary:
	return {
		"id": "fixture_event",
		"nodes": [{
			"id": "start",
			"options": [{
				"id": "take",
				"results": [result],
				"next_node_id": "",
				"completes_event": true
			}]
		}]
	}
