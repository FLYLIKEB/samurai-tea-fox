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
	_assert_world_replacement_queries_current_world(asserts)
	_assert_facility_pending_actions_preserve_inventory_until_valid_confirm(asserts)
	_assert_main_instances_keep_pointer_and_facility_state_independent(asserts)
	_assert_option_only_narrative_command_uses_active_session_ids(asserts)
	_assert_failed_boss_precombat_completion_keeps_active_session_ids(asserts)

class FakeNarrativeRuntime:
	extends RefCounted

	var selected_options := []
	var next_result := {
		"ok": true,
		"complete": false,
		"read_model": {
			"event_id": "story_b01_03",
			"node_id": "dlg_b01_004"
		},
		"commands": []
	}

	func select_option(event_id: String, node_id: String, option_id: String, _run_state, _meta_state = null) -> Dictionary:
		selected_options.append({
			"event_id": event_id,
			"node_id": node_id,
			"option_id": option_id
		})
		return next_result.duplicate(true)

class FailingBossPrecombatRuntime:
	extends RefCounted

	var completion_attempts := []

	func to_projection() -> Dictionary:
		return {
			"boss_flow_state": "pre_dialogue_active",
			"pre_boss_dialogue_event_id": "story_b01_03"
		}

	func complete_boss_precombat_dialogue(event_id: String) -> Dictionary:
		completion_attempts.append(event_id)
		return {"ok": false, "reason": "fixture_boss_completion_failed"}

func _assert_world_replacement_queries_current_world(asserts) -> void:
	var main := Main.new()
	var first_world := WorldData.new(4, 4, "grass", true)
	first_world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_zone_old", Vector2i(1, 1))
	var next_world := WorldData.new(4, 4, "grass", true)
	next_world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_zone_new", Vector2i(2, 2))

	main.world_data = first_world
	asserts.equal(main._interaction_target_id_for_cell(Vector2i(1, 1)), "teleport_zone_old", "fixture reads the initial world landmark")

	main.world_data = next_world
	asserts.equal(main._interaction_target_id_for_cell(Vector2i(1, 1)), "", "world replacement drops stale spatial targets from the old world")
	asserts.equal(main._interaction_target_id_for_cell(Vector2i(2, 2)), "teleport_zone_new", "world replacement resolves spatial targets from the newest world")
	main.free()

func _assert_facility_pending_actions_preserve_inventory_until_valid_confirm(asserts) -> void:
	var fixture := _facility_runtime(asserts)
	var main: Main = fixture.main
	var inventory: InventoryModel = fixture.inventory
	var world: WorldData = fixture.world
	var player: TestPlayer = fixture.player
	var command := GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "wooden_workbench"})

	asserts.true_value(main._handle_craft_recipe_command(command), "facility crafting enters pending placement")
	asserts.true_value(main.has_pending_facility_placement(), "pending placement is active before a tile is confirmed")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "pending placement does not consume wood")
	asserts.equal(inventory.get_total_quantity("stone"), 3, "pending placement does not consume stone")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_ROTATE)), "pending placement accepts rotation")
	asserts.equal(main._pending_facility_rotation, 1, "rotation is stored on the pending placement")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "rotating pending placement preserves wood")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_CANCEL)), "pending placement can be cancelled")
	asserts.false_value(main.has_pending_facility_placement(), "cancel clears pending placement")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "cancel preserves wood")
	asserts.equal(main._pending_facility_rotation, 0, "cancel resets pending rotation")

	asserts.true_value(main._handle_craft_recipe_command(command), "facility placement can start again after cancel")
	var selected_cell := Vector2i(4, 3)
	asserts.true_value(main.submit_pointer_interaction(main.world_position_for_cell_center(selected_cell)), "valid placement selection is accepted")
	asserts.true_value(world.reserve_entity("late_blocker", selected_cell).ok, "late blocker invalidates selected footprint")
	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_CONFIRM)), "blocked confirm rejects stale selected placement")
	asserts.true_value(main.has_pending_facility_placement(), "blocked confirm keeps placement pending")
	asserts.equal(inventory.get_total_quantity("wood"), 6, "blocked confirm preserves wood")
	asserts.equal(inventory.get_total_quantity("stone"), 3, "blocked confirm preserves stone")
	asserts.equal(main.run_state.placed_facilities.size(), 0, "blocked confirm does not record a facility")
	asserts.true_value(world.release_footprint("late_blocker"), "late blocker fixture releases")

	asserts.true_value(main.submit_pointer_interaction(main.world_position_for_cell_center(selected_cell)), "valid placement can be selected after blocked confirm")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.FACILITY_CONFIRM)), "valid confirm installs the facility")
	asserts.false_value(main.has_pending_facility_placement(), "valid confirm clears pending placement")
	asserts.equal(inventory.get_total_quantity("wood"), 0, "valid confirm consumes wood exactly once")
	asserts.equal(inventory.get_total_quantity("stone"), 0, "valid confirm consumes stone exactly once")
	asserts.equal(main.run_state.placed_facilities.size(), 1, "valid confirm records one facility")

	player.free()
	main.world_visuals.free()
	main.free()

