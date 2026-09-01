extends RefCounted
class_name MovementCommandSelector

const GameCommand = preload("res://src/core/commands/game_command.gd")

var _mobile_command = GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)

func submit_mobile_command(command) -> bool:
	if not _is_movement_command(command):
		return false
	_mobile_command = command
	return true

func select(desktop_command):
	if _is_movement_command(desktop_command) and desktop_command.direction != Vector2i.ZERO:
		return desktop_command
	return _mobile_command

func _is_movement_command(command) -> bool:
	return command is GameCommand and command.type == GameCommand.Type.MOVE
