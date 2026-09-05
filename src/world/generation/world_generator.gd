extends RefCounted
class_name WorldGenerator

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const DeterministicRng = preload("res://src/core/rng/deterministic_rng.gd")
const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const MonsterSpawnPoolResolver = preload("res://src/world/generation/monster_spawn_pool_resolver.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

static var MAP_WIDTH := RuntimeConstants.int_value("world.overworld_width")
static var MAP_HEIGHT := RuntimeConstants.int_value("world.overworld_height")
static var CHUNK_WIDTH := RuntimeConstants.int_value("world.chunk_width")
static var CHUNK_HEIGHT := RuntimeConstants.int_value("world.chunk_height")
static var DEFAULT_RETRY_LIMIT := RuntimeConstants.int_value("world.generation_retry_limit")
const TEMPLATE_PATH := "res://data/world_templates.json"
static var TEMPLATE_BANK: Array = _load_template_bank()
const BIOME_COMMON := "common_region"
const BIOME_MOUNTAIN := "mountain_region"
const BIOME_WASTELAND := "wasteland"
const BIOME_SNOWFIELD := "snowfield"
const BIOME_RAINFOREST := "rainforest"

const CHUNK_RULE_COMMON_GRASS := "common_grass"
const CHUNK_RULE_COMMON_FIELD := "common_field"
const CHUNK_RULE_COMMON_FOREST := "common_forest"
const CHUNK_RULE_COMMON_PATH := "common_path"
const CHUNK_RULE_COMMON_WATER := "common_water"
const CHUNK_RULE_COMMON_GROUND := "common_ground"
const CHUNK_RULE_MOUNTAIN_TRAIL := "mountain_trail"
const CHUNK_RULE_ROCK_FIELD := "rock_field"
const CHUNK_RULE_CLIFF_PASS := "cliff_pass"
const CHUNK_RULE_CONIFER_FOREST := "conifer_forest"
const CHUNK_RULE_VALLEY_WATER := "valley_water"
const CHUNK_RULE_CAVE_GROUND := "cave_ground"
const CHUNK_RULE_DRY_DETOUR := "dry_detour"
const CHUNK_RULE_ASYMMETRIC_RUIN := "asymmetric_ruin"
const CHUNK_RULE_LONG_DETOUR := "long_detour"
const CHUNK_RULE_DEAD_END := "dead_end"
const CHUNK_RULE_DRY_RIVER_BYPASS := "dry_river_bypass"
const CHUNK_RULE_BATTLEFIELD_TRACE := "battlefield_trace"
const CHUNK_RULE_SNOW_PATH_CROSSING := "snow_path_crossing"
const CHUNK_RULE_FROZEN_RIVER_EDGE := "frozen_river_edge"
const CHUNK_RULE_PINE_SILENCE := "pine_silence"
const CHUNK_RULE_ICE_WALL_PASS := "ice_wall_pass"
const CHUNK_RULE_SAFE_CLEARING := "safe_clearing"
const CHUNK_RULE_SNOWY_MOUNTAIN_PATH := "snowy_mountain_path"
const CHUNK_RULE_DENSE_JUNGLE_VINE_PATH := "dense_jungle_vine_path"
const CHUNK_RULE_WIDE_RIVER_BANK := "wide_river_bank"
const CHUNK_RULE_SWAMP_BOUNDARY := "swamp_boundary"
const CHUNK_RULE_TEA_CULTIVATION := "tea_cultivation"
const CHUNK_RULE_AGARWOOD_GROVE := "agarwood_grove"
const CHUNK_RULE_RIVER_BYPASS := "river_bypass"

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
	var resource_result := _biome_resource_item_ids(profile, item_definitions)
	if not resource_result.ok:
		return _failure(seed, data_version, biome_definition, retry_limit, resource_result.reason, resource_result)
	var resource_ids: Array = resource_result.ids
	var monster_spawn_pool := {}
	if options.has("monster_definitions"):
		monster_spawn_pool = MonsterSpawnPoolResolver.new().resolve(
			biome_definition,
			options.get("monster_definitions", []),
			String(options.get("time_phase", "day")),
			seed,
			data_version
		)
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
	var template := _template_for_seed(seed, String(biome_definition.get("id", "")))
	var progression_projection: Dictionary = options.get("progression_projection", {})

	for attempt in range(retry_limit + 1):
		# Layout randomness comes from the selected template. Run randomness is
		# kept separate so resources can vary without changing the map shape.
		var layout_rng := DeterministicRng.new(int(template.seed) + attempt)
		var content_rng := DeterministicRng.new(combined_seed + attempt)
		var world := _generate_attempt(
			seed,
			data_version,
			biome_definition,
			layout_rng,
			content_rng,
			attempt,
			retry_limit,
			int(core_dungeon_count),
			int(teleport_zone_count),
			min_resource_nodes,
			max_resource_placement_attempts,
			resource_ids,
			progression_projection,
			profile,
			monster_spawn_pool
		)
		if world.ok:
			world.template_id = String(template.id)
			return world

	return _failure(seed, data_version, biome_definition, retry_limit, "connectivity_or_resource_validation_failed")

func _generate_attempt(seed: int, data_version: String, biome_definition: Dictionary, layout_rng: DeterministicRng, content_rng: DeterministicRng, attempt: int, retry_limit: int, core_dungeon_count: int, teleport_zone_count: int, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array, progression_projection: Dictionary, profile: Dictionary, monster_spawn_pool: Dictionary) -> Dictionary:
	var world_data := WorldData.new(MAP_WIDTH, MAP_HEIGHT, String(profile.default_terrain_id), bool(profile.default_walkable))
	var chunks := _compose_chunks(layout_rng, world_data, profile)
	_apply_map_boundary(world_data, profile, progression_projection.get("edge_exit_positions", []))
	var templates := _apply_common_templates(world_data, layout_rng, chunks, profile)
	var biome_id := String(biome_definition.get("id", ""))
	var landmarks := _place_required_landmarks(world_data, layout_rng, core_dungeon_count, teleport_zone_count, biome_id, profile)
	_carve_landmark_paths(world_data, landmarks, profile)
	var large_house_result := _place_large_fenced_house(world_data, layout_rng, profile)
	if not large_house_result.ok:
		return _failed_attempt(seed, data_version, biome_definition, attempt, retry_limit, "large_fenced_house_placement_failed")
	_place_path_edge_fences(world_data, layout_rng, templates, profile)
	var validator := ConnectivityValidator.new()
	var facility_nodes := _place_facility_nodes(world_data, layout_rng, landmarks, profile, validator.reachable_cell_keys_from_entry(world_data.to_dictionary()))
	var reachable_cells := validator.reachable_cell_keys_from_entry(world_data.to_dictionary())
	var resource_nodes := _place_resource_nodes(world_data, content_rng, min_resource_nodes, max_resource_placement_attempts, resource_ids, reachable_cells, String(profile.id), templates, landmarks)
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
		"template_id": "",
		"biome_id": biome_id,
		"biome_progression_order": biome_definition.get("progression_order", null),
		"biome_generation_rule_id": String(profile.id),
		"landmarks": landmarks,
		"large_house": _strip_presentation_sources(large_house_result.house),
		"chunks": chunks,
		"templates": _strip_presentation_sources(templates),
		"facility_nodes": _semantic_node_snapshots(facility_nodes),
		"resource_nodes": _semantic_node_snapshots(resource_nodes),
		"monster_spawn_pool": monster_spawn_pool.duplicate(true),
		"min_resource_nodes": min_resource_nodes,
		"retry_attempt": attempt,
		"retry_limit": retry_limit,
		"facility_accessibility": {},
		"resource_accessibility": {},
		"connectivity": {},
		"world_data": _world_data_projection_snapshot(world_data)
	}

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

