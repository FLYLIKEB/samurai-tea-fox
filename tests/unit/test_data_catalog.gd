extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")

const TEST_DIRECTORY := "user://dev16_data_catalog_tests"

func run(asserts) -> void:
	_cleanup_test_directory()
	var catalog := DataCatalog.new()
	var result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(result.ok, "generated Notion export files load: %s" % result.get("error", ""))
	asserts.equal(catalog.data_version, "notion-2026-09-01", "data version is pinned")
	asserts.equal(int(catalog.find_balance_value("player_hp_max")), 100, "player HP max comes from balance data")
	asserts.equal(catalog.find_by_id("biomes", "common_region").name, "일반 지역", "common biome is present")
	asserts.equal(catalog.find_by_id("events", "roadside_teahouse_intro").get("replay_policy", ""), "once", "narrative event definitions are present")
	asserts.equal(catalog.find_by_id("choices", "daimyo_relinquish_tea").get("choice_key", ""), "DAIMYO_RELINQUISH_TEA", "choice result definitions are present")
	asserts.equal(catalog.sources.get("drops", ""), "collection://362e7813-5332-420b-aca0-fb2824dbcce0", "authoritative drop table source is registered")
	asserts.equal(catalog.find_by_id("drops", "drop_1").get("item_id", ""), "item_33", "drop relation resolves to generated item stable ID")
	asserts.equal(catalog.sources.get("shops", ""), "collection://3f6354ff-02fb-4b92-9b81-9f821ae6408b", "authoritative shop table source is registered")
	asserts.equal(catalog.get_definitions("shops").size(), 14, "all authoritative shop rows load")
	asserts.equal(catalog.find_by_id("shops", "shop_14").get("sell_price", 0), 25, "shop sell price is explicit generated data")
	asserts.equal(catalog.sources.get("dungeons", ""), "collection://cd97553c-f51f-44fe-9604-c257cc9d9342", "authoritative dungeon table source is registered")
	asserts.equal(catalog.find_by_id("dungeons", "dungeon_4").get("name", ""), "오리베의 다실", "canonical common dungeon row loads")
	asserts.equal(catalog.get_definitions("bosses").size(), 2, "two boss runtime sample definitions are present")
	asserts.equal(catalog.find_by_id("bosses", "sample_bamboo_guardian").get("dungeon_id", ""), "dungeon_4", "boss definition keeps its canonical dungeon id")
	asserts.equal(catalog.sources.get("characters", ""), "collection://86d9c16b-e60e-4434-9c84-26b4b00d16c8", "authoritative character memory policy source is registered")
	asserts.true_value(catalog.character_has_meta_memory("CHR-1"), "Muchau's father may observe previous-run memory")
	asserts.true_value(catalog.character_has_meta_memory("CHR-5"), "Sen Rikyu may observe previous-run memory")
	asserts.false_value(catalog.character_has_meta_memory("CHR-2"), "ordinary characters may not observe previous-run memory")
	asserts.false_value(catalog.character_has_meta_memory("unknown_character"), "unknown characters may not observe previous-run memory")

	_create_generated_fixture_without_characters()
	var missing_characters := DataCatalog.new().load_from_directory(TEST_DIRECTORY)
	asserts.false_value(missing_characters.ok, "characters.json is required generated policy data")
	if not missing_characters.ok:
		asserts.true_value("Missing generated data file" in missing_characters.error, "missing character policy reports a generated file error")
		asserts.true_value("characters.json" in missing_characters.error, "missing character policy error names characters.json")
	_cleanup_test_directory()

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

	var missing_boss_dungeon := validator.validate_catalog({
		"dungeons": [{"id": "dungeon_4"}],
		"biomes": [{"id": "common_region"}],
		"items": [{"id": "oribe_green_glazed_bowl"}],
		"monsters": [{"id": "road_bandit"}],
		"bosses": [_boss_definition({"dungeon_id": "missing_dungeon"})]
	}, {
		"dungeons": {"required_fields": ["id"]},
		"biomes": {"required_fields": ["id"]},
		"items": {"required_fields": ["id"]},
		"monsters": {"required_fields": ["id"]},
		"bosses": {"required_fields": ["id"], "relations": {"dungeon_id": "dungeons", "biome_id": "biomes", "reward_item_ids": "items", "summon_monster_ids": "monsters"}}
	})
	asserts.false_value(missing_boss_dungeon.ok, "boss dungeon_id relation must target a loaded dungeon definition")
	if not missing_boss_dungeon.ok:
		asserts.true_value("missing_dungeon" in missing_boss_dungeon.error, "boss dungeon relation error names the missing id")

	var missing_nested_summon := validator.validate_catalog({
		"dungeons": [{"id": "dungeon_4"}],
		"biomes": [{"id": "common_region"}],
		"items": [{"id": "oribe_green_glazed_bowl"}],
		"monsters": [{"id": "road_bandit"}],
		"bosses": [_boss_definition({"nested_summon_id": "missing_monster"})]
	}, {
		"dungeons": {"required_fields": ["id"]},
		"biomes": {"required_fields": ["id"]},
		"items": {"required_fields": ["id"]},
		"monsters": {"required_fields": ["id"]},
		"bosses": {"required_fields": ["id"], "relations": {"dungeon_id": "dungeons", "biome_id": "biomes", "reward_item_ids": "items", "summon_monster_ids": "monsters"}}
	})
	asserts.false_value(missing_nested_summon.ok, "nested summon monster IDs must resolve through the monsters catalog")
	if not missing_nested_summon.ok:
		asserts.true_value("missing_monster" in missing_nested_summon.error, "nested summon relation error names the missing monster")

	var boss_tea_rules := {
		"bosses": {"required_fields": ["id"]},
		"choices": {"required_fields": ["id"]},
		"teas": {"required_fields": ["id"]},
		"monsters": {"required_fields": ["id"]}
	}
	var valid_boss_tea := validator.validate_catalog({
		"bosses": [_boss_definition({"tea_resolution": _boss_tea_resolution()})],
		"choices": [_catalog_choice()],
		"teas": [{"id": "oribe_green_matcha"}],
		"monsters": [{"id": "road_bandit"}]
	}, boss_tea_rules)
	asserts.true_value(valid_boss_tea.ok, "boss tea nested references resolve through choices and teas")
	var missing_boss_choice := validator.validate_catalog({
		"bosses": [_boss_definition({"tea_resolution": _boss_tea_resolution()})],
		"choices": [],
		"teas": [{"id": "oribe_green_matcha"}],
		"monsters": [{"id": "road_bandit"}]
	}, boss_tea_rules)
	asserts.false_value(missing_boss_choice.ok, "boss tea choice_id must resolve through choices")
	if not missing_boss_choice.ok:
		asserts.true_value("fixture_share_tea" in missing_boss_choice.error, "boss tea choice relation names the missing choice")
	var missing_boss_tea := validator.validate_catalog({
		"bosses": [_boss_definition({"tea_resolution": _boss_tea_resolution()})],
		"choices": [_catalog_choice()],
		"teas": [],
		"monsters": [{"id": "road_bandit"}]
	}, boss_tea_rules)
	asserts.false_value(missing_boss_tea.ok, "boss required_tea_ids must resolve through teas")
	if not missing_boss_tea.ok:
		asserts.true_value("oribe_green_matcha" in missing_boss_tea.error, "boss tea relation names the missing tea")

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

	var invalid_drop := validator.validate_catalog({
		"monsters": [{"id": "road_bandit"}],
		"items": [{"id": "item_33"}],
		"teas": [{"id": "tea_8"}],
		"drops": [{"id": "drop_broken", "name": "broken", "status": "테스트", "monster_id": "road_bandit", "item_id": "item_33", "tea_id": "tea_8", "condition": "항상", "min_quantity": 1, "max_quantity": 1, "chance": 1.0}]
	}, {
		"monsters": {"required_fields": ["id"]},
		"items": {"required_fields": ["id"]},
		"teas": {"required_fields": ["id"]},
		"drops": {"required_fields": ["id"], "relations": {"monster_id": "monsters", "item_id": "items", "tea_id": "teas"}}
	})
	asserts.false_value(invalid_drop.ok, "drop definitions reject ambiguous item and tea targets")

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

