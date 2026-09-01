extends RefCounted
class_name WorldGenerator

const DeterministicRng = preload("res://src/core/rng/deterministic_rng.gd")
const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

const MAP_WIDTH := 64
const MAP_HEIGHT := 36
const CHUNK_WIDTH := 8
const CHUNK_HEIGHT := 6
const DEFAULT_RETRY_LIMIT := 8
const DEFAULT_MIN_RESOURCE_NODES := 9

const TERRAIN_GROUND := "common_ground"
const TERRAIN_GRASS := "common_grass"
const TERRAIN_PATH := "common_path"
const TERRAIN_FIELD := "common_field"
const TERRAIN_FOREST := "common_forest"
const TERRAIN_WATER := "common_water"
const TERRAIN_BRIDGE := "common_bridge"

const RENDER_GROUND := "assets/tiles/art-9_common_flat_ground_32.png"
const RENDER_GRASS := "assets/tiles/terrain/plains/grass_ground_01_32x32.png"
const RENDER_FIELD := "assets/tiles/terrain/plains/flower_grass_01_32x32.png"
const RENDER_FOREST := "assets/tiles/terrain/forest/forest_boundary_tree_tileset_8x32.png"
const RENDER_WATER := "assets/tiles/terrain/river/river_water_00_32.png"

const COMMON_RESOURCE_ITEM_IDS := ["clay", "stone", "wood"]

func generate(seed: int, data_version: String, biome_definition: Dictionary, balance_definitions: Array, item_definitions := [], options := {}) -> Dictionary:
	var retry_limit := int(options.get("retry_limit", DEFAULT_RETRY_LIMIT))
	var min_resource_nodes := int(_balance_value(balance_definitions, "biome_min_resource_nodes", DEFAULT_MIN_RESOURCE_NODES))
	var max_resource_placement_attempts := int(options.get("max_resource_placement_attempts", max(64, min_resource_nodes * 24)))
	var core_dungeon_count := _balance_value(balance_definitions, "biome_core_dungeon_count", 1)
	var teleport_zone_count := _balance_value(balance_definitions, "biome_teleport_zone_count", 1)
	var combined_seed := _combined_seed(seed, data_version, biome_definition.get("id", ""))

	for attempt in range(retry_limit + 1):
		var rng := DeterministicRng.new(combined_seed + attempt)
		var world := _generate_attempt(
			seed,
			data_version,
			biome_definition,
			rng,
			attempt,
			retry_limit,
			int(core_dungeon_count),
			int(teleport_zone_count),
			min_resource_nodes,
			max_resource_placement_attempts,
			item_definitions
		)
		if world.ok:
			return world

	return _failure(seed, data_version, biome_definition, retry_limit, "connectivity_or_resource_validation_failed")

func _generate_attempt(seed: int, data_version: String, biome_definition: Dictionary, rng: DeterministicRng, attempt: int, retry_limit: int, core_dungeon_count: int, teleport_zone_count: int, min_resource_nodes: int, max_resource_placement_attempts: int, item_definitions: Array) -> Dictionary:
	var world_data := WorldData.new(MAP_WIDTH, MAP_HEIGHT, TERRAIN_GROUND, true)
	var chunks := _compose_chunks(rng, world_data)
	var landmarks := _place_required_landmarks(world_data, rng, core_dungeon_count, teleport_zone_count)
	_carve_landmark_paths(world_data, landmarks)
	var resource_nodes := _place_resource_nodes(world_data, rng, min_resource_nodes, max_resource_placement_attempts, _resource_item_ids(item_definitions))

	var world := {
		"schema_version": 1,
		"ok": false,
		"data_version": data_version,
		"seed": seed,
		"biome_id": biome_definition.get("id", ""),
		"biome_progression_order": biome_definition.get("progression_order", null),
		"landmarks": landmarks,
		"chunks": chunks,
		"resource_nodes": resource_nodes,
		"min_resource_nodes": min_resource_nodes,
		"retry_attempt": attempt,
		"retry_limit": retry_limit,
		"connectivity": {},
		"world_data": world_data.to_dictionary()
	}

	var validator := ConnectivityValidator.new()
	world.renderer_input = WorldRendererProjection.new().project(world.world_data)
	world.connectivity = validator.validate(world)
	world.ok = world.connectivity.valid and resource_nodes.size() >= min_resource_nodes
	if not world.ok:
		world.failure_reason = "connectivity_failed" if not world.connectivity.valid else "minimum_resource_nodes_unmet"
	return world

func _compose_chunks(rng: DeterministicRng, world_data: WorldData) -> Array:
	var chunks := []
	for chunk_y in range(MAP_HEIGHT / CHUNK_HEIGHT):
		for chunk_x in range(MAP_WIDTH / CHUNK_WIDTH):
			var variant := rng.next_range(0, 5)
			var chunk := {
				"id": "chunk_%d_%d" % [chunk_x, chunk_y],
				"variant": variant,
				"origin": {"x": chunk_x * CHUNK_WIDTH, "y": chunk_y * CHUNK_HEIGHT},
				"size": {"x": CHUNK_WIDTH, "y": CHUNK_HEIGHT}
			}
			chunks.append(chunk)
			_apply_chunk(world_data, chunk, rng)
	return chunks

