extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

@onready var player = $Player
@onready var combat_dummy = $CombatDummy
@onready var world_visuals: Node2D = $WorldVisuals

var catalog
var inventory
var equipment
var tea_service
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

	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, RunState.new())
	if not progression_result.ok:
		push_error(progression_result.error)
		return
	var projection: Dictionary = progression_result.progression_state.to_projection()
	generated_world = generator.generate(11037, catalog.data_version, common_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), {"progression_projection": projection})
	if not generated_world.get("ok", false):
		push_error("World generation failed: %s" % generated_world.get("failure_reason", "unknown"))
		return
	_render_generated_world(generated_world)

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
	return player.submit_command(command)

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
	equipment = equipment_result.equipment
	tea_service = tea_result.tea_service
	tea_service.drink_completed.connect(_on_tea_drink_completed)
	return {"ok": true}

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
