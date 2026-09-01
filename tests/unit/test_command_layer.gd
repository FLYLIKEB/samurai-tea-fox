extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")

func run(asserts) -> void:
	var mobile := MobileCommandAdapter.new()
	var attack := mobile.command_for_button("attack", Vector2i.RIGHT)
	asserts.equal(attack.type, GameCommand.Type.ATTACK, "mobile attack maps to shared command")
	asserts.equal(attack.direction, Vector2i.RIGHT, "mobile attack preserves direction")

	var tea := mobile.command_for_button("drink_tea", Vector2i.ZERO, 1)
	asserts.equal(tea.type, GameCommand.Type.DRINK_TEA, "mobile tea maps to shared command")
	asserts.equal(tea.slot, 1, "mobile tea preserves slot")