static func _load_template_bank() -> Array:
	if not FileAccess.file_exists(TEMPLATE_PATH):
		push_error("Missing world template bank: %s" % TEMPLATE_PATH)
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE_PATH))
	var templates = parsed.get("templates", []) if typeof(parsed) == TYPE_DICTIONARY else []
	if templates is not Array or templates.is_empty():
		push_error("World template bank must contain templates: %s" % TEMPLATE_PATH)
		return []
	return templates.duplicate(true)

static func _template_for_seed(seed: int, biome_id: String) -> Dictionary:
	if TEMPLATE_BANK.is_empty():
		return {"id": "fallback", "seed": seed}
	var biome_hash := 0
	for character in biome_id:
		biome_hash = (biome_hash * 31 + character.unicode_at(0)) & 0x7fffffff
	var index := absi(seed + biome_hash) % TEMPLATE_BANK.size()
	return TEMPLATE_BANK[index].duplicate(true)

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

func _world_data_projection_snapshot(world_data: WorldData) -> Dictionary:
	return _strip_presentation_sources(world_data.to_dictionary())

func _semantic_node_snapshots(nodes: Array) -> Array:
	var snapshots := []
	for node in nodes:
		var snapshot = node.duplicate(true) if node is Dictionary else node
		if snapshot is Dictionary:
			snapshot.erase("source_id")
		snapshots.append(snapshot)
	return snapshots

