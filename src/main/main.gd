extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

var catalog
var generated_world: Dictionary = {}

func _ready() -> void:
	catalog = DataCatalog.new()
	var result := catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
		return

	var biomes := catalog.get_definitions("biomes")
	if biomes.is_empty():
		push_error("No biome data loaded.")
		return

	var generator := WorldGenerator.new()
	generated_world = generator.generate(11037, catalog.data_version, biomes[0], catalog.get_definitions("balance"))

