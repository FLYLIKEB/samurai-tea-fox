extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

@onready var player = $Player
@onready var combat_dummy = $CombatDummy

var catalog
var inventory
var equipment
var tea_service
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

	var generator := WorldGenerator.new()
	generated_world = generator.generate(11037, catalog.data_version, common_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))

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
