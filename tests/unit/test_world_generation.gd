extends RefCounted

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "catalog loads before world generation")

	var biome := catalog.find_by_id("biomes", "common_region")
	var generator := WorldGenerator.new()
	var options := {}
	var a := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var b := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var c := generator.generate(11038, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var d := generator.generate(11037, "notion-2026-09-02", biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)

	asserts.true_value(a.ok, "world generation succeeds")
	asserts.equal(_canonical_world(a), _canonical_world(b), "same seed and data version generate same canonical world")
	asserts.true_value(_canonical_world(a) != _canonical_world(c), "different seed changes generated canonical world")
	asserts.true_value(_canonical_world(a) != _canonical_world(d), "different data version changes generated canonical world")
	asserts.true_value(a.connectivity.valid, "required landmarks are connectivity-valid")
	asserts.true_value(a.resource_accessibility.valid, "resources have reachable access points")
	asserts.equal(a.data_version, "notion-2026-09-01", "world stores data version")
	asserts.true_value(a.chunks.size() > 0, "world records deterministic chunk composition")
	asserts.equal(a.min_resource_nodes, 9, "minimum resource nodes come from balance data")
	asserts.true_value(a.resource_nodes.size() >= a.min_resource_nodes, "world places minimum resources")
	asserts.equal(a.connectivity.required_landmark_ids.size(), 3, "entry, teleport, and core dungeon are required")
	asserts.equal(a.biome_generation_rule_id, "common_region", "common biome uses its own generation ruleset")
	asserts.true_value(a.has("world_data"), "generator exposes pure world data")
	asserts.true_value(a.has("renderer_input"), "generator exposes renderer input contract")
	asserts.equal(a.renderer_input.read_only, true, "renderer input is read-only projection")
	_assert_teleport_landmark_metadata(asserts, a.world_data, "common_region")
	_assert_renderer_source_paths_exist(asserts, a.renderer_input)
	_assert_resource_accessibility(asserts, a)
	_assert_mountain_generation(asserts, catalog, generator)
	_assert_wasteland_generation(asserts, catalog, generator)

	var progression_result: Dictionary = BiomeProgressionState.from_catalog(catalog, RunState.new())
	asserts.true_value(progression_result.ok, "progression state configures for renderer projection")
	if progression_result.ok:
		var projected := generator.generate(
			11037,
			catalog.data_version,
			biome,
			catalog.get_definitions("balance"),
			catalog.get_definitions("items"),
			{"progression_projection": progression_result.progression_state.to_projection()}
		)
		asserts.true_value(projected.ok, "world generation succeeds with progression projection")
		_assert_projected_teleport_state(asserts, projected.renderer_input, "common_region", BiomeProgressionState.TELEPORT_BROKEN)

	for seed in range(11000, 11125):
		var generated := generator.generate(seed, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
		var repeated := generator.generate(seed, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
		asserts.true_value(generated.ok, "seed %d generates successfully" % seed)
		asserts.equal(_canonical_world(generated), _canonical_world(repeated), "seed %d is canonically deterministic" % seed)
		asserts.true_value(generated.connectivity.valid, "seed %d connects all required landmarks" % seed)
		asserts.true_value(generated.resource_accessibility.valid, "seed %d keeps resources reachable" % seed)
		asserts.true_value(generated.retry_attempt <= generated.retry_limit, "seed %d stays inside retry limit" % seed)
		asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "seed %d places minimum resources" % seed)
		_assert_renderer_source_paths_exist(asserts, generated.renderer_input)
		_assert_resource_accessibility(asserts, generated)

	var impossible_options := {"min_resource_nodes": 5000, "retry_limit": 2, "max_resource_placement_attempts": 32}
	var failed := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), impossible_options)
	asserts.false_value(failed.ok, "generator reports failure after retry cap")
	asserts.equal(failed.retry_limit, 2, "failure records retry limit")
	asserts.equal(failed.failure_reason, "connectivity_or_resource_validation_failed", "failure reason is explicit")

	var missing_resource_biome := biome.duplicate(true)
	missing_resource_biome.erase("resources")
	var missing_resource := generator.generate(11037, catalog.data_version, missing_resource_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	asserts.false_value(missing_resource.ok, "biome without resource text fails")
	asserts.equal(missing_resource.failure_reason, "missing_biome_resources", "missing biome resources are explicit")

	var non_material_items := []
	for item in catalog.get_definitions("items"):
		var copied: Dictionary = item.duplicate(true)
		copied.type = "도구"
		non_material_items.append(copied)
	var missing_item := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), non_material_items, options)
	asserts.false_value(missing_item.ok, "biome resource text must resolve to material item definitions")
	asserts.equal(missing_item.failure_reason, "missing_biome_resource_item_definitions", "missing material item definitions are explicit")

	var balance_without_minimum := []
	for item in catalog.get_definitions("balance"):
		if item.get("id", "") != "biome_min_resource_nodes":
			balance_without_minimum.append(item)
	var missing_minimum := generator.generate(11037, catalog.data_version, biome, balance_without_minimum, catalog.get_definitions("items"))
	asserts.false_value(missing_minimum.ok, "minimum resource count is not hidden behind production fallback")
	asserts.equal(missing_minimum.failure_reason, "missing_min_resource_nodes_config", "missing minimum resource count is explicit")

	var unknown_biome := biome.duplicate(true)
	unknown_biome.id = "unimplemented_region"
	var unsupported := generator.generate(11037, catalog.data_version, unknown_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(unsupported.ok, "unknown biome rules are not silently treated as common terrain")
	asserts.equal(unsupported.failure_reason, "unsupported_biome_generation_rules", "unsupported biome rules fail explicitly")

func _assert_mountain_generation(asserts, catalog, generator: WorldGenerator) -> void:
	var mountain: Dictionary = catalog.find_by_id("biomes", "mountain_region")
	asserts.false_value(mountain.is_empty(), "mountain biome definition exists")
	var generated := generator.generate(22033, catalog.data_version, mountain, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var repeated := generator.generate(22033, catalog.data_version, mountain, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var alternate := generator.generate(22034, catalog.data_version, mountain, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.true_value(generated.ok, "mountain world generation succeeds")
	asserts.equal(_canonical_world(generated), _canonical_world(repeated), "mountain generation is deterministic for the same seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(alternate), "mountain generation varies by seed")
	asserts.equal(generated.biome_generation_rule_id, "mountain_region", "mountain biome records its generation ruleset")
	asserts.equal(generated.biome_progression_order, 2, "mountain generation preserves data-driven progression order")
	asserts.true_value(generated.connectivity.valid, "mountain landmarks are connectivity-valid")
	asserts.true_value(generated.facility_accessibility.valid, "mountain facilities have reachable access points")
	asserts.true_value(generated.resource_accessibility.valid, "mountain resources have reachable access points")
	asserts.equal(generated.facility_nodes.size(), 4, "mountain places every canonical facility term")
	asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "mountain places minimum resources")
	_assert_teleport_landmark_metadata(asserts, generated.world_data, "mountain_region")
	_assert_resource_accessibility(asserts, generated)
	_assert_facility_accessibility(asserts, generated)
	_assert_renderer_source_paths_exist(asserts, generated.renderer_input)
	_assert_mountain_terrain_profile(asserts, generated.world_data)
	_assert_mountain_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terrain_terms(asserts, generated.landmarks)
	_assert_resource_ids_resolve_to_mountain_materials(asserts, generated.resource_nodes, mountain, catalog.get_definitions("items"))

	for seed in range(22000, 22020):
		var sampled := generator.generate(seed, catalog.data_version, mountain, catalog.get_definitions("balance"), catalog.get_definitions("items"))
		asserts.true_value(sampled.ok, "mountain seed %d generates successfully" % seed)
		asserts.equal(_canonical_world(sampled), _canonical_world(generator.generate(seed, catalog.data_version, mountain, catalog.get_definitions("balance"), catalog.get_definitions("items"))), "mountain seed %d remains deterministic" % seed)
		asserts.true_value(sampled.connectivity.valid, "mountain seed %d keeps landmarks connected" % seed)
		asserts.true_value(sampled.facility_accessibility.valid, "mountain seed %d keeps facilities accessible" % seed)
		asserts.true_value(sampled.resource_accessibility.valid, "mountain seed %d keeps resources accessible" % seed)

	var missing_term_biome: Dictionary = mountain.duplicate(true)
	missing_term_biome.terrain = "산길, 절벽, 바위지대, 계곡, 폭포, 침엽수림"
	var missing_term := generator.generate(22033, catalog.data_version, missing_term_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_term.ok, "mountain rules require every canonical terrain term")
	asserts.equal(missing_term.failure_reason, "missing_biome_generation_terms", "missing mountain terrain term fails explicitly")

	var missing_facility_biome: Dictionary = mountain.duplicate(true)
	missing_facility_biome.facilities = "광산, 산사, 폐광"
	var missing_facility := generator.generate(22033, catalog.data_version, missing_facility_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_facility.ok, "mountain rules require every canonical facility term")
	asserts.equal(missing_facility.failure_reason, "missing_biome_facility_terms", "missing mountain facility term fails explicitly")

func _assert_wasteland_generation(asserts, catalog, generator: WorldGenerator) -> void:
	var wasteland: Dictionary = catalog.find_by_id("biomes", "wasteland")
	asserts.false_value(wasteland.is_empty(), "wasteland biome definition exists")
	var generated := generator.generate(34033, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var repeated := generator.generate(34033, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var alternate := generator.generate(34034, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.true_value(generated.ok, "wasteland world generation succeeds")
	asserts.equal(_canonical_world(generated), _canonical_world(repeated), "wasteland generation is deterministic for the same seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(alternate), "wasteland generation varies by seed")
	asserts.equal(generated.biome_generation_rule_id, "wasteland", "wasteland records its generation ruleset")
	asserts.equal(generated.biome_progression_order, 3, "wasteland generation preserves data-driven progression order")
	asserts.true_value(generated.connectivity.valid, "wasteland landmarks are connectivity-valid")
	asserts.true_value(generated.facility_accessibility.valid, "wasteland facilities have reachable access points")
	asserts.true_value(generated.resource_accessibility.valid, "wasteland resources have reachable access points")
	asserts.equal(generated.facility_nodes.size(), 4, "wasteland places every canonical facility term")
	asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "wasteland places minimum resources")
	_assert_teleport_landmark_metadata(asserts, generated.world_data, "wasteland")
	_assert_resource_accessibility(asserts, generated)
	_assert_facility_accessibility_for_terms(asserts, generated, ["폐촌", "버려진 초소", "무너진 다실", "전쟁터 흔적"])
	_assert_renderer_source_paths_exist(asserts, generated.renderer_input)
	_assert_wasteland_terrain_profile(asserts, generated.world_data)
	_assert_wasteland_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terms(asserts, generated.landmarks, ["마른 흙", "갈라진 땅", "죽은 나무", "폐허", "말라붙은 하천", "군영 흔적"])
	_assert_resource_ids_resolve_to_biome_materials(asserts, generated.resource_nodes, wasteland, catalog.get_definitions("items"))
	_assert_wasteland_chunk_features(asserts, generated.chunks)

	for seed in range(34000, 34025):
		var sampled := generator.generate(seed, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"))
		asserts.true_value(sampled.ok, "wasteland seed %d generates successfully" % seed)
		asserts.equal(_canonical_world(sampled), _canonical_world(generator.generate(seed, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"))), "wasteland seed %d remains deterministic" % seed)
		asserts.true_value(sampled.connectivity.valid, "wasteland seed %d keeps landmarks connected" % seed)
		asserts.true_value(sampled.facility_accessibility.valid, "wasteland seed %d keeps facilities accessible" % seed)
		asserts.true_value(sampled.resource_accessibility.valid, "wasteland seed %d keeps resources accessible" % seed)
		_assert_wasteland_chunk_features(asserts, sampled.chunks)

	var missing_term_biome: Dictionary = wasteland.duplicate(true)
	missing_term_biome.terrain = "마른 흙, 갈라진 땅, 죽은 나무, 폐허, 말라붙은 하천"
	var missing_term := generator.generate(34033, catalog.data_version, missing_term_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_term.ok, "wasteland rules require every canonical terrain term")
	asserts.equal(missing_term.failure_reason, "missing_biome_generation_terms", "missing wasteland terrain term fails explicitly")

	var missing_facility_biome: Dictionary = wasteland.duplicate(true)
	missing_facility_biome.facilities = "폐촌, 버려진 초소, 무너진 다실"
	var missing_facility := generator.generate(34033, catalog.data_version, missing_facility_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_facility.ok, "wasteland rules require every canonical facility term")
	asserts.equal(missing_facility.failure_reason, "missing_biome_facility_terms", "missing wasteland facility term fails explicitly")

func _assert_resource_accessibility(asserts, world: Dictionary) -> void:
	var validator := ConnectivityValidator.new()
	var access_points := []
	var interactable_owner_ids := _interactable_owner_ids(world.renderer_input)
	var entity_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_ENTITIES)
	var interactable_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_INTERACTABLES)
	for node in world.resource_nodes:
		access_points.append(node.access_position)
		asserts.true_value(bool(node.placement_was_entry_reachable), "%s was placed on an entry-reachable cell" % node.id)
		asserts.true_value(bool(node.interactable), "%s is marked interactable" % node.id)
		asserts.true_value(interactable_owner_ids.has(node.id), "%s appears in renderer interactables" % node.id)
		asserts.equal(_manhattan_distance(node.position, node.access_position), 1, "%s has adjacent access cell" % node.id)
		if node.has("source_id"):
			asserts.equal(entity_sources.get(node.id, ""), node.source_id, "%s entity renderer source matches resource source" % node.id)
			asserts.equal(interactable_sources.get(node.id, ""), node.source_id, "%s interactable renderer source matches resource source" % node.id)
			asserts.true_value(FileAccess.file_exists("res://%s" % String(node.source_id)), "%s resource source path exists" % node.id)
	var access_validation := validator.validate_access_points(world.world_data, access_points)
	asserts.true_value(access_validation.valid, "all resource access points are entry-reachable")

func _assert_facility_accessibility(asserts, world: Dictionary) -> void:
	_assert_facility_accessibility_for_terms(asserts, world, ["광산", "산사", "폐광", "산중 찻집"])

func _assert_facility_accessibility_for_terms(asserts, world: Dictionary, expected_terms_list: Array) -> void:
	var validator := ConnectivityValidator.new()
	var access_points := []
	var interactable_owner_ids := _interactable_owner_ids(world.renderer_input)
	var facility_owner_ids := _layer_owner_ids(world.renderer_input, WorldData.LAYER_FACILITIES)
	var expected_terms := {}
	for term in expected_terms_list:
		expected_terms[String(term)] = true
	var seen_terms := {}
	for node in world.facility_nodes:
		access_points.append(node.access_position)
		seen_terms[String(node.facility_term)] = true
		asserts.true_value(bool(node.placement_was_entry_reachable), "%s facility has a reachable access cell" % node.id)
		asserts.true_value(bool(node.interactable), "%s facility is marked interactable" % node.id)
		asserts.true_value(interactable_owner_ids.has(node.id), "%s appears in renderer interactables" % node.id)
		asserts.true_value(facility_owner_ids.has(node.id), "%s appears in renderer facilities" % node.id)
		asserts.equal(_manhattan_distance(node.position, node.access_position), 1, "%s has adjacent facility access cell" % node.id)
		asserts.true_value(FileAccess.file_exists("res://%s" % String(node.source_id)), "%s source path exists" % node.id)
	for term in expected_terms.keys():
		asserts.true_value(seen_terms.has(term), "%s facility term is placed" % term)
	var access_validation := validator.validate_access_points(world.world_data, access_points)
	asserts.true_value(access_validation.valid, "all facility access points are entry-reachable")

func _assert_teleport_landmark_metadata(asserts, world_data: Dictionary, biome_id: String) -> void:
	var teleports := []
	for landmark in world_data.required_landmarks:
		if String(landmark.get("kind", "")) == WorldData.LANDMARK_TELEPORT_ZONE:
			teleports.append(landmark)
	asserts.equal(teleports.size(), 1, "world data records generated teleport landmark")
	if not teleports.is_empty():
		asserts.equal(teleports[0].metadata.teleport_biome_id, biome_id, "teleport landmark metadata uses stable biome id")

func _assert_projected_teleport_state(asserts, renderer_input: Dictionary, biome_id: String, expected_state: String) -> void:
	var teleports := []
	for landmark in renderer_input.required_landmarks:
		if String(landmark.get("kind", "")) == WorldData.LANDMARK_TELEPORT_ZONE:
			teleports.append(landmark)
	asserts.equal(teleports.size(), 1, "renderer projection includes generated teleport landmark")
	if not teleports.is_empty():
		asserts.equal(teleports[0].teleport_biome_id, biome_id, "renderer projection exposes stable teleport biome id")
		asserts.equal(teleports[0].teleport_state, expected_state, "renderer projection uses progression teleport state")

func _interactable_owner_ids(renderer_input: Dictionary) -> Dictionary:
	return _layer_owner_ids(renderer_input, WorldData.LAYER_INTERACTABLES)

func _layer_owner_ids(renderer_input: Dictionary, layer_id: String) -> Dictionary:
	var owner_ids := {}
	for layer in renderer_input.layers:
		if String(layer.id) != layer_id:
			continue
		for cell in layer.cells:
			owner_ids[cell.owner_id] = true
	return owner_ids

func _layer_source_ids_by_owner(renderer_input: Dictionary, layer_id: String) -> Dictionary:
	var source_ids := {}
	for layer in renderer_input.layers:
		if String(layer.id) != layer_id:
			continue
		for cell in layer.cells:
			var owner_id := String(cell.get("owner_id", ""))
			var source_id := String(cell.get("source_id", ""))
			if not owner_id.is_empty() and not source_id.is_empty():
				source_ids[owner_id] = source_id
	return source_ids

func _assert_renderer_source_paths_exist(asserts, renderer_input: Dictionary) -> void:
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			if not cell.has("source_id"):
				continue
			var source_id := String(cell.source_id)
			if not source_id.begins_with("assets/"):
				continue
			seen[source_id] = true

	for source_id in seen.keys():
		var source_path := "res://%s" % source_id
		asserts.true_value(FileAccess.file_exists(source_path), "renderer source path exists: %s" % source_id)

func _assert_mountain_terrain_profile(asserts, world_data: Dictionary) -> void:
	var required_walkable := {
		"mountain_slope": true,
		"mountain_path": true,
		"mountain_cave_ground": true
	}
	var required_blocked := {
		"mountain_cliff": true,
		"mountain_rock": true,
		"mountain_conifer_forest": true,
		"mountain_valley_water": true
	}
	var terrain_counts := {}
	var blocked_counts := {}
	for cell in world_data.cells:
		var terrain: Dictionary = cell.layers.terrain
		var terrain_id := String(terrain.id)
		terrain_counts[terrain_id] = int(terrain_counts.get(terrain_id, 0)) + 1
		if not bool(terrain.walkable):
			blocked_counts[terrain_id] = int(blocked_counts.get(terrain_id, 0)) + 1
	for terrain_id in required_walkable.keys():
		asserts.true_value(int(terrain_counts.get(terrain_id, 0)) > 0, "mountain includes walkable terrain: %s" % terrain_id)
	for terrain_id in required_blocked.keys():
		asserts.true_value(int(blocked_counts.get(terrain_id, 0)) > 0, "mountain includes blocked terrain: %s" % terrain_id)

func _assert_mountain_renderer_sources(asserts, renderer_input: Dictionary) -> void:
	var expected_sources := {
		"assets/sprites/objects/natural-props/flat_rock_32x32.png": true,
		"assets/sprites/objects/natural-props/mossy_rock_32x32.png": true,
		"assets/sprites/objects/natural-props/mountain_rock_04_32x32.png": true,
		"assets/sprites/objects/natural-props/mountain_rock_01_32x32.png": true,
		"assets/sprites/objects/natural-props/pine_tree_small_32x32.png": true,
		"assets/sprites/objects/mining/rock_cave_entrance_1x2_64x32.png": true,
		"assets/sprites/objects/structures/shrine_torii_gate_2x2_64x64.png": true,
		"assets/sprites/objects/mining/timber_support_1x2_32x64.png": true,
		"assets/sprites/objects/crafting/tea_table_2x2_64x64.png": true
	}
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			var source_id := String(cell.get("source_id", ""))
			if expected_sources.has(source_id):
				seen[source_id] = true
	for source_id in expected_sources.keys():
		asserts.true_value(seen.has(source_id), "mountain renderer uses promoted source: %s" % source_id)

func _assert_wasteland_terrain_profile(asserts, world_data: Dictionary) -> void:
	var required_walkable := {
		"wasteland_dry_soil": true,
		"wasteland_cracked_ground": true,
		"wasteland_detour_path": true
	}
	var required_blocked := {
		"wasteland_ruin": true,
		"wasteland_dead_tree": true,
		"wasteland_dry_river": true,
		"wasteland_camp_trace": true
	}
	var terrain_counts := {}
	var blocked_counts := {}
	for cell in world_data.cells:
		var terrain: Dictionary = cell.layers.terrain
		var terrain_id := String(terrain.id)
		terrain_counts[terrain_id] = int(terrain_counts.get(terrain_id, 0)) + 1
		if not bool(terrain.walkable):
			blocked_counts[terrain_id] = int(blocked_counts.get(terrain_id, 0)) + 1
	for terrain_id in required_walkable.keys():
		asserts.true_value(int(terrain_counts.get(terrain_id, 0)) > 0, "wasteland includes walkable terrain: %s" % terrain_id)
	for terrain_id in required_blocked.keys():
		asserts.true_value(int(blocked_counts.get(terrain_id, 0)) > 0, "wasteland includes blocked terrain: %s" % terrain_id)

func _assert_wasteland_renderer_sources(asserts, renderer_input: Dictionary) -> void:
	var expected_sources := {
		"assets/tiles/terrain/desert/dry_soil_01_32x32.png": true,
		"assets/tiles/terrain/desert/cracked_clay_32x32.png": true,
		"assets/tiles/terrain/desert/sand_ripple_01_32x32.png": true,
		"assets/sprites/objects/structures/ruined_wall_1x2_64x32.png": true,
		"assets/sprites/objects/natural-props/dead_tree_small_32x32.png": true,
		"assets/tiles/terrain/desert/dry_scrub_patch_32x32.png": true,
		"assets/tiles/terrain/desert/bone_scatter_32x32.png": true,
		"assets/sprites/objects/mining/iron_ore_32x32.png": true,
		"assets/sprites/objects/structures/small_storage_shed_64x64.png": true,
		"assets/sprites/objects/crafting/tea_table_2x2_64x64.png": true
	}
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			var source_id := String(cell.get("source_id", ""))
			if expected_sources.has(source_id):
				seen[source_id] = true
	for source_id in expected_sources.keys():
		asserts.true_value(seen.has(source_id), "wasteland renderer uses promoted source: %s" % source_id)

func _assert_landmark_terrain_terms(asserts, landmarks: Array) -> void:
	_assert_landmark_terms(asserts, landmarks, ["산길", "절벽", "바위지대", "계곡", "폭포", "침엽수림", "동굴"])

func _assert_landmark_terms(asserts, landmarks: Array, required_terms: Array) -> void:
	for landmark in landmarks:
		var metadata: Dictionary = landmark.get("metadata", {})
		var terms: Array = metadata.get("terrain_terms", [])
		for term in required_terms:
			asserts.true_value(terms.has(term), "%s landmark carries terrain term: %s" % [landmark.get("id", ""), term])

func _assert_resource_ids_resolve_to_mountain_materials(asserts, resource_nodes: Array, biome: Dictionary, item_definitions: Array) -> void:
	_assert_resource_ids_resolve_to_biome_materials(asserts, resource_nodes, biome, item_definitions)

func _assert_resource_ids_resolve_to_biome_materials(asserts, resource_nodes: Array, biome: Dictionary, item_definitions: Array) -> void:
	var biome_resource_text := String(biome.get("resources", ""))
	var material_ids := {}
	for item in item_definitions:
		if String(item.get("type", "")) == "재료" and biome_resource_text.contains(String(item.get("name", ""))):
			material_ids[String(item.get("id", ""))] = true
	for node in resource_nodes:
		asserts.true_value(material_ids.has(String(node.resource_id)), "%s uses an existing biome material item id" % node.id)

func _assert_wasteland_chunk_features(asserts, chunks: Array) -> void:
	var feature_counts := {}
	for chunk in chunks:
		var feature := String(chunk.get("feature", ""))
		feature_counts[feature] = int(feature_counts.get(feature, 0)) + 1
	asserts.true_value(int(feature_counts.get("asymmetric_ruin", 0)) > 0, "wasteland includes asymmetric ruin chunks")
	asserts.true_value(int(feature_counts.get("long_detour", 0)) > 0 or int(feature_counts.get("dry_detour", 0)) > 0 or int(feature_counts.get("dry_river_bypass", 0)) > 0, "wasteland includes bypass/detour chunks")
	asserts.true_value(int(feature_counts.get("dead_end", 0)) > 0, "wasteland includes dead-end chunks")
	asserts.true_value(int(feature_counts.get("battlefield_trace", 0)) > 0, "wasteland includes battlefield trace chunks")

func _manhattan_distance(a: Dictionary, b: Dictionary) -> int:
	return abs(int(a.x) - int(b.x)) + abs(int(a.y) - int(b.y))

func _canonical_world(world: Dictionary) -> Dictionary:
	var canonical := world.duplicate(true)
	canonical.erase("retry_attempt")
	canonical.erase("retry_limit")
	canonical.erase("seed")
	canonical.erase("data_version")
	return canonical
