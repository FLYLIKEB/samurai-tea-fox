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
const BIOME_COMMON := "common_region"
const BIOME_MOUNTAIN := "mountain_region"
const BIOME_WASTELAND := "wasteland"
const BIOME_SNOWFIELD := "snowfield"

const TERRAIN_GROUND := "common_ground"
const TERRAIN_GRASS := "common_grass"
const TERRAIN_PATH := "common_path"
const TERRAIN_FIELD := "common_field"
const TERRAIN_FOREST := "common_forest"
const TERRAIN_WATER := "common_water"
const TERRAIN_BRIDGE := "common_bridge"
const TERRAIN_MOUNTAIN_SLOPE := "mountain_slope"
const TERRAIN_MOUNTAIN_PATH := "mountain_path"
const TERRAIN_MOUNTAIN_CLIFF := "mountain_cliff"
const TERRAIN_MOUNTAIN_ROCK := "mountain_rock"
const TERRAIN_MOUNTAIN_CONIFER := "mountain_conifer_forest"
const TERRAIN_MOUNTAIN_VALLEY_WATER := "mountain_valley_water"
const TERRAIN_MOUNTAIN_CAVE_GROUND := "mountain_cave_ground"
const TERRAIN_WASTELAND_DRY_SOIL := "wasteland_dry_soil"
const TERRAIN_WASTELAND_CRACKED_GROUND := "wasteland_cracked_ground"
const TERRAIN_WASTELAND_DETOUR_PATH := "wasteland_detour_path"
const TERRAIN_WASTELAND_RUIN := "wasteland_ruin"
const TERRAIN_WASTELAND_DEAD_TREE := "wasteland_dead_tree"
const TERRAIN_WASTELAND_DRY_RIVER := "wasteland_dry_river"
const TERRAIN_WASTELAND_CAMP_TRACE := "wasteland_camp_trace"
const TERRAIN_SNOWFIELD_SNOW := "snowfield_snow"
const TERRAIN_SNOWFIELD_SNOW_PATH := "snowfield_snow_path"
const TERRAIN_SNOWFIELD_ICE := "snowfield_ice"
const TERRAIN_SNOWFIELD_ICE_EDGE := "snowfield_ice_edge"
const TERRAIN_SNOWFIELD_PINE := "snowfield_pine"
const TERRAIN_SNOWFIELD_ICE_WALL := "snowfield_ice_wall"
const TERRAIN_SNOWFIELD_SAFE_CLEARING := "snowfield_safe_clearing"