func _strip_presentation_sources(value):
	if value is Dictionary:
		var clean := {}
		for key in value.keys():
			var normalized := String(key)
			if normalized in [
				"render_id",
				"projection_source_id",
				"source_id",
				"base_render_id",
				"path_render_id",
				"bridge_render_id",
				"water_render_id",
				"shore_render_id",
				"boundary_render_id"
			]:
				continue
			clean[key] = _strip_presentation_sources(value[key])
		return clean
	if value is Array:
		var clean_array := []
		for item in value:
			clean_array.append(_strip_presentation_sources(item))
		return clean_array
	return value

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
		{"id": "large_house_fence_nw", "origin": outer_origin, "size": Vector2i.ONE, "rotation_degrees": 0.0},
		{"id": "large_house_fence_ne", "origin": outer_origin + Vector2i(3, 0), "size": Vector2i.ONE, "rotation_degrees": 90.0},
		{"id": "large_house_fence_sw", "origin": outer_origin + Vector2i(0, 3), "size": Vector2i.ONE, "rotation_degrees": 270.0},
		{"id": "large_house_fence_se", "origin": outer_origin + Vector2i(3, 3), "size": Vector2i.ONE, "rotation_degrees": 180.0},
		{"id": "large_house_fence_n", "origin": outer_origin + Vector2i(1, 0), "size": Vector2i(2, 1), "rotation_degrees": 0.0},
		{"id": "large_house_fence_s", "origin": outer_origin + Vector2i(1, 3), "size": Vector2i(2, 1), "rotation_degrees": 0.0},
		{"id": "large_house_fence_w", "origin": outer_origin + Vector2i(0, 1), "size": Vector2i(1, 2), "rotation_degrees": 90.0},
		{"id": "large_house_fence_e", "origin": outer_origin + Vector2i(3, 1), "size": Vector2i(1, 2), "rotation_degrees": 90.0}
	]
	var owner_ids: Array = []
	for segment in segments:
		var result := world_data.reserve_entity(String(segment.id), segment.origin, segment.size, false, {
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
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			if x != 0 and y != 0 and x != MAP_WIDTH - 1 and y != MAP_HEIGHT - 1:
				continue
			var position := Vector2i(x, y)
			if preserved.has(_key(position)):
				continue
			world_data.set_terrain(position, cliff_terrain_id, false)

func _compose_chunks(rng: DeterministicRng, world_data: WorldData, profile: Dictionary) -> Array:
	var chunks := []
	var chunk_rule_ids: Array = profile.get("chunk_rule_ids", [])
	var variant_count := chunk_rule_ids.size()
	for chunk_y in range(MAP_HEIGHT / CHUNK_HEIGHT):
		for chunk_x in range(MAP_WIDTH / CHUNK_WIDTH):
			var variant := rng.next_range(0, variant_count - 1)
			var rule_id := String(chunk_rule_ids[variant])
			var chunk := {
				"id": "chunk_%d_%d" % [chunk_x, chunk_y],
				"variant": variant,
				"rule_id": rule_id,
				"feature": rule_id,
				"origin": {"x": chunk_x * CHUNK_WIDTH, "y": chunk_y * CHUNK_HEIGHT},
				"size": {"x": CHUNK_WIDTH, "y": CHUNK_HEIGHT}
			}
			chunks.append(chunk)
			_apply_chunk_rule(world_data, chunk, rng, rule_id)
	return chunks

func _apply_chunk_rule(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	match rule_id:
		CHUNK_RULE_COMMON_GRASS, CHUNK_RULE_COMMON_FIELD, CHUNK_RULE_COMMON_FOREST, CHUNK_RULE_COMMON_PATH, CHUNK_RULE_COMMON_WATER, CHUNK_RULE_COMMON_GROUND:
			_apply_common_chunk(world_data, chunk, rng, rule_id)
		CHUNK_RULE_MOUNTAIN_TRAIL, CHUNK_RULE_ROCK_FIELD, CHUNK_RULE_CLIFF_PASS, CHUNK_RULE_CONIFER_FOREST, CHUNK_RULE_VALLEY_WATER, CHUNK_RULE_CAVE_GROUND:
			_apply_mountain_chunk(world_data, chunk, rng, rule_id)
		CHUNK_RULE_DRY_DETOUR, CHUNK_RULE_ASYMMETRIC_RUIN, CHUNK_RULE_LONG_DETOUR, CHUNK_RULE_DEAD_END, CHUNK_RULE_DRY_RIVER_BYPASS, CHUNK_RULE_BATTLEFIELD_TRACE:
			_apply_wasteland_chunk(world_data, chunk, rng, rule_id)
		CHUNK_RULE_SNOW_PATH_CROSSING, CHUNK_RULE_FROZEN_RIVER_EDGE, CHUNK_RULE_PINE_SILENCE, CHUNK_RULE_ICE_WALL_PASS, CHUNK_RULE_SAFE_CLEARING, CHUNK_RULE_SNOWY_MOUNTAIN_PATH:
			_apply_snowfield_chunk(world_data, chunk, rng, rule_id)
		CHUNK_RULE_DENSE_JUNGLE_VINE_PATH, CHUNK_RULE_WIDE_RIVER_BANK, CHUNK_RULE_SWAMP_BOUNDARY, CHUNK_RULE_TEA_CULTIVATION, CHUNK_RULE_AGARWOOD_GROVE, CHUNK_RULE_RIVER_BYPASS:
			_apply_rainforest_chunk(world_data, chunk, rng, rule_id)

func _apply_common_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			match rule_id:
				CHUNK_RULE_COMMON_GRASS:
					world_data.set_terrain(position, TERRAIN_GRASS, true)
				CHUNK_RULE_COMMON_FIELD:
					world_data.set_terrain(position, TERRAIN_FIELD, true)
				CHUNK_RULE_COMMON_FOREST:
					if rng.next_range(0, 99) < 32:
						_set_tree_obstacle(world_data, position, TERRAIN_FOREST, TERRAIN_GRASS)
					else:
						world_data.set_terrain(position, TERRAIN_GRASS, true)
				CHUNK_RULE_COMMON_PATH:
					if y == origin.y + CHUNK_HEIGHT / 2:
						world_data.set_terrain(position, TERRAIN_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_GROUND, true)
				CHUNK_RULE_COMMON_WATER:
					if x == origin.x + CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_WATER, false)
					else:
						world_data.set_terrain(position, TERRAIN_GRASS, true)
				_:
					world_data.set_terrain(position, TERRAIN_GROUND, true)

func _apply_mountain_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			match rule_id:
				CHUNK_RULE_MOUNTAIN_TRAIL:
					if y == origin.y + CHUNK_HEIGHT / 2 or x == origin.x + CHUNK_WIDTH - 2:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true)
				CHUNK_RULE_ROCK_FIELD:
					if rng.next_range(0, 99) < 40:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_ROCK, false)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true)
				CHUNK_RULE_CLIFF_PASS:
					if x == origin.x or y == origin.y or rng.next_range(0, 99) < 24:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_CLIFF, false)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true)
				CHUNK_RULE_CONIFER_FOREST:
					if rng.next_range(0, 99) < 35:
						_set_tree_obstacle(world_data, position, TERRAIN_MOUNTAIN_CONIFER, TERRAIN_MOUNTAIN_SLOPE)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true)
				CHUNK_RULE_VALLEY_WATER:
					if x == origin.x + CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_VALLEY_WATER, false)
					elif abs(x - (origin.x + CHUNK_WIDTH / 2)) == 1:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true)
				CHUNK_RULE_CAVE_GROUND:
					if y == origin.y + CHUNK_HEIGHT - 1:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_PATH, true)
					elif rng.next_range(0, 99) < 20:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_CAVE_GROUND, true)
					else:
						world_data.set_terrain(position, TERRAIN_MOUNTAIN_ROCK, false)
				_:
					world_data.set_terrain(position, TERRAIN_MOUNTAIN_SLOPE, true)

