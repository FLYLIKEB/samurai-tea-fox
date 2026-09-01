extends RefCounted
class_name CommandDispatcher

const GameCommand = preload("res://src/core/commands/game_command.gd")

signal command_issued(command)

func dispatch(command) -> bool:
	if not command is GameCommand:
		return false
	command_issued.emit(command)
	return true
