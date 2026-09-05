extends RefCounted

const DungeonCommandCoordinator = preload("res://src/main/dungeon_command_coordinator.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const RunState = preload("res://src/save/run_state.gd")

class FakeCommand:
	extends RefCounted
	var payload: Dictionary

	func _init(next_payload := {}) -> void:
		payload = next_payload.duplicate(true)

class FakeDungeonRuntime:
	extends RefCounted
	var lifecycle_state := DungeonInstanceState.STATE_OUTSIDE
	var completed_payloads := []
	var returns := []

	func to_projection() -> Dictionary:
		return {
			"lifecycle_state": lifecycle_state,
			"dungeon_id": "common_region_core_dungeon"
		}

	func complete_dungeon(payload: Dictionary) -> Dictionary:
		completed_payloads.append(payload.duplicate(true))
		lifecycle_state = DungeonInstanceState.STATE_COMPLETED
		return {"ok": true}

	func begin_return() -> Dictionary:
		returns.append("begin")
		lifecycle_state = DungeonInstanceState.STATE_RETURNING
		return {"ok": true}

	func finish_return() -> Dictionary:
		returns.append("finish")
		lifecycle_state = DungeonInstanceState.STATE_RETURNED
		return {"ok": true}

class FakeHud:
	extends RefCounted
	var feedback := []
	var events := []

	func show_command_feedback(message: String) -> void:
		feedback.append(message)

	func show_status_event(event: Dictionary) -> void:
		events.append(event.duplicate(true))

var calls := []
var entered_result := {"ok": true}
var runtime_active := false
var objective_met := false

func run(asserts) -> void:
	_assert_entry_only_saves_refreshes_and_emits_entered(asserts)
	_assert_completion_applies_defaults_then_returns(asserts)

func _assert_entry_only_saves_refreshes_and_emits_entered(asserts) -> void:
	calls.clear()
	entered_result = {"ok": true}
	runtime_active = false
	objective_met = false
	var runtime := FakeDungeonRuntime.new()
	var state := RunState.new()
	state.current_biome_id = "common_region"
	var hud := FakeHud.new()

	var accepted := _coordinator().handle_complete_dungeon_command(
		FakeCommand.new({"entry_only": true}),
		runtime,
		state,
		true,
		hud
	)

	asserts.true_value(accepted, "entry-only dungeon command is accepted")
	asserts.equal(_without_debug(calls), ["ensure_playable", "ensure_entered", "save", "hud"], "entry-only command keeps save before HUD refresh")
	asserts.equal(hud.events[0].type, "dungeon_entered", "entry-only command emits dungeon entered status")
	asserts.equal(runtime.completed_payloads, [], "entry-only command does not complete the dungeon")

func _assert_completion_applies_defaults_then_returns(asserts) -> void:
	calls.clear()
	entered_result = {"ok": true}
	runtime_active = false
	objective_met = true
	var runtime := FakeDungeonRuntime.new()
	runtime.lifecycle_state = DungeonInstanceState.STATE_ACTIVE
	var state := RunState.new()
	state.current_biome_id = "mountain_region"

	var accepted := _coordinator().handle_complete_dungeon_command(
		FakeCommand.new({}),
		runtime,
		state,
		true,
		null
	)

	asserts.true_value(accepted, "completed dungeon command is accepted")
	asserts.equal(_without_debug(calls), ["ensure_playable", "ensure_entered", "sync", "return", "save", "hud"], "completion syncs active dungeon before return and save")
	asserts.equal(runtime.completed_payloads[0].resolution_type, "combat", "completion defaults resolution type")
	asserts.equal(runtime.completed_payloads[0].choice_key, "dev17_minimal_clear", "completion defaults choice key")
	asserts.equal(runtime.completed_payloads[0].progression_unlock_ids, ["mountain_region"], "completion defaults progression unlock to current biome")
	asserts.equal(runtime.returns, ["begin", "finish"], "completion finishes runtime return lifecycle")

func _coordinator() -> DungeonCommandCoordinator:
	return DungeonCommandCoordinator.new(
		Callable(self, "_debug"),
		Callable(self, "_ensure_playable"),
		Callable(self, "_ensure_entered"),
		Callable(self, "_runtime_is_active"),
		Callable(self, "_restore"),
		Callable(self, "_objective_met"),
		Callable(self, "_sync"),
		Callable(self, "_return"),
		Callable(self, "_save"),
		Callable(self, "_hud")
	)

func _debug(_message: String) -> void:
	if calls.is_empty() or calls.back() != "debug":
		calls.append("debug")

func _ensure_playable() -> Dictionary:
	calls.append("ensure_playable")
	return {"ok": true}

func _ensure_entered() -> Dictionary:
	calls.append("ensure_entered")
	return entered_result.duplicate(true)

func _runtime_is_active() -> bool:
	return runtime_active

func _restore() -> void:
	calls.append("restore")

func _objective_met(_payload: Dictionary) -> bool:
	return objective_met

func _sync() -> void:
	calls.append("sync")

func _return() -> void:
	calls.append("return")

func _save() -> Dictionary:
	calls.append("save")
	return {"ok": true}

func _hud() -> void:
	calls.append("hud")

func _without_debug(values: Array) -> Array:
	var filtered := []
	for value in values:
		if value != "debug":
			filtered.append(value)
	return filtered
