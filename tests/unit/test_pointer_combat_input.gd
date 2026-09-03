extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class ActionPlayer:
	extends Node2D
	var submitted_commands: Array[GameCommand] = []
	var accepts_actions := true

	func submit_command(command: GameCommand) -> bool:
		submitted_commands.append(command)
		return accepts_actions

class EnemyTarget:
	extends Node2D
	var hp := 1

	func current_hp() -> int:
		return hp

func run(asserts) -> void:
	var main := Main.new()
	main.world_data = WorldData.new(4, 4, "grass", true)
	var player := ActionPlayer.new()
	player.global_position = main.world_position_for_cell_center(Vector2i.ZERO)
	main.player = player
	var enemy := EnemyTarget.new()
	enemy.global_position = main.world_position_for_cell_center(Vector2i.RIGHT)
	main.combat_dummy = enemy

	asserts.true_value(main.submit_pointer_interaction(enemy.global_position), "clicking a living enemy submits an attack")
	asserts.equal(player.submitted_commands.size(), 1, "enemy click submits exactly one command")
	asserts.equal(player.submitted_commands[0].type, GameCommand.Type.ATTACK, "enemy click uses the shared attack command")
	asserts.equal(player.submitted_commands[0].direction, Vector2i.RIGHT, "enemy click attacks toward the enemy")

	player.accepts_actions = false
	main._pointer_move_target_world = main.world_position_for_cell_center(Vector2i(2, 0))
	main._has_pointer_move_target = true
	asserts.true_value(main.submit_pointer_interaction(enemy.global_position), "enemy click consumes input while an attack is unavailable")
	asserts.false_value(main._has_pointer_move_target, "enemy click cancels pending pointer movement before attacking")

	enemy.hp = 0
	asserts.false_value(main.submit_pointer_interaction(enemy.global_position), "clicking a defeated enemy does not submit an attack")
	asserts.equal(player.submitted_commands.size(), 2, "defeated enemy click leaves commands unchanged")
	enemy.free()
	player.free()
	main.free()
