extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RepairInteractionService = preload("res://src/world/interactions/repair_interaction_service.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

const TARGET_ID := "wasteland_abandoned_workbench"
const REPAIR_ACTION := "repair_abandoned_workbench"
const RECYCLE_ACTION := "recycle_abandoned_workbench"

class ReleaseFailureWorld:
	extends RefCounted
	var reservation := {"owner_id": TARGET_ID, "origin": {"x": 1, "y": 0}, "metadata": {}}

	func get_reservation(owner_id: String) -> Dictionary:
		return reservation.duplicate(true) if owner_id == TARGET_ID else {}

	func release_footprint(_owner_id: String) -> bool:
		return false

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "repair interaction loads generated catalog")
	_assert_exported_definition_matches_notion_contract(asserts, catalog)
	_assert_repair_success_and_duplicate_rejection(asserts, catalog)
	_assert_recycle_success_capacity_and_cross_rejection(asserts, catalog)
	_assert_failure_paths_are_atomic(asserts, catalog)
	_assert_saved_state_restore_is_definition_bounded(asserts, catalog)

func _assert_exported_definition_matches_notion_contract(asserts, catalog: DataCatalog) -> void:
	var hammer: Dictionary = catalog.find_by_id("items", "repair_hammer")
	var definition: Dictionary = hammer.get("interaction_definition", {})
	asserts.equal(String(definition.get("required_tool_item_id", "")), "repair_hammer", "repair hammer interaction requires the hammer tool")
	asserts.false_value(bool(definition.get("tool_consumed", true)), "repair hammer interaction does not consume the tool")
	asserts.equal(String(definition.get("target", {}).get("definition_id", "")), TARGET_ID, "repair hammer targets the abandoned wasteland workbench")
	asserts.equal(_item_quantities(definition.get("actions", [])[0].materials), {"old_wood": 2, "item_28": 1}, "repair costs the confirmed old wood and iron scrap quantities")
	asserts.equal(_item_quantities(definition.get("actions", [])[1].result.inventory_items), {"old_wood": 2, "item_28": 1}, "recycle grants the confirmed output quantities")

func _assert_repair_success_and_duplicate_rejection(asserts, catalog: DataCatalog) -> void:
	var fixture := _fixture(catalog)
	_stock(fixture.inventory, {"repair_hammer": 1, "old_wood": 2, "item_28": 1})
	var result: Dictionary = fixture.service.handle_command(REPAIR_ACTION, TARGET_ID, fixture.inventory, fixture.run_state, fixture.world_data, "wasteland")
	asserts.true_value(result.ok, "repair action succeeds with tool, unlock, and materials")
	asserts.equal(fixture.inventory.get_total_quantity("repair_hammer"), 1, "repair action keeps the reusable tool")
	asserts.equal(fixture.inventory.get_total_quantity("old_wood"), 0, "repair action consumes old wood")
	asserts.equal(fixture.inventory.get_total_quantity("item_28"), 0, "repair action consumes iron scrap")
	asserts.equal(fixture.run_state.world_interactions[TARGET_ID].state, "repaired", "repair action records repaired target state")
	asserts.equal(fixture.run_state.placed_facilities[0].facility_item_id, "wooden_workbench", "repair action enables the fixed wooden workbench")
	var after_repair := _snapshot(fixture)
	asserts.false_value(fixture.service.handle_command(REPAIR_ACTION, TARGET_ID, fixture.inventory, fixture.run_state, fixture.world_data, "wasteland").ok, "duplicate repair is rejected")
	asserts.false_value(fixture.service.handle_command(RECYCLE_ACTION, TARGET_ID, fixture.inventory, fixture.run_state, fixture.world_data, "wasteland").ok, "recycle after repair is rejected")
	asserts.equal(_snapshot(fixture), after_repair, "duplicate and cross actions do not mutate repaired state")

