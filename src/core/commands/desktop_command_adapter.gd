extends RefCounted
class_name DesktopCommandAdapter

const GameCommand = preload("res://src/core/commands/game_command.gd")

func poll_movement_command():
	return movement_command_from_strengths(
		Input.get_action_strength("move_left"),
		Input.get_action_strength("move_right"),
		Input.get_action_strength("move_up"),
		Input.get_action_strength("move_down")
	)

func movement_command_from_strengths(left: float, right: float, up: float, down: float):
	var direction := Vector2i(
		int(signf(right - left)),
		int(signf(down - up))
	)
	return GameCommand.new(GameCommand.Type.MOVE, direction)

func command_for_action(action: String, direction := Vector2i.ZERO, slot := 0):
	match action:
		"attack":
			return GameCommand.new(GameCommand.Type.ATTACK, direction)
		"dodge":
			return GameCommand.new(GameCommand.Type.DODGE, direction)
		"drink_tea":
			return GameCommand.new(GameCommand.Type.DRINK_TEA, Vector2i.ZERO, slot)
		"cast_ability":
			return GameCommand.new(GameCommand.Type.CAST_ABILITY, direction, slot)
		"interact":
			return GameCommand.new(GameCommand.Type.INTERACT)
		_:
			return null