func _assert_main_instances_keep_pointer_and_facility_state_independent(asserts) -> void:
	var left := _facility_runtime(asserts)
	var right := _facility_runtime(asserts)
	var left_main: Main = left.main
	var right_main: Main = right.main
	var left_player: TestPlayer = left.player
	var right_player: TestPlayer = right.player

	asserts.true_value(left_main.submit_pointer_movement(left_main.world_position_for_cell_center(Vector2i(6, 3))), "left instance accepts pointer movement")
	asserts.true_value(left_main._has_pointer_move_target, "left instance stores its pointer target")
	asserts.false_value(right_main._has_pointer_move_target, "right instance does not share pointer target state")
	asserts.equal(right_main._pointer_move_target_world, Vector2.ZERO, "right instance keeps default pointer target")

	var command := GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "wooden_workbench"})
	asserts.true_value(left_main._handle_craft_recipe_command(command), "left instance starts pending facility placement")
	asserts.true_value(left_main.has_pending_facility_placement(), "left instance has pending facility state")
	asserts.false_value(right_main.has_pending_facility_placement(), "right instance has no shared pending facility state")
	asserts.equal(right_main._pending_facility_rotation, 0, "right instance keeps default facility rotation")
	asserts.equal(right_main._pending_facility_origin, Vector2i(-1, -1), "right instance keeps default facility origin")
	asserts.equal(right.inventory.get_total_quantity("wood"), 6, "right instance inventory is not mutated by left placement")

	left_player.free()
	right_player.free()
	left_main.world_visuals.free()
	right_main.world_visuals.free()
	left_main.free()
	right_main.free()

func _assert_option_only_narrative_command_uses_active_session_ids(asserts) -> void:
	var main := Main.new()
	var narrative := FakeNarrativeRuntime.new()
	main.narrative_runtime = narrative
	main.run_state = RunState.new()
	main._active_narrative_event_id = "story_b01_03"
	main._active_narrative_node_id = "dlg_b01_003"

	asserts.true_value(main._handle_narrative_option_command(GameCommand.new(
		GameCommand.Type.NARRATIVE_SELECT_OPTION,
		Vector2i.ZERO,
		-1,
		{"option_id": "complete_dlg_b01_003"}
	)), "option-only narrative command is routed through active session ids")
	asserts.equal(narrative.selected_options, [{
		"event_id": "story_b01_03",
		"node_id": "dlg_b01_003",
		"option_id": "complete_dlg_b01_003"
	}], "narrative runtime receives the active event and node ids when command only carries option_id")
	asserts.equal(main._active_narrative_event_id, "story_b01_03", "non-complete option keeps active event id from read model")
	asserts.equal(main._active_narrative_node_id, "dlg_b01_004", "non-complete option advances active node id from read model")
	main.free()

func _assert_failed_boss_precombat_completion_keeps_active_session_ids(asserts) -> void:
	var main := Main.new()
	var narrative := FakeNarrativeRuntime.new()
	narrative.next_result = {
		"ok": true,
		"complete": true,
		"commands": []
	}
	var dungeon := FailingBossPrecombatRuntime.new()
	main.narrative_runtime = narrative
	main.dungeon_runtime = dungeon
	main.run_state = RunState.new()
	main._active_narrative_event_id = "story_b01_03"
	main._active_narrative_node_id = "dlg_b01_003"

	asserts.false_value(main._handle_narrative_option_command(GameCommand.new(
		GameCommand.Type.NARRATIVE_SELECT_OPTION,
		Vector2i.ZERO,
		-1,
		{"option_id": "complete_dlg_b01_003"}
	)), "failed boss precombat completion rejects the option command")
	asserts.equal(narrative.selected_options, [{
		"event_id": "story_b01_03",
		"node_id": "dlg_b01_003",
		"option_id": "complete_dlg_b01_003"
	}], "boss precombat completion uses active ids for option-only command")
	asserts.equal(dungeon.completion_attempts, ["story_b01_03"], "boss precombat completion attempts the active event id")
	asserts.equal(main._active_narrative_event_id, "story_b01_03", "failed boss completion keeps active event id for retry")
	asserts.equal(main._active_narrative_node_id, "dlg_b01_003", "failed boss completion keeps active node id for retry")
	main.free()

func _facility_runtime(asserts) -> Dictionary:
	var main := Main.new()
	var player := TestPlayer.new()
	var world := WorldData.new(7, 7, "grass", true)
	var inventory := InventoryModel.new()
	asserts.true_value(inventory.configure(6, _item_definitions()).ok, "feature boundary fixture inventory configures")
	asserts.true_value(inventory.add_item("wood", 6).ok, "feature boundary fixture stocks wood")
	asserts.true_value(inventory.add_item("stone", 3).ok, "feature boundary fixture stocks stone")
	var crafting := CraftingService.new()
	asserts.true_value(crafting.configure(_recipe_definitions(), _item_definitions(), {"목재 작업대": "wooden_workbench"}).ok, "feature boundary fixture crafting configures")
	var placement := FacilityPlacementService.new()
	asserts.true_value(placement.configure(_item_definitions()).ok, "feature boundary fixture placement configures")

	main.player = player
	main.inventory = inventory
	main.crafting_service = crafting
	main.facility_placement_service = placement
	main.world_data = world
	main.world_visuals = Node2D.new()
	main.run_state = RunState.new()
	main.run_state.current_biome_id = "common_region"
	main.generated_world = {
		"biome_id": "common_region",
		"facility_nodes": [],
		"renderer_input": {"bounds": {"width": 7, "height": 7}, "tile_size": 32}
	}
	player.global_position = main.world_position_for_cell_center(Vector2i(3, 3))
	return {"main": main, "player": player, "world": world, "inventory": inventory}

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
			"materials": [{"item_id": "wood", "quantity": 1}],
			"facility_item_ids": ["wooden_workbench"],
			"result_item_id": "humble_clay_bowl",
			"result_quantity": 1,
			"definition_errors": []
		}
	}