func _apply_wasteland_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match rule_id:
				CHUNK_RULE_DRY_DETOUR:
					if local_y == 1 or (local_x >= 3 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)
				CHUNK_RULE_ASYMMETRIC_RUIN:
					if local_x >= 1 and local_x <= 5 and local_y >= 1 and local_y <= 3 and (local_x == 1 or local_x == 5 or local_y == 1 or local_y == 3):
						world_data.set_terrain(position, TERRAIN_WASTELAND_RUIN, false)
					elif local_x == 3 and local_y == 2:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)
				CHUNK_RULE_LONG_DETOUR:
					if local_x == CHUNK_WIDTH - 2 and local_y < CHUNK_HEIGHT - 1:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					elif local_y == CHUNK_HEIGHT - 2 and local_x > 1:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					elif local_x == 1 and local_y == CHUNK_HEIGHT - 2:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)
				CHUNK_RULE_DEAD_END:
					if local_x == 2 and local_y <= 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					elif local_x == 2 and local_y == 4:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true)
					elif rng.next_range(0, 99) < 28:
						_set_tree_obstacle(world_data, position, TERRAIN_WASTELAND_DEAD_TREE, TERRAIN_WASTELAND_DRY_SOIL)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)
				CHUNK_RULE_DRY_RIVER_BYPASS:
					if local_x == 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_RIVER, false)
					elif local_x == 2 or local_x == 4:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_CRACKED_GROUND, true)
				CHUNK_RULE_BATTLEFIELD_TRACE:
					if local_x == 0 or local_y == 0 or (local_x == 6 and local_y < 5):
						world_data.set_terrain(position, TERRAIN_WASTELAND_CAMP_TRACE, false)
					elif local_y == 3 or local_x == 3:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DETOUR_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)
				_:
					world_data.set_terrain(position, TERRAIN_WASTELAND_DRY_SOIL, true)

