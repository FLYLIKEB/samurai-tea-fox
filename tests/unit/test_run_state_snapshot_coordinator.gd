extends RefCounted

const RunRuntimeStateBinder = preload("res://src/save/run_runtime_state_binder.gd")
const RunState = preload("res://src/save/run_state.gd")
const RunStateSnapshotCoordinator = preload("res://src/main/run_state_snapshot_coordinator.gd")

class FakeRuntime:
	extends RefCounted

	var snapshot: Dictionary

	func _init(initial_snapshot: Dictionary) -> void:
		snapshot = initial_snapshot.duplicate(true)

	func to_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func load_snapshot(next_snapshot: Dictionary) -> Dictionary:
		snapshot = next_snapshot.duplicate(true)
		return {"ok": true}

func run(asserts) -> void:
	_assert_snapshot_stores_runtime_state_and_biome_alias(asserts)
	_assert_restore_hydrates_before_swapping_state(asserts)
	_assert_legacy_alias_migration_is_biome_scoped(asserts)

func _assert_snapshot_stores_runtime_state_and_biome_alias(asserts) -> void:
	var coordinator := RunStateSnapshotCoordinator.new()
	var state := RunState.new()
	state.current_biome_id = "common_region"
	var inventory := FakeRuntime.new({"slots": [{"item_id": "wood", "quantity": 2}]})

	var result: Dictionary = coordinator.snapshot_run_state(state, RunRuntimeStateBinder.new(), [
		{"field": "inventory", "runtime": inventory}
	], {
		"player_cell": Vector2i(3, 4),
		"overworld_enemy_state": {"cell": {"x": 5, "y": 6}},
		"generated_world": {"biome_id": "mountain_region"}
	})

	asserts.true_value(result.ok, "snapshot coordinator writes current runtime state")
	asserts.equal(result.run_state.inventory.slots[0].item_id, "wood", "snapshot stores inventory runtime")
	asserts.equal(result.run_state.player_cell, {"x": 3, "y": 4}, "snapshot stores current player cell")
	asserts.equal(result.run_state.overworld_enemy_state.cell, {"x": 5, "y": 6}, "snapshot stores overworld enemy state")
	asserts.equal(result.run_state.biome_acquisitions.keys(), ["mountain_region"], "snapshot aliases state by current generated biome")

func _assert_restore_hydrates_before_swapping_state(asserts) -> void:
	var coordinator := RunStateSnapshotCoordinator.new()
	var restore_state := RunState.new()
	restore_state.inventory = {"slots": [{"item_id": "stone", "quantity": 1}]}
	var inventory := FakeRuntime.new({"slots": []})

	var result: Dictionary = coordinator.restore_run_state(restore_state, RunRuntimeStateBinder.new(), [
		{"field": "inventory", "runtime": inventory}
	])

	asserts.true_value(result.ok, "restore coordinator accepts valid RunState")
	asserts.equal(inventory.to_snapshot().slots[0].item_id, "stone", "restore hydrates runtime before returning state")
	asserts.equal(result.run_state, restore_state, "restore returns the hydrated state for Main to swap")

func _assert_legacy_alias_migration_is_biome_scoped(asserts) -> void:
	var coordinator := RunStateSnapshotCoordinator.new()
	var state := RunState.new()
	state.acquisitions = {"gatherables": [{"node_id": "tea_leaf_1"}]}
	state.map_discovery = {"cells": {"1,1": true}}

	coordinator.prepare_runtime_state_aliases_for_biome(state, "common_region")

	asserts.equal(state.biome_acquisitions.common_region.gatherables[0].node_id, "tea_leaf_1", "legacy acquisitions migrate to the active biome")
	asserts.equal(state.map_discovery_by_biome.common_region.cells, {"1,1": true}, "legacy map discovery migrates to the active biome")
