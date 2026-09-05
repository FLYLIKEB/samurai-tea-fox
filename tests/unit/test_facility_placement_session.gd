extends RefCounted

const CraftingService = preload("res://src/crafting/crafting_service.gd")
const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const FacilityPlacementSession = preload("res://src/main/facility_placement_session.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	_assert_pending_lifecycle_preserves_materials_until_confirm(asserts)
	_assert_player_required_for_facility_placement(asserts)
	_assert_available_and_restore_use_current_arguments(asserts)

func _assert_pending_lifecycle_preserves_materials_until_confirm(asserts) -> void:
	var fixture := _facility_fixture(asserts)
	var session: FacilityPlacementSession = fixture.session
	var inventory: InventoryModel = fixture.inventory
	var placement: FacilityPlacementService = fixture.placement
	var world: WorldData = fixture.world

	var result := session.begin_or_craft_recipe(
		"wooden_workbench",
		fixture.crafting,
		inventory,
		{},
		placement,
		world,
		Vector2i(3, 3),
		false,
		{"source_id": "item_wooden_workbench_object_64"}
	)
	asserts.true_value(result.ok, "session starts facility placement")
	asserts.true_value(session.has_pending(), "session owns pending placement state")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "start does not consume materials")
	asserts.equal(session.pending_origin, Vector2i(-1, -1), "start resets selected origin")

	var selected_origin := Vector2i(4, 3)
	var validation := session.select_origin(selected_origin, placement, world, Vector2i(3, 3))
	asserts.true_value(validation.ok, "session validates selected origin")
	asserts.equal(session.pending_result.origin, {"x": selected_origin.x, "y": selected_origin.y}, "session stores selected validation")
	asserts.true_value(world.reserve_entity("late_blocker", selected_origin).ok, "fixture blocks stale placement")
	var blocked := session.confirm(fixture.crafting, inventory, {}, placement, world)
	asserts.false_value(blocked.ok, "session rejects stale selected placement")
	asserts.true_value(session.has_pending(), "stale confirm keeps placement pending")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "stale confirm does not consume materials")

	asserts.true_value(world.release_footprint("late_blocker"), "fixture releases blocker")
	session.select_origin(selected_origin, placement, world, Vector2i(3, 3))
	var confirmed := session.confirm(fixture.crafting, inventory, {}, placement, world)
	asserts.true_value(confirmed.ok, "session installs valid placement")
	asserts.true_value(session.has_pending(), "committed placement remains observable until scene effects finish")
	session.clear()
	asserts.false_value(session.has_pending(), "scene finalization clears pending placement")
	asserts.equal(inventory.get_total_quantity("wood"), 0, "confirm consumes materials exactly once")
	asserts.equal(confirmed.placement.origin, {"x": selected_origin.x, "y": selected_origin.y}, "confirm returns placement for Main to record")

func _assert_player_required_for_facility_placement(asserts) -> void:
	var fixture := _facility_fixture(asserts)
	var session: FacilityPlacementSession = fixture.session
	var result := session.begin_or_craft_recipe(
		"wooden_workbench",
		fixture.crafting,
		fixture.inventory,
		{},
		fixture.placement,
		fixture.world,
		Vector2i.ZERO,
		false,
		{},
		false
	)
	asserts.false_value(result.ok, "facility placement rejects missing player")
	asserts.equal(result.reason, "facility_placement_unavailable", "missing player preserves Main failure reason")
	asserts.false_value(session.has_pending(), "missing player does not create pending state")

func _assert_available_and_restore_use_current_arguments(asserts) -> void:
	var fixture := _facility_fixture(asserts)
	var session: FacilityPlacementSession = fixture.session
	var run_state := RunState.new()
	run_state.current_biome_id = "common_region"
	run_state.placed_facilities.append({
		"biome_id": "common_region",
		"facility_item_id": "wooden_workbench",
		"owner_id": "saved_workbench",
		"origin": {"x": 2, "y": 2},
		"metadata": {"facility_item_id": "wooden_workbench"}
	})

	var first_world := WorldData.new(6, 6, "grass", true)
	var restored := session.restore_placed_facilities_for_current_biome(fixture.placement, first_world, run_state, {"biome_id": "common_region"})
	asserts.true_value(restored.ok, "session restores saved facility into provided world")
	asserts.equal(session.available_facility_item_ids(fixture.crafting, fixture.placement, first_world, run_state, {"biome_id": "common_region", "facility_nodes": []}, Vector2i(3, 3)), ["wooden_workbench"], "session queries restored current world")

	var next_world := WorldData.new(6, 6, "grass", true)
	asserts.equal(session.available_facility_item_ids(fixture.crafting, fixture.placement, next_world, run_state, {"biome_id": "common_region", "facility_nodes": []}, Vector2i(5, 5)), [], "session does not keep stale world state")

func _facility_fixture(asserts) -> Dictionary:
	var inventory := InventoryModel.new()
	asserts.true_value(inventory.configure(6, _item_definitions()).ok, "fixture inventory configures")
	asserts.true_value(inventory.add_item("wood", 6).ok, "fixture stocks wood")
	asserts.true_value(inventory.add_item("stone", 3).ok, "fixture stocks stone")
	var crafting := CraftingService.new()
	asserts.true_value(crafting.configure(_recipe_definitions(), _item_definitions(), {"목재 작업대": "wooden_workbench"}).ok, "fixture crafting configures")
	var placement := FacilityPlacementService.new()
	asserts.true_value(placement.configure(_item_definitions()).ok, "fixture placement configures")
	return {
		"session": FacilityPlacementSession.new(),
		"inventory": inventory,
		"crafting": crafting,
		"placement": placement,
		"world": WorldData.new(7, 7, "grass", true)
	}

func _item_definitions() -> Dictionary:
	return {
		"wood": {"id": "wood", "name": "목재", "type": "재료", "max_stack": 10},
		"stone": {"id": "stone", "name": "돌", "type": "재료", "max_stack": 10},
		"wooden_workbench": {"id": "wooden_workbench", "name": "목재 작업대", "type": "도구", "max_stack": 1, "footprint_size": Vector2i(2, 2)},
		"humble_clay_bowl": {"id": "humble_clay_bowl", "name": "소박한 흙사발", "type": "다구", "max_stack": 1}
	}

func _recipe_definitions() -> Dictionary:
	return {
		"wooden_workbench": {
			"id": "wooden_workbench",
			"materials": [{"item_id": "wood", "quantity": 6}, {"item_id": "stone", "quantity": 3}],
			"facility_item_ids": [],
			"result_item_id": "wooden_workbench",
			"result_quantity": 1,
			"definition_errors": []
		},
		"humble_clay_bowl": {
			"id": "humble_clay_bowl",
			"materials": [],
			"facility_item_ids": ["wooden_workbench"],
			"result_item_id": "humble_clay_bowl",
			"result_quantity": 1,
			"definition_errors": []
		}
	}
