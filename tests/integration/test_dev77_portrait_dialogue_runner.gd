extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")
const TestGameHud = preload("res://tests/unit/test_game_hud.gd")

func _init() -> void:
	var asserts := TestAssert.new()
	TestGameHud.new().run(asserts)
	if asserts.ok():
		print("DEV-77 portrait dialogue HUD checks passed")
		quit(0)
		return
	for failure in asserts.failures:
		push_error(failure)
	quit(1)