const RENDER_GROUND := "assets/tiles/terrain/plains/grass_ground_01_32x32.png"
const RENDER_GRASS := "assets/tiles/terrain/plains/grass_ground_01_32x32.png"
const RENDER_FIELD := "assets/tiles/terrain/plains/flower_grass_01_32x32.png"
const RENDER_FOREST := "assets/tiles/terrain/forest/forest_boundary_tree_tileset_8x32.png"
const RENDER_WATER := "assets/tiles/terrain/river/3128FD1E-45B5-438E-A810-C6049FC50F77_crop_202_420_146x145_resize_32x32.png"
const RENDER_MOUNTAIN_SLOPE := "assets/sprites/objects/natural-props/flat_rock_32x32.png"
const RENDER_MOUNTAIN_PATH := "assets/sprites/objects/natural-props/mossy_rock_32x32.png"
const RENDER_MOUNTAIN_CLIFF := "assets/sprites/objects/natural-props/mountain_rock_04_32x32.png"
const RENDER_MOUNTAIN_ROCK := "assets/sprites/objects/natural-props/mountain_rock_01_32x32.png"
const RENDER_MOUNTAIN_CONIFER := "assets/sprites/objects/natural-props/pine_tree_small_32x32.png"
const RENDER_MOUNTAIN_CAVE := "assets/sprites/objects/mining/rock_cave_entrance_1x2_64x32.png"
const RENDER_MOUNTAIN_MINE := "assets/sprites/objects/mining/rock_cave_entrance_1x2_64x32.png"
const RENDER_MOUNTAIN_TEMPLE := "assets/sprites/objects/structures/shrine_torii_gate_2x2_64x64.png"
const RENDER_MOUNTAIN_ABANDONED_MINE := "assets/sprites/objects/mining/timber_support_1x2_32x64.png"
const RENDER_MOUNTAIN_TEA_HOUSE := "assets/sprites/objects/crafting/tea_table_2x2_64x64.png"
const RENDER_WASTELAND_DRY_SOIL := "assets/tiles/terrain/desert/dry_soil_01_32x32.png"
const RENDER_WASTELAND_CRACKED_GROUND := "assets/tiles/terrain/desert/cracked_clay_32x32.png"
const RENDER_WASTELAND_DETOUR_PATH := "assets/tiles/terrain/desert/sand_ripple_01_32x32.png"
const RENDER_WASTELAND_RUIN := "assets/sprites/objects/structures/ruined_wall_1x2_64x32.png"
const RENDER_WASTELAND_DEAD_TREE := "assets/sprites/objects/natural-props/dead_tree_small_32x32.png"
const RENDER_WASTELAND_DRY_RIVER := "assets/tiles/terrain/desert/dry_scrub_patch_32x32.png"
const RENDER_WASTELAND_CAMP_TRACE := "assets/tiles/terrain/desert/bone_scatter_32x32.png"
const RENDER_WASTELAND_ABANDONED_VILLAGE := "assets/sprites/objects/structures/small_storage_shed_64x64.png"
const RENDER_WASTELAND_ABANDONED_OUTPOST := "assets/sprites/objects/structures/ruined_wall_1x2_64x32.png"
const RENDER_WASTELAND_RUINED_TEA_ROOM := "assets/sprites/objects/crafting/tea_table_2x2_64x64.png"
const RENDER_WASTELAND_BATTLEFIELD_TRACE := "assets/tiles/terrain/desert/bone_scatter_32x32.png"
const RENDER_RESOURCE_IRON_SCRAP := "assets/sprites/objects/mining/iron_ore_32x32.png"
const RENDER_SNOWFIELD_SNOW := "assets/tiles/terrain/snow/snow_ground_01_32x32.png"
const RENDER_SNOWFIELD_PATH := "assets/tiles/terrain/snow/snow_ground_03_32x32.png"
const RENDER_SNOWFIELD_ICE := "assets/tiles/terrain/snow/snow_ground_04_32x32.png"
const RENDER_SNOWFIELD_ICE_EDGE := "assets/tiles/terrain/snow/snow_rock_edge_01_32x32.png"
const RENDER_SNOWFIELD_PINE := "assets/tiles/terrain/snow/snowy_pine_tree_01_32x32.png"
const RENDER_SNOWFIELD_ICE_WALL := "assets/tiles/terrain/snow/snow_rock_edge_02_32x32.png"
const RENDER_SNOWFIELD_SAFE_CLEARING := "assets/tiles/terrain/snow/snow_mound_32x32.png"
const RENDER_SNOWFIELD_LODGE := "assets/sprites/objects/structures/small_wood_house_2x2_64x64.png"
const RENDER_SNOWFIELD_HOT_SPRING := "assets/sprites/objects/shrine-props/stone_water_basin_32x32.png"
const RENDER_SNOWFIELD_SHRINE := "assets/sprites/objects/structures/shrine_torii_gate_2x2_64x64.png"
const RENDER_SNOWFIELD_FROZEN_MINE := "assets/sprites/objects/mining/rock_cave_entrance_1x2_64x32.png"

const BALANCE_MIN_RESOURCE_NODES_ID := "biome_min_resource_nodes"

func generate(seed: int, data_version: String, biome_definition: Dictionary, balance_definitions: Array, item_definitions := [], options := {}) -> Dictionary:
	var retry_limit := int(options.get("retry_limit", DEFAULT_RETRY_LIMIT))
	var profile_result := _biome_generation_profile(biome_definition)
	if not profile_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, profile_result.reason, profile_result)
	var profile: Dictionary = profile_result.profile
	var resource_result := _biome_resource_item_ids(biome_definition, item_definitions)
	if not resource_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, resource_result.reason, resource_result)
	var resource_ids: Array = resource_result.ids
	var min_resource_result := _minimum_resource_nodes(balance_definitions, options)
	if not min_resource_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, min_resource_result.reason)
	var min_resource_nodes := int(min_resource_result.value)
	var max_resource_placement_attempts := int(options.get("max_resource_placement_attempts", max(64, min_resource_nodes * 24)))
	var core_dungeon_count := _balance_value(balance_definitions, "biome_core_dungeon_count", 1)
	var teleport_zone_count := _balance_value(balance_definitions, "biome_teleport_zone_count", 1)
	var combined_seed := _combined_seed(seed, data_version, biome_definition.get("id", ""))
	var progression_projection: Dictionary = options.get("progression_projection", {})

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
			resource_ids,
			progression_projection,
			profile
		)
		if world.ok:
			return world

	return _failure(seed, data_version, biome_definition, retry_limit, "connectivity_or_resource_validation_failed")

