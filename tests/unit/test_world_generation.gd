extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "catalog loads before world generation")

	var biome := catalog.find_by_id("biomes", "common_region")
	var generator := WorldGenerator.new()
	var a := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"))
	var b := generator.generate(11037, catalog.data_version, biome, catalog.get_definitions("balance"))
	var c := generator.generate(11038, catalog.data_version, biome, catalog.get_definitions("balance"))

	asserts.equal(a, b, "same seed and data version generate same world")
	asserts.true_value(a != c, "different seed changes generated world")
	asserts.true_value(a.connectivity.valid, "required landmarks are connectivity-valid in scaffold")
	asserts.equal(a.data_version, "notion-2026-09-01", "world stores data version")
	asserts.true_value(a.has("world_data"), "generator exposes pure world data")
	asserts.true_value(a.has("renderer_input"), "generator exposes renderer input contract")
	asserts.equal(a.renderer_input.read_only, true, "renderer input is read-only projection")
