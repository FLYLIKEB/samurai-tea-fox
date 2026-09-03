extends RefCounted
class_name WorldGenerator

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const DeterministicRng = preload("res://src/core/rng/deterministic_rng.gd")
const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

static var MAP_WIDTH := RuntimeConstants.int_value("world.overworld_width")
static var MAP_HEIGHT := RuntimeConstants.int_value("world.overworld_height")
static var CHUNK_WIDTH := RuntimeConstants.int_value("world.chunk_width")
static var CHUNK_HEIGHT := RuntimeConstants.int_value("world.chunk_height")
static var DEFAULT_RETRY_LIMIT := RuntimeConstants.int_value("world.generation_retry_limit")
const BIOME_COMMON := "common_region"
const BIOME_MOUNTAIN := "mountain_region"
const BIOME_WASTELAND := "wasteland"
const BIOME_SNOWFIELD := "snowfield"
const BIOME_RAINFOREST := "rainforest"

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
const TERRAIN_RAINFOREST_JUNGLE := "rainforest_jungle"
const TERRAIN_RAINFOREST_SWAMP := "rainforest_swamp"
const TERRAIN_RAINFOREST_RIVER := "rainforest_river"
const TERRAIN_RAINFOREST_VINE_PATH := "rainforest_vine_path"
const TERRAIN_RAINFOREST_TEA_FIELD := "rainforest_tea_field"
const TERRAIN_RAINFOREST_AGARWOOD := "rainforest_agarwood_grove"
const TERRAIN_RAINFOREST_RIVER_BANK := "rainforest_river_bank"

const RENDER_GROUND := "terrain_plains_grass_ground_01"
const RENDER_GRASS := "terrain_plains_grass_ground_01"
const RENDER_PATH := "asset_assets_tiles_terrain_paths_road_isolated_32x32_png"
const RENDER_FIELD := "terrain_plains_flower_grass_01"
const RENDER_FOREST_TREE := "terrain_tree_broadleaf_32x32"
const RENDER_WATER := "terrain_river_water_01"
const RENDER_MOUNTAIN_SLOPE := "asset_assets_sprites_objects_natural_props_flat_rock_32x32_png"
const RENDER_MOUNTAIN_PATH := "asset_assets_sprites_objects_natural_props_mossy_rock_32x32_png"
const RENDER_MOUNTAIN_CLIFF := "asset_assets_sprites_objects_natural_props_mountain_rock_04_32x32_png"
const RENDER_BRIDGE_VERTICAL := "asset_assets_tiles_terrain_bridges_bridge_vertical_32x32_png"
const RENDER_BRIDGE_HORIZONTAL := "asset_assets_tiles_terrain_bridges_bridge_horizontal_32x32_png"
const RENDER_BRIDGE := RENDER_BRIDGE_VERTICAL
const RENDER_TELEPORT_ZONE := "asset_assets_tiles_sheets_biome_atlases_biome_tile_map_light_object_biome_map_atlas_crop_1261_363_32x32_resize_32x32_png"
const RENDER_MAP_EDGE_CLIFF := "asset_assets_tiles_sheets_biome_atlases_biome_tile_map_light_object_biome_map_atlas_crop_147_91_35x34_resize_32x32_png"
const RENDER_MOUNTAIN_ROCK := "asset_assets_sprites_objects_natural_props_mountain_rock_01_32x32_png"
const RENDER_MOUNTAIN_CONIFER := "terrain_tree_pine_32x32"
const RENDER_MOUNTAIN_CAVE := "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png"
const RENDER_MOUNTAIN_MINE := "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png"
const RENDER_MOUNTAIN_TEMPLE := "asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png"
const RENDER_MOUNTAIN_ABANDONED_MINE := "asset_assets_sprites_objects_mining_timber_support_1x2_32x64_png"
const RENDER_MOUNTAIN_TEA_HOUSE := "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png"
const RENDER_WASTELAND_DRY_SOIL := "asset_assets_tiles_terrain_desert_dry_soil_01_32x32_png"
const RENDER_WASTELAND_CRACKED_GROUND := "asset_assets_tiles_terrain_desert_cracked_clay_32x32_png"
const RENDER_WASTELAND_DETOUR_PATH := "asset_assets_tiles_terrain_desert_sand_ripple_01_32x32_png"
const RENDER_WASTELAND_RUIN := "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png"
const RENDER_WASTELAND_DEAD_TREE := "terrain_tree_round_32x32"
const RENDER_WASTELAND_DRY_RIVER := "asset_assets_tiles_terrain_desert_dry_scrub_patch_32x32_png"
const RENDER_WASTELAND_CAMP_TRACE := "asset_assets_tiles_terrain_desert_bone_scatter_32x32_png"
const RENDER_WASTELAND_ABANDONED_VILLAGE := "asset_assets_sprites_objects_structures_small_storage_shed_64x64_png"
const RENDER_WASTELAND_ABANDONED_OUTPOST := "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png"
const RENDER_WASTELAND_RUINED_TEA_ROOM := "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png"
const RENDER_WASTELAND_BATTLEFIELD_TRACE := "asset_assets_tiles_terrain_desert_bone_scatter_32x32_png"
const RENDER_RESOURCE_IRON_SCRAP := "asset_assets_sprites_objects_mining_iron_ore_32x32_png"
const RENDER_SNOWFIELD_SNOW := "asset_assets_tiles_terrain_snow_snow_ground_01_32x32_png"
const RENDER_SNOWFIELD_PATH := "asset_assets_tiles_terrain_snow_snow_ground_03_32x32_png"
const RENDER_SNOWFIELD_ICE := "asset_assets_tiles_terrain_snow_snow_ground_04_32x32_png"
const RENDER_SNOWFIELD_ICE_EDGE := "asset_assets_tiles_terrain_snow_snow_rock_edge_01_32x32_png"
const RENDER_SNOWFIELD_PINE := "terrain_tree_pine_32x32"
const RENDER_SNOWFIELD_ICE_WALL := "asset_assets_tiles_terrain_snow_snow_rock_edge_02_32x32_png"
const RENDER_SNOWFIELD_SAFE_CLEARING := "asset_assets_tiles_terrain_snow_snow_mound_32x32_png"
const RENDER_SNOWFIELD_LODGE := "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png"
const RENDER_SNOWFIELD_HOT_SPRING := "asset_assets_sprites_objects_shrine_props_stone_water_basin_32x32_png"
const RENDER_SNOWFIELD_SHRINE := "asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png"
const RENDER_SNOWFIELD_FROZEN_MINE := "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png"
const RENDER_RAINFOREST_JUNGLE := "terrain_tree_broadleaf_32x32"
const RENDER_RAINFOREST_SWAMP := "asset_assets_sprites_objects_natural_props_reed_clump_32x32_png"
const RENDER_RAINFOREST_RIVER := "terrain_river_water_01"
const RENDER_RAINFOREST_VINE_PATH := "asset_assets_tiles_terrain_plains_flower_grass_02_32x32_png"
const RENDER_RAINFOREST_TEA_FIELD := "asset_assets_sprites_objects_crafting_tea_leaf_worktable_32x32_png"
const RENDER_RAINFOREST_AGARWOOD := "terrain_tree_round_32x32"
const RENDER_RAINFOREST_RIVER_BANK := "asset_assets_tiles_terrain_plains_flower_grass_02_32x32_png"
const RENDER_RAINFOREST_RIVERSIDE_VILLAGE := "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png"
const RENDER_RAINFOREST_FOREST_TEA_ROOM := "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png"
const RENDER_RAINFOREST_INCENSE_SPACE := "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png"
const LARGE_HOUSE_SOURCE_ID := "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png"
const FENCE_CORNER_SOURCE_ID := "asset_assets_sprites_objects_structures_wood_fence_corner_32x32_png"
const FENCE_HORIZONTAL_SOURCE_ID := "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png"
const FENCE_HORIZONTAL_BOTTOM_SOURCE_ID := "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_bottom_180_png"
const LARGE_HOUSE_ID := "large_fenced_house"