func _generate_attempt(seed: int, data_version: String, biome_definition: Dictionary, rng: DeterministicRng, attempt: int, retry_limit: int, core_dungeon_count: int, teleport_zone_count: int, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array, progression_projection: Dictionary, profile: Dictionary) -> Dictionary:
	var world_data := WorldData.new(MAP_WIDTH, MAP_HEIGHT, String(profile.default_terrain_id), bool(profile.default_walkable))
	var chunks := _compose_chunks(rng, world_data, profile)
	var biome_id := String(biome_definition.get("id", ""))
	var landmarks := _place_required_landmarks(world_data, rng, core_dungeon_count, teleport_zone_count, biome_id, profile)
	_carve_landmark_paths(world_data, landmarks, profile)
	var validator := ConnectivityValidator.new()
	var facility_nodes := _place_facility_nodes(world_data, rng, landmarks, profile, validator.reachable_cell_keys_from_entry(world_data.to_dictionary()))
	var reachable_cells := validator.reachable_cell_keys_from_entry(world_data.to_dictionary())
	var resource_nodes := _place_resource_nodes(world_data, rng, min_resource_nodes, max_resource_placement_attempts, resource_ids, reachable_cells, profile.get("resource_source_by_id", {}))
	var access_points := []
	for resource_node in resource_nodes:
		access_points.append(resource_node.access_position)
	var facility_access_points := []
	for facility_node in facility_nodes:
		facility_access_points.append(facility_node.access_position)

	var world := {
		"schema_version": 1,
		"ok": false,
		"data_version": data_version,
		"seed": seed,
		"biome_id": biome_id,
		"biome_progression_order": biome_definition.get("progression_order", null),
		"biome_generation_rule_id": String(profile.id),
		"landmarks": landmarks,
		"chunks": chunks,
		"facility_nodes": facility_nodes,
		"resource_nodes": resource_nodes,
		"min_resource_nodes": min_resource_nodes,
		"retry_attempt": attempt,
		"retry_limit": retry_limit,
		"facility_accessibility": {},
		"resource_accessibility": {},
		"connectivity": {},
		"world_data": world_data.to_dictionary()
	}

	world.renderer_input = WorldRendererProjection.new().project(world.world_data, progression_projection)
	world.connectivity = validator.validate(world)
	world.facility_accessibility = validator.validate_access_points(world.world_data, facility_access_points)
	world.resource_accessibility = validator.validate_access_points(world.world_data, access_points)
	world.ok = (
		world.connectivity.valid
		and world.facility_accessibility.valid
		and world.resource_accessibility.valid
		and facility_nodes.size() >= int(profile.minimum_facility_nodes)
		and resource_nodes.size() >= min_resource_nodes
	)
	if not world.ok:
		world.failure_reason = _attempt_failure_reason(world.connectivity, world.facility_accessibility, world.resource_accessibility, facility_nodes.size(), int(profile.minimum_facility_nodes), resource_nodes.size(), min_resource_nodes)
	return world

func _compose_chunks(rng: DeterministicRng, world_data: WorldData, profile: Dictionary) -> Array:
	var chunks := []
	var variant_count := int(profile.chunk_variant_count)
	for chunk_y in range(MAP_HEIGHT / CHUNK_HEIGHT):
		for chunk_x in range(MAP_WIDTH / CHUNK_WIDTH):
			var variant := rng.next_range(0, variant_count - 1)
			var chunk := {
				"id": "chunk_%d_%d" % [chunk_x, chunk_y],
				"variant": variant,
				"origin": {"x": chunk_x * CHUNK_WIDTH, "y": chunk_y * CHUNK_HEIGHT},
				"size": {"x": CHUNK_WIDTH, "y": CHUNK_HEIGHT}
			}
			chunks.append(chunk)
			_apply_chunk(world_data, chunk, rng, profile)
	return chunks

func _apply_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, profile: Dictionary) -> void:
	match String(profile.id):
		BIOME_MOUNTAIN:
			_apply_mountain_chunk(world_data, chunk, rng)
		BIOME_WASTELAND:
			_apply_wasteland_chunk(world_data, chunk, rng)
		BIOME_SNOWFIELD:
			_apply_snowfield_chunk(world_data, chunk, rng)
		_:
			_apply_common_chunk(world_data, chunk, rng)

