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
	asserts.true_value(a.has("world_data"), "generator exposes pure world data")
	asserts.true_value(a.has("renderer_input"), "generator exposes renderer input contract")
	asserts.equal(a.renderer_input.read_only, true, "renderer input is read-only projection")
	_assert_teleport_landmark_metadata(asserts, a.world_data, "common_region")
	_assert_renderer_source_paths_exist(asserts, a.renderer_input)
	_assert_resource_accessibility(asserts, a)

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

func _assert_resource_accessibility(asserts, world: Dictionary) -> void:
	var validator := ConnectivityValidator.new()
	var access_points := []
	var interactable_owner_ids := _interactable_owner_ids(world.renderer_input)
	for node in world.resource_nodes:
		access_points.append(node.access_position)
		asserts.true_value(bool(node.placement_was_entry_reachable), "%s was placed on an entry-reachable cell" % node.id)
		asserts.true_value(bool(node.interactable), "%s is marked interactable" % node.id)
		asserts.true_value(interactable_owner_ids.has(node.id), "%s appears in renderer interactables" % node.id)
		asserts.equal(_manhattan_distance(node.position, node.access_position), 1, "%s has adjacent access cell" % node.id)
	var access_validation := validator.validate_access_points(world.world_data, access_points)
	asserts.true_value(access_validation.valid, "all resource access points are entry-reachable")

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
	var owner_ids := {}
	for layer in renderer_input.layers:
		if layer.id != WorldData.LAYER_INTERACTABLES:
			continue
		for cell in layer.cells:
			owner_ids[cell.owner_id] = true
	return owner_ids

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

func _manhattan_distance(a: Dictionary, b: Dictionary) -> int:
	return abs(int(a.x) - int(b.x)) + abs(int(a.y) - int(b.y))

func _canonical_world(world: Dictionary) -> Dictionary:
	var canonical := world.duplicate(true)
	canonical.erase("retry_attempt")
	canonical.erase("retry_limit")
	return canonical
