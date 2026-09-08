extends RefCounted

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads for starting home island")
	var generated := WorldGenerator.new().generate(
		11037,
		catalog.data_version,
		catalog.find_by_id("biomes", "common_region"),
		catalog.get_definitions("balance"),
		catalog.get_definitions("items"),
		{
			"dungeon_definitions": catalog.get_definitions("dungeons"),
			"boss_character_definitions": catalog.get_definitions("characters"),
			"repair_interaction_targets": []
		}
	)
	asserts.true_value(generated.ok, "common map generates with a starting home island: %s" % String(generated.get("failure_reason", "unknown")))
	if not generated.ok:
		return
	var entry_position := _entry_position(generated.world_data)
	var core_dungeon_position := _core_dungeon_position(generated.world_data)
	var home: Dictionary = generated.get("large_house", {})
	asserts.equal(home.get("entry_position", {}), {"x": entry_position.x, "y": entry_position.y}, "starting home records the fox entry position")
	asserts.equal(home.get("footprint_size", {}), {"x": 2, "y": 2}, "fox home uses the supplied 2x2 house sprite")
	asserts.equal(home.get("fence_owner_ids", []).size(), 8, "fox home keeps a complete decorative fence")
	asserts.equal(home.get("bridge_owner_ids", []).size(), 1, "fox home has one eastward bridge")
	var world: WorldData = WorldData.from_dictionary(generated.world_data)
	for owner_id in WorldGenerator.STARTING_HOME_BRIDGE_IDS:
		var reservation: Dictionary = world.get_reservation(owner_id)
		asserts.true_value(not reservation.is_empty(), "%s bridge is reserved in world data" % owner_id)
		asserts.true_value(bool(reservation.get("metadata", {}).get("passable", false)), "%s bridge remains walkable" % owner_id)
	var east_water := entry_position + Vector2i(2, 0)
	asserts.equal(world.terrain_id_at(east_water), WorldGenerator.TERRAIN_BRIDGE, "east crossing uses bridge terrain over the river")
	asserts.true_value(world.is_walkable(east_water), "east bridge can be crossed from the starting island")
	asserts.false_value(world.is_walkable(entry_position + Vector2i(-4, 0)), "west side becomes river immediately outside the compact home ground")
	asserts.false_value(world.is_walkable(entry_position + Vector2i(0, -6)), "north side becomes river immediately outside the compact home ground")
	asserts.false_value(world.is_walkable(entry_position + Vector2i(0, 2)), "south side becomes river immediately outside the compact home ground")
	asserts.true_value(ConnectivityValidator.new().validate_world_data(generated.world_data).valid, "starting island bridges preserve required landmark connectivity")
	asserts.true_value(entry_position.distance_to(core_dungeon_position) >= 36, "core dungeon stays at least 36 tiles away from the starting entry")
	var projection := WorldRendererProjection.new().project(generated.world_data)
	var entity_sources := _entity_sources(projection)
	for owner_id in WorldGenerator.STARTING_HOME_BRIDGE_IDS:
		asserts.equal(entity_sources.get(owner_id, ""), "asset_assets_sprites_objects_structures_wooden_stage_platform_96x64_png", "%s uses the supplied bridge image" % owner_id)

func _entry_position(world_data: Dictionary) -> Vector2i:
	for landmark in world_data.get("required_landmarks", []):
		if String(landmark.get("kind", "")) == WorldData.LANDMARK_ENTRY:
			var position: Dictionary = landmark.get("position", {})
			return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
	return Vector2i(-1, -1)

func _core_dungeon_position(world_data: Dictionary) -> Vector2i:
	for landmark in world_data.get("required_landmarks", []):
		if String(landmark.get("kind", "")) == WorldData.LANDMARK_CORE_DUNGEON:
			var position: Dictionary = landmark.get("position", {})
			return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
	return Vector2i(-1, -1)

func _entity_sources(projection: Dictionary) -> Dictionary:
	var sources := {}
	for layer in projection.get("layers", []):
		if String(layer.get("id", "")) != WorldData.LAYER_ENTITIES:
			continue
		for cell in layer.get("cells", []):
			sources[String(cell.get("owner_id", ""))] = String(cell.get("source_id", ""))
	return sources