func _apply_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	var variant := int(chunk.variant)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			match variant:
				0:
					world_data.set_terrain(position, TERRAIN_GRASS, true, RENDER_GRASS)
				1:
					world_data.set_terrain(position, TERRAIN_FIELD, true, RENDER_FIELD)
				2:
					if rng.next_range(0, 99) < 32:
						world_data.set_terrain(position, TERRAIN_FOREST, false, RENDER_FOREST)
					else:
						world_data.set_terrain(position, TERRAIN_GRASS, true, RENDER_GRASS)
				3:
					if y == origin.y + CHUNK_HEIGHT / 2:
						world_data.set_terrain(position, TERRAIN_PATH, true, RENDER_GROUND)
					else:
						world_data.set_terrain(position, TERRAIN_GROUND, true, RENDER_GROUND)
				4:
					if x == origin.x + CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_WATER, false, RENDER_WATER)
					else:
						world_data.set_terrain(position, TERRAIN_GRASS, true, RENDER_GRASS)
				_:
					world_data.set_terrain(position, TERRAIN_GROUND, true, RENDER_GROUND)

func _place_required_landmarks(world_data: WorldData, rng: DeterministicRng, core_dungeon_count: int, teleport_zone_count: int) -> Array:
	var landmarks := []
	landmarks.append(_add_landmark(world_data, WorldData.LANDMARK_ENTRY, 0, Vector2i(3, rng.next_range(8, MAP_HEIGHT - 9))))

	for index in range(teleport_zone_count):
		landmarks.append(_add_landmark(
			world_data,
			WorldData.LANDMARK_TELEPORT_ZONE,
			index,
			Vector2i(rng.next_range(MAP_WIDTH / 3, MAP_WIDTH / 3 * 2), rng.next_range(6, MAP_HEIGHT - 7))
		))

	for index in range(core_dungeon_count):
		landmarks.append(_add_landmark(
			world_data,
			WorldData.LANDMARK_CORE_DUNGEON,
			index,
			Vector2i(rng.next_range(MAP_WIDTH - 12, MAP_WIDTH - 4), rng.next_range(6, MAP_HEIGHT - 7))
		))

	return landmarks

func _add_landmark(world_data: WorldData, kind: String, index: int, position: Vector2i) -> Dictionary:
	world_data.set_terrain(position, TERRAIN_PATH, true, RENDER_GROUND)
	var id := "%s_%d" % [kind, index]
	world_data.add_required_landmark(kind, id, position)
	return {
		"id": id,
		"kind": kind,
		"position": _position_dictionary(position),
		"required": true
	}

func _carve_landmark_paths(world_data: WorldData, landmarks: Array) -> void:
	if landmarks.is_empty():
		return
	var entry := _vector_from_dictionary(landmarks[0].position)
	for index in range(1, landmarks.size()):
		_carve_path(world_data, entry, _vector_from_dictionary(landmarks[index].position))

func _carve_path(world_data: WorldData, start: Vector2i, target: Vector2i) -> void:
	var step_x := 1 if target.x >= start.x else -1
	for x in range(start.x, target.x + step_x, step_x):
		_make_path_cell(world_data, Vector2i(x, start.y))

	var step_y := 1 if target.y >= start.y else -1
	for y in range(start.y, target.y + step_y, step_y):
		_make_path_cell(world_data, Vector2i(target.x, y))

func _make_path_cell(world_data: WorldData, position: Vector2i) -> void:
	if not world_data.contains(position):
		return
	var terrain := TERRAIN_BRIDGE if not world_data.is_walkable(position) else TERRAIN_PATH
	world_data.set_terrain(position, terrain, true, RENDER_GROUND)

func _place_resource_nodes(world_data: WorldData, rng: DeterministicRng, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array) -> Array:
	var nodes := []
	var max_attempts: int = max(0, max_resource_placement_attempts)
	for attempt in range(max_attempts):
		if nodes.size() >= min_resource_nodes:
			break
		var position := Vector2i(rng.next_range(2, MAP_WIDTH - 3), rng.next_range(2, MAP_HEIGHT - 3))
		if not world_data.is_walkable(position):
			continue
		var owner_id := "resource_%d" % nodes.size()
		var resource_id: String = String(resource_ids[nodes.size() % resource_ids.size()])
		var reserved := world_data.reserve_entity(owner_id, position, Vector2i.ONE, true, {"resource_id": resource_id})
		if not reserved.ok:
			continue
		nodes.append({
			"id": owner_id,
			"resource_id": resource_id,
			"position": _position_dictionary(position)
		})
	return nodes

func _resource_item_ids(item_definitions: Array) -> Array:
	var exported_ids := {}
	for item in item_definitions:
		var exported_id := String(item.get("id", ""))
		if exported_id != "":
			exported_ids[exported_id] = true

	var ids := []
	for id in COMMON_RESOURCE_ITEM_IDS:
		if exported_ids.is_empty() or exported_ids.has(id):
			ids.append(id)
	if ids.is_empty():
		return COMMON_RESOURCE_ITEM_IDS.duplicate()
	return ids

func _failure(seed: int, data_version: String, biome_definition: Dictionary, retry_limit: int, reason: String) -> Dictionary:
	return {
		"schema_version": 1,
		"ok": false,
		"data_version": data_version,
		"seed": seed,
		"biome_id": biome_definition.get("id", ""),
		"retry_limit": retry_limit,
		"failure_reason": reason
	}

func _balance_value(balance_definitions: Array, id: String, fallback: float) -> float:
	for item in balance_definitions:
		if item.get("id", "") == id:
			return float(item.get("value", fallback))
	return fallback

func _combined_seed(seed: int, data_version: String, biome_id: String) -> int:
	var hash := seed
	for character in "%s:%s" % [data_version, biome_id]:
		hash = int((hash * 31 + character.unicode_at(0)) % DeterministicRng.MODULUS)
	return max(1, hash)

func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