const BALANCE_MIN_RESOURCE_NODES_ID := "biome_min_resource_nodes"
const TEMPLATE_PATH_SPINE := "path_spine"
const TEMPLATE_WATER_STROKE := "water_stroke"
const TEMPLATE_RESOURCE_CLUSTER := "resource_cluster"
const COMMON_TEMPLATE_IDS := [
	TEMPLATE_PATH_SPINE,
	TEMPLATE_WATER_STROKE,
	TEMPLATE_RESOURCE_CLUSTER
]

func generate(seed: int, data_version: String, biome_definition: Dictionary, balance_definitions: Array, item_definitions := [], options := {}) -> Dictionary:
	var retry_limit := int(options.get("retry_limit", DEFAULT_RETRY_LIMIT))
	var profile_result := _biome_generation_profile(biome_definition)
	if not profile_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, profile_result.reason, profile_result)
	var profile: Dictionary = profile_result.profile
	var resource_result := _biome_resource_item_ids(biome_definition, item_definitions, profile.get("resource_type_allowlist", ["재료"]))
	if not resource_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, resource_result.reason, resource_result)
	var resource_ids: Array = resource_result.ids
	var min_resource_result := _minimum_resource_nodes(balance_definitions, options)
	if not min_resource_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, min_resource_result.reason)
	var min_resource_nodes := int(min_resource_result.value)
	var max_resource_placement_attempts := int(options.get("max_resource_placement_attempts", max(64, min_resource_nodes * 24)))
	var core_dungeon_count := _balance_value(balance_definitions, "biome_core_dungeon_count", 1)
	# Every overworld must expose exactly one primary teleport zone, even when
	# balance data is missing or temporarily sets the count to zero.
	var teleport_zone_count := maxi(1, _balance_value(balance_definitions, "biome_teleport_zone_count", 1))
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
	_apply_map_boundary(world_data, profile, progression_projection.get("edge_exit_positions", []))
	var templates := _apply_common_templates(world_data, rng, chunks, profile)
	var biome_id := String(biome_definition.get("id", ""))
	var landmarks := _place_required_landmarks(world_data, rng, core_dungeon_count, teleport_zone_count, biome_id, profile)
	_carve_landmark_paths(world_data, landmarks, profile)
	var large_house_result := _place_large_fenced_house(world_data, rng, profile)
	if not large_house_result.ok:
		return _failed_attempt(seed, data_version, biome_definition, attempt, retry_limit, "large_fenced_house_placement_failed")
	_place_path_edge_fences(world_data, rng, templates, profile)
	var validator := ConnectivityValidator.new()
	var facility_nodes := _place_facility_nodes(world_data, rng, landmarks, profile, validator.reachable_cell_keys_from_entry(world_data.to_dictionary()))
	var reachable_cells := validator.reachable_cell_keys_from_entry(world_data.to_dictionary())
	var resource_nodes := _place_resource_nodes(world_data, rng, min_resource_nodes, max_resource_placement_attempts, resource_ids, reachable_cells, profile.get("resource_source_by_id", {}), templates, landmarks)
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
		"large_house": large_house_result.house,
		"chunks": chunks,
		"templates": templates,
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

func _failed_attempt(seed: int, data_version: String, biome_definition: Dictionary, attempt: int, retry_limit: int, reason: String) -> Dictionary:
	return {
		"ok": false,
		"data_version": data_version,
		"seed": seed,
		"biome_id": String(biome_definition.get("id", "")),
		"retry_attempt": attempt,
		"retry_limit": retry_limit,
		"failure_reason": reason
	}

