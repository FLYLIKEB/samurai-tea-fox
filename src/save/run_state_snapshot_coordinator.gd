extends RefCounted
class_name RunStateSnapshotCoordinator

const RunState = preload("res://src/save/run_state.gd")

func restore_run_state(state, binder, entries: Array) -> Dictionary:
	if not state is RunState:
		return {"ok": false, "reason": "invalid_run_state", "error": "Main runtime requires a RunState."}
	var hydrate_result: Dictionary = binder.hydrate_from_run_state(state, entries)
	if not hydrate_result.ok:
		return hydrate_result
	return {"ok": true, "run_state": state}

func snapshot_run_state(current_state, binder, entries: Array, context := {}) -> Dictionary:
	var state: RunState = current_state if current_state is RunState else RunState.new()
	var player_resources = context.get("player_resources")
	if player_resources != null and player_resources.has_method("to_dictionary"):
		state.player_resources = player_resources.to_dictionary()
	if bool(context.get("in_dungeon_map", false)):
		var sync_dungeon_runtime_save_state: Callable = context.get("sync_dungeon_runtime_save_state", Callable())
		if sync_dungeon_runtime_save_state.is_valid():
			sync_dungeon_runtime_save_state.call()
	elif context.has("player_cell"):
		var cell: Vector2i = context.player_cell
		state.player_cell = {"x": cell.x, "y": cell.y}
	if not bool(context.get("in_dungeon_map", false)) and context.has("overworld_enemy_state"):
		state.overworld_enemy_state = context.overworld_enemy_state.duplicate(true)
	var snapshot_result: Dictionary = binder.snapshot_to_run_state(state, entries)
	if not snapshot_result.ok:
		return snapshot_result
	store_current_biome_runtime_aliases(
		state,
		context.get("biome_id", current_runtime_biome_id(state, context.get("generated_world", {})))
	)
	return {"ok": true, "run_state": state, "snapshot": state.to_dictionary()}

func load_or_create_run_state(current_state, start_mode: String, save_store, catalog, default_run_seed: int) -> Dictionary:
	if current_state != null:
		return {"ok": true, "state": "provided", "run_state": current_state}
	if start_mode in ["new", "cheat"]:
		return create_new_run_state_from_start_request(start_mode, save_store, catalog, default_run_seed)
	if save_store != null and FileAccess.file_exists(save_store.run_path):
		var loaded: Dictionary = save_store.load_run()
		if not loaded.ok:
			return loaded
		return {"ok": true, "state": "loaded", "run_state": loaded.run_state}
	return {"ok": true, "state": "created", "run_state": RunState.new()}

func create_new_run_state_from_start_request(_start_mode: String, save_store, catalog, default_run_seed: int) -> Dictionary:
	var state := RunState.new()
	if catalog != null:
		state.data_version = catalog.data_version
	state.seed = default_run_seed
	if save_store == null:
		return {"ok": true, "state": "created_new_start", "run_state": state}
	var invalidation: Dictionary = save_store.invalidate_run()
	if not invalidation.ok and String(invalidation.get("reason", "")) != "missing_invalidation":
		return invalidation
	state.lifecycle_epoch = int(invalidation.get("invalidated_lifecycle_epoch", 0)) + 1
	var saved: Dictionary = save_store.save_run(state)
	if not saved.ok:
		return saved
	return {"ok": true, "state": "created_new_start", "run_state": state}

func sync_runtime_state(current_state, binder, entries: Array) -> Dictionary:
	var state: RunState = current_state if current_state is RunState else RunState.new()
	var result: Dictionary = binder.snapshot_to_run_state(state, entries)
	if result.ok:
		result["run_state"] = state
	return result

func prepare_runtime_state_aliases_for_biome(state: RunState, biome_id: String) -> void:
	if state == null or biome_id.is_empty():
		return
	migrate_legacy_runtime_aliases(state, biome_id)
	state.acquisitions = _dictionary_value(state.biome_acquisitions.get(biome_id, {}))
	state.map_discovery = _dictionary_value(state.map_discovery_by_biome.get(biome_id, {}))

func store_current_biome_runtime_aliases(state: RunState, biome_id := "") -> void:
	if state == null or biome_id.is_empty():
		return
	state.biome_acquisitions[biome_id] = state.acquisitions.duplicate(true)
	state.map_discovery_by_biome[biome_id] = state.map_discovery.duplicate(true)

func migrate_legacy_runtime_aliases(state: RunState, biome_id: String) -> void:
	if state == null or biome_id.is_empty():
		return
	if not state.acquisitions.is_empty() and state.biome_acquisitions.is_empty():
		state.biome_acquisitions[biome_id] = state.acquisitions.duplicate(true)
	if not state.map_discovery.is_empty() and state.map_discovery_by_biome.is_empty():
		state.map_discovery_by_biome[biome_id] = state.map_discovery.duplicate(true)

func current_runtime_biome_id(state: RunState, generated_world) -> String:
	if state == null:
		return ""
	var world_biome_id := String(generated_world.get("biome_id", "")) if typeof(generated_world) == TYPE_DICTIONARY else ""
	return world_biome_id if not world_biome_id.is_empty() else String(state.current_biome_id)

func restore_run_state_from_snapshot(current_state, snapshot: Dictionary) -> RunState:
	var state: RunState = current_state if current_state is RunState else RunState.new()
	var restored: RunState = RunState.from_dictionary(snapshot)
	for field in restored.to_dictionary().keys():
		state.set(String(field), restored.get(String(field)))
	return state

static func vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
