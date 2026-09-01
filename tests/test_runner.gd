extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")

const TESTS := [
	preload("res://tests/unit/test_command_layer.gd"),
	preload("res://tests/unit/test_bounded_resource.gd"),
	preload("res://tests/unit/test_data_catalog.gd"),
	preload("res://tests/unit/test_player_movement.gd"),
	preload("res://tests/unit/test_player_resources.gd"),
	preload("res://tests/unit/test_save_codec.gd"),
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
