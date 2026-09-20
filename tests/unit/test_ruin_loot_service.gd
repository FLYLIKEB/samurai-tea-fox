extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CraftingService = preload("res://src/crafting/crafting_service.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RuinLootService = preload("res://src/world/interactions/ruin_loot_service.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "ruin loot loads generated catalog")
	_assert_each_ruin_category_is_lootable_once(asserts, catalog)
	_assert_starter_cloth_crafts_one_bandage_per_run(asserts, catalog)
	_assert_inventory_failure_does_not_consume_ruin(asserts, catalog)

func _assert_each_ruin_category_is_lootable_once(asserts, catalog) -> void:
	var fixture := _fixture(catalog)
	var service := RuinLootService.new()
	for index in range(3):
		var target_id := "abandoned_house_%d" % index
		var result: Dictionary = service.loot(target_id, 11037, "common_region", catalog, fixture.inventory, fixture.state)
		var interaction_key := RuinLootService.state_key("common_region", target_id)
		asserts.true_value(result.ok, "%s grants a loot reward" % target_id)
		asserts.equal(String(result.category), ["material", "armor", "tea"][index], "%s uses the expected reward category" % target_id)
		asserts.equal(fixture.state.world_interactions[interaction_key].state, "looted", "%s persists its consumed state in run storage" % target_id)
		asserts.equal(fixture.inventory.get_total_quantity(String(result.item_id)), 2 if index == 0 else 1, "%s grants the recorded quantity" % target_id)
		var duplicate: Dictionary = service.loot(target_id, 11037, "common_region", catalog, fixture.inventory, fixture.state)
		asserts.false_value(duplicate.ok, "%s cannot be searched twice" % target_id)
		asserts.equal(String(duplicate.reason), "already_looted", "%s reports its persisted consumed state" % target_id)
		var other_biome: Dictionary = service.loot(target_id, 11037, "mountain_region", catalog, fixture.inventory, fixture.state)
		asserts.true_value(other_biome.ok, "%s remains searchable in another biome" % target_id)

func _assert_starter_cloth_crafts_one_bandage_per_run(asserts, catalog) -> void:
	var service := RuinLootService.new()
	var fixture := _fixture(catalog)
	var reward: Dictionary = service.loot("abandoned_house_0", 11037, "common_region", catalog, fixture.inventory, fixture.state)
	asserts.equal([reward.item_id, reward.quantity], ["cloth", 2], "first common-region abandoned house guarantees one bandage worth of cloth")
	var crafting_result: Dictionary = CraftingService.from_catalog(catalog)
	asserts.true_value(crafting_result.ok, "starter cloth scenario configures crafting")
	var crafted: Dictionary = crafting_result.crafting_service.craft("bandage", fixture.inventory, {"unlocked_biome_ids": ["common_region"]})
	asserts.true_value(crafted.ok, "guaranteed cloth crafts the hand-made bandage")
	asserts.equal(fixture.inventory.get_total_quantity("cloth"), 0, "bandage crafting consumes both cloth")
	asserts.equal(fixture.inventory.get_total_quantity("bandage"), 1, "bandage crafting stores one bandage")

	var fresh_run := _fixture(catalog)
	var fresh_reward: Dictionary = service.loot("abandoned_house_0", 11037, "common_region", catalog, fresh_run.inventory, fresh_run.state)
	asserts.equal([fresh_reward.item_id, fresh_reward.quantity], ["cloth", 2], "fresh run resets the one-time starter cloth reward")

func _assert_inventory_failure_does_not_consume_ruin(asserts, catalog) -> void:
	var fixture := _fixture(catalog)
	asserts.true_value(fixture.inventory.load_snapshot({"schema_version": 1, "data_version": catalog.data_version, "slot_count": 1, "next_instance_id": 1, "slots": [{"item_id": "short_travel_sword", "quantity": 1, "instance_id": "instance_1", "metadata": {}}]}).ok, "capacity fixture fills the only inventory slot")
	var result: Dictionary = RuinLootService.new().loot("abandoned_house_0", 11037, "common_region", catalog, fixture.inventory, fixture.state)
	asserts.false_value(result.ok, "full inventory rejects the ruin reward")
	asserts.false_value(fixture.state.world_interactions.has(RuinLootService.state_key("common_region", "abandoned_house_0")), "failed reward does not consume the abandoned house")

func _fixture(catalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	var state := RunState.new()
	state.seed = 11037
	state.current_biome_id = "common_region"
	return {"inventory": inventory_result.inventory, "state": state}