func _assert_recycle_success_capacity_and_cross_rejection(asserts, catalog: DataCatalog) -> void:
	var fixture := _fixture(catalog)
	_stock(fixture.inventory, {"repair_hammer": 1})
	var result: Dictionary = fixture.service.handle_command(RECYCLE_ACTION, TARGET_ID, fixture.inventory, fixture.run_state, fixture.world_data, "wasteland")
	asserts.true_value(result.ok, "recycle action succeeds with tool and capacity")
	asserts.equal(fixture.inventory.get_total_quantity("repair_hammer"), 1, "recycle action keeps the reusable tool")
	asserts.equal(fixture.inventory.get_total_quantity("old_wood"), 2, "recycle action grants old wood")
	asserts.equal(fixture.inventory.get_total_quantity("item_28"), 1, "recycle action grants iron scrap")
	asserts.equal(fixture.run_state.world_interactions[TARGET_ID].state, "recycled", "recycle action records recycled target state")
	asserts.true_value(fixture.world_data.get_reservation(TARGET_ID).is_empty(), "recycle action depletes the world target")
	var after_recycle := _snapshot(fixture)
	asserts.false_value(fixture.service.handle_command(REPAIR_ACTION, TARGET_ID, fixture.inventory, fixture.run_state, fixture.world_data, "wasteland").ok, "repair after recycle is rejected")
	asserts.equal(_snapshot(fixture), after_recycle, "cross action does not mutate recycled state")

	var full_fixture := _fixture(catalog)
	asserts.true_value(full_fixture.inventory.load_snapshot({"schema_version": 1, "data_version": "", "slot_count": 1, "next_instance_id": 1, "slots": [{"item_id": "repair_hammer", "quantity": 1, "instance_id": "", "metadata": {}}]}).ok, "capacity fixture loads one occupied slot")
	var before_capacity := _snapshot(full_fixture)
	var capacity_result: Dictionary = full_fixture.service.handle_command(RECYCLE_ACTION, TARGET_ID, full_fixture.inventory, full_fixture.run_state, full_fixture.world_data, "wasteland")
	asserts.false_value(capacity_result.ok, "recycle checks output capacity before mutating")
	asserts.equal(_snapshot(full_fixture), before_capacity, "capacity failure leaves inventory, target, and run state unchanged")

	var release_failure := _fixture(catalog)
	_stock(release_failure.inventory, {"repair_hammer": 1})
	var before_release := _snapshot(release_failure)
	var release_result: Dictionary = release_failure.service.handle_command(RECYCLE_ACTION, TARGET_ID, release_failure.inventory, release_failure.run_state, ReleaseFailureWorld.new(), "wasteland")
	asserts.false_value(release_result.ok, "recycle fails when target depletion cannot be applied")
	asserts.equal(_snapshot(release_failure), before_release, "target depletion failure rolls inventory and run state back")