func _apply_common_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
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

func _apply_mountain_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	var variant := int(chunk.variant)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			match variant:
				0:
					if y == origin.y + CHUNK_HEIGHT / 2 or x == origin.x + CHUNK_WIDTH - 2:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true, RENDER_MOUNTAIN_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true, RENDER_MOUNTAIN_SLOPE)
				1:
					if rng.next_range(0, 99) < 40:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_ROCK, false, RENDER_MOUNTAIN_ROCK)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true, RENDER_MOUNTAIN_SLOPE)
				2:
					if x == origin.x or y == origin.y or rng.next_range(0, 99) < 24:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_CLIFF, false, RENDER_MOUNTAIN_CLIFF)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true, RENDER_MOUNTAIN_PATH)
				3:
					if rng.next_range(0, 99) < 35:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_CONIFER, false, RENDER_MOUNTAIN_CONIFER)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true, RENDER_MOUNTAIN_SLOPE)
				4:
					if x == origin.x + CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_VALLEY_WATER, false, RENDER_WATER)
					elif abs(x - (origin.x + CHUNK_WIDTH / 2)) == 1:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true, RENDER_MOUNTAIN_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true, RENDER_MOUNTAIN_SLOPE)
				5:
					if y == origin.y + CHUNK_HEIGHT - 1:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true, RENDER_MOUNTAIN_PATH)
					elif rng.next_range(0, 99) < 20:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_CAVE_GROUND, true, RENDER_MOUNTAIN_CAVE)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_ROCK, false, RENDER_MOUNTAIN_ROCK)
				_:
					world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true, RENDER_MOUNTAIN_SLOPE)

func _apply_wasteland_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	var variant := int(chunk.variant)
	chunk["feature"] = _wasteland_feature_for_variant(variant)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match variant:
				0:
					if local_y == 1 or (local_x >= 3 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)
				1:
					if local_x >= 1 and local_x <= 5 and local_y >= 1 and local_y <= 3 and (local_x == 1 or local_x == 5 or local_y == 1 or local_y == 3):
						world_data.set_terrain(position, TERRAIN_WASTELAND_RUIN, false, RENDER_WASTELAND_RUIN)
					elif local_x == 3 and local_y == 2:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true, RENDER_WASTELAND_CRACKED_GROUND)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)
				2:
					if local_x == CHUNK_WIDTH - 2 and local_y < CHUNK_HEIGHT - 1:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					elif local_y == CHUNK_HEIGHT - 2 and local_x > 1:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					elif local_x == 1 and local_y == CHUNK_HEIGHT - 2:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true, RENDER_WASTELAND_CRACKED_GROUND)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)
				3:
					if local_x == 2 and local_y <= 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					elif local_x == 2 and local_y == 4:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true, RENDER_WASTELAND_CRACKED_GROUND)
					elif rng.next_range(0, 99) < 28:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DEAD_TREE, false, RENDER_WASTELAND_DEAD_TREE)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)
				4:
					if local_x == 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_RIVER, false, RENDER_WASTELAND_DRY_RIVER)
					elif local_x == 2 or local_x == 4:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true, RENDER_WASTELAND_CRACKED_GROUND)
				5:
					if local_x == 0 or local_y == 0 or (local_x == 6 and local_y < 5):
						world_data.set_terrain(position, TERRAIN_WASTELAND_CAMP_TRACE, false, RENDER_WASTELAND_CAMP_TRACE)
					elif local_y == 3 or local_x == 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true, RENDER_WASTELAND_DETOUR_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)
				_:
					world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true, RENDER_WASTELAND_DRY_SOIL)

func _wasteland_feature_for_variant(variant: int) -> String:
	match variant:
		0:
			return "dry_detour"
		1:
			return "asymmetric_ruin"
		2:
			return "long_detour"
		3:
			return "dead_end"
		4:
			return "dry_river_bypass"
		5:
			return "battlefield_trace"
		_:
			return "dry_soil"

