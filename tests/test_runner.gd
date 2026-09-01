extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")

const TESTS := [
	"res://tests/unit/test_command_layer.gd",
	"res://tests/unit/test_data_catalog.gd",
	"res://tests/unit/test_player_resources.gd",
	"res://tests/unit/test_save_codec.gd",
	"res://tests/unit/test_world_generation.gd"
]

func _init() -> void:
	var asserts := TestAssert.new()

	for path in TESTS:
		var script = load(path)
		if script == null:
			asserts.fail("Could not load test: %s" % path)
			continue
		var reload_error: Error = script.reload()
		if reload_error != OK:
			asserts.fail("Could not compile test: %s" % path)
			continue
		var test = script.new()
		if test == null:
			asserts.fail("Could not instantiate test: %s" % path)
			continue
		test.run(asserts)

	if asserts.ok():
		print("All tests passed: %d" % TESTS.size())
		quit(0)
		return

	for failure in asserts.failures:
		push_error(failure)
	quit(1)
