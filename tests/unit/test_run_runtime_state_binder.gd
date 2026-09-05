extends RefCounted

const RunRuntimeStateBinder = preload("res://src/save/run_runtime_state_binder.gd")
const Main = preload("res://src/main/main.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")

class FakeRuntime:
	extends RefCounted
	var snapshot: Dictionary

	func _init(initial_snapshot: Dictionary) -> void:
		snapshot = initial_snapshot.duplicate(true)

	func to_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func load_snapshot(next_snapshot: Dictionary) -> Dictionary:
		if bool(next_snapshot.get("fail", false)):
			return {"ok": false, "reason": "fixture_rejected_snapshot", "error": "Fixture rejected snapshot."}
		snapshot = next_snapshot.duplicate(true)
		return {"ok": true}

class PlayerResourcesRuntime:
	extends RefCounted
	var resources: PlayerResources

	func _init(initial_resources: PlayerResources) -> void:
		resources = initial_resources

	func to_snapshot() -> Dictionary:
		return resources.to_dictionary()

	func load_snapshot(next_snapshot: Dictionary) -> Dictionary:
		return resources.load_snapshot(next_snapshot)

func run(asserts) -> void:
	_assert_snapshot_to_run_state(asserts)
	_assert_hydrate_rolls_back_partial_failure(asserts)
	_assert_hydrate_preserves_resource_state_after_invalid_snapshot(asserts)
	_assert_hydrate_success_canonicalizes_runtime_snapshots(asserts)
	_assert_main_wrappers_use_runtime_binder(asserts)

func _assert_snapshot_to_run_state(asserts) -> void:
	var binder := RunRuntimeStateBinder.new()
	var state := RunState.new()
	state.seed = 101
	var inventory := FakeRuntime.new({"schema_version": 1, "slots": [{"item_id": "wood", "quantity": 2}]})
	var consumables := FakeRuntime.new({"schema_version": 1, "active_action": {}})
	var acquisitions := FakeRuntime.new({"schema_version": 1, "pickups": [{"pickup_id": "pickup_1"}]})

	var result: Dictionary = binder.snapshot_to_run_state(state, [
		{"field": "inventory", "runtime": inventory},
		{"field": "consumables", "runtime": consumables, "clear_when_empty_key": "active_action"},
		{"field": "acquisitions", "runtime": acquisitions, "active": true}
	])

	asserts.true_value(result.ok, "binder snapshots active runtimes")
	asserts.equal(state.inventory.slots[0].item_id, "wood", "binder writes inventory snapshot to run state")
	asserts.equal(state.consumables, {}, "binder keeps inactive consumable progress out of run state")
	asserts.equal(state.acquisitions.pickups[0].pickup_id, "pickup_1", "binder writes acquisition snapshot when active")
	asserts.equal(SaveCodec.CURRENT_SCHEMA_VERSION, 1, "runtime binder does not change save schema version")

func _assert_hydrate_rolls_back_partial_failure(asserts) -> void:
	var binder := RunRuntimeStateBinder.new()
	var state := RunState.new()
	state.seed = 101
	state.inventory = {"schema_version": 1, "slots": [{"item_id": "charcoal", "quantity": 1}]}
	state.equipment = {"schema_version": 1, "slots": {"tea_ware": {"item_id": "travel_bottle"}}}
	state.tea = {"fail": true}
	var inventory := FakeRuntime.new({"schema_version": 1, "slots": [{"item_id": "wood", "quantity": 2}]})
	var equipment := FakeRuntime.new({"schema_version": 1, "slots": {}})
	var tea := FakeRuntime.new({"schema_version": 1, "quick_slots": []})

	var result: Dictionary = binder.hydrate_from_run_state(state, [
		{"field": "inventory", "runtime": inventory},
		{"field": "equipment", "runtime": equipment},
		{"field": "tea", "runtime": tea}
	])

	asserts.false_value(result.ok, "binder reports hydrate failure")
	asserts.true_value(bool(result.get("rollback_ok", false)), "binder rolls back after partial hydrate failure")
	asserts.equal(inventory.to_snapshot().slots[0].item_id, "wood", "inventory runtime rolls back to pre-hydrate snapshot")
	asserts.equal(equipment.to_snapshot().slots, {}, "equipment runtime rolls back to pre-hydrate snapshot")
	asserts.equal(tea.to_snapshot().quick_slots, [], "failing runtime keeps its pre-hydrate snapshot")
	asserts.equal(result.applied_fields, ["inventory", "equipment"], "failure reports fields applied before rollback")