func _apply_snowfield_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	var variant := int(chunk.variant)
	chunk["feature"] = _snowfield_feature_for_variant(variant)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match variant:
				0:
					if local_y == CHUNK_HEIGHT / 2 or local_x == CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true, RENDER_SNOWFIELD_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				1:
					if local_x == 2 or local_x == 5:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_EDGE, true, RENDER_SNOWFIELD_ICE_EDGE)
					elif local_x > 2 and local_x < 5:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE, false, RENDER_SNOWFIELD_ICE)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				2:
					if rng.next_range(0, 99) < 38:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_PINE, false, RENDER_SNOWFIELD_PINE)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				3:
					if local_y == 0 or local_x == 0 or local_x == CHUNK_WIDTH - 1:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_WALL, false, RENDER_SNOWFIELD_ICE_WALL)
					elif local_y == 2 or local_x == 3:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true, RENDER_SNOWFIELD_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				4:
					if local_x >= 2 and local_x <= 5 and local_y >= 1 and local_y <= 4:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SAFE_CLEARING, true, RENDER_SNOWFIELD_SAFE_CLEARING)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				5:
					if local_y == 1 or (local_x >= 4 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true, RENDER_SNOWFIELD_PATH)
					elif local_x == 1 and local_y >= 2:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_EDGE, true, RENDER_SNOWFIELD_ICE_EDGE)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)
				_:
					world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true, RENDER_SNOWFIELD_SNOW)

func _snowfield_feature_for_variant(variant: int) -> String:
	match variant:
		0:
			return "snow_path_crossing"
		1:
			return "frozen_river_edge"
		2:
			return "pine_silence"
		3:
			return "ice_wall_pass"
		4:
			return "safe_clearing"
		5:
			return "snowy_mountain_path"
		_:
			return "snowfield"

func _place_required_landmarks(world_data: WorldData, rng: DeterministicRng, core_dungeon_count: int, teleport_zone_count: int, biome_id: String, profile: Dictionary) -> Array:
	var landmarks := []
	landmarks.append(_add_landmark(world_data, WorldData.LANDMARK_ENTRY, 0, Vector2i(3, rng.next_range(8, MAP_HEIGHT - 9)), profile))

	for index in range(teleport_zone_count):
		landmarks.append(_add_landmark(
			world_data,
			WorldData.LANDMARK_TELEPORT_ZONE,
			index,
			Vector2i(rng.next_range(MAP_WIDTH / 3, MAP_WIDTH / 3 * 2), rng.next_range(6, MAP_HEIGHT - 7)),
			profile,
			{"teleport_biome_id": biome_id}
		))

	for index in range(core_dungeon_count):
		landmarks.append(_add_landmark(
			world_data,
			WorldData.LANDMARK_CORE_DUNGEON,
			index,
			Vector2i(rng.next_range(MAP_WIDTH - 12, MAP_WIDTH - 4), rng.next_range(6, MAP_HEIGHT - 7)),
			profile
		))

	return landmarks

func _add_landmark(world_data: WorldData, kind: String, index: int, position: Vector2i, profile: Dictionary, metadata := {}) -> Dictionary:
	world_data.set_terrain(position, String(profile.path_terrain_id), true, String(profile.path_render_id))
	var id := "%s_%d" % [kind, index]
	var landmark_metadata := metadata.duplicate(true)
	landmark_metadata["biome_rule_id"] = String(profile.id)
	landmark_metadata["terrain_terms"] = profile.required_terrain_terms.duplicate(true)
	world_data.add_required_landmark(kind, id, position, landmark_metadata)
	return {
		"id": id,
		"kind": kind,
		"position": _position_dictionary(position),
		"required": true,
		"metadata": landmark_metadata.duplicate(true)
	}

func _carve_landmark_paths(world_data: WorldData, landmarks: Array, profile: Dictionary) -> void:
	if landmarks.is_empty():
		return
	var entry := _vector_from_dictionary(landmarks[0].position)
	for index in range(1, landmarks.size()):
		_carve_path(world_data, entry, _vector_from_dictionary(landmarks[index].position), profile)

func _carve_path(world_data: WorldData, start: Vector2i, target: Vector2i, profile: Dictionary) -> void:
	var step_x := 1 if target.x >= start.x else -1
	for x in range(start.x, target.x + step_x, step_x):
		_make_path_cell(world_data, Vector2i(x, start.y), profile)

	var step_y := 1 if target.y >= start.y else -1
	for y in range(start.y, target.y + step_y, step_y):
		_make_path_cell(world_data, Vector2i(target.x, y), profile)

func _make_path_cell(world_data: WorldData, position: Vector2i, profile: Dictionary) -> void:
	if not world_data.contains(position):
		return
	var terrain_id := String(profile.bridge_terrain_id) if not world_data.is_walkable(position) else String(profile.path_terrain_id)
	world_data.set_terrain(position, terrain_id, true, String(profile.path_render_id))