func _boss_definition(overrides: Dictionary = {}) -> Dictionary:
	var nested_summon_id := String(overrides.get("nested_summon_id", "road_bandit"))
	var boss := {
		"id": "fixture_boss",
		"dungeon_id": "dungeon_4",
		"biome_id": "common_region",
		"reward_item_ids": ["oribe_green_glazed_bowl"],
		"summon_monster_ids": ["road_bandit"],
		"resolution_types": ["combat", "peaceful"],
		"phases": [{
			"id": "opening",
			"patterns": [{
				"id": "call",
				"interval_seconds": 1.0,
				"summon_monster_ids": [nested_summon_id]
			}]
		}]
	}
	for key in overrides:
		if key == "nested_summon_id":
			continue
		boss[key] = overrides[key]
	return boss

func _boss_tea_resolution() -> Dictionary:
	return {
		"choice_id": "fixture_share_tea",
		"required_tea_ids": ["oribe_green_matcha"],
		"peaceful_conditions": [{"type": "prepared_tea", "id": "oribe_green_matcha"}],
		"hooks": {"common": {"memory": ["memory.fixture_boss.met"]}}
	}

func _catalog_choice() -> Dictionary:
	return {
		"id": "fixture_share_tea",
		"run_flag": "fixture_shared_tea",
		"meta_record": false,
		"target_survives": true,
		"philosophy_marks": []
	}

func _create_generated_fixture_without_characters() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	for file_name in DataCatalog.FILES.values():
		if file_name == "characters.json":
			continue
		var target := FileAccess.open("%s/%s" % [TEST_DIRECTORY, file_name], FileAccess.WRITE)
		target.store_buffer(FileAccess.get_file_as_bytes("res://data/generated/%s" % file_name))
		target.close()

func _cleanup_test_directory() -> void:
	for file_name in DataCatalog.FILES.values():
		var path := "%s/%s" % [TEST_DIRECTORY, file_name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
