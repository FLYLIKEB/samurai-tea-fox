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

@onready var player = $Player
@onready var combat_dummy = $CombatDummy

var catalog
var inventory
var equipment
var tea_service
var acquisition_service
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
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
	var player_combat_result: Dictionary = player.configure_combat(catalog)
	if not player_combat_result.ok:
		push_error(player_combat_result.error)
		return
	var dummy_combat_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
	if not dummy_combat_result.ok:
		push_error(dummy_combat_result.error)
		return

	var common_biome: Dictionary = catalog.find_by_id("biomes", "common_region")
	if common_biome.is_empty():
		push_error("No common biome data loaded.")
		return

	if run_state == null:
		run_state = RunState.new()
	run_state.data_version = catalog.data_version
	run_state.seed = 11037
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		push_error(progression_result.error)
		return
	var projection: Dictionary = progression_result.progression_state.to_projection()
	generated_world = generator.generate(11037, catalog.data_version, common_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), {"progression_projection": projection})
	if not generated_world.get("ok", false):
		push_error(String(generated_world.get("failure_reason", "World generation failed.")))
		return
	var acquisition_result := _configure_acquisition_for_generated_world()
	if not acquisition_result.ok:
		push_error(acquisition_result.error)
		return
	var drop_connection := _connect_acquisition_combat_source(combat_dummy)
	if not drop_connection.ok:
		push_error(drop_connection.error)

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

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _on_tea_drink_completed(result: Dictionary) -> void:
	if equipment == null:
		return
	var accounting_result: Dictionary = equipment.record_tea_ware_use_completion(result, inventory)
	if not accounting_result.ok:
		push_error(accounting_result.error)