func _place_large_fenced_house(world_data: WorldData, rng: DeterministicRng, profile: Dictionary) -> Dictionary:
	var candidates: Array[Vector2i] = []
	var center := Vector2i(MAP_WIDTH / 2 - 2, MAP_HEIGHT / 2 - 2)
	for radius in range(0, 28):
		for offset in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius), Vector2i(radius, radius), Vector2i(-radius, radius), Vector2i(radius, -radius), Vector2i(-radius, -radius)]:
			var outer_origin: Vector2i = center + offset
			if outer_origin.x < 2 or outer_origin.y < 2 or outer_origin.x + 4 >= MAP_WIDTH - 2 or outer_origin.y + 4 >= MAP_HEIGHT - 2:
				continue
			if not candidates.has(outer_origin):
				candidates.append(outer_origin)
	if candidates.is_empty():
		return {"ok": false}
	var start := rng.next_range(0, candidates.size() - 1)
	var validator := ConnectivityValidator.new()
	for attempt in range(candidates.size()):
		var outer_origin: Vector2i = candidates[(start + attempt) % candidates.size()]
		var all_cells := _large_house_footprint_cells(outer_origin)
		var blocked := false
		for position in all_cells:
			if not world_data.contains(position) or not world_data.is_walkable(position):
				blocked = true
				break
		if blocked:
			continue
		var house_origin := outer_origin + Vector2i.ONE
		var house_reserved := world_data.reserve_entity(LARGE_HOUSE_ID, house_origin, Vector2i(2, 2), false, {
			"source_id": LARGE_HOUSE_SOURCE_ID,
			"role": "core_dungeon_entrance"
		})
		if not house_reserved.ok:
			continue
		var fence_result := _reserve_large_house_fence(world_data, outer_origin)
		if not fence_result.ok or not validator.validate_world_data(world_data.to_dictionary()).valid:
			world_data.release_footprint(LARGE_HOUSE_ID)
			for owner_id in fence_result.get("owner_ids", []):
				world_data.release_footprint(String(owner_id))
			continue
		return {
			"ok": true,
			"house": {
				"id": LARGE_HOUSE_ID,
				"source_id": LARGE_HOUSE_SOURCE_ID,
				"position": _position_dictionary(house_origin),
				"footprint_size": {"x": 2, "y": 2},
				"fence_owner_ids": fence_result.owner_ids
			}
		}
	return {"ok": false}

func _large_house_footprint_cells(outer_origin: Vector2i) -> Array:
	var cells: Array = []
	for y in range(4):
		for x in range(4):
			cells.append(outer_origin + Vector2i(x, y))
	return cells

func _reserve_large_house_fence(world_data: WorldData, outer_origin: Vector2i) -> Dictionary:
	var segments := [
		{"id": "large_house_fence_nw", "origin": outer_origin, "size": Vector2i.ONE, "source_id": FENCE_CORNER_SOURCE_ID, "rotation_degrees": 0.0},
		{"id": "large_house_fence_ne", "origin": outer_origin + Vector2i(3, 0), "size": Vector2i.ONE, "source_id": FENCE_CORNER_SOURCE_ID, "rotation_degrees": 90.0},
		{"id": "large_house_fence_sw", "origin": outer_origin + Vector2i(0, 3), "size": Vector2i.ONE, "source_id": FENCE_CORNER_SOURCE_ID, "rotation_degrees": 270.0},
		{"id": "large_house_fence_se", "origin": outer_origin + Vector2i(3, 3), "size": Vector2i.ONE, "source_id": FENCE_CORNER_SOURCE_ID, "rotation_degrees": 180.0},
		{"id": "large_house_fence_n", "origin": outer_origin + Vector2i(1, 0), "size": Vector2i(2, 1), "source_id": FENCE_HORIZONTAL_SOURCE_ID, "rotation_degrees": 0.0},
		{"id": "large_house_fence_s", "origin": outer_origin + Vector2i(1, 3), "size": Vector2i(2, 1), "source_id": FENCE_HORIZONTAL_SOURCE_ID, "rotation_degrees": 0.0},
		{"id": "large_house_fence_w", "origin": outer_origin + Vector2i(0, 1), "size": Vector2i(1, 2), "source_id": FENCE_HORIZONTAL_SOURCE_ID, "rotation_degrees": 90.0},
		{"id": "large_house_fence_e", "origin": outer_origin + Vector2i(3, 1), "size": Vector2i(1, 2), "source_id": FENCE_HORIZONTAL_SOURCE_ID, "rotation_degrees": 90.0}
	]
	var owner_ids: Array = []
	for segment in segments:
		var result := world_data.reserve_entity(String(segment.id), segment.origin, segment.size, false, {
			"source_id": String(segment.source_id),
			"role": "large_house_fence",
			"rotation_degrees": float(segment.rotation_degrees)
		})
		if not result.ok:
			for owner_id in owner_ids:
				world_data.release_footprint(String(owner_id))
			return {"ok": false, "owner_ids": owner_ids}
		owner_ids.append(String(segment.id))
	return {"ok": true, "owner_ids": owner_ids}