func _apply_snowfield_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match rule_id:
				CHUNK_RULE_SNOW_PATH_CROSSING:
					if local_y == CHUNK_HEIGHT / 2 or local_x == CHUNK_WIDTH / 2:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				CHUNK_RULE_FROZEN_RIVER_EDGE:
					if local_x == 2 or local_x == 5:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_EDGE, true)
					elif local_x > 2 and local_x < 5:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE, false)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				CHUNK_RULE_PINE_SILENCE:
					if rng.next_range(0, 99) < 38:
						_set_tree_obstacle(world_data, position, TERRAIN_SNOWFIELD_PINE, TERRAIN_SNOWFIELD_SNOW)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				CHUNK_RULE_ICE_WALL_PASS:
					if local_y == 0 or local_x == 0 or local_x == CHUNK_WIDTH - 1:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_WALL, false)
					elif local_y == 2 or local_x == 3:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				CHUNK_RULE_SAFE_CLEARING:
					if local_x >= 2 and local_x <= 5 and local_y >= 1 and local_y <= 4:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SAFE_CLEARING, true)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				CHUNK_RULE_SNOWY_MOUNTAIN_PATH:
					if local_y == 1 or (local_x >= 4 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW_PATH, true)
					elif local_x == 1 and local_y >= 2:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_ICE_EDGE, true)
					else:
						world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)
				_:
					world_data.set_terrain(position, TERRAIN_SNOWFIELD_SNOW, true)

func _apply_rainforest_chunk(world_data: WorldData, chunk: Dictionary, rng: DeterministicRng, rule_id: String) -> void:
	var origin := _vector_from_dictionary(chunk.origin)
	for y in range(origin.y, origin.y + CHUNK_HEIGHT):
		for x in range(origin.x, origin.x + CHUNK_WIDTH):
			var position := Vector2i(x, y)
			var local_x := x - origin.x
			var local_y := y - origin.y
			match rule_id:
				CHUNK_RULE_DENSE_JUNGLE_VINE_PATH:
					if local_y == CHUNK_HEIGHT / 2 or (local_x == 5 and local_y > 1):
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, false)
				CHUNK_RULE_WIDE_RIVER_BANK:
					if local_x == 3 or local_x == 4:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER, false)
					elif local_x == 2 or local_x == 5:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true)
				CHUNK_RULE_SWAMP_BOUNDARY:
					if rng.next_range(0, 99) < 45:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_SWAMP, false)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true)
				CHUNK_RULE_TEA_CULTIVATION:
					if local_x >= 2 and local_x <= 5 and local_y >= 1 and local_y <= 4:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_TEA_FIELD, true)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true)
				CHUNK_RULE_AGARWOOD_GROVE:
					if local_x == 1 or local_x == 6 or local_y == 1:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true)
					elif rng.next_range(0, 99) < 50:
						_set_tree_obstacle(world_data, position, TERRAIN_RAINFOREST_AGARWOOD, TERRAIN_RAINFOREST_RIVER_BANK)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true)
				CHUNK_RULE_RIVER_BYPASS:
					if local_y == 2 or (local_x >= 4 and local_y == 4):
						world_data.set_terrain(position, TERRAIN_RAINFOREST_VINE_PATH, true)
					elif local_x == 2:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER, false)
					elif local_x == 3:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_RIVER_BANK, true)
					else:
						world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true)
				_:
					world_data.set_terrain(position, TERRAIN_RAINFOREST_JUNGLE, true)

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
		"shore_terrain_id": String(profile.shore_terrain_id),
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
	world_data.set_terrain(position, String(profile.water_terrain_id), bool(profile.water_walkable))
	water_cells.append(position)

func _paint_shore_cell(world_data: WorldData, position: Vector2i, profile: Dictionary, shore_cells: Array) -> void:
	if not world_data.contains(position):
		return
	_clear_generated_tree_obstacle(world_data, position)
	if not world_data.is_walkable(position):
		return
	world_data.set_terrain(position, String(profile.shore_terrain_id), true)
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
	world_data.set_terrain(position, String(profile.path_terrain_id), true)
	var id := "%s_%d" % [kind, index]
	var landmark_metadata := metadata.duplicate(true)
	landmark_metadata["biome_rule_id"] = String(profile.id)
	landmark_metadata["terrain_ids"] = profile.terrain_ids.duplicate(true)
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
	world_data.set_terrain(position, terrain_id, true)

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
			# Path fencing is reserved for river-side banks.  Fencing every
			# path edge makes long straight roads look artificial and causes
			# rotated 1x2 pieces to read as continuous vertical rails.
			var water_terrain_id := String(profile.water_terrain_id)
			var next_to_river := false
			for river_side in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if world_data.terrain_id_at(fence_position + river_side) == water_terrain_id:
					next_to_river = true
					break
			if not next_to_river:
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
			var rotation_degrees := 90.0 if side.x != 0 else 0.0
			var owner_id := "path_fence_%d_%d" % [fence_position.x, fence_position.y]
			var reservation := world_data.reserve_entity(owner_id, fence_position, Vector2i.ONE, false, {
				"rotation_degrees": rotation_degrees,
				"terrain_overlay": "path_fence",
				"path_terrain_id": String(profile.path_terrain_id)
			})
			if reservation.ok:
				placed += 1

