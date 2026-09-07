extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RuinLootService = preload("res://src/world/interactions/ruin_loot_service.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "ruin loot loads generated catalog")
	_assert_each_ruin_category_is_lootable_once(asserts, catalog)
	_assert_inventory_failure_does_not_consume_ruin(asserts, catalog)

func _assert_each_ruin_category_is_lootable_once(asserts, catalog) -> void:
	var fixture := _fixture(catalog)
	var service := RuinLootService.new()
	for index in range(3):
		var target_id := "abandoned_house_%d" % index
		var result: Dictionary = service.loot(target_id, 11037, "common_region", catalog, fixture.inventory, fixture.state)
		asserts.true_value(result.ok, "%s grants a loot reward" % target_id)
		asserts.equal(String(result.category), ["weapon", "armor", "tea"][index], "%s rotates the available reward categories" % target_id)
		asserts.equal(fixture.state.world_interactions[target_id].state, "looted", "%s persists its consumed state in run storage" % target_id)
		asserts.equal(fixture.inventory.get_total_quantity(String(result.item_id)), 1, "%s grants the recorded item" % target_id)
		var duplicate: Dictionary = service.loot(target_id, 11037, "common_region", catalog, fixture.inventory, fixture.state)
		asserts.false_value(duplicate.ok, "%s cannot be searched twice" % target_id)
		asserts.equal(String(duplicate.reason), "already_looted", "%s reports its persisted consumed state" % target_id)

func _assert_inventory_failure_does_not_consume_ruin(asserts, catalog) -> void:
	var fixture := _fixture(catalog)
	asserts.true_value(fixture.inventory.load_snapshot({"schema_version": 1, "data_version": catalog.data_version, "slot_count": 1, "next_instance_id": 1, "slots": [{"item_id": "short_travel_sword", "quantity": 1, "instance_id": "instance_1", "metadata": {}}]}).ok, "capacity fixture fills the only inventory slot")
	var result: Dictionary = RuinLootService.new().loot("abandoned_house_0", 11037, "common_region", catalog, fixture.inventory, fixture.state)
	asserts.false_value(result.ok, "full inventory rejects the ruin reward")
	asserts.false_value(fixture.state.world_interactions.has("abandoned_house_0"), "failed reward does not consume the abandoned house")

func _fixture(catalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	var state := RunState.new()
	state.seed = 11037
	state.current_biome_id = "common_region"
	return {"inventory": inventory_result.inventory, "state": state}