func _assert_failure_paths_are_atomic(asserts, catalog: DataCatalog) -> void:
	var locked := _fixture(catalog)
	locked.run_state.crafting_unlocks = []
	_stock(locked.inventory, {"repair_hammer": 1, "old_wood": 2, "item_28": 1})
	var before_locked := _snapshot(locked)
	asserts.false_value(locked.service.handle_command(REPAIR_ACTION, TARGET_ID, locked.inventory, locked.run_state, locked.world_data, "wasteland").ok, "locked target rejects repair")
	asserts.equal(_snapshot(locked), before_locked, "locked failure is atomic")

	var unrepaired_teleport := _fixture(catalog)
	unrepaired_teleport.run_state.teleport_states = {"wasteland": "repairable"}
	unrepaired_teleport.run_state.repaired_teleports = []
	_stock(unrepaired_teleport.inventory, {"repair_hammer": 1, "old_wood": 2, "item_28": 1})
	var before_unrepaired := _snapshot(unrepaired_teleport)
	asserts.false_value(unrepaired_teleport.service.handle_command(REPAIR_ACTION, TARGET_ID, unrepaired_teleport.inventory, unrepaired_teleport.run_state, unrepaired_teleport.world_data, "wasteland").ok, "unrepaired teleport rejects repair interaction")
	asserts.equal(_snapshot(unrepaired_teleport), before_unrepaired, "unrepaired teleport failure is atomic")

	var missing_tool := _fixture(catalog)
	_stock(missing_tool.inventory, {"old_wood": 2, "item_28": 1})
	var before_tool := _snapshot(missing_tool)
	asserts.false_value(missing_tool.service.handle_command(REPAIR_ACTION, TARGET_ID, missing_tool.inventory, missing_tool.run_state, missing_tool.world_data, "wasteland").ok, "missing tool rejects repair")
	asserts.equal(_snapshot(missing_tool), before_tool, "missing tool failure is atomic")

	var missing_material := _fixture(catalog)
	_stock(missing_material.inventory, {"repair_hammer": 1, "old_wood": 1, "item_28": 1})
	var before_material := _snapshot(missing_material)
	asserts.false_value(missing_material.service.handle_command(REPAIR_ACTION, TARGET_ID, missing_material.inventory, missing_material.run_state, missing_material.world_data, "wasteland").ok, "missing material rejects repair")
	asserts.equal(_snapshot(missing_material), before_material, "missing material failure is atomic")

func _assert_saved_state_restore_is_definition_bounded(asserts, catalog: DataCatalog) -> void:
	var valid := _fixture(catalog)
	valid.run_state.world_interactions[TARGET_ID] = {"target_id": TARGET_ID, "biome_id": "wasteland", "state": "recycled", "action_id": RECYCLE_ACTION}
	asserts.true_value(valid.service.apply_saved_target_states(valid.world_data, valid.run_state).ok, "valid saved recycled state applies")
	asserts.true_value(valid.world_data.get_reservation(TARGET_ID).is_empty(), "valid saved recycled state removes the target")

	var stale := _fixture(catalog)
	stale.run_state.world_interactions[TARGET_ID] = {"target_id": TARGET_ID, "biome_id": "wasteland", "state": "recycled", "action_id": "stale_action"}
	asserts.true_value(stale.service.apply_saved_target_states(stale.world_data, stale.run_state).ok, "stale saved target state is tolerated")
	asserts.false_value(stale.world_data.get_reservation(TARGET_ID).is_empty(), "stale saved action cannot remove the world target")

func _fixture(catalog: DataCatalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	var service_result: Dictionary = RepairInteractionService.from_catalog(catalog)
	var state := RunState.new()
	state.current_biome_id = "wasteland"
	state.crafting_unlocks = ["wasteland"]
	state.teleport_states = {"wasteland": "repaired"}
	var world := WorldData.new(3, 1, "wasteland_dry_soil", true)
	world.reserve_facility(TARGET_ID, Vector2i(1, 0), Vector2i.ONE, true, {
		"repair_target_id": TARGET_ID,
		"source_facility_item_id": "wooden_workbench"
	})
	return {
		"inventory": inventory_result.inventory,
		"service": service_result.repair_interaction_service,
		"run_state": state,
		"world_data": world
	}

func _stock(inventory, quantities: Dictionary) -> void:
	for item_id in quantities:
		inventory.add_item(String(item_id), int(quantities[item_id]))

func _item_quantities(items: Array) -> Dictionary:
	var quantities := {}
	for item in items:
		quantities[String(item.get("item_id", ""))] = int(item.get("quantity", 0))
	return quantities

func _snapshot(fixture: Dictionary) -> Dictionary:
	return {
		"inventory": fixture.inventory.to_snapshot(),
		"world_interactions": fixture.run_state.world_interactions.duplicate(true),
		"placed_facilities": fixture.run_state.placed_facilities.duplicate(true),
		"target_present": not fixture.world_data.get_reservation(TARGET_ID).is_empty()
	}
