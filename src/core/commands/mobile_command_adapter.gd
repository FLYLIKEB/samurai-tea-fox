extends RefCounted
class_name MobileCommandAdapter

const GameCommand = preload("res://src/core/commands/game_command.gd")

func command_for_button(button_id: String, direction := Vector2i.ZERO, slot := 0) -> GameCommand:
	match button_id:
		"move":
			return GameCommand.move(direction)
		"attack":
			return GameCommand.attack(direction)
		"dodge":
			return GameCommand.dodge(direction)
		"drink_tea":
			return GameCommand.drink_tea(slot)
		"cast_ability":
			return GameCommand.cast_ability(slot, direction)
		"interact":
			return GameCommand.interact()
		_:
			push_error("Unknown mobile command button: %s" % button_id)
			return GameCommand.interact()

