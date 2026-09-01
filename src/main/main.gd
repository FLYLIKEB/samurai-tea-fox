extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

@onready var player: PlayerController = $Player

var catalog
var generated_world: Dictionary = {}
var _desktop_adapter := DesktopCommandAdapter.new()
var _movement_selector := MovementCommandSelector.new()

func _ready() -> void:
	catalog = DataCatalog.new()
	var result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
		return

	var biomes: Array = catalog.get_definitions("biomes")
	if biomes.is_empty():
		push_error("No biome data loaded.")
		return

	var generator := WorldGenerator.new()
	generated_world = generator.generate(11037, catalog.data_version, biomes[0], catalog.get_definitions("balance"))

func _physics_process(_delta: float) -> void:
	var desktop_command = _desktop_adapter.poll_movement_command()
	player.submit_command(_movement_selector.select(desktop_command))

func submit_mobile_movement_command(command) -> bool:
	return _movement_selector.submit_mobile_command(command)
