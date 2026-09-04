extends RefCounted
class_name DesktopCommandAdapter

const ActionCommandFactory = preload("res://src/core/commands/action_command_factory.gd")

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
	return ActionCommandFactory.movement_command(direction)

func command_for_action(action: String, direction := Vector2i.ZERO, slot := 0, payload := {}):
	return ActionCommandFactory.command_for_action(action, direction, slot, payload)
