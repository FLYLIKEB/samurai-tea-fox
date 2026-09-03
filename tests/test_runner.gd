extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")

const TESTS := [
	preload("res://tests/unit/test_command_layer.gd"),
	preload("res://tests/unit/test_game_hud.gd"),
	preload("res://tests/unit/test_map_read_model.gd"),
	preload("res://tests/unit/test_bounded_resource.gd"),
	preload("res://tests/unit/test_asset_catalog.gd"),
	preload("res://tests/unit/test_directional_walk_animator.gd"),
	preload("res://tests/unit/test_data_catalog.gd"),
	preload("res://tests/unit/test_player_movement.gd"),
	preload("res://tests/unit/test_player_resources.gd"),
	preload("res://tests/unit/test_tail_state.gd"),
	preload("res://tests/unit/test_time_state.gd"),
	preload("res://tests/unit/test_combat_state.gd"),
	preload("res://tests/unit/test_monster_runtime.gd"),
	preload("res://tests/unit/test_monster_behavior.gd"),
	preload("res://tests/unit/test_ability_runtime.gd"),
	preload("res://tests/unit/test_inventory_model.gd"),
	preload("res://tests/unit/test_equipment_model.gd"),
	preload("res://tests/unit/test_inventory_command_runtime.gd"),
	preload("res://tests/unit/test_tea_service.gd"),
	preload("res://tests/unit/test_tea_brewing_command_runtime.gd"),
	preload("res://tests/unit/test_consumable_service.gd"),
	preload("res://tests/unit/test_crafting_service.gd"),
	preload("res://tests/unit/test_trade_service.gd"),
	preload("res://tests/unit/test_narrative_runtime.gd"),
	preload("res://tests/unit/test_memory_tea_cutscene_runtime.gd"),
	preload("res://tests/unit/test_choice_runtime.gd"),
	preload("res://tests/unit/test_meta_unlock_processor.gd"),
	preload("res://tests/unit/test_final_room_state_builder.gd"),
	preload("res://tests/unit/test_sen_rikyu_phase_one_runtime.gd"),
	preload("res://tests/unit/test_sen_rikyu_phase_two_runtime.gd"),
	preload("res://tests/unit/test_sen_rikyu_phase_three_runtime.gd"),
	preload("res://tests/unit/test_run_lifecycle_service.gd"),
	preload("res://tests/unit/test_save_codec.gd"),
	preload("res://tests/unit/test_save_store.gd"),
	preload("res://tests/unit/test_biome_progression.gd"),
	preload("res://tests/unit/test_dungeon_runtime.gd"),
	preload("res://tests/unit/test_core_tea_ware_collection.gd"),
	preload("res://tests/unit/test_ending_route_runtime.gd"),
	preload("res://tests/unit/test_meta_codex_command_runtime.gd"),
	preload("res://tests/unit/test_boss_encounter_runtime.gd"),
	preload("res://tests/unit/test_boss_tea_resolution_runtime.gd"),
	preload("res://tests/unit/test_world_data.gd"),
	preload("res://tests/unit/test_world_scene_renderer.gd"),
	preload("res://tests/unit/test_acquisition_service.gd"),
	preload("res://tests/unit/test_main_vertical_slice_runtime.gd"),
	preload("res://tests/unit/test_main_acquisition_runtime.gd"),
	preload("res://tests/unit/test_world_generation.gd")
]

func _init() -> void:
	var asserts := TestAssert.new()
	var test_filter := OS.get_environment("TEST_FILTER")
	var filters := _test_filters(test_filter)
	var selected_count := 0

	for script in TESTS:
		if not filters.is_empty() and not _matches_any_filter(script.resource_path, filters):
			continue
		selected_count += 1
		var test = script.new()
		if test == null:
			asserts.fail("Could not instantiate test: %s" % script.resource_path)
			continue
		test.run(asserts)

	if selected_count == 0:
		asserts.fail("No tests matched TEST_FILTER='%s'" % test_filter)

	if asserts.ok():
		print("All tests passed: %d" % selected_count)
		quit(0)
		return

	for failure in asserts.failures:
		push_error(failure)
	quit(1)

func _test_filters(test_filter: String) -> Array[String]:
	var filters: Array[String] = []
	for raw_filter in test_filter.split(",", false):
		var filter := raw_filter.strip_edges()
		if not filter.is_empty():
			filters.append(filter)
	return filters

func _matches_any_filter(resource_path: String, filters: Array[String]) -> bool:
	for filter in filters:
		if filter in resource_path:
			return true
	return false
