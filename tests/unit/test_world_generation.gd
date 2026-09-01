extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "catalog loads before world generation")

	var biome := catalog.find_by_id("biomes", "common_region")
	var generator := WorldGenerator.new()
	var a := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var b := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var c := generator.generate(11038, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
	var d := generator.generate(11037, "notion-2026-09-02", biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))

	asserts.true_value(a.ok, "world generation succeeds")
	asserts.equal(a, b, "same seed and data version generate same world")
	asserts.true_value(a != c, "different seed changes generated world")
	asserts.true_value(a != d, "different data version changes generated world")
	asserts.true_value(a.connectivity.valid, "required landmarks are connectivity-valid")
	asserts.equal(a.data_version, "notion-2026-09-01", "world stores data version")
	asserts.true_value(a.chunks.size() > 0, "world records deterministic chunk composition")
	asserts.true_value(a.resource_nodes.size() >= a.min_resource_nodes, "world places minimum resources")
	asserts.equal(a.connectivity.required_landmark_ids.size(), 3, "entry, teleport, and core dungeon are required")
	asserts.true_value(a.has("world_data"), "generator exposes pure world data")
	asserts.true_value(a.has("renderer_input"), "generator exposes renderer input contract")
	asserts.equal(a.renderer_input.read_only, true, "renderer input is read-only projection")

	for seed in range(11000, 11025):
		var generated := generator.generate(seed, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"))
		asserts.true_value(generated.ok, "seed %d generates successfully" % seed)
		asserts.true_value(generated.connectivity.valid, "seed %d connects all required landmarks" % seed)
		asserts.true_value(generated.retry_attempt <= generated.retry_limit, "seed %d stays inside retry limit" % seed)
		asserts.true_value(generated.resource_nodes.size() >= generated.min_resource_nodes, "seed %d places minimum resources" % seed)

	var impossible_balance := catalog.get_definitions("balance").duplicate(true)
	impossible_balance.append({"id": "biome_min_resource_nodes", "value": 5000})
	var failed := generator.generate(11037, catalog.data_version, biome, impossible_balance, catalog.get_definitions("items"), {"retry_limit": 2, "max_resource_placement_attempts": 32})
	asserts.false_value(failed.ok, "generator reports failure after retry cap")
	asserts.equal(failed.retry_limit, 2, "failure records retry limit")
	asserts.equal(failed.failure_reason, "connectivity_or_resource_validation_failed", "failure reason is explicit")
