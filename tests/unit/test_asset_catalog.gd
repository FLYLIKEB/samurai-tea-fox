extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")

func run(asserts) -> void:
	var catalog := AssetCatalog.new()
	var result := catalog.load_manifest()
	asserts.true_value(result.ok, "authoritative asset manifest loads")
	asserts.true_value(catalog.has("fox_samurai_front_idle"), "stable asset ID is registered")
	asserts.equal(
		catalog.path_for("fox_samurai_front_idle"),
		"res://assets/sprites/characters/player/chr-8-fox-samurai/fox_samurai_front_idle_32x32.png",
		"stable asset ID resolves to the promoted runtime path"
	)
	asserts.true_value(catalog.load_texture("fox_samurai_front_idle") != null, "registered PNG loads as Texture2D")
	asserts.equal(catalog.path_for("missing_asset"), "", "unknown stable asset ID has no path")
	asserts.true_value(catalog.load_texture("missing_asset") == null, "unknown stable asset ID has no texture")