func _apply_map_boundary(world_data: WorldData, profile: Dictionary, edge_exit_positions: Array) -> void:
	var preserved := {}
	for raw_position in edge_exit_positions:
		var position: Variant = _vector_from_dictionary(raw_position) if raw_position is Dictionary else raw_position
		if position is Vector2i and (position.x == 0 or position.y == 0 or position.x == MAP_WIDTH - 1 or position.y == MAP_HEIGHT - 1):
			preserved[_key(position)] = true
	var cliff_terrain_id := String(profile.get("boundary_terrain_id", TERRAIN_MOUNTAIN_CLIFF))
	var cliff_render_id := String(profile.get("boundary_render_id", RENDER_MAP_EDGE_CLIFF))
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			if x != 0 and y != 0 and x != MAP_WIDTH - 1 and y != MAP_HEIGHT - 1:
				continue
			var position := Vector2i(x, y)
			if preserved.has(_key(position)):
				continue
			world_data.set_terrain(position, cliff_terrain_id, false, cliff_render_id)

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
		BIOME_RAINFOREST:
			_apply_rainforest_chunk(world_data, chunk, rng)
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
						_set_tree_obstacle(world_data, position, TERRAIN_FOREST, TERRAIN_GRASS, RENDER_GRASS, RENDER_FOREST_TREE)
					else:
						world_data.set_terrain(position, TERRAIN_GRASS, true, RENDER_GRASS)
				3:
					if y == origin.y + CHUNK_HEIGHT / 2:
						world_data.set_terrain(position, TERRAIN_PATH, true, RENDER_PATH)
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
						_set_tree_obstacle(world_data, position, TERRAIN_MOUNTAIN_CONIFER, TERRAIN_MOUNTAIN_SLOPE, RENDER_MOUNTAIN_SLOPE, RENDER_MOUNTAIN_CONIFER)
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
						_set_tree_obstacle(world_data, position, TERRAIN_WASTELAND_DEAD_TREE, TERRAIN_WASTELAND_DRY_SOIL, RENDER_WASTELAND_DRY_SOIL, RENDER_WASTELAND_DEAD_TREE)
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
						_set_tree_obstacle(world_data, position, TERRAIN_SNOWFIELD_PINE, TERRAIN_SNOWFIELD_SNOW, RENDER_SNOWFIELD_SNOW, RENDER_SNOWFIELD_PINE)
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

func _apply_rainforest_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	var variant := int(chunk.variant)
	chunk["feature"] = _rainforest_feature_for_variant(variant)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match variant:
				0:
					if local_y == CHUNK_HEIGHT / 2 or (local_x == 5 and local_y > 1):
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true, RENDER_RAINFOREST_VINE_PATH)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, false, RENDER_RAINFOREST_JUNGLE)
				1:
					if local_x == 3 or local_x == 4:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER, false, RENDER_RAINFOREST_RIVER)
					elif local_x == 2 or local_x == 5:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true, RENDER_RAINFOREST_RIVER_BANK)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true, RENDER_RAINFOREST_JUNGLE)
				2:
					if rng.next_range(0, 99) < 45:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_SWAMP, false, RENDER_RAINFOREST_SWAMP)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true, RENDER_RAINFOREST_RIVER_BANK)
				3:
					if local_x >= 2 and local_x <= 5 and local_y >= 1 and local_y <= 4:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_TEA_FIELD, true, RENDER_RAINFOREST_TEA_FIELD)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true, RENDER_RAINFOREST_VINE_PATH)
				4:
					if local_x == 1 or local_x == 6 or local_y == 1:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true, RENDER_RAINFOREST_VINE_PATH)
					elif rng.next_range(0, 99) < 50:
						_set_tree_obstacle(world_data, position, TERRAIN_RAINFOREST_AGARWOOD, TERRAIN_RAINFOREST_RIVER_BANK, RENDER_RAINFOREST_RIVER_BANK, RENDER_RAINFOREST_AGARWOOD)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true, RENDER_RAINFOREST_JUNGLE)
				5:
					if local_y == 2 or (local_x >= 4 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true, RENDER_RAINFOREST_VINE_PATH)
					elif local_x == 2:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER, false, RENDER_RAINFOREST_RIVER)
					elif local_x == 3:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true, RENDER_RAINFOREST_RIVER_BANK)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true, RENDER_RAINFOREST_JUNGLE)
				_:
					world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true, RENDER_RAINFOREST_JUNGLE)

func _rainforest_feature_for_variant(variant: int) -> String:
	match variant:
		0:
			return "dense_jungle_vine_path"
		1:
			return "wide_river_bank"
		2:
			return "swamp_boundary"
		3:
			return "tea_cultivation"
		4:
			return "agarwood_grove"
		5:
			return "river_bypass"
		_:
			return "rainforest"

func _apply_common_templates(world_data: WorldData, rng: DeterministicRng, chunks: Array, profile: Dictionary) -> Array:
	var templates := []
	var water_template := _apply_template_water_stroke(world_data, rng, profile)
	templates.append(water_template)
	var path_template := _apply_template_path_spine(world_data, rng, profile)
	templates.append(path_template)
	templates.append(_apply_template_resource_cluster_anchors(rng, chunks, path_template, water_template))
	return templates

func _apply_template_water_stroke(world_data: WorldData, rng: DeterministicRng, profile: Dictionary) -> Dictionary:
	var water_cells := []
	var shore_cells := []
	var x := rng.next_range(MAP_WIDTH / 3, MAP_WIDTH / 3 * 2)
	for y in range(1, MAP_HEIGHT - 1):
		var position := Vector2i(x, y)
		_paint_water_cell(world_data, position, profile, water_cells)
		_paint_shore_cell(world_data, position + Vector2i.LEFT, profile, shore_cells)
		_paint_shore_cell(world_data, position + Vector2i.RIGHT, profile, shore_cells)
		if y % CHUNK_HEIGHT == CHUNK_HEIGHT - 1 and y < MAP_HEIGHT - 2:
			var bend := rng.next_range(-1, 1)
			var next_x := clampi(x + bend, 3, MAP_WIDTH - 4)
			var step := 1 if next_x >= x else -1
			for connector_x in range(x + step, next_x + step, step):
				var connector := Vector2i(connector_x, y)
				_paint_water_cell(world_data, connector, profile, water_cells)
				_paint_shore_cell(world_data, connector + Vector2i.UP, profile, shore_cells)
				_paint_shore_cell(world_data, connector + Vector2i.DOWN, profile, shore_cells)
			x = next_x
	return {
		"id": TEMPLATE_WATER_STROKE,
		"water_terrain_id": String(profile.water_terrain_id),
		"water_render_id": String(profile.water_render_id),
		"shore_terrain_id": String(profile.shore_terrain_id),
		"shore_render_id": String(profile.shore_render_id),
		"cells": _position_dictionary_array(water_cells),
		"shore_cells": _position_dictionary_array(shore_cells),
		"crosses_chunk_boundary": _positions_cross_chunk_boundary(water_cells)
	}

