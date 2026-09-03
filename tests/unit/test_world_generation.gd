extends RefCounted

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
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
	_assert_tree_obstacles_render_over_base(asserts, a, WorldGenerator.TERRAIN_FOREST, WorldGenerator.RENDER_GRASS, WorldGenerator.RENDER_FOREST_TREE, "common forest")
	_assert_resource_accessibility(asserts, a)
	_assert_common_templates(asserts, a)
	_assert_continuous_water_stroke(asserts, a)
	_assert_resources_near_templates(asserts, a)
	_assert_mountain_generation(asserts, catalog, generator)
	_assert_wasteland_generation(asserts, catalog, generator)
	_assert_snowfield_generation(asserts, catalog, generator)
	_assert_rainforest_generation(asserts, catalog, generator)

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
		_assert_common_templates(asserts, generated)
		_assert_continuous_water_stroke(asserts, generated)
		_assert_resources_near_templates(asserts, generated)

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
	_assert_tree_obstacles_render_over_base(asserts, generated, WorldGenerator.TERRAIN_MOUNTAIN_CONIFER, WorldGenerator.RENDER_MOUNTAIN_SLOPE, WorldGenerator.RENDER_MOUNTAIN_CONIFER, "mountain conifer")
	_assert_mountain_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terrain_terms(asserts, generated.landmarks)
	_assert_resource_ids_resolve_to_mountain_materials(asserts, generated.resource_nodes, mountain, catalog.get_definitions("items"))
	_assert_common_templates(asserts, generated)
	_assert_continuous_water_stroke(asserts, generated)
	_assert_resources_near_templates(asserts, generated)

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
	_assert_tree_obstacles_render_over_base(asserts, generated, WorldGenerator.TERRAIN_WASTELAND_DEAD_TREE, WorldGenerator.RENDER_WASTELAND_DRY_SOIL, WorldGenerator.RENDER_WASTELAND_DEAD_TREE, "wasteland dead tree")
	_assert_wasteland_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terms(asserts, generated.landmarks, ["마른 흙", "갈라진 땅", "죽은 나무", "폐허", "말라붙은 하천", "군영 흔적"])
	_assert_resource_ids_resolve_to_biome_materials(asserts, generated.resource_nodes, wasteland, catalog.get_definitions("items"))
	_assert_wasteland_chunk_features(asserts, generated.chunks)
	_assert_common_templates(asserts, generated)
	_assert_continuous_water_stroke(asserts, generated)
	_assert_resources_near_templates(asserts, generated)

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

