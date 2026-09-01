extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")

func run(asserts) -> void:
	var movement := PlayerMovementState.new()
	var diagonal := movement.resolve(Vector2i(1, 1))
	asserts.equal(diagonal, Vector2.RIGHT, "simultaneous axes resolve to one of four movement directions")
	asserts.equal(movement.facing, PlayerMovementState.Facing.RIGHT, "horizontal axis wins diagonal facing ties")

	var stopped := movement.resolve(Vector2i.ZERO)
	asserts.equal(stopped, Vector2.ZERO, "zero input stops movement")
	asserts.equal(movement.facing, PlayerMovementState.Facing.RIGHT, "stopping preserves the last facing")

	movement.resolve(Vector2i.UP)
	asserts.equal(movement.facing, PlayerMovementState.Facing.UP, "vertical input updates facing")

	var desktop := DesktopCommandAdapter.new()
	var mobile := MobileCommandAdapter.new()
	var desktop_move = desktop.movement_command_from_strengths(1.0, 0.0, 0.0, 0.0)
	var mobile_move = mobile.command_for_button("move", Vector2i.LEFT)
	asserts.equal(desktop_move.type, GameCommand.Type.MOVE, "desktop produces a movement command")
	asserts.equal(desktop_move.direction, mobile_move.direction, "desktop and mobile use the same movement direction")

	var selector := MovementCommandSelector.new()
	var mobile_down = mobile.command_for_button("move", Vector2i.DOWN)
	asserts.true_value(selector.submit_mobile_command(mobile_down), "mobile movement becomes the current command")
	var desktop_idle = desktop.movement_command_from_strengths(0.0, 0.0, 0.0, 0.0)
	asserts.equal(selector.select(desktop_idle).direction, Vector2i.DOWN, "mobile movement persists while desktop is idle")
	asserts.equal(selector.select(desktop_move).direction, Vector2i.LEFT, "active desktop input can take over immediately")
	asserts.true_value(selector.submit_mobile_command(mobile.command_for_button("move", Vector2i.ZERO)), "mobile release submits a stop command")
	asserts.equal(selector.select(desktop_idle).direction, Vector2i.ZERO, "mobile release stops persistent movement")
