extends RefCounted

const CraftingService = preload("res://src/crafting/crafting_service.gd")
const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class TestPlayer:
	extends Node2D

func run(asserts) -> void:
	_assert_player_facility_metadata_uses_content_image_map(asserts)
	var runtime := Main.new()
	var player := TestPlayer.new()
	var world := WorldData.new(7, 7, "grass", true)
	var item_definitions := _item_definitions()
	var inventory := InventoryModel.new()
	asserts.true_value(inventory.configure(6, item_definitions).ok, "facility runtime inventory configures")
	asserts.true_value(inventory.add_item("wood", 6).ok, "facility runtime stocks wood")
	asserts.true_value(inventory.add_item("stone", 3).ok, "facility runtime stocks stone")
	asserts.true_value(inventory.add_item("clay", 6).ok, "facility runtime stocks clay")

	var crafting := CraftingService.new()
	asserts.true_value(crafting.configure(_recipe_definitions(), item_definitions, {"목재 작업대": "wooden_workbench"}).ok, "facility runtime crafting configures")
	var placement := FacilityPlacementService.new()
	asserts.true_value(placement.configure(item_definitions).ok, "facility runtime placement configures")

	runtime.player = player
	runtime.inventory = inventory
	runtime.crafting_service = crafting
	runtime.facility_placement_service = placement
	runtime.world_data = world
	runtime.world_visuals = Node2D.new()
	runtime.run_state = RunState.new()
	runtime.run_state.current_biome_id = "common_region"
	runtime.generated_world = {
		"biome_id": "common_region",
		"facility_nodes": [],
		"renderer_input": {"bounds": {"width": 7, "height": 7}, "tile_size": 32}
	}
	player.global_position = runtime.world_position_for_cell_center(Vector2i(3, 3))

	var workbench_command := GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "wooden_workbench"})
	asserts.true_value(runtime._handle_craft_recipe_command(workbench_command), "crafting a facility enters placement mode")
	asserts.true_value(runtime.has_pending_facility_placement(), "facility waits for the player to choose a tile")
	asserts.equal(runtime.run_state.placed_facilities.size(), 0, "facility is not installed before a tile is chosen")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "placement mode does not consume materials early")
	asserts.true_value(runtime.submit_action_command(GameCommand.new(GameCommand.Type.HIDE_MENU)), "closing the menu cancels facility placement")
	asserts.false_value(runtime.has_pending_facility_placement(), "cancelled placement clears the pending facility")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "cancelling placement preserves materials")
	asserts.true_value(runtime._handle_craft_recipe_command(workbench_command), "facility placement can be started again after cancellation")
	asserts.true_value(runtime.submit_pointer_interaction(runtime.world_position_for_cell_center(Vector2i(6, 6))), "an invalid placement click is consumed instead of moving the player")
	asserts.true_value(runtime.has_pending_facility_placement(), "invalid placement keeps placement mode active")
	asserts.equal(runtime.run_state.placed_facilities.size(), 0, "invalid placement does not add a facility")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "invalid placement does not consume materials")

	var selected_install_cell := Vector2i(4, 3)
	asserts.true_value(runtime.submit_pointer_interaction(runtime.world_position_for_cell_center(selected_install_cell)), "a valid placement click selects the install tile")
	asserts.equal(runtime._pending_facility_result.origin, {"x": selected_install_cell.x, "y": selected_install_cell.y}, "pending placement result records selected origin")
	asserts.equal(runtime._pending_facility_result.footprint_size, {"x": 2, "y": 2}, "pending placement result records 64x64 footprint")
	asserts.equal(runtime._pending_facility_result.footprint_cells, [
		{"x": 4, "y": 3},
		{"x": 5, "y": 3},
		{"x": 4, "y": 4},
		{"x": 5, "y": 4}
	], "pending placement result records selected footprint cells")
	asserts.equal(runtime._facility_placement_preview.origin, selected_install_cell, "preview uses selected placement result origin")
	asserts.equal(runtime._facility_placement_preview.footprint, Vector2i(2, 2), "preview uses selected placement result footprint")
	asserts.true_value(world.reserve_entity("late_blocker", selected_install_cell).ok, "late blocker occupies selected install tile")
	asserts.false_value(runtime.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_CONFIRM)), "stale selected placement cannot install after the footprint becomes blocked")
	asserts.true_value(runtime.has_pending_facility_placement(), "blocked confirm keeps placement mode active")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "blocked confirm does not consume materials")
	asserts.equal(runtime.run_state.placed_facilities.size(), 0, "blocked confirm does not record a facility")
	asserts.true_value(world.release_footprint("late_blocker"), "late blocker can be removed")
	asserts.true_value(runtime.submit_pointer_interaction(runtime.world_position_for_cell_center(selected_install_cell)), "placement can be reselected after a stale result is rejected")
	asserts.true_value(runtime.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_CONFIRM)), "confirming placement installs at the selected tile")
	asserts.false_value(runtime.has_pending_facility_placement(), "successful placement leaves placement mode")
	asserts.equal(inventory.get_total_quantity("wooden_workbench"), 0, "installed facility is not stored in inventory")
	asserts.equal(runtime.run_state.placed_facilities.size(), 1, "installed facility is recorded in run state")
	asserts.equal(runtime.run_state.placed_facilities[0].origin, {"x": selected_install_cell.x, "y": selected_install_cell.y}, "facility uses the exact player-selected origin")
	var installed_owner_id := String(runtime.run_state.placed_facilities[0].owner_id)
	asserts.false_value(world.get_reservation(installed_owner_id).is_empty(), "installed facility occupies the live map")
	asserts.equal(world.get_reservation(installed_owner_id).cells, [
		{"x": 4, "y": 3},
		{"x": 5, "y": 3},
		{"x": 4, "y": 4},
		{"x": 5, "y": 4}
	], "installed facility reserves the same cells preview validated")
	asserts.equal(runtime._available_facility_item_ids(), ["wooden_workbench"], "installed facility unlocks recipes while the player is adjacent")

	var bowl_command := GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "humble_clay_bowl"})
	asserts.true_value(runtime._handle_craft_recipe_command(bowl_command), "facility recipe crafts beside the installed workbench")
	asserts.equal(inventory.get_total_quantity("humble_clay_bowl"), 1, "nearby facility craft grants its result")

	player.global_position = runtime.world_position_for_cell_center(Vector2i(6, 6))
	asserts.equal(runtime._available_facility_item_ids(), [], "installed facility no longer unlocks recipes when the player moves away")
	var clay_before := inventory.get_total_quantity("clay")
	asserts.false_value(runtime._handle_craft_recipe_command(bowl_command), "facility recipe is rejected away from the installed workbench")
	asserts.equal(inventory.get_total_quantity("clay"), clay_before, "rejected distant craft does not consume materials")

	var restored_world := WorldData.new(7, 7, "grass", true)
	runtime.world_data = restored_world
	asserts.true_value(runtime._restore_placed_facilities_for_current_biome().ok, "saved facility restores into a regenerated biome map")
	asserts.equal(placement.facility_item_ids_near(restored_world, selected_install_cell), ["wooden_workbench"], "restored facility keeps its selected position and proximity behavior")

	runtime.world_visuals.free()
	runtime.world_visuals = null
	player.free()
	runtime.free()

func _assert_player_facility_metadata_uses_content_image_map(asserts) -> void:
	var runtime := Main.new()
	var placement := FacilityPlacementService.new()
	asserts.true_value(placement.configure(_item_definitions()).ok, "facility metadata placement fixture configures")
	runtime.facility_placement_service = placement
	var metadata: Dictionary = runtime._player_facility_metadata("wooden_workbench")
	asserts.equal(metadata.source_id, "item_wooden_workbench_object_64", "player facility metadata uses the dedicated content image")
	runtime.free()

func _item_definitions() -> Dictionary:
	return {
		"wood": {"id": "wood", "name": "목재", "type": "재료", "max_stack": 10},
		"stone": {"id": "stone", "name": "돌", "type": "재료", "max_stack": 10},
		"clay": {"id": "clay", "name": "점토", "type": "재료", "max_stack": 10},
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
			"materials": [{"item_id": "clay", "quantity": 3}],
			"facility_item_ids": ["wooden_workbench"],
			"result_item_id": "humble_clay_bowl",
			"result_quantity": 1,
			"definition_errors": []
		}
	}
