extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")

const TESTS := [
	preload("res://tests/unit/test_command_layer.gd"),
	preload("res://tests/unit/test_bounded_resource.gd"),
	preload("res://tests/unit/test_asset_catalog.gd"),
	preload("res://tests/unit/test_data_catalog.gd"),
	preload("res://tests/unit/test_player_movement.gd"),
	preload("res://tests/unit/test_player_resources.gd"),
	preload("res://tests/unit/test_time_state.gd"),
	preload("res://tests/unit/test_combat_state.gd"),
	preload("res://tests/unit/test_monster_runtime.gd"),
	preload("res://tests/unit/test_ability_runtime.gd"),
	preload("res://tests/unit/test_inventory_model.gd"),
	preload("res://tests/unit/test_equipment_model.gd"),
	preload("res://tests/unit/test_tea_service.gd"),
	preload("res://tests/unit/test_consumable_service.gd"),
	preload("res://tests/unit/test_crafting_service.gd"),
	preload("res://tests/unit/test_narrative_runtime.gd"),
	preload("res://tests/unit/test_save_codec.gd"),
	preload("res://tests/unit/test_world_data.gd"),
	preload("res://tests/unit/test_world_generation.gd")
]

func _init() -> void:
	var asserts := TestAssert.new()
	var test_filter := OS.get_environment("TEST_FILTER")
	var selected_count := 0

	for script in TESTS:
		if not test_filter.is_empty() and not test_filter in script.resource_path:
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
