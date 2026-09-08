extends SceneTree

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	var generator := WorldGenerator.new()
	var options := {
		"dungeon_definitions": catalog.get_definitions("dungeons"),
		"boss_character_definitions": catalog.get_definitions("characters")
	}
	var biome := catalog.find_by_id("biomes", "common_region")
	var world := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var other_world := generator.generate(11038, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var bandages: Array = world.get("resource_nodes", []).filter(func(node): return String(node.get("resource_id", "")) == "bandage")
	var other_bandages: Array = other_world.get("resource_nodes", []).filter(func(node): return String(node.get("resource_id", "")) == "bandage")
	var projection := WorldRendererProjection.new().project(world.get("world_data", {})) if bool(world.get("ok", false)) else {}
	var entity_cells: Array = projection.get("layers", [])[3].get("cells", []) if not projection.is_empty() else []
	var rendered_bandages: Array = entity_cells.filter(func(cell): return String(cell.get("owner_id", "")) == String(bandages[0].id) and String(cell.get("source_id", "")) == "item_cloth_bandage_icon") if bandages.size() == 1 else []
	var passed: bool = bool(loaded.get("ok", false)) and bool(world.get("ok", false)) and bandages.size() == 1 and other_bandages.size() == 1 and bandages[0].position != other_bandages[0].position and bool(bandages[0].get("ground_pickup", false)) and rendered_bandages.size() == 1
	if passed:
		print("World places one rendered bandage pickup")
		quit(0)
		return
	push_error("World did not place one rendered bandage pickup")
	quit(1)