func _place_resource_nodes(world_data: WorldData, rng: DeterministicRng, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array, reachable_cells: Dictionary, source_by_resource_id: Dictionary) -> Array:
	var nodes := []
	var max_attempts: int = max(0, max_resource_placement_attempts)
	var cardinal_offsets := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for attempt in range(max_attempts):
		if nodes.size() >= min_resource_nodes:
			break
		var position := Vector2i(rng.next_range(2, MAP_WIDTH - 3), rng.next_range(2, MAP_HEIGHT - 3))
		if not world_data.is_walkable(position) or not reachable_cells.has(_key(position)):
			continue
		var access_position := _reachable_access_position(position, reachable_cells, cardinal_offsets)
		if access_position == Vector2i(-1, -1):
			continue
		var owner_id := "resource_%d" % nodes.size()
		var resource_id: String = String(resource_ids[nodes.size() % resource_ids.size()])
		var source_id := String(source_by_resource_id.get(resource_id, ""))
		var metadata := {"resource_id": resource_id}
		if not source_id.is_empty():
			metadata["source_id"] = source_id
		var reserved := world_data.reserve_entity(owner_id, position, Vector2i.ONE, true, metadata)
		if not reserved.ok:
			continue
		var node := {
			"id": owner_id,
			"resource_id": resource_id,
			"position": _position_dictionary(position),
			"access_position": _position_dictionary(access_position),
			"placement_was_entry_reachable": true,
			"interactable": true
		}
		if not source_id.is_empty():
			node["source_id"] = source_id
		nodes.append(node)
	return nodes

func _place_facility_nodes(world_data: WorldData, rng: DeterministicRng, landmarks: Array, profile: Dictionary, reachable_cells: Dictionary) -> Array:
	var nodes := []
	var facility_terms: Array = profile.get("facility_terms", [])
	if facility_terms.is_empty() or landmarks.is_empty():
		return nodes
	var source_by_term: Dictionary = profile.get("facility_source_by_term", {})
	for index in range(facility_terms.size()):
		var term := String(facility_terms[index])
		var source_id := String(source_by_term.get(term, ""))
		var anchor: Dictionary = landmarks[index % landmarks.size()]
		var placed := _place_facility_near(world_data, rng, _vector_from_dictionary(anchor.position), reachable_cells, index, term, source_id, String(profile.id))
		if placed.ok:
			nodes.append(placed.node)
	return nodes

func _place_facility_near(world_data: WorldData, rng: DeterministicRng, anchor: Vector2i, reachable_cells: Dictionary, index: int, term: String, source_id: String, biome_rule_id: String) -> Dictionary:
	var offsets := _facility_candidate_offsets()
	var start_offset := rng.next_range(0, offsets.size() - 1)
	var cardinal_offsets := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for attempt in range(offsets.size()):
		var position: Vector2i = anchor + offsets[(start_offset + attempt) % offsets.size()]
		if not world_data.contains(position) or not world_data.is_walkable(position):
			continue
		var access_position := _reachable_access_position(position, reachable_cells, cardinal_offsets)
		if access_position == Vector2i(-1, -1):
			continue
		var owner_id := "facility_%d" % index
		var metadata := {
			"biome_rule_id": biome_rule_id,
			"facility_term": term,
			"source_id": source_id
		}
		var reserved := world_data.reserve_facility(owner_id, position, Vector2i.ONE, true, metadata)
		if not reserved.ok:
			continue
		var validation := ConnectivityValidator.new().validate_world_data(world_data.to_dictionary())
		if not bool(validation.get("valid", false)):
			world_data.release_footprint(owner_id)
			continue
		return {
			"ok": true,
			"node": {
				"id": owner_id,
				"facility_term": term,
				"source_id": source_id,
				"position": _position_dictionary(position),
				"access_position": _position_dictionary(access_position),
				"placement_was_entry_reachable": true,
				"interactable": true
			}
		}
	return {"ok": false, "reason": "facility_placement_failed", "facility_term": term}

func _facility_candidate_offsets() -> Array:
	return [
		Vector2i(0, -2),
		Vector2i(0, 2),
		Vector2i(-2, 0),
		Vector2i(2, 0),
		Vector2i(-2, -1),
		Vector2i(2, -1),
		Vector2i(-2, 1),
		Vector2i(2, 1),
		Vector2i(-1, -2),
		Vector2i(1, -2),
		Vector2i(-1, 2),
		Vector2i(1, 2),
		Vector2i(-3, 0),
		Vector2i(3, 0),
		Vector2i(0, -3),
		Vector2i(0, 3),
		Vector2i(-3, -1),
		Vector2i(3, 1),
		Vector2i(-1, -3),
		Vector2i(1, 3)
	]