func _set_tree_obstacle(world_data: WorldData, position: Vector2i, terrain_id: String, base_terrain_id: String) -> bool:
	# Wall cells are structural boundaries and must remain free of tree
	# overlays/obstacles, regardless of the biome's tree placement pass.
	if _is_structural_wall_terrain_id(terrain_id) or _is_structural_wall_terrain_id(base_terrain_id):
		return false
	_clear_generated_tree_obstacle(world_data, position)
	world_data.set_terrain(position, terrain_id, true)
	var reserved := world_data.reserve_entity(_tree_owner_id(position), position, Vector2i.ONE, true, {
		"resource_id": "wood",
		"terrain_id": terrain_id,
		"base_terrain_id": base_terrain_id,
		"terrain_overlay": "tree"
	})
	if not reserved.ok:
		world_data.set_terrain(position, base_terrain_id, true)
		return false
	return true

func _clear_generated_tree_obstacle(world_data: WorldData, position: Vector2i) -> void:
	world_data.release_footprint(_tree_owner_id(position))

func _tree_owner_id(position: Vector2i) -> String:
	return "terrain_tree_wood_%d_%d" % [position.x, position.y]

func _is_structural_wall_terrain_id(terrain_id: String) -> bool:
	return terrain_id in [TERRAIN_SNOWFIELD_ICE_WALL]

func _place_resource_nodes(world_data: WorldData, rng: DeterministicRng, min_resource_nodes: int, max_resource_placement_attempts: int, resource_ids: Array, reachable_cells: Dictionary, biome_rule_id: String, templates := [], landmarks := []) -> Array:
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
		_try_place_resource_node(world_data, position, access_position, resource_ids, biome_rule_id, nodes)
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
		_try_place_resource_node(world_data, position, access_position, resource_ids, biome_rule_id, nodes)
	return nodes

func _template_path_key_set(templates: Array) -> Dictionary:
	var path_keys := {}
	for position in _template_path_cells(templates):
		path_keys[_key(position)] = true
	return path_keys

func _try_place_resource_node(world_data: WorldData, position: Vector2i, access_position: Vector2i, resource_ids: Array, biome_rule_id: String, nodes: Array) -> bool:
	var owner_id := "resource_%d" % nodes.size()
	var resource_id: String = String(resource_ids[nodes.size() % resource_ids.size()])
	# Stones are common roadside pickups: bias the deterministic rotation so
	# roughly one out of every three generated nodes is a stone when available.
	if resource_ids.has("stone") and nodes.size() % 3 == 0:
		resource_id = "stone"
	var metadata := {"resource_id": resource_id, "biome_rule_id": biome_rule_id}
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
		"biome_rule_id": biome_rule_id,
		"position": _position_dictionary(position),
		"access_position": _position_dictionary(access_position),
		"placement_was_entry_reachable": true,
		"interactable": true
	}
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
	var facility_ids: Array = profile.get("facility_ids", [])
	if facility_ids.is_empty() or landmarks.is_empty():
		return nodes
	for index in range(facility_ids.size()):
		var facility_id := String(facility_ids[index])
		var anchor: Dictionary = landmarks[index % landmarks.size()]
		var placed := _place_facility_near(world_data, rng, _vector_from_dictionary(anchor.position), reachable_cells, index, facility_id, String(profile.id))
		if placed.ok:
			nodes.append(placed.node)
	return nodes

