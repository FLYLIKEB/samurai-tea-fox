extends RefCounted

const Main = preload("res://src/main/main.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")

class Resources:
	extends RefCounted
	var kokoro := 100

	func reduce_kokoro(amount: int) -> int:
		var applied := mini(kokoro, amount)
		kokoro -= applied
		return applied

class TurnPlayer:
	extends Node2D
	var resources := Resources.new()
	var ability_runtime = null

	func submit_command(_command) -> bool:
		return false

func run(asserts) -> void:
	var main := Main.new()
	var player := TurnPlayer.new()
	main.player = player
	main.time_state = TimeState.new(TimeConfig.new({
		"day_phase_duration_seconds": 300.0,
		"dusk_phase_duration_seconds": 120.0,
		"night_phase_duration_seconds": 240.0,
		"late_night_phase_duration_seconds": 180.0,
		"dusk_kokoro_decay_per_second": 0.02,
		"night_kokoro_decay_per_second": 0.05,
		"late_night_kokoro_decay_per_second": 0.1,
		"low_kokoro_ability_cost_increase_percent": 25.0,
		"sleep_heal_ratio": 0.2
	}))

	main._physics_process(60.0)
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "idle physics frames do not advance game time")
	main._advance_time_for_turn()
	asserts.equal(main.time_state.phase_elapsed_seconds, 1.0, "one completed turn advances game time by one turn unit")

	player.free()
	main.free()