func _reachable_access_position(position: Vector2i, reachable_cells: Dictionary, offsets: Array) -> Vector2i:
	for offset in offsets:
		var access_position: Vector2i = position + offset
		if reachable_cells.has(_key(access_position)):
			return access_position
	return Vector2i(-1, -1)

func _biome_generation_profile(biome_definition: Dictionary) -> Dictionary:
	var biome_id := String(biome_definition.get("id", ""))
	match biome_id:
		BIOME_COMMON:
			return _profile_ok({
				"id": BIOME_COMMON,
				"chunk_variant_count": 6,
				"default_terrain_id": TERRAIN_GROUND,
				"default_walkable": true,
				"path_terrain_id": TERRAIN_PATH,
				"bridge_terrain_id": TERRAIN_BRIDGE,
				"path_render_id": RENDER_GROUND,
				"required_terrain_terms": [],
				"facility_terms": [],
				"facility_source_by_term": {},
				"resource_source_by_id": {},
				"minimum_facility_nodes": 0
			})
		BIOME_MOUNTAIN:
			var required_terms := ["산길", "절벽", "바위지대", "계곡", "폭포", "침엽수림", "동굴"]
			var terrain_text := String(biome_definition.get("terrain", ""))
			for term in required_terms:
				if not terrain_text.contains(term):
					return {"ok": false, "reason": "missing_biome_generation_terms", "missing_term": term}
			var facility_terms := ["광산", "산사", "폐광", "산중 찻집"]
			var facility_text := String(biome_definition.get("facilities", ""))
			for term in facility_terms:
				if not facility_text.contains(term):
					return {"ok": false, "reason": "missing_biome_facility_terms", "missing_term": term}
			return _profile_ok({
				"id": BIOME_MOUNTAIN,
				"chunk_variant_count": 6,
				"default_terrain_id": TERRAIN_MOUNTAIN_SLOPE,
				"default_walkable": true,
				"path_terrain_id": TERRAIN_MOUNTAIN_PATH,
				"bridge_terrain_id": TERRAIN_MOUNTAIN_PATH,
				"path_render_id": RENDER_MOUNTAIN_PATH,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"광산": RENDER_MOUNTAIN_MINE,
					"산사": RENDER_MOUNTAIN_TEMPLE,
					"폐광": RENDER_MOUNTAIN_ABANDONED_MINE,
					"산중 찻집": RENDER_MOUNTAIN_TEA_HOUSE
				},
				"resource_source_by_id": {},
				"minimum_facility_nodes": facility_terms.size()
			})
		BIOME_WASTELAND:
			var required_terms := ["마른 흙", "갈라진 땅", "죽은 나무", "폐허", "말라붙은 하천", "군영 흔적"]
			var terrain_text := String(biome_definition.get("terrain", ""))
			for term in required_terms:
				if not terrain_text.contains(term):
					return {"ok": false, "reason": "missing_biome_generation_terms", "missing_term": term}
			var facility_terms := ["폐촌", "버려진 초소", "무너진 다실", "전쟁터 흔적"]
			var facility_text := String(biome_definition.get("facilities", ""))
			for term in facility_terms:
				if not facility_text.contains(term):
					return {"ok": false, "reason": "missing_biome_facility_terms", "missing_term": term}
			return _profile_ok({
				"id": BIOME_WASTELAND,
				"chunk_variant_count": 6,
				"default_terrain_id": TERRAIN_WASTELAND_DRY_SOIL,
				"default_walkable": true,
				"path_terrain_id": TERRAIN_WASTELAND_DETOUR_PATH,
				"bridge_terrain_id": TERRAIN_WASTELAND_DETOUR_PATH,
				"path_render_id": RENDER_WASTELAND_DETOUR_PATH,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"폐촌": RENDER_WASTELAND_ABANDONED_VILLAGE,
					"버려진 초소": RENDER_WASTELAND_ABANDONED_OUTPOST,
					"무너진 다실": RENDER_WASTELAND_RUINED_TEA_ROOM,
					"전쟁터 흔적": RENDER_WASTELAND_BATTLEFIELD_TRACE
				},
				"resource_source_by_id": {
					"item_28": RENDER_RESOURCE_IRON_SCRAP
				},
				"minimum_facility_nodes": facility_terms.size()
			})
		BIOME_SNOWFIELD:
			var required_terms := ["눈밭", "얼어붙은 강", "침엽수", "빙벽", "눈 덮인 산길"]
			var terrain_text := String(biome_definition.get("terrain", ""))
			for term in required_terms:
				if not terrain_text.contains(term):
					return {"ok": false, "reason": "missing_biome_generation_terms", "missing_term": term}
			var facility_terms := ["산장", "온천", "설원 사당", "얼어붙은 광산"]
			var facility_text := String(biome_definition.get("facilities", ""))
			for term in facility_terms:
				if not facility_text.contains(term):
					return {"ok": false, "reason": "missing_biome_facility_terms", "missing_term": term}
			return _profile_ok({
				"id": BIOME_SNOWFIELD,
				"chunk_variant_count": 6,
				"default_terrain_id": TERRAIN_SNOWFIELD_SNOW,
				"default_walkable": true,
				"path_terrain_id": TERRAIN_SNOWFIELD_SNOW_PATH,
				"bridge_terrain_id": TERRAIN_SNOWFIELD_ICE_EDGE,
				"path_render_id": RENDER_SNOWFIELD_PATH,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"산장": RENDER_SNOWFIELD_LODGE,
					"온천": RENDER_SNOWFIELD_HOT_SPRING,
					"설원 사당": RENDER_SNOWFIELD_SHRINE,
					"얼어붙은 광산": RENDER_SNOWFIELD_FROZEN_MINE
				},
				"resource_source_by_id": {
					"wood": RENDER_SNOWFIELD_PINE
				},
				"minimum_facility_nodes": facility_terms.size()
			})
		_:
			return {"ok": false, "reason": "unsupported_biome_generation_rules", "biome_id": biome_id}