func _apply_template_path_spine(world_data: WorldData, rng: DeterministicRng, profile: Dictionary) -> Dictionary:
	var path_cells := []
	var spine_y := rng.next_range(8, MAP_HEIGHT - 9)
	var current_y := spine_y
	for x in range(2, MAP_WIDTH - 2):
		var previous_y := current_y
		if x > 2 and x % 4 == 0:
			current_y = clampi(current_y + rng.next_range(-1, 1), 4, MAP_HEIGHT - 5)
			var bend_step := 1 if current_y >= previous_y else -1
			for bend_y in range(previous_y, current_y + bend_step, bend_step):
				var bend_position := Vector2i(x, bend_y)
				_make_path_cell(world_data, bend_position, profile)
				path_cells.append(bend_position)
		var position := Vector2i(x, current_y)
		_make_path_cell(world_data, position, profile)
		path_cells.append(position)
	var branch_targets := [
		Vector2i(MAP_WIDTH / 4, rng.next_range(4, MAP_HEIGHT - 5)),
		Vector2i(MAP_WIDTH / 2, rng.next_range(4, MAP_HEIGHT - 5)),
		Vector2i(MAP_WIDTH / 4 * 3, rng.next_range(4, MAP_HEIGHT - 5))
	]
	for branch_index in range(branch_targets.size()):
		var target: Vector2i = branch_targets[branch_index]
		var branch_x := target.x + rng.next_range(-2, 2)
		var anchor_y := spine_y
		for row in path_cells:
			var candidate: Vector2i = row
			if candidate.x == branch_x:
				anchor_y = candidate.y
				break
		var step := 1 if target.y >= anchor_y else -1
		for y in range(anchor_y, target.y + step, step):
			var branch_position := Vector2i(branch_x, y)
			_make_path_cell(world_data, branch_position, profile)
			path_cells.append(branch_position)
	return {
		"id": TEMPLATE_PATH_SPINE,
		"path_terrain_id": String(profile.path_terrain_id),
		"path_render_id": String(profile.path_render_id),
		"cells": _position_dictionary_array(_unique_positions(path_cells))
	}

func _apply_template_resource_cluster_anchors(rng: DeterministicRng, chunks: Array, path_template: Dictionary, water_template: Dictionary) -> Dictionary:
	var path_cells := _vector_array_from_dictionaries(path_template.get("cells", []))
	var water_cells := _vector_array_from_dictionaries(water_template.get("cells", []))
	var anchors := []
	var candidate_indexes := [
		maxi(0, path_cells.size() / 5),
		maxi(0, path_cells.size() / 2),
		maxi(0, path_cells.size() / 5 * 4)
	]
	for index in candidate_indexes:
		if path_cells.is_empty():
			break
		var anchor: Vector2i = path_cells[clampi(index + rng.next_range(-2, 2), 0, path_cells.size() - 1)]
		anchors.append(anchor)
	for chunk_index in range(mini(3, chunks.size())):
		var chunk: Dictionary = chunks[(chunk_index * 7 + rng.next_range(0, 3)) % chunks.size()]
		var origin := _vector_from_dictionary(chunk.origin)
		anchors.append(Vector2i(origin.x + CHUNK_WIDTH / 2, origin.y + CHUNK_HEIGHT / 2))
	return {
		"id": TEMPLATE_RESOURCE_CLUSTER,
		"anchors": _position_dictionary_array(_unique_positions(anchors)),
		"path_cell_count": path_cells.size(),
		"water_cell_count": water_cells.size()
	}

func _paint_water_cell(world_data: WorldData, position: Vector2i, profile: Dictionary, water_cells: Array) -> void:
	if not world_data.contains(position):
		return
	_clear_generated_tree_obstacle(world_data, position)
	world_data.set_terrain(position, String(profile.water_terrain_id), bool(profile.water_walkable), String(profile.water_render_id))
	water_cells.append(position)

func _paint_shore_cell(world_data: WorldData, position: Vector2i, profile: Dictionary, shore_cells: Array) -> void:
	if not world_data.contains(position):
		return
	_clear_generated_tree_obstacle(world_data, position)
	if not world_data.is_walkable(position):
		return
	world_data.set_terrain(position, String(profile.shore_terrain_id), true, String(profile.shore_render_id))
	shore_cells.append(position)

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

	# Ruins are independent points of interest, separate from both the dungeon
	# entrance and the teleport zone.
	landmarks.append(_add_landmark(
		world_data,
		WorldData.LANDMARK_RUIN,
		0,
		Vector2i(rng.next_range(6, MAP_WIDTH / 4), rng.next_range(6, MAP_HEIGHT - 7)),
		profile
	))

	for index in range(core_dungeon_count):
		landmarks.append(_add_landmark(
			world_data,
			WorldData.LANDMARK_CORE_DUNGEON,
			index,
			# Keep ruins in the far-east zone, well away from central teleports.
			Vector2i(rng.next_range(MAP_WIDTH - 6, MAP_WIDTH - 3), rng.next_range(6, MAP_HEIGHT - 7)),
			profile
		))

	return landmarks

