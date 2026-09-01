extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")

const TESTS := [
	preload("res://tests/unit/test_command_layer.gd"),
	preload("res://tests/unit/test_bounded_resource.gd"),
	preload("res://tests/unit/test_data_catalog.gd"),
	preload("res://tests/unit/test_player_movement.gd"),
	preload("res://tests/unit/test_player_resources.gd"),
	preload("res://tests/unit/test_time_state.gd"),
	preload("res://tests/unit/test_combat_state.gd"),
	preload("res://tests/unit/test_ability_runtime.gd"),
	preload("res://tests/unit/test_inventory_model.gd"),
	preload("res://tests/unit/test_equipment_model.gd"),
	preload("res://tests/unit/test_tea_service.gd"),
	preload("res://tests/unit/test_crafting_service.gd"),
	preload("res://tests/unit/test_save_codec.gd"),
	preload("res://tests/unit/test_world_data.gd"),
	preload("res://tests/unit/test_world_generation.gd")
]

func _init() -> void:
	var asserts := TestAssert.new()

	for script in TESTS:
		var test = script.new()
		if test == null:
			asserts.fail("Could not instantiate test: %s" % script.resource_path)
			continue
		test.run(asserts)

	if asserts.ok():
		print("All tests passed: %d" % TESTS.size())
		quit(0)
		return

	for failure in asserts.failures:
		push_error(failure)
	quit(1)