func _profile_ok(profile: Dictionary) -> Dictionary:
	return {"ok": true, "profile": profile}

func _biome_resource_item_ids(biome_definition: Dictionary, item_definitions: Array) -> Dictionary:
	var resource_text := String(biome_definition.get("resources", ""))
	if resource_text.strip_edges() == "":
		return {"ok": false, "reason": "missing_biome_resources", "ids": []}

	var ids := []
	for item in item_definitions:
		if String(item.get("type", "")) != "재료":
			continue
		var item_id := String(item.get("id", ""))
		var item_name := String(item.get("name", ""))
		if item_id == "" or item_name == "":
			continue
		if resource_text.contains(item_name):
			ids.append(item_id)
	if ids.is_empty():
		return {"ok": false, "reason": "missing_biome_resource_item_definitions", "ids": []}
	return {"ok": true, "ids": ids}

func _minimum_resource_nodes(balance_definitions: Array, options: Dictionary) -> Dictionary:
	if options.has("min_resource_nodes"):
		return {"ok": true, "value": max(0, int(options.min_resource_nodes))}
	for item in balance_definitions:
		if item.get("id", "") == BALANCE_MIN_RESOURCE_NODES_ID:
			return {"ok": true, "value": max(0, int(item.get("value", 0)))}
	return {"ok": false, "reason": "missing_min_resource_nodes_config"}

func _attempt_failure_reason(connectivity: Dictionary, facility_accessibility: Dictionary, resource_accessibility: Dictionary, facility_count: int, min_facility_nodes: int, resource_count: int, min_resource_nodes: int) -> String:
	if not connectivity.valid:
		return "connectivity_failed"
	if not facility_accessibility.valid:
		return "facility_accessibility_failed"
	if not resource_accessibility.valid:
		return "resource_accessibility_failed"
	if facility_count < min_facility_nodes:
		return "minimum_facility_nodes_unmet"
	if resource_count < min_resource_nodes:
		return "minimum_resource_nodes_unmet"
	return "unknown_generation_failure"

func _failure(seed: int, data_version: String, biome_definition: Dictionary, retry_limit: int, reason: String, details := {}) -> Dictionary:
	var failure := {
		"schema_version": 1,
		"ok": false,
		"data_version": data_version,
		"seed": seed,
		"biome_id": biome_definition.get("id", ""),
		"retry_limit": retry_limit,
		"failure_reason": reason
	}
	for key in details.keys():
		if key != "ok" and key != "reason":
			failure[key] = details[key]
	return failure

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

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]