func _assert_snowfield_generation(asserts, catalog, generator: WorldGenerator) -> void:
	var snowfield: Dictionary = catalog.find_by_id("biomes", "snowfield")
	asserts.false_value(snowfield.is_empty(), "snowfield biome definition exists")
	var generated := generator.generate(35033, catalog.data_version, snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var repeated := generator.generate(35033, catalog.data_version, snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var alternate := generator.generate(35034, catalog.data_version, snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var next_version := generator.generate(35033, "notion-2026-09-02", snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.true_value(generated.ok, "snowfield world generation succeeds")
	asserts.equal(_canonical_world(generated), _canonical_world(repeated), "snowfield generation is deterministic for the same seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(alternate), "snowfield generation varies by seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(next_version), "snowfield generation varies by data version")
	asserts.equal(generated.biome_generation_rule_id, "snowfield", "snowfield records its generation ruleset")
	asserts.equal(generated.biome_progression_order, 4, "snowfield generation preserves data-driven progression order")
	asserts.true_value(generated.connectivity.valid, "snowfield landmarks are connectivity-valid")
	asserts.true_value(generated.facility_accessibility.valid, "snowfield facilities have reachable access points")
	asserts.true_value(generated.resource_accessibility.valid, "snowfield resources have reachable access points")
	asserts.equal(generated.facility_nodes.size(), 4, "snowfield places every canonical safe point/facility term")
	asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "snowfield places minimum resources")
	_assert_teleport_landmark_metadata(asserts, generated.world_data, "snowfield")
	_assert_resource_accessibility(asserts, generated)
	_assert_facility_accessibility_for_terms(asserts, generated, ["산장", "온천", "설원 사당", "얼어붙은 광산"])
	_assert_renderer_source_paths_exist(asserts, generated.renderer_input)
	_assert_snowfield_terrain_profile(asserts, generated.world_data)
	_assert_tree_obstacles_render_over_base(asserts, generated, WorldGenerator.TERRAIN_SNOWFIELD_PINE, WorldGenerator.RENDER_SNOWFIELD_SNOW, WorldGenerator.RENDER_SNOWFIELD_PINE, "snowfield pine")
	_assert_snowfield_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terms(asserts, generated.landmarks, ["눈밭", "얼어붙은 강", "침엽수", "빙벽", "눈 덮인 산길"])
	_assert_resource_ids_resolve_to_biome_materials(asserts, generated.resource_nodes, snowfield, catalog.get_definitions("items"))
	_assert_snowfield_chunk_features(asserts, generated.chunks)
	_assert_no_temperature_state(asserts, generated)
	_assert_common_templates(asserts, generated)
	_assert_continuous_water_stroke(asserts, generated)
	_assert_resources_near_templates(asserts, generated)

	for seed in range(35000, 35025):
		var sampled := generator.generate(seed, catalog.data_version, snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))
		asserts.true_value(sampled.ok, "snowfield seed %d generates successfully" % seed)
		asserts.equal(_canonical_world(sampled), _canonical_world(generator.generate(seed, catalog.data_version, snowfield, catalog.get_definitions("balance"), catalog.get_definitions("items"))), "snowfield seed %d remains deterministic" % seed)
		asserts.true_value(sampled.connectivity.valid, "snowfield seed %d keeps landmarks connected" % seed)
		asserts.true_value(sampled.facility_accessibility.valid, "snowfield seed %d keeps facilities accessible" % seed)
		asserts.true_value(sampled.resource_accessibility.valid, "snowfield seed %d keeps resources accessible" % seed)
		_assert_snowfield_chunk_features(asserts, sampled.chunks)

	var missing_term_biome: Dictionary = snowfield.duplicate(true)
	missing_term_biome.terrain = "눈밭, 얼어붙은 강, 침엽수, 빙벽"
	var missing_term := generator.generate(35033, catalog.data_version, missing_term_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_term.ok, "snowfield rules require every canonical terrain term")
	asserts.equal(missing_term.failure_reason, "missing_biome_generation_terms", "missing snowfield terrain term fails explicitly")

	var missing_facility_biome: Dictionary = snowfield.duplicate(true)
	missing_facility_biome.facilities = "산장, 온천, 설원 사당"
	var missing_facility := generator.generate(35033, catalog.data_version, missing_facility_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_facility.ok, "snowfield rules require every canonical facility term")
	asserts.equal(missing_facility.failure_reason, "missing_biome_facility_terms", "missing snowfield facility term fails explicitly")

func _assert_rainforest_generation(asserts, catalog, generator: WorldGenerator) -> void:
	var rainforest: Dictionary = catalog.find_by_id("biomes", "rainforest")
	asserts.false_value(rainforest.is_empty(), "rainforest biome definition exists")
	var generated := generator.generate(36033, catalog.data_version, rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var repeated := generator.generate(36033, catalog.data_version, rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var alternate := generator.generate(36034, catalog.data_version, rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var next_version := generator.generate(36033, "notion-2026-09-02", rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.true_value(generated.ok, "rainforest world generation succeeds")
	asserts.equal(_canonical_world(generated), _canonical_world(repeated), "rainforest generation is deterministic for the same seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(alternate), "rainforest generation varies by seed")
	asserts.true_value(_canonical_world(generated) != _canonical_world(next_version), "rainforest generation varies by data version")
	asserts.equal(generated.biome_generation_rule_id, "rainforest", "rainforest records its generation ruleset")
	asserts.equal(generated.biome_progression_order, 5, "rainforest generation preserves data-driven progression order")
	asserts.true_value(generated.connectivity.valid, "rainforest landmarks are connectivity-valid")
	asserts.true_value(generated.facility_accessibility.valid, "rainforest facilities have reachable access points")
	asserts.true_value(generated.resource_accessibility.valid, "rainforest resources have reachable access points")
	asserts.equal(generated.facility_nodes.size(), 4, "rainforest places every canonical facility term")
	asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "rainforest places minimum resources")
	_assert_teleport_landmark_metadata(asserts, generated.world_data, "rainforest")
	_assert_resource_accessibility(asserts, generated)
	_assert_facility_accessibility_for_terms(asserts, generated, ["차 재배지", "강변 취락", "숲속 다실", "향 문화 공간"])
	_assert_renderer_source_paths_exist(asserts, generated.renderer_input)
	_assert_rainforest_terrain_profile(asserts, generated.world_data)
	_assert_tree_obstacles_render_over_base(asserts, generated, WorldGenerator.TERRAIN_RAINFOREST_AGARWOOD, WorldGenerator.RENDER_RAINFOREST_RIVER_BANK, WorldGenerator.RENDER_RAINFOREST_AGARWOOD, "rainforest agarwood")
	_assert_rainforest_renderer_sources(asserts, generated.renderer_input)
	_assert_landmark_terms(asserts, generated.landmarks, ["밀림", "습지", "넓은 강", "덩굴 통로", "차 재배지", "향목 숲"])
	_assert_resource_ids_resolve_to_biome_materials(asserts, generated.resource_nodes, rainforest, catalog.get_definitions("items"))
	_assert_rainforest_rare_resource_ids(asserts, generated.resource_nodes)
	_assert_rainforest_chunk_features(asserts, generated.chunks)
	_assert_no_forbidden_survival_state(asserts, generated)
	_assert_common_templates(asserts, generated)
	_assert_continuous_water_stroke(asserts, generated)
	_assert_resources_near_templates(asserts, generated)

	for seed in range(36000, 36025):
		var sampled := generator.generate(seed, catalog.data_version, rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))
		asserts.true_value(sampled.ok, "rainforest seed %d generates successfully" % seed)
		asserts.equal(_canonical_world(sampled), _canonical_world(generator.generate(seed, catalog.data_version, rainforest, catalog.get_definitions("balance"), catalog.get_definitions("items"))), "rainforest seed %d remains deterministic" % seed)
		asserts.true_value(sampled.connectivity.valid, "rainforest seed %d keeps landmarks connected" % seed)
		asserts.true_value(sampled.facility_accessibility.valid, "rainforest seed %d keeps facilities accessible" % seed)
		asserts.true_value(sampled.resource_accessibility.valid, "rainforest seed %d keeps resources accessible" % seed)
		_assert_rainforest_chunk_features(asserts, sampled.chunks)

	var missing_term_biome: Dictionary = rainforest.duplicate(true)
	missing_term_biome.terrain = "밀림, 습지, 넓은 강, 덩굴 통로, 차 재배지"
	var missing_term := generator.generate(36033, catalog.data_version, missing_term_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_term.ok, "rainforest rules require every canonical terrain term")
	asserts.equal(missing_term.failure_reason, "missing_biome_generation_terms", "missing rainforest terrain term fails explicitly")

	var missing_facility_biome: Dictionary = rainforest.duplicate(true)
	missing_facility_biome.facilities = "차 재배지, 강변 취락, 숲속 다실"
	var missing_facility := generator.generate(36033, catalog.data_version, missing_facility_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	asserts.false_value(missing_facility.ok, "rainforest rules require every canonical facility term")
	asserts.equal(missing_facility.failure_reason, "missing_biome_facility_terms", "missing rainforest facility term fails explicitly")

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
			_assert_asset_reference_exists(asserts, String(node.source_id), "%s resource source exists" % node.id)
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
		_assert_asset_reference_exists(asserts, String(node.source_id), "%s source exists" % node.id)
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

func _layer_source_ids_by_position(renderer_input: Dictionary, layer_id: String) -> Dictionary:
	var source_ids := {}
	for layer in renderer_input.layers:
		if String(layer.id) != layer_id:
			continue
		for cell in layer.cells:
			var position := _vector_from_dictionary(cell.get("position", {}))
			var source_id := String(cell.get("source_id", ""))
			if not source_id.is_empty():
				source_ids[_key(position)] = source_id
	return source_ids

func _assert_renderer_source_paths_exist(asserts, renderer_input: Dictionary) -> void:
	var asset_catalog := AssetCatalog.new()
	var load_result: Dictionary = asset_catalog.load_manifest()
	asserts.true_value(load_result.ok, "asset manifest loads for renderer source references")
	if not load_result.ok:
		return
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			if not cell.has("source_id"):
				continue
			var source_id := String(cell.source_id)
			seen[source_id] = true

	for source_id in seen.keys():
		asserts.true_value(not asset_catalog.id_for_reference(source_id).is_empty(), "renderer source reference uses manifest ID: %s" % source_id)
		asserts.true_value(not asset_catalog.path_for_reference(source_id).is_empty(), "renderer source reference path exists: %s" % source_id)

func _assert_tree_obstacles_render_over_base(asserts, world: Dictionary, tree_terrain_id: String, base_render_id: String, tree_source_id: String, label: String) -> void:
	var tree_owner_positions := {}
	var interactable_owner_ids := _interactable_owner_ids(world.renderer_input)
	for cell in world.world_data.cells:
		var terrain: Dictionary = cell.layers.terrain
		if String(terrain.id) != tree_terrain_id:
			continue
		asserts.equal(String(terrain.render_id), base_render_id, "%s terrain renders the base tile under the tree object" % label)
		asserts.true_value(bool(terrain.walkable), "%s terrain keeps base walkability and delegates blocking to the tree object" % label)
		var owners: Array = cell.layers.entities
		asserts.equal(owners.size(), 1, "%s terrain cell owns one blocking tree object" % label)
		if not owners.is_empty():
			var owner_id := String(owners[0])
			tree_owner_positions[owner_id] = _vector_from_dictionary(cell.position)
			asserts.true_value(owner_id.begins_with("terrain_tree_"), "%s tree object uses generated terrain owner id" % label)
			asserts.false_value(interactable_owner_ids.has(owner_id), "%s tree object is not registered as an interactable resource" % label)
	asserts.true_value(not tree_owner_positions.is_empty(), "%s biome includes tree object obstacles" % label)
	var terrain_sources := _layer_source_ids_by_position(world.renderer_input, WorldData.LAYER_TERRAIN)
	var entity_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_ENTITIES)
	for owner_id in tree_owner_positions.keys():
		var position: Vector2i = tree_owner_positions[owner_id]
		asserts.equal(String(terrain_sources.get(_key(position), "")), base_render_id, "%s renderer keeps the base tile behind tree %s" % [label, owner_id])
		asserts.equal(String(entity_sources.get(owner_id, "")), tree_source_id, "%s renderer uses the biome tree object source for %s" % [label, owner_id])
	_assert_asset_reference_exists(asserts, tree_source_id, "%s tree object source exists" % label)

func _assert_common_templates(asserts, world: Dictionary) -> void:
	asserts.true_value(world.has("templates"), "world records common map templates")
	var ids := {}
	for template in world.get("templates", []):
		ids[String(template.get("id", ""))] = true
	for template_id in [
		WorldGenerator.TEMPLATE_PATH_SPINE,
		WorldGenerator.TEMPLATE_WATER_STROKE,
		WorldGenerator.TEMPLATE_RESOURCE_CLUSTER
	]:
		asserts.true_value(ids.has(template_id), "world applies common template: %s" % template_id)

func _assert_continuous_water_stroke(asserts, world: Dictionary) -> void:
	var water_template := _template_by_id(world, WorldGenerator.TEMPLATE_WATER_STROKE)
	asserts.false_value(water_template.is_empty(), "water stroke template is recorded")
	var water_cells: Array = water_template.get("cells", [])
	asserts.true_value(water_cells.size() >= WorldGenerator.MAP_HEIGHT - 2, "water stroke spans the map height")
	asserts.true_value(bool(water_template.get("crosses_chunk_boundary", false)), "water stroke crosses chunk boundaries")
	var cell_index := _world_cell_index(world.world_data)
	var bridge_count := 0
	var water_count := 0
	for index in range(water_cells.size()):
		var position := _vector_from_dictionary(water_cells[index])
		var cell: Dictionary = cell_index.get(_key(position), {})
		if bool(cell.layers.terrain.walkable):
			bridge_count += 1
		else:
			water_count += 1
			asserts.equal(String(cell.layers.terrain.id), String(water_template.water_terrain_id), "recorded water cell uses template water terrain")
			asserts.equal(String(cell.layers.terrain.render_id), String(water_template.water_render_id), "recorded water cell uses template water render id")
		if index > 0:
			var previous := _vector_from_dictionary(water_cells[index - 1])
			asserts.true_value(_position_distance(previous, position) <= 1, "water stroke remains continuous")
	asserts.true_value(water_count > 0, "water stroke leaves readable non-walkable water")
	asserts.true_value(bridge_count > 0, "path template creates walkable crossings through water")

func _assert_resources_near_templates(asserts, world: Dictionary) -> void:
	var template_positions := _template_neighborhood_positions(world)
	asserts.true_value(not template_positions.is_empty(), "template neighborhoods are available for resource placement")
	for node in world.resource_nodes:
		var position := _vector_from_dictionary(node.position)
		var near_template := false
		for candidate in template_positions:
			if _position_distance(position, candidate) <= 3:
				near_template = true
				break
		asserts.true_value(near_template, "%s resource is clustered near a path, landmark, or template anchor" % node.id)

func _template_by_id(world: Dictionary, template_id: String) -> Dictionary:
	for template in world.get("templates", []):
		if String(template.get("id", "")) == template_id:
			return template
	return {}

func _template_neighborhood_positions(world: Dictionary) -> Array:
	var positions := []
	var path_template := _template_by_id(world, WorldGenerator.TEMPLATE_PATH_SPINE)
	for row in path_template.get("cells", []):
		positions.append(_vector_from_dictionary(row))
	var cluster_template := _template_by_id(world, WorldGenerator.TEMPLATE_RESOURCE_CLUSTER)
	for row in cluster_template.get("anchors", []):
		positions.append(_vector_from_dictionary(row))
	for landmark in world.get("landmarks", []):
		positions.append(_vector_from_dictionary(landmark.position))
	return positions

func _world_cell_index(world_data: Dictionary) -> Dictionary:
	var index := {}
	for cell in world_data.cells:
		index[_key(_vector_from_dictionary(cell.position))] = cell
	return index

func _assert_asset_reference_exists(asserts, source_id: String, message: String) -> void:
	var asset_catalog := AssetCatalog.new()
	var load_result: Dictionary = asset_catalog.load_manifest()
	asserts.true_value(load_result.ok, "asset manifest loads for source reference")
	if load_result.ok:
		asserts.true_value(not asset_catalog.id_for_reference(source_id).is_empty(), message)

func _assert_mountain_terrain_profile(asserts, world_data: Dictionary) -> void:
	var required_walkable := {
		"mountain_slope": true,
		"mountain_path": true,
		"mountain_cave_ground": true
	}
	var required_blocked := {
		"mountain_cliff": true,
		"mountain_rock": true,
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
		"asset_assets_sprites_objects_natural_props_flat_rock_32x32_png": true,
		"asset_assets_sprites_objects_natural_props_mossy_rock_32x32_png": true,
		"asset_assets_sprites_objects_natural_props_mountain_rock_04_32x32_png": true,
		"asset_assets_sprites_objects_natural_props_mountain_rock_01_32x32_png": true,
		"terrain_tree_pine_32x32": true,
		"asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png": true,
		"asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png": true,
		"asset_assets_sprites_objects_mining_timber_support_1x2_32x64_png": true,
		"asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png": true
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
		"asset_assets_tiles_terrain_desert_dry_soil_01_32x32_png": true,
		"asset_assets_tiles_terrain_desert_cracked_clay_32x32_png": true,
		"asset_assets_tiles_terrain_desert_sand_ripple_01_32x32_png": true,
		"asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png": true,
		"terrain_tree_round_32x32": true,
		"asset_assets_tiles_terrain_desert_dry_scrub_patch_32x32_png": true,
		"asset_assets_tiles_terrain_desert_bone_scatter_32x32_png": true,
		"asset_assets_sprites_objects_mining_iron_ore_32x32_png": true,
		"asset_assets_sprites_objects_structures_small_storage_shed_64x64_png": true,
		"asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png": true
	}
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			var source_id := String(cell.get("source_id", ""))
			if expected_sources.has(source_id):
				seen[source_id] = true
	for source_id in expected_sources.keys():
		asserts.true_value(seen.has(source_id), "wasteland renderer uses promoted source: %s" % source_id)

func _assert_snowfield_terrain_profile(asserts, world_data: Dictionary) -> void:
	var required_walkable := {
		"snowfield_snow": true,
		"snowfield_snow_path": true,
		"snowfield_ice_edge": true,
		"snowfield_safe_clearing": true
	}
	var required_blocked := {
		"snowfield_ice": true,
		"snowfield_ice_wall": true
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
		asserts.true_value(int(terrain_counts.get(terrain_id, 0)) > 0, "snowfield includes walkable terrain: %s" % terrain_id)
	for terrain_id in required_blocked.keys():
		asserts.true_value(int(blocked_counts.get(terrain_id, 0)) > 0, "snowfield includes blocked terrain: %s" % terrain_id)

func _assert_snowfield_renderer_sources(asserts, renderer_input: Dictionary) -> void:
	var expected_sources := {
		"asset_assets_tiles_terrain_snow_snow_ground_01_32x32_png": true,
		"asset_assets_tiles_terrain_snow_snow_ground_03_32x32_png": true,
		"asset_assets_tiles_terrain_snow_snow_ground_04_32x32_png": true,
		"asset_assets_tiles_terrain_snow_snow_rock_edge_01_32x32_png": true,
		"terrain_tree_pine_32x32": true,
		"asset_assets_tiles_terrain_snow_snow_rock_edge_02_32x32_png": true,
		"asset_assets_tiles_terrain_snow_snow_mound_32x32_png": true,
		"asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png": true,
		"asset_assets_sprites_objects_shrine_props_stone_water_basin_32x32_png": true,
		"asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png": true,
		"asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png": true
	}
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			var source_id := String(cell.get("source_id", ""))
			if expected_sources.has(source_id):
				seen[source_id] = true
	for source_id in expected_sources.keys():
		asserts.true_value(seen.has(source_id), "snowfield renderer uses promoted source: %s" % source_id)

func _assert_rainforest_terrain_profile(asserts, world_data: Dictionary) -> void:
	var required_walkable := {
		"rainforest_vine_path": true,
		"rainforest_tea_field": true,
		"rainforest_river_bank": true
	}
	var required_blocked := {
		"rainforest_jungle": true,
		"rainforest_swamp": true,
		"rainforest_river": true
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
		asserts.true_value(int(terrain_counts.get(terrain_id, 0)) > 0, "rainforest includes walkable terrain: %s" % terrain_id)
	for terrain_id in required_blocked.keys():
		asserts.true_value(int(blocked_counts.get(terrain_id, 0)) > 0, "rainforest includes blocked terrain: %s" % terrain_id)

func _assert_rainforest_renderer_sources(asserts, renderer_input: Dictionary) -> void:
	var expected_sources := {
		"terrain_tree_broadleaf_32x32": true,
		"asset_assets_sprites_objects_natural_props_reed_clump_32x32_png": true,
		"terrain_river_water_01": true,
		"asset_assets_tiles_terrain_plains_flower_grass_02_32x32_png": true,
		"asset_assets_sprites_objects_crafting_tea_leaf_worktable_32x32_png": true,
		"terrain_tree_round_32x32": true,
		"asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png": true,
		"asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png": true,
		"asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png": true
	}
	var seen := {}
	for layer in renderer_input.layers:
		for cell in layer.cells:
			var source_id := String(cell.get("source_id", ""))
			if expected_sources.has(source_id):
				seen[source_id] = true
	for source_id in expected_sources.keys():
		asserts.true_value(seen.has(source_id), "rainforest renderer uses promoted source: %s" % source_id)

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
		var item_type := String(item.get("type", ""))
		if (item_type == "재료" or item_type == "향") and biome_resource_text.contains(String(item.get("name", ""))):
			material_ids[String(item.get("id", ""))] = true
	for node in resource_nodes:
		asserts.true_value(material_ids.has(String(node.resource_id)), "%s uses an existing biome material item id" % node.id)

func _assert_rainforest_rare_resource_ids(asserts, resource_nodes: Array) -> void:
	var has_incense := false
	for node in resource_nodes:
		if String(node.get("resource_id", "")) == "item_5":
			asserts.equal(String(node.get("source_id", "")), "terrain_tree_round_32x32", "rainforest 침향 resource uses agarwood source")
			has_incense = true
	asserts.true_value(has_incense, "rainforest includes confirmed 침향 rare resource id")

func _assert_wasteland_chunk_features(asserts, chunks: Array) -> void:
	var feature_counts := {}
	for chunk in chunks:
		var feature := String(chunk.get("feature", ""))
		feature_counts[feature] = int(feature_counts.get(feature, 0)) + 1
	asserts.true_value(int(feature_counts.get("asymmetric_ruin", 0)) > 0, "wasteland includes asymmetric ruin chunks")
	asserts.true_value(int(feature_counts.get("long_detour", 0)) > 0 or int(feature_counts.get("dry_detour", 0)) > 0 or int(feature_counts.get("dry_river_bypass", 0)) > 0, "wasteland includes bypass/detour chunks")
	asserts.true_value(int(feature_counts.get("dead_end", 0)) > 0, "wasteland includes dead-end chunks")
	asserts.true_value(int(feature_counts.get("battlefield_trace", 0)) > 0, "wasteland includes battlefield trace chunks")

func _assert_snowfield_chunk_features(asserts, chunks: Array) -> void:
	var feature_counts := {}
	for chunk in chunks:
		var feature := String(chunk.get("feature", ""))
		feature_counts[feature] = int(feature_counts.get(feature, 0)) + 1
	asserts.true_value(int(feature_counts.get("snow_path_crossing", 0)) > 0 or int(feature_counts.get("snowy_mountain_path", 0)) > 0, "snowfield includes snow path chunks")
	asserts.true_value(int(feature_counts.get("frozen_river_edge", 0)) > 0, "snowfield includes frozen river edge chunks")
	asserts.true_value(int(feature_counts.get("ice_wall_pass", 0)) > 0, "snowfield includes ice wall boundary chunks")
	asserts.true_value(int(feature_counts.get("safe_clearing", 0)) > 0, "snowfield includes safe-point clearings")

func _assert_rainforest_chunk_features(asserts, chunks: Array) -> void:
	var feature_counts := {}
	for chunk in chunks:
		var feature := String(chunk.get("feature", ""))
		feature_counts[feature] = int(feature_counts.get(feature, 0)) + 1
	asserts.true_value(int(feature_counts.get("dense_jungle_vine_path", 0)) > 0, "rainforest includes dense jungle/vine path chunks")
	asserts.true_value(int(feature_counts.get("wide_river_bank", 0)) > 0 or int(feature_counts.get("river_bypass", 0)) > 0, "rainforest includes water boundary/bypass chunks")
	asserts.true_value(int(feature_counts.get("swamp_boundary", 0)) > 0, "rainforest includes swamp boundary chunks")
	asserts.true_value(int(feature_counts.get("agarwood_grove", 0)) > 0, "rainforest includes agarwood grove chunks")

func _assert_no_temperature_state(asserts, world: Dictionary) -> void:
	var text := JSON.stringify(world).to_lower()
	asserts.false_value(text.contains("temperature"), "snowfield generation does not add temperature state")
	asserts.false_value(text.contains("body_temperature"), "snowfield generation does not add body temperature state")
	asserts.false_value(text.contains("체온"), "snowfield generation does not add 체온 state")

func _assert_no_forbidden_survival_state(asserts, world: Dictionary) -> void:
	var text := JSON.stringify(world).to_lower()
	asserts.false_value(text.contains("poison"), "rainforest generation does not add poison state")
	asserts.false_value(text.contains("disease"), "rainforest generation does not add disease state")
	asserts.false_value(text.contains("독"), "rainforest generation does not add 독 state")
	asserts.false_value(text.contains("질병"), "rainforest generation does not add 질병 state")

func _manhattan_distance(a: Dictionary, b: Dictionary) -> int:
	return abs(int(a.x) - int(b.x)) + abs(int(a.y) - int(b.y))

func _position_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]

func _canonical_world(world: Dictionary) -> Dictionary:
	var canonical := world.duplicate(true)
	canonical.erase("retry_attempt")
	canonical.erase("retry_limit")
	canonical.erase("seed")
	canonical.erase("data_version")
	return canonical