func _add_landmark(world_data: WorldData, kind: String, index: int, position: Vector2i, profile: Dictionary, metadata := {}) -> Dictionary:
	_clear_generated_tree_obstacle(world_data, position)
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
	# A route may cross an already-built bridge, but only at one tile.  Snapshot
	# bridge cells before carving so newly-created cells on this route are not
	# mistaken for overlaps.
	var bridge_terrain_id := String(profile.bridge_terrain_id)
	var existing_bridge_cells := {}
	for x in range(start.x, target.x + (1 if target.x >= start.x else -1), (1 if target.x >= start.x else -1)):
		var horizontal_cell := Vector2i(x, start.y)
		if world_data.contains(horizontal_cell) and world_data.terrain_id_at(horizontal_cell) == bridge_terrain_id:
			existing_bridge_cells[horizontal_cell] = true
	for y in range(start.y, target.y + (1 if target.y >= start.y else -1), (1 if target.y >= start.y else -1)):
		var vertical_cell := Vector2i(target.x, y)
		if world_data.contains(vertical_cell) and world_data.terrain_id_at(vertical_cell) == bridge_terrain_id:
			existing_bridge_cells[vertical_cell] = true

	var bridge_overlap_count := 0
	var step_x := 1 if target.x >= start.x else -1
	for x in range(start.x, target.x + step_x, step_x):
		var position := Vector2i(x, start.y)
		if existing_bridge_cells.has(position):
			if bridge_overlap_count >= 1:
				continue
			bridge_overlap_count += 1
		_make_path_cell(world_data, position, profile)

	var step_y := 1 if target.y >= start.y else -1
	for y in range(start.y, target.y + step_y, step_y):
		var vertical_position := Vector2i(target.x, y)
		if existing_bridge_cells.has(vertical_position):
			if bridge_overlap_count >= 1:
				continue
			bridge_overlap_count += 1
		_make_path_cell(world_data, vertical_position, profile)

func _make_path_cell(world_data: WorldData, position: Vector2i, profile: Dictionary) -> void:
	if not world_data.contains(position):
		return
	_clear_generated_tree_obstacle(world_data, position)
	var is_bridge := not world_data.is_walkable(position)
	var terrain_id := String(profile.bridge_terrain_id) if is_bridge else String(profile.path_terrain_id)
	var render_id := String(profile.get("bridge_render_id", profile.path_render_id)) if is_bridge else String(profile.path_render_id)
	if is_bridge:
		var water_north_south := world_data.terrain_id_at(position + Vector2i.UP) == String(profile.water_terrain_id) or world_data.terrain_id_at(position + Vector2i.DOWN) == String(profile.water_terrain_id)
		var water_east_west := world_data.terrain_id_at(position + Vector2i.LEFT) == String(profile.water_terrain_id) or world_data.terrain_id_at(position + Vector2i.RIGHT) == String(profile.water_terrain_id)
		if water_north_south and not water_east_west:
			render_id = RENDER_BRIDGE_VERTICAL
		elif water_east_west:
			render_id = RENDER_BRIDGE_HORIZONTAL
	world_data.set_terrain(position, terrain_id, true, render_id)

func _place_path_edge_fences(world_data: WorldData, rng: DeterministicRng, templates: Array, profile: Dictionary) -> void:
	var path_template := {}
	for template in templates:
		if String(template.get("id", "")) == TEMPLATE_PATH_SPINE:
			path_template = template
			break
	var path_positions := {}
	# Include the spine and every landmark connector carved afterward; the
	# visible road is often one of those connector cells.
	for cell in world_data.to_dictionary().get("cells", []):
		var terrain: Dictionary = cell.get("layers", {}).get(WorldData.LAYER_TERRAIN, {})
		if String(terrain.get("id", "")) != String(profile.path_terrain_id):
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		path_positions[_key(position)] = position
	var placed := 0
	for value in path_positions.values():
		var position: Vector2i = value
		# Border both sides of the trail, leaving deterministic occasional gaps
		# so the player can still cut across the surrounding terrain.
		for side in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if rng.next_range(0, 7) == 0:
				continue
			var fence_position: Vector2i = position + side
			if not world_data.contains(fence_position) or path_positions.has(_key(fence_position)):
				continue
			# Never fill the narrow gap between two nearby road lanes.
			var adjacent_path_count := 0
			for adjacent_side in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if path_positions.has(_key(fence_position + adjacent_side)):
					adjacent_path_count += 1
			if adjacent_path_count >= 2:
				continue
			if not world_data.is_walkable(fence_position):
				continue
			# A rotated 1x2 segment is taller than one tile and overlaps on
			# descending lanes; use the 1x1 corner piece for those side posts.
			var source_id := FENCE_CORNER_SOURCE_ID if side.x != 0 or placed % 5 == 4 else (FENCE_HORIZONTAL_BOTTOM_SOURCE_ID if side == Vector2i.DOWN else FENCE_HORIZONTAL_SOURCE_ID)
			var rotation_degrees := 90.0 if side.x != 0 else 0.0
			var owner_id := "path_fence_%d_%d" % [fence_position.x, fence_position.y]
			var reservation := world_data.reserve_entity(owner_id, fence_position, Vector2i.ONE, false, {
				"source_id": source_id,
				"rotation_degrees": rotation_degrees,
				"terrain_overlay": "path_fence",
				"path_terrain_id": String(profile.path_terrain_id)
			})
			if reservation.ok:
				placed += 1

func _set_tree_obstacle(world_data: WorldData, position: Vector2i, terrain_id: String, base_terrain_id: String, base_render_id: String, tree_source_id: String) -> bool:
	# Wall cells are structural boundaries and must remain free of tree
	# overlays/obstacles, regardless of the biome's tree placement pass.
	if terrain_id.to_lower().contains("wall") or base_terrain_id.to_lower().contains("wall"):
		return false
	_clear_generated_tree_obstacle(world_data, position)
	world_data.set_terrain(position, terrain_id, true, base_render_id)
	var reserved := world_data.reserve_entity(_tree_owner_id(position), position, Vector2i.ONE, true, {
		"source_id": tree_source_id,
		"resource_id": "wood",
		"terrain_id": terrain_id,
		"base_terrain_id": base_terrain_id,
		"base_render_id": base_render_id,
		"terrain_overlay": "tree"
	})
	if not reserved.ok:
		world_data.set_terrain(position, base_terrain_id, true, base_render_id)
		return false
	return true

func _clear_generated_tree_obstacle(world_data: WorldData, position: Vector2i) -> void:
	world_data.release_footprint(_tree_owner_id(position))

func _tree_owner_id(position: Vector2i) -> String:
	return "terrain_tree_wood_%d_%d" % [position.x, position.y]