func _assert_hydrate_preserves_resource_state_after_invalid_snapshot(asserts) -> void:
	var binder := RunRuntimeStateBinder.new()
	var state := RunState.new()
	state.seed = 101
	state.inventory = {"schema_version": 1, "slots": [{"item_id": "charcoal", "quantity": 1}]}
	state.player_resources = {
		"hp": 120,
		"hp_max": 100,
		"ki": 60,
		"ki_max": 100,
		"kokoro": 70,
		"kokoro_max": 100,
		"kokoro_low_threshold": 20
	}
	var inventory := FakeRuntime.new({"schema_version": 1, "slots": [{"item_id": "wood", "quantity": 2}]})
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.apply_damage(25)
	resources.spend_ki(30)
	resources.reduce_kokoro(40)
	var resources_before: Dictionary = resources.to_dictionary()

	var result: Dictionary = binder.hydrate_from_run_state(state, [
		{"field": "inventory", "runtime": inventory},
		{"field": "player_resources", "runtime": PlayerResourcesRuntime.new(resources)}
	])

	asserts.false_value(result.ok, "binder rejects invalid player resource hydrate")
	asserts.equal(result.reason, "invalid_resource_snapshot", "resource hydrate failure keeps its reason")
	asserts.true_value(bool(result.get("rollback_ok", false)), "binder rolls back runtimes after invalid resource hydrate")
	asserts.equal(inventory.to_snapshot().slots[0].item_id, "wood", "inventory runtime rolls back before resource hydrate failure")
	asserts.equal(resources.to_dictionary(), resources_before, "invalid resource hydrate preserves pre-hydrate resources")
	asserts.equal(result.applied_fields, ["inventory"], "resource failure reports fields applied before rollback")

func _assert_hydrate_success_canonicalizes_runtime_snapshots(asserts) -> void:
	var binder := RunRuntimeStateBinder.new()
	var state := RunState.new()
	state.seed = 101
	state.inventory = {"schema_version": 1, "slots": [{"item_id": "stone", "quantity": 3}]}
	state.consumables = {"schema_version": 1, "active_action": {"item_id": "bandage"}}
	var inventory := FakeRuntime.new({"schema_version": 1, "slots": []})
	var consumables := FakeRuntime.new({"schema_version": 1, "active_action": {}})

	var result: Dictionary = binder.hydrate_from_run_state(state, [
		{"field": "inventory", "runtime": inventory},
		{"field": "consumables", "runtime": consumables, "clear_when_empty_key": "active_action"}
	])

	asserts.true_value(result.ok, "binder hydrates all valid runtime snapshots")
	asserts.equal(inventory.to_snapshot().slots[0].item_id, "stone", "inventory runtime receives saved snapshot")
	asserts.equal(consumables.to_snapshot().active_action.item_id, "bandage", "consumable runtime receives active action snapshot")
	asserts.equal(state.inventory.slots[0].quantity, 3, "successful hydrate writes canonical runtime state back to RunState")
	asserts.equal(state.consumables.active_action.item_id, "bandage", "successful hydrate preserves active consumable state")

func _assert_main_wrappers_use_runtime_binder(asserts) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	main.run_state.seed = 101
	main.inventory = FakeRuntime.new({"schema_version": 1, "slots": [{"item_id": "wood", "quantity": 2}]})
	main.equipment = FakeRuntime.new({"schema_version": 1, "slots": {}})
	main.tea_service = FakeRuntime.new({"schema_version": 1, "quick_slots": []})
	main.consumable_service = FakeRuntime.new({"schema_version": 1, "active_action": {}})
	main.memory_tea_cutscene_runtime = FakeRuntime.new({"schema_version": 1, "active_sequence": {}})

	var saved: Dictionary = main.snapshot_run_state()
	asserts.equal(saved.inventory.slots[0].item_id, "wood", "Main snapshot_run_state keeps the public wrapper")
	asserts.equal(saved.consumables, {}, "Main snapshot wrapper keeps empty consumables out of run save")

	var restore_state := RunState.new()
	restore_state.seed = 102
	restore_state.inventory = {"schema_version": 1, "slots": [{"item_id": "stone", "quantity": 1}]}
	restore_state.equipment = {"schema_version": 1, "slots": {"tea_ware": {"item_id": "travel_bottle"}}}
	restore_state.tea = {"fail": true}
	var restored: Dictionary = main.restore_run_state(restore_state)
	asserts.false_value(restored.ok, "Main restore wrapper reports runtime hydrate failure")
	asserts.true_value(bool(restored.get("rollback_ok", false)), "Main restore wrapper rolls back partial runtime hydrate")
	asserts.equal(main.inventory.to_snapshot().slots[0].item_id, "wood", "Main restore rollback preserves previous inventory runtime")
	asserts.equal(main.equipment.to_snapshot().slots, {}, "Main restore rollback preserves previous equipment runtime")
	asserts.equal(main.run_state.seed, 101, "Main restore does not swap run_state after failed hydrate")
	main.free()
