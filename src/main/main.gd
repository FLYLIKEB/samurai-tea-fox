extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const DEFAULT_RUN_SEED := 11037
const FRESH_RUN_SEED := 0

@onready var player = $Player
@onready var combat_dummy = $CombatDummy
@onready var world_visuals: Node2D = $WorldVisuals
@onready var game_hud = $GameHud

var catalog
var inventory
var equipment
var tea_service
var acquisition_service
var run_lifecycle_service
var save_store = SaveStore.new()
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
var world_render_result: Dictionary = {}
var _desktop_adapter := DesktopCommandAdapter.new()
var _movement_selector := MovementCommandSelector.new()

func _ready() -> void:
	catalog = DataCatalog.new()
	var result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
		return
	var runtime_result := _configure_run_services(catalog)
	if not runtime_result.ok:
		push_error(runtime_result.error)
		return
	var combat_lifecycle_result := _configure_combat_lifecycle()
	if not combat_lifecycle_result.ok:
		push_error(combat_lifecycle_result.error)
		return

	if run_state == null:
		run_state = RunState.new()
	run_state.data_version = catalog.data_version
	if run_state.seed == 0:
		run_state.seed = DEFAULT_RUN_SEED
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		push_error(world_result.error)

func _configure_combat_lifecycle() -> Dictionary:
	var player_combat_result: Dictionary = player.configure_combat(catalog)
	if not player_combat_result.ok:
		return player_combat_result
	var lifecycle_result: Dictionary = RunLifecycleService.from_catalog(catalog)
	if not lifecycle_result.ok:
		return lifecycle_result
	run_lifecycle_service = lifecycle_result.run_lifecycle_service
	player.resources.hp_depleted.connect(_on_player_hp_depleted)
	var dummy_combat_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
	if not dummy_combat_result.ok:
		return dummy_combat_result
	return {"ok": true}

func _configure_world_for_current_run() -> Dictionary:
	var common_biome: Dictionary = catalog.find_by_id("biomes", "common_region")
	if common_biome.is_empty():
		return {"ok": false, "reason": "missing_common_biome", "error": "No common biome data loaded."}
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		return progression_result
	var projection: Dictionary = progression_result.progression_state.to_projection()
	generated_world = generator.generate(run_state.seed, catalog.data_version, common_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), {"progression_projection": projection})
	if not generated_world.get("ok", false):
		return {"ok": false, "reason": "world_generation_failed", "error": String(generated_world.get("failure_reason", "World generation failed."))}
	var acquisition_result := _configure_acquisition_for_generated_world()
	if not acquisition_result.ok:
		return acquisition_result
	var drop_connection := _connect_acquisition_combat_source(combat_dummy)
	if not drop_connection.ok:
		return drop_connection
	_render_generated_world(generated_world)
	game_hud.configure(player, generated_world, world_render_result)
	return {"ok": true}

func _physics_process(_delta: float) -> void:
	var desktop_command = _desktop_adapter.poll_movement_command()
	player.submit_command(_movement_selector.select(desktop_command))
	if Input.is_action_just_pressed("attack"):
		player.submit_command(_desktop_adapter.command_for_action("attack", desktop_command.direction))
	if Input.is_action_just_pressed("dodge"):
		player.submit_command(_desktop_adapter.command_for_action("dodge", desktop_command.direction))

func submit_mobile_movement_command(command) -> bool:
	return _movement_selector.submit_mobile_command(command)

func submit_mobile_action_command(command) -> bool:
	if command is GameCommand and command.type == GameCommand.Type.INTERACT and not String(command.payload.get("target_id", "")).is_empty():
		return acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
	return player.submit_command(command)

func restore_run_state(state) -> Dictionary:
	if not state is RunState:
		return {"ok": false, "reason": "invalid_run_state", "error": "Main runtime requires a RunState."}
	var inventory_before: Dictionary = inventory.to_snapshot() if inventory != null else {}
	var acquisitions_before: Dictionary = acquisition_service.to_snapshot() if acquisition_service != null else {}
	if inventory != null and not state.inventory.is_empty():
		var inventory_result: Dictionary = inventory.load_snapshot(state.inventory)
		if not inventory_result.ok:
			return inventory_result
	if acquisition_service != null and not state.acquisitions.is_empty():
		var acquisition_result: Dictionary = acquisition_service.load_snapshot(state.acquisitions)
		if not acquisition_result.ok:
			if inventory != null and not inventory_before.is_empty():
				inventory.load_snapshot(inventory_before)
			if not acquisitions_before.is_empty():
				acquisition_service.load_snapshot(acquisitions_before)
			return acquisition_result
	run_state = state
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if acquisition_service != null:
		run_state.acquisitions = acquisition_service.to_snapshot()
	return {"ok": true}

func snapshot_run_state() -> Dictionary:
	if run_state == null:
		run_state = RunState.new()
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if acquisition_service != null:
		run_state.acquisitions = acquisition_service.to_snapshot()
	return run_state.to_dictionary()

