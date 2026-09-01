extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(result.ok, "generated Notion export files load")
	asserts.equal(catalog.data_version, "notion-2026-09-01", "data version is pinned")
	asserts.equal(int(catalog.find_balance_value("player_hp_max")), 100, "player HP max comes from balance data")
	asserts.equal(catalog.find_by_id("biomes", "common_region").name, "일반 지역", "common biome is present")

