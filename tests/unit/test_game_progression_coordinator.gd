extends RefCounted

const GameProgressionCoordinator = preload("res://src/main/game_progression_coordinator.gd")
const RunState = preload("res://src/save/run_state.gd")

class FakeCoreTeaWareCollection:
	extends RefCounted

	var preflight_state = null
	var reward_state = null

	func validate_boss_resolution_rewards(_event: Dictionary, state) -> Dictionary:
		preflight_state = state
		return {"ok": true}

	func record_boss_resolution_rewards(_event: Dictionary, state) -> Dictionary:
		reward_state = state
		return {"ok": true}

class FakeProgressionState:
	extends RefCounted

	func complete_dungeon(_biome_id: String) -> Dictionary:
		return {"ok": true}

	func complete_dungeon_transaction(_biome_id: String, transaction: Callable) -> Dictionary:
		return transaction.call()

	func current_biome_id() -> String:
		return "common_region"

class FakeMain:
	extends RefCounted

	var run_state: RunState
	var core_tea_ware_collection := FakeCoreTeaWareCollection.new()
	var dungeon_runtime = null

	func _normalize_reward_hook_result(result) -> Dictionary:
		return result if result is Dictionary else {"ok": bool(result)}

func run(asserts) -> void:
	var coordinator := GameProgressionCoordinator.new()
	var main := FakeMain.new()
	var configured_state := RunState.new()
	main.run_state = configured_state

	var configured := coordinator.configure_dungeon_runtime(
		main,
		FakeProgressionState.new(),
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.true_value(configured.ok, "dungeon runtime configures for progression coordinator")

	var active_state := RunState.new()
	main.run_state = active_state
	var reward_hook: Callable = main.dungeon_runtime.get("_reward_hook")
	asserts.true_value(reward_hook.call({}).ok, "configured reward hook accepts the active run")
	asserts.equal(main.core_tea_ware_collection.preflight_state, active_state, "reward preflight reads the current run state")
	asserts.equal(main.core_tea_ware_collection.reward_state, active_state, "reward recording writes to the current run state")
	asserts.false_value(main.core_tea_ware_collection.reward_state == configured_state, "reward hook does not retain the configured run state")