func _place_resource_nodes(world_data: WorldData, rng: DeterministicRng, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array, reachable_cells: Dictionary, source_by_resource_id: Dictionary, templates := [], landmarks := []) -> Array:
	var nodes := []
	var max_attempts: int = max(0, max_resource_placement_attempts)
	var cardinal_offsets := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var candidate_positions := _resource_candidate_positions(rng, templates, landmarks)
	var path_cell_keys := _template_path_key_set(templates)
	var attempt := 0
	for candidate_position in candidate_positions:
		if nodes.size() >= min_resource_nodes:
			break
		if attempt >= max_attempts:
			break
		attempt += 1
		var position: Vector2i = candidate_position
		if path_cell_keys.has(_key(position)):
			continue
		if not world_data.is_walkable(position) or not reachable_cells.has(_key(position)):
			continue
		var access_position := _reachable_access_position(position, reachable_cells, cardinal_offsets)
		if access_position == Vector2i(-1, -1):
			continue
		_try_place_resource_node(world_data, position, access_position, resource_ids, source_by_resource_id, nodes)
	while nodes.size() < min_resource_nodes and attempt < max_attempts:
		attempt += 1
		var position := Vector2i(rng.next_range(2, MAP_WIDTH - 3), rng.next_range(2, MAP_HEIGHT - 3))
		if path_cell_keys.has(_key(position)):
			continue
		if not world_data.is_walkable(position) or not reachable_cells.has(_key(position)):
			continue
		var access_position := _reachable_access_position(position, reachable_cells, cardinal_offsets)
		if access_position == Vector2i(-1, -1):
			continue
		_try_place_resource_node(world_data, position, access_position, resource_ids, source_by_resource_id, nodes)
	return nodes

func _template_path_key_set(templates: Array) -> Dictionary:
	var path_keys := {}
	for position in _template_path_cells(templates):
		path_keys[_key(position)] = true
	return path_keys

func _try_place_resource_node(world_data: WorldData, position: Vector2i, access_position: Vector2i, resource_ids: Array, source_by_resource_id: Dictionary, nodes: Array) -> bool:
	var owner_id := "resource_%d" % nodes.size()
	var resource_id: String = String(resource_ids[nodes.size() % resource_ids.size()])
	# Stones are common roadside pickups: bias the deterministic rotation so
	# roughly one out of every three generated nodes is a stone when available.
	if resource_ids.has("stone") and nodes.size() % 3 == 0:
		resource_id = "stone"
	var source_id := String(source_by_resource_id.get(resource_id, ""))
	var metadata := {"resource_id": resource_id}
	if not source_id.is_empty():
		metadata["source_id"] = source_id
	var reserved := world_data.reserve_entity(owner_id, position, Vector2i.ONE, true, metadata)
	if not reserved.ok:
		return false
	var validator := ConnectivityValidator.new()
	var world_dictionary := world_data.to_dictionary()
	if not bool(validator.validate_world_data(world_dictionary).get("valid", false)):
		world_data.release_footprint(owner_id)
		return false
	var access_points := []
	for node in nodes:
		access_points.append(node.access_position)
	access_points.append(_position_dictionary(access_position))
	if not bool(validator.validate_access_points(world_dictionary, access_points).get("valid", false)):
		world_data.release_footprint(owner_id)
		return false
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
	return true

func _resource_candidate_positions(rng: DeterministicRng, templates: Array, landmarks: Array) -> Array:
	var candidates := []
	var anchors := _resource_cluster_anchors(templates)
	for anchor in anchors:
		candidates.append_array(_cluster_positions_near(anchor))
	for path_cell in _template_path_cells(templates):
		if rng.next_range(0, 99) < 40:
			candidates.append_array(_cardinal_positions_near(path_cell))
	for landmark in landmarks:
		candidates.append_array(_cluster_positions_near(_vector_from_dictionary(landmark.get("position", {}))))
	return _unique_positions(candidates)

func _resource_cluster_anchors(templates: Array) -> Array:
	for template in templates:
		if String(template.get("id", "")) == TEMPLATE_RESOURCE_CLUSTER:
			return _vector_array_from_dictionaries(template.get("anchors", []))
	return []

func _template_path_cells(templates: Array) -> Array:
	for template in templates:
		if String(template.get("id", "")) == TEMPLATE_PATH_SPINE:
			return _vector_array_from_dictionaries(template.get("cells", []))
	return []

func _cluster_positions_near(anchor: Vector2i) -> Array:
	var positions := []
	for offset in [
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP,
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
		Vector2i(2, 0),
		Vector2i(-2, 0),
		Vector2i(0, 2),
		Vector2i(0, -2)
	]:
		var position: Vector2i = anchor + offset
		if position.x >= 2 and position.y >= 2 and position.x < MAP_WIDTH - 2 and position.y < MAP_HEIGHT - 2:
			positions.append(position)
	return positions

