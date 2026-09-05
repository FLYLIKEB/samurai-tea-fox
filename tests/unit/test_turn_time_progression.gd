extends RefCounted

const Main = preload("res://src/main/main.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")

class Resources:
	extends RefCounted
	var kokoro := 100
	var hp := 100
	var ki := 100
	var hp_max := 100
	var ki_max := 100
	var kokoro_max := 100

	func reduce_kokoro(amount: int) -> int:
		var applied := mini(kokoro, amount)
		kokoro -= applied
		return applied

	func to_dictionary() -> Dictionary:
		return {
			"hp": hp,
			"hp_max": hp_max,
			"ki": ki,
			"ki_max": ki_max,
			"kokoro": kokoro,
			"kokoro_max": kokoro_max
		}

class TurnPlayer:
	extends Node2D
	var resources := Resources.new()
	var ability_runtime = null
	var accepted_types := {}

	func submit_command(command) -> bool:
		return accepted_types.has(command.type)

class FakeHud:
	extends Node
	signal mobile_command_issued(command)

	func show_inventory_menu() -> bool:
		return true

	func hide_menu() -> bool:
		return true

	func configure(_player, _world, _render_result, _context := {}) -> void:
		pass

	func show_command_feedback(_message: String) -> void:
		pass

class FakeInventory:
	extends RefCounted

	func get_total_quantity(item_id: String) -> int:
		return 1 if item_id == "bandage" else 0

	func to_snapshot() -> Dictionary:
		return {"slots": [{"item_id": "bandage", "quantity": 1}]}

class FakeConsumableService:
	extends RefCounted
	var active := false

	func has_definition(item_id: String) -> bool:
		return item_id == "bandage"

	func start_use(item_id: String, _inventory, _context := {}) -> Dictionary:
		if item_id != "bandage":
			return {"ok": false}
		active = true
		return {"ok": true, "item_id": item_id, "action": {"item_id": item_id}}

	func has_active_use() -> bool:
		return active

	func tick_use(_delta_seconds: float, _inventory, _resources) -> Dictionary:
		active = false
		return {"ok": true, "consumed": true, "action": {"item_id": "bandage", "completed": true}}

	func complete_use(_inventory, _resources) -> Dictionary:
		active = false
		return {"ok": true, "applied": true, "consumed": true}

	func to_snapshot() -> Dictionary:
		return {"schema_version": 1, "active_action": {"item_id": "bandage"} if active else {}}

class FakeAcquisitionService:
	extends RefCounted

	func handle_command(command) -> Dictionary:
		return {"ok": String(command.payload.get("target_id", "")) == "stone_node"}

	func to_snapshot() -> Dictionary:
		return {}

class FakeSaveStore:
	extends RefCounted
	var saved_run := {}

	func save_run(snapshot: Dictionary) -> Dictionary:
		saved_run = snapshot.duplicate(true)
		return {"ok": true}

func run(asserts) -> void:
	_assert_idle_and_explicit_turn_boundary(asserts)
	_assert_only_successful_turn_commands_advance_time(asserts)
	_assert_save_load_preserves_turn_time_without_idle_catchup(asserts)

func _assert_idle_and_explicit_turn_boundary(asserts) -> void:
	var main := Main.new()
	var player := TurnPlayer.new()
	_configure_time_fixture(main, player)

	main._physics_process(60.0)
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "idle physics frames do not advance game time")
	main._advance_time_for_turn()
	asserts.equal(main.time_state.phase_elapsed_seconds, 1.0, "one completed turn advances game time by one turn unit")

	player.free()
	main.free()

func _assert_only_successful_turn_commands_advance_time(asserts) -> void:
	var main := Main.new()
	var player := TurnPlayer.new()
	_configure_time_fixture(main, player)
	main.game_hud = FakeHud.new()
	main.inventory = FakeInventory.new()
	main.consumable_service = FakeConsumableService.new()
	main.acquisition_service = FakeAcquisitionService.new()
	main.save_store = FakeSaveStore.new()
	main.run_state = RunState.new()

	asserts.false_value(main.submit_action_command(null), "invalid command is rejected")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "invalid command does not advance time")

	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.OPEN_INVENTORY)), "UI command can be accepted")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "UI command does not advance time")

	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.RIGHT)), "blocked move is rejected by player command contract")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "blocked move does not advance time")

	player.accepted_types[GameCommand.Type.MOVE] = true
	main._on_player_grid_step_finished(Vector2i(2, 1))
	asserts.equal(main.time_state.phase_elapsed_seconds, 1.0, "finished grid step advances time exactly once")

	player.accepted_types[GameCommand.Type.ATTACK] = true
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)), "successful attack command is accepted")
	asserts.equal(main.time_state.phase_elapsed_seconds, 2.0, "successful attack advances time exactly once")

	player.accepted_types[GameCommand.Type.CAST_ABILITY] = true
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.CAST_ABILITY, Vector2i.RIGHT)), "successful ability command is accepted")
	asserts.equal(main.time_state.phase_elapsed_seconds, 3.0, "successful ability advances time exactly once")

	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "stone_node"})), "successful interaction command is accepted")
	asserts.equal(main.time_state.phase_elapsed_seconds, 4.0, "successful interaction advances time exactly once")

	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "missing_node"})), "failed interaction command is rejected")
	asserts.equal(main.time_state.phase_elapsed_seconds, 4.0, "failed interaction does not advance time")

	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "successful consumable command is accepted")
	asserts.equal(main.time_state.phase_elapsed_seconds, 4.0, "consumable start command does not advance time before completion")
	asserts.true_value(main.tick_consumable_runtime(1.0).ok, "consumable completion tick succeeds")
	asserts.equal(main.time_state.phase_elapsed_seconds, 5.0, "successful consumable completion advances time exactly once")

	main.game_hud.free()
	player.free()
	main.free()

func _assert_save_load_preserves_turn_time_without_idle_catchup(asserts) -> void:
	var main := Main.new()
	var player := TurnPlayer.new()
	var save_store := FakeSaveStore.new()
	_configure_time_fixture(main, player)
	main.save_store = save_store
	main.run_state = RunState.new()
	main._advance_time_for_turn()
	main._advance_time_for_turn()
	asserts.true_value(main.save_current_run().ok, "turn-based time snapshot saves")
	asserts.equal(float(save_store.saved_run.time.phase_elapsed_seconds), 2.0, "saved run records the last completed turn time")

	var restored := Main.new()
	var restored_player := TurnPlayer.new()
	_configure_time_fixture(restored, restored_player)
	asserts.true_value(restored.time_state.load_snapshot(save_store.saved_run.time).ok, "saved turn time snapshot loads")
	restored._physics_process(120.0)
	asserts.equal(restored.time_state.phase_elapsed_seconds, 2.0, "loaded time state ignores idle wall-clock catchup")

	restored_player.free()
	restored.free()
	player.free()
	main.free()

func _configure_time_fixture(main: Main, player: TurnPlayer) -> void:
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