func _place_facility_near(world_data: WorldData, rng: DeterministicRng, anchor: Vector2i, reachable_cells: Dictionary, index: int, facility_id: String, biome_rule_id: String) -> Dictionary:
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
			"facility_id": facility_id
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
				"facility_id": facility_id,
				"position": _position_dictionary(position),
				"access_position": _position_dictionary(access_position),
				"placement_was_entry_reachable": true,
				"interactable": true
			}
		}
	return {"ok": false, "reason": "facility_placement_failed", "facility_id": facility_id}

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
	var profile_id := String(biome_definition.get("generation_profile_id", ""))
	if profile_id == "":
		return {"ok": false, "reason": "missing_biome_generation_profile_id", "biome_id": biome_id}
	if profile_id != biome_id:
		return {"ok": false, "reason": "invalid_biome_generation_profile_id", "biome_id": biome_id, "generation_profile_id": profile_id}
	var terrain_ids_result := _required_string_array_field(biome_definition, "generation_terrain_ids", "missing_biome_generation_terrain_ids")
	if not terrain_ids_result.ok:
		return terrain_ids_result
	var chunk_rule_ids_result := _required_string_array_field(biome_definition, "generation_chunk_rule_ids", "missing_biome_generation_chunk_rule_ids")
	if not chunk_rule_ids_result.ok:
		return chunk_rule_ids_result
	var resource_ids_result := _required_string_array_field(biome_definition, "generation_resource_item_ids", "missing_biome_resource_item_ids")
	if not resource_ids_result.ok:
		return resource_ids_result
	var walkability_rule_ids_result := _required_string_array_field(biome_definition, "generation_walkability_rule_ids", "missing_biome_generation_walkability_rule_ids")
	if not walkability_rule_ids_result.ok:
		return walkability_rule_ids_result
	var chunk_validation := _validate_chunk_rule_ids(chunk_rule_ids_result.values)
	if not chunk_validation.ok:
		return chunk_validation
	var terrain_roles := _terrain_roles_for_profile(terrain_ids_result.values, walkability_rule_ids_result.values)
	if not terrain_roles.ok:
		return terrain_roles
	var facility_ids := _string_array_field(biome_definition, "generation_facility_ids")
	var minimum_facility_nodes := int(biome_definition.get("generation_minimum_facility_nodes", 0))
	if minimum_facility_nodes < 0 or minimum_facility_nodes > facility_ids.size():
		return {"ok": false, "reason": "invalid_biome_minimum_facility_nodes", "biome_id": biome_id}
	return _profile_ok({
		"id": profile_id,
		"chunk_rule_ids": chunk_rule_ids_result.values,
		"default_terrain_id": String(terrain_roles.default_terrain_id),
		"default_walkable": true,
		"path_terrain_id": String(terrain_roles.path_terrain_id),
		"bridge_terrain_id": String(terrain_roles.bridge_terrain_id),
		"water_terrain_id": String(terrain_roles.water_terrain_id),
		"water_walkable": false,
		"shore_terrain_id": String(terrain_roles.shore_terrain_id),
		"boundary_terrain_id": String(terrain_roles.boundary_terrain_id),
		"terrain_ids": terrain_ids_result.values,
		"facility_ids": facility_ids,
		"resource_item_ids": resource_ids_result.values,
		"resource_type_allowlist": ["재료", "향"],
		"minimum_facility_nodes": minimum_facility_nodes
	})

func _profile_ok(profile: Dictionary) -> Dictionary:
	return {"ok": true, "profile": profile}

func _required_string_array_field(source: Dictionary, field: String, reason: String) -> Dictionary:
	var values := _string_array_field(source, field)
	if values.is_empty():
		return {"ok": false, "reason": reason, "field": field}
	return {"ok": true, "values": values}

func _string_array_field(source: Dictionary, field: String) -> Array:
	var ids := []
	var raw = source.get(field, [])
	if raw is Array:
		for value in raw:
			var id := String(value).strip_edges()
			if id != "" and not ids.has(id):
				ids.append(id)
	elif raw is String:
		for value in String(raw).split(",", false):
			var id := String(value).strip_edges()
			if id != "" and not ids.has(id):
				ids.append(id)
	return ids

func _validate_chunk_rule_ids(rule_ids: Array) -> Dictionary:
	for rule_id in rule_ids:
		if not _is_supported_chunk_rule_id(String(rule_id)):
			return {"ok": false, "reason": "unsupported_biome_generation_chunk_rule", "chunk_rule_id": String(rule_id)}
	return {"ok": true}

func _is_supported_chunk_rule_id(rule_id: String) -> bool:
	return rule_id in [
		CHUNK_RULE_COMMON_GRASS,
		CHUNK_RULE_COMMON_FIELD,
		CHUNK_RULE_COMMON_FOREST,
		CHUNK_RULE_COMMON_PATH,
		CHUNK_RULE_COMMON_WATER,
		CHUNK_RULE_COMMON_GROUND,
		CHUNK_RULE_MOUNTAIN_TRAIL,
		CHUNK_RULE_ROCK_FIELD,
		CHUNK_RULE_CLIFF_PASS,
		CHUNK_RULE_CONIFER_FOREST,
		CHUNK_RULE_VALLEY_WATER,
		CHUNK_RULE_CAVE_GROUND,
		CHUNK_RULE_DRY_DETOUR,
		CHUNK_RULE_ASYMMETRIC_RUIN,
		CHUNK_RULE_LONG_DETOUR,
		CHUNK_RULE_DEAD_END,
		CHUNK_RULE_DRY_RIVER_BYPASS,
		CHUNK_RULE_BATTLEFIELD_TRACE,
		CHUNK_RULE_SNOW_PATH_CROSSING,
		CHUNK_RULE_FROZEN_RIVER_EDGE,
		CHUNK_RULE_PINE_SILENCE,
		CHUNK_RULE_ICE_WALL_PASS,
		CHUNK_RULE_SAFE_CLEARING,
		CHUNK_RULE_SNOWY_MOUNTAIN_PATH,
		CHUNK_RULE_DENSE_JUNGLE_VINE_PATH,
		CHUNK_RULE_WIDE_RIVER_BANK,
		CHUNK_RULE_SWAMP_BOUNDARY,
		CHUNK_RULE_TEA_CULTIVATION,
		CHUNK_RULE_AGARWOOD_GROVE,
		CHUNK_RULE_RIVER_BYPASS
	]