func _cardinal_positions_near(anchor: Vector2i) -> Array:
	return [
		anchor + Vector2i.RIGHT,
		anchor + Vector2i.LEFT,
		anchor + Vector2i.DOWN,
		anchor + Vector2i.UP
	]

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
				"path_render_id": RENDER_PATH,
				"bridge_render_id": RENDER_BRIDGE,
				"water_terrain_id": TERRAIN_WATER,
				"water_render_id": RENDER_WATER,
				"water_walkable": false,
				"shore_terrain_id": TERRAIN_GRASS,
				"shore_render_id": RENDER_GRASS,
				"required_terrain_terms": [],
				"facility_terms": [],
				"facility_source_by_term": {},
				"resource_type_allowlist": ["재료"],
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
				"water_terrain_id": TERRAIN_MOUNTAIN_VALLEY_WATER,
				"water_render_id": RENDER_WATER,
				"water_walkable": false,
				"shore_terrain_id": TERRAIN_MOUNTAIN_PATH,
				"shore_render_id": RENDER_MOUNTAIN_PATH,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"광산": RENDER_MOUNTAIN_MINE,
					"산사": RENDER_MOUNTAIN_TEMPLE,
					"폐광": RENDER_MOUNTAIN_ABANDONED_MINE,
					"산중 찻집": RENDER_MOUNTAIN_TEA_HOUSE
				},
				"resource_type_allowlist": ["재료"],
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
				"water_terrain_id": TERRAIN_WASTELAND_DRY_RIVER,
				"water_render_id": RENDER_WASTELAND_DRY_RIVER,
				"water_walkable": false,
				"shore_terrain_id": TERRAIN_WASTELAND_DETOUR_PATH,
				"shore_render_id": RENDER_WASTELAND_DETOUR_PATH,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"폐촌": RENDER_WASTELAND_ABANDONED_VILLAGE,
					"버려진 초소": RENDER_WASTELAND_ABANDONED_OUTPOST,
					"무너진 다실": RENDER_WASTELAND_RUINED_TEA_ROOM,
					"전쟁터 흔적": RENDER_WASTELAND_BATTLEFIELD_TRACE
				},
				"resource_type_allowlist": ["재료"],
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
				"water_terrain_id": TERRAIN_SNOWFIELD_ICE,
				"water_render_id": RENDER_SNOWFIELD_ICE,
				"water_walkable": false,
				"shore_terrain_id": TERRAIN_SNOWFIELD_ICE_EDGE,
				"shore_render_id": RENDER_SNOWFIELD_ICE_EDGE,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"산장": RENDER_SNOWFIELD_LODGE,
					"온천": RENDER_SNOWFIELD_HOT_SPRING,
					"설원 사당": RENDER_SNOWFIELD_SHRINE,
					"얼어붙은 광산": RENDER_SNOWFIELD_FROZEN_MINE
				},
				"resource_type_allowlist": ["재료"],
				"resource_source_by_id": {
					"wood": RENDER_SNOWFIELD_PINE
				},
				"minimum_facility_nodes": facility_terms.size()
			})
		BIOME_RAINFOREST:
			var required_terms := ["밀림", "습지", "넓은 강", "덩굴 통로", "차 재배지", "향목 숲"]
			var terrain_text := String(biome_definition.get("terrain", ""))
			for term in required_terms:
				if not terrain_text.contains(term):
					return {"ok": false, "reason": "missing_biome_generation_terms", "missing_term": term}
			var facility_terms := ["차 재배지", "강변 취락", "숲속 다실", "향 문화 공간"]
			var facility_text := String(biome_definition.get("facilities", ""))
			for term in facility_terms:
				if not facility_text.contains(term):
					return {"ok": false, "reason": "missing_biome_facility_terms", "missing_term": term}
			return _profile_ok({
				"id": BIOME_RAINFOREST,
				"chunk_variant_count": 6,
				"default_terrain_id": TERRAIN_RAINFOREST_RIVER_BANK,
				"default_walkable": true,
				"path_terrain_id": TERRAIN_RAINFOREST_VINE_PATH,
				"bridge_terrain_id": TERRAIN_RAINFOREST_RIVER_BANK,
				"path_render_id": RENDER_RAINFOREST_VINE_PATH,
				"water_terrain_id": TERRAIN_RAINFOREST_RIVER,
				"water_render_id": RENDER_RAINFOREST_RIVER,
				"water_walkable": false,
				"shore_terrain_id": TERRAIN_RAINFOREST_RIVER_BANK,
				"shore_render_id": RENDER_RAINFOREST_RIVER_BANK,
				"required_terrain_terms": required_terms,
				"facility_terms": facility_terms,
				"facility_source_by_term": {
					"차 재배지": RENDER_RAINFOREST_TEA_FIELD,
					"강변 취락": RENDER_RAINFOREST_RIVERSIDE_VILLAGE,
					"숲속 다실": RENDER_RAINFOREST_FOREST_TEA_ROOM,
					"향 문화 공간": RENDER_RAINFOREST_INCENSE_SPACE
				},
				"resource_type_allowlist": ["재료", "향"],
				"resource_source_by_id": {
					"item_5": RENDER_RAINFOREST_AGARWOOD,
					"wood": RENDER_RAINFOREST_AGARWOOD,
					"clay": RENDER_RAINFOREST_SWAMP
				},
				"minimum_facility_nodes": facility_terms.size()
			})
		_:
			return {"ok": false, "reason": "unsupported_biome_generation_rules", "biome_id": biome_id}

func _profile_ok(profile: Dictionary) -> Dictionary:
	return {"ok": true, "profile": profile}

func _biome_resource_item_ids(biome_definition: Dictionary, item_definitions: Array, allowed_types: Array) -> Dictionary:
	var resource_text := String(biome_definition.get("resources", ""))
	if resource_text.strip_edges() == "":
		return {"ok": false, "reason": "missing_biome_resources", "ids": []}

	var ids := []
	for item in item_definitions:
		if not allowed_types.has(String(item.get("type", ""))):
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

func _position_dictionary_array(positions: Array) -> Array:
	var rows := []
	for position in positions:
		rows.append(_position_dictionary(position))
	return rows

func _vector_array_from_dictionaries(rows: Array) -> Array:
	var positions := []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			positions.append(_vector_from_dictionary(row))
	return positions

func _unique_positions(positions: Array) -> Array:
	var seen := {}
	var unique := []
	for position in positions:
		var key := _key(position)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(position)
	return unique

func _positions_cross_chunk_boundary(positions: Array) -> bool:
	if positions.is_empty():
		return false
	var previous_chunk := Vector2i(-1, -1)
	for position in positions:
		var chunk := Vector2i(position.x / CHUNK_WIDTH, position.y / CHUNK_HEIGHT)
		if previous_chunk != Vector2i(-1, -1) and chunk != previous_chunk:
			return true
		previous_chunk = chunk
	return false

func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]