func _configure_run_services(loaded_catalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(loaded_catalog)
	if not inventory_result.ok:
		return inventory_result
	var equipment_result: Dictionary = EquipmentModel.from_catalog(loaded_catalog)
	if not equipment_result.ok:
		return equipment_result
	var tea_result: Dictionary = TeaService.from_catalog(loaded_catalog)
	if not tea_result.ok:
		return tea_result
	inventory = inventory_result.inventory
	if run_state != null and not run_state.inventory.is_empty():
		var inventory_load_result: Dictionary = inventory.load_snapshot(run_state.inventory)
		if not inventory_load_result.ok:
			return inventory_load_result
	equipment = equipment_result.equipment
	tea_service = tea_result.tea_service
	tea_service.drink_completed.connect(_on_tea_drink_completed)
	return {"ok": true}

func _configure_acquisition_for_generated_world() -> Dictionary:
	if not generated_world.get("ok", false) or typeof(generated_world.get("world_data")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_generated_world", "error": "Acquisition requires a generated world snapshot."}
	var saved_acquisitions := run_state.acquisitions.duplicate(true) if run_state != null else {}
	world_data = WorldData.from_dictionary(generated_world.world_data)
	acquisition_service = AcquisitionService.new()
	var definitions := _confirmed_generated_resource_definitions(generated_world.get("resource_nodes", []))
	var configured: Dictionary = acquisition_service.configure(inventory, world_data, definitions, _generated_drop_definitions())
	if not configured.ok:
		return configured
	var definition_ids := {}
	for definition in definitions:
		definition_ids[String(definition.id)] = true
	for node in generated_world.get("resource_nodes", []):
		var resource_id := String(node.get("resource_id", ""))
		if not definition_ids.has(resource_id):
			continue
		var registered: Dictionary = acquisition_service.register_gatherable(
			String(node.get("id", "")),
			resource_id,
			_vector_from_dictionary(node.get("position", {}))
		)
		if not registered.ok:
			return registered
	if not saved_acquisitions.is_empty():
		var loaded: Dictionary = acquisition_service.load_snapshot(saved_acquisitions)
		if not loaded.ok:
			return loaded
	acquisition_service.changed.connect(_on_acquisition_changed)
	_on_acquisition_changed(acquisition_service.to_snapshot())
	return {"ok": true}

func _confirmed_generated_resource_definitions(resource_nodes: Array) -> Array:
	var definitions := []
	var seen := {}
	for node in resource_nodes:
		var resource_id := String(node.get("resource_id", ""))
		if resource_id.is_empty() or seen.has(resource_id) or inventory == null or not inventory.has_definition(resource_id):
			continue
		var item: Dictionary = catalog.find_by_id("items", resource_id)
		if String(item.get("status", "")) != "확정" or String(item.get("type", "")) != "재료":
			continue
		definitions.append({"id": resource_id, "item_id": resource_id, "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT})
		seen[resource_id] = true
	return definitions

func _generated_drop_definitions() -> Array:
	var grants_by_monster := {}
	for drop in catalog.get_definitions("drops"):
		var monster_id := String(drop.get("monster_id", ""))
		var target_id := String(drop.get("item_id", drop.get("tea_id", "")))
		if not grants_by_monster.has(monster_id):
			grants_by_monster[monster_id] = []
		grants_by_monster[monster_id].append({
			"drop_id": String(drop.get("id", "")),
			"item_id": target_id,
			"min_quantity": int(drop.get("min_quantity", 0)),
			"max_quantity": int(drop.get("max_quantity", 0)),
			"chance": float(drop.get("chance", 0.0)),
			"condition": String(drop.get("condition", "")),
			"policy": AcquisitionService.POLICY_DIRECT
		})
	var definitions := []
	var monster_ids: Array = grants_by_monster.keys()
	monster_ids.sort()
	for monster_id in monster_ids:
		definitions.append({"monster_id": monster_id, "grants": grants_by_monster[monster_id]})
	return definitions

func _connect_acquisition_combat_source(source) -> Dictionary:
	if source == null or not source.has_signal("drop_requested"):
		return {"ok": false, "reason": "invalid_drop_source", "error": "Combat source must expose drop_requested."}
	var callback := Callable(self, "_on_combat_drop_requested")
	if not source.is_connected("drop_requested", callback):
		source.connect("drop_requested", callback)
	return {"ok": true}

func _on_acquisition_changed(snapshot: Dictionary) -> void:
	if run_state != null:
		run_state.acquisitions = snapshot.duplicate(true)

func _on_combat_drop_requested(event: Dictionary) -> void:
	if acquisition_service == null:
		return
	var normalized := event.duplicate(true)
	if not normalized.has("position") and combat_dummy != null:
		normalized.position = {
			"x": int(round(combat_dummy.global_position.x / 32.0)),
			"y": int(round(combat_dummy.global_position.y / 32.0))
		}
	var result: Dictionary = acquisition_service.process_drop_request(normalized)
	if not result.ok:
		push_error(result.error)

func _on_player_hp_depleted() -> Dictionary:
	if run_lifecycle_service == null:
		return {"ok": false, "reason": "missing_run_lifecycle", "error": "Run lifecycle service is not configured."}
	var result: Dictionary = run_lifecycle_service.resolve_lethal_hp(
		player.resources,
		inventory,
		player.combat_state,
		player.get_combat_id()
	)
	if not result.ok:
		push_error(result.error)
		return result
	if String(result.get("state", "")) != "death_pending":
		return result
	var replacement := _replace_confirmed_dead_run()
	if not replacement.ok:
		push_error(replacement.error)
	return replacement

func _replace_confirmed_dead_run() -> Dictionary:
	var confirmed: Dictionary = run_lifecycle_service.confirm_death(save_store, run_state)
	if not confirmed.ok:
		return confirmed
	if bool(confirmed.get("preserved_newer_run", false)):
		var preserved_run = confirmed.get("current_run_state")
		if not preserved_run is RunState:
			var loaded: Dictionary = save_store.load_run()
			if not loaded.ok:
				return loaded
			preserved_run = loaded.run_state
		var preserved_activation := _activate_run_state(preserved_run)
		if not preserved_activation.ok:
			return preserved_activation
		return {
			"ok": true,
			"state": "preserved_run_activated",
			"preserved_newer_run": true,
			"invalidated_lifecycle_epoch": int(confirmed.get("invalidated_lifecycle_epoch", 0)),
			"current_lifecycle_epoch": preserved_run.lifecycle_epoch
		}
	var fresh_run: RunState = run_lifecycle_service.create_fresh_run_after_confirmed_death(
		int(confirmed.invalidated_lifecycle_epoch),
		FRESH_RUN_SEED
	)
	var save_result: Dictionary = save_store.save_run(fresh_run)
	if not save_result.ok:
		return save_result
	var activation_result := _activate_run_state(fresh_run)
	if not activation_result.ok:
		return activation_result
	return {
		"ok": true,
		"state": "fresh_run",
		"invalidated_lifecycle_epoch": int(confirmed.invalidated_lifecycle_epoch),
		"lifecycle_epoch": fresh_run.lifecycle_epoch
	}

func _activate_run_state(state: RunState) -> Dictionary:
	run_state = state
	var services_result := _configure_run_services(catalog)
	if not services_result.ok:
		return services_result
	var combat_lifecycle_result := _configure_combat_lifecycle()
	if not combat_lifecycle_result.ok:
		return combat_lifecycle_result
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		return world_result
	return {"ok": true}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _on_tea_drink_completed(result: Dictionary) -> void:
	if equipment == null:
		return
	var accounting_result: Dictionary = equipment.record_tea_ware_use_completion(result, inventory)
	if not accounting_result.ok:
		push_error(accounting_result.error)

func _render_generated_world(world: Dictionary) -> void:
	_hide_prototype_visuals()
	var renderer_input: Dictionary = world.get("renderer_input", {})
	var origin := _centered_world_origin(renderer_input)
	world_render_result = WorldSceneRenderer.new().render(
		world_visuals,
		renderer_input,
		_owner_sprite_sources(world),
		origin
	)
	if not world_render_result.ok:
		push_error(world_render_result.error)

func _centered_world_origin(renderer_input: Dictionary) -> Vector2:
	var bounds: Dictionary = renderer_input.get("bounds", {})
	var tile_size := int(renderer_input.get("tile_size", 32))
	return Vector2(
		-float(int(bounds.get("width", 0)) * tile_size) * 0.5,
		-float(int(bounds.get("height", 0)) * tile_size) * 0.5
	)

func _owner_sprite_sources(world: Dictionary) -> Dictionary:
	var sources := {
		WorldData.LANDMARK_ENTRY: "res://assets/sprites/objects/structures/small_signpost_32x32.png",
		WorldData.LANDMARK_CORE_DUNGEON: "res://assets/sprites/objects/structures/dungeon_entry_small_32x32.png",
		WorldData.LANDMARK_TELEPORT_ZONE: "res://assets/sprites/objects/shrine-props/stone_pagoda_lantern_32x32.png",
		"wood": "res://assets/sprites/objects/nature/log_32x32.png",
		"stone": "res://assets/sprites/objects/natural-props/small_rock_32x32.png",
		"clay": "res://assets/sprites/objects/natural-props/mud_patch_32x32.png"
	}
	for node in world.get("resource_nodes", []):
		var owner_id := String(node.get("id", ""))
		var resource_id := String(node.get("resource_id", ""))
		if owner_id != "" and sources.has(resource_id):
			sources[owner_id] = sources[resource_id]
	return sources

func _hide_prototype_visuals() -> void:
	for child in get_children():
		if child is Polygon2D:
			child.visible = false