func _terrain_roles_for_profile(terrain_ids: Array, walkability_rule_ids: Array) -> Dictionary:
	var path_terrain_id := _first_supported_terrain(terrain_ids, [
		TERRAIN_PATH,
		TERRAIN_MOUNTAIN_PATH,
		TERRAIN_WASTELAND_DETOUR_PATH,
		TERRAIN_SNOWFIELD_SNOW_PATH,
		TERRAIN_RAINFOREST_VINE_PATH
	])
	var water_terrain_id := _first_supported_terrain(terrain_ids, [
		TERRAIN_WATER,
		TERRAIN_MOUNTAIN_VALLEY_WATER,
		TERRAIN_WASTELAND_DRY_RIVER,
		TERRAIN_SNOWFIELD_ICE,
		TERRAIN_RAINFOREST_RIVER
	])
	var default_terrain_id := _first_supported_terrain(terrain_ids, [
		TERRAIN_GROUND,
		TERRAIN_MOUNTAIN_SLOPE,
		TERRAIN_WASTELAND_DRY_SOIL,
		TERRAIN_SNOWFIELD_SNOW,
		TERRAIN_RAINFOREST_RIVER_BANK,
		TERRAIN_GRASS
	])
	var shore_terrain_id := _first_supported_terrain(terrain_ids, [
		TERRAIN_GRASS,
		TERRAIN_MOUNTAIN_PATH,
		TERRAIN_WASTELAND_DETOUR_PATH,
		TERRAIN_SNOWFIELD_ICE_EDGE,
		TERRAIN_RAINFOREST_RIVER_BANK
	])
	var bridge_terrain_id := _first_supported_terrain(terrain_ids, [TERRAIN_BRIDGE])
	if bridge_terrain_id == "":
		bridge_terrain_id = shore_terrain_id if shore_terrain_id != "" else path_terrain_id
	var boundary_terrain_id := _first_supported_terrain(terrain_ids, [
		TERRAIN_MOUNTAIN_CLIFF,
		TERRAIN_WASTELAND_CAMP_TRACE,
		TERRAIN_SNOWFIELD_ICE_WALL,
		TERRAIN_RAINFOREST_JUNGLE
	])
	if boundary_terrain_id == "":
		boundary_terrain_id = TERRAIN_MOUNTAIN_CLIFF
	if default_terrain_id == "" or path_terrain_id == "" or water_terrain_id == "" or shore_terrain_id == "" or bridge_terrain_id == "":
		return {"ok": false, "reason": "invalid_biome_generation_terrain_roles"}
	if not _has_supported_walkability_rules(walkability_rule_ids):
		return {"ok": false, "reason": "invalid_biome_generation_walkability_rules"}
	return {
		"ok": true,
		"default_terrain_id": default_terrain_id,
		"path_terrain_id": path_terrain_id,
		"bridge_terrain_id": bridge_terrain_id,
		"water_terrain_id": water_terrain_id,
		"shore_terrain_id": shore_terrain_id,
		"boundary_terrain_id": boundary_terrain_id
	}

func _first_supported_terrain(terrain_ids: Array, candidates: Array) -> String:
	for candidate in candidates:
		if terrain_ids.has(String(candidate)):
			return String(candidate)
	return ""

func _has_supported_walkability_rules(rule_ids: Array) -> bool:
	for rule_id in rule_ids:
		if String(rule_id) in [
			"default_walkable",
			"water_blocked",
			"path_walkable",
			"bridge_walkable",
			"bridge_as_path",
			"shore_walkable",
			"dry_river_blocked",
			"ice_blocked",
			"bridge_ice_edge_walkable",
			"river_blocked",
			"swamp_blocked",
			"bridge_as_river_bank"
		]:
			return true
	return false

func _biome_resource_item_ids(profile: Dictionary, item_definitions: Array) -> Dictionary:
	var configured_ids: Array = profile.get("resource_item_ids", [])
	var allowed_types: Array = profile.get("resource_type_allowlist", ["재료", "향"])
	var known_ids := {}
	for item in item_definitions:
		if not allowed_types.has(String(item.get("type", ""))):
			continue
		var item_id := String(item.get("id", ""))
		if item_id != "":
			known_ids[item_id] = true
	var ids := []
	for item_id in configured_ids:
		if known_ids.has(String(item_id)):
			ids.append(String(item_id))
	if ids.size() != configured_ids.size():
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
