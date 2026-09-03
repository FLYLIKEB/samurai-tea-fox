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
	asserts.true_value(catalog.has("wasteland_daimyo_front_idle"), "enemy sprite stable asset ID is registered")
	asserts.equal(
		catalog.path_for("wasteland_daimyo_front_idle"),
		"res://assets/sprites/characters/bosses/chr-2-wasteland-daimyo/wasteland_daimyo_front_32x32.png",
		"enemy sprite stable asset ID resolves to the promoted runtime path"
	)
	asserts.true_value(catalog.load_texture("wasteland_daimyo_front_idle") != null, "registered enemy PNG loads as Texture2D")
	asserts.equal(
		catalog.character_animation_id("CHR-8", "walk"),
		"chr_8_fox_samurai_walk",
		"character animation metadata resolves a stable runtime asset ID"
	)
	asserts.equal(
		catalog.id_for_path("assets/sprites/objects/structures/small_signpost_32x32.png"),
		"small_signpost",
		"promoted runtime path resolves back to a manifest ID"
	)
	asserts.equal(
		catalog.path_for_reference("small_signpost"),
		"res://assets/sprites/objects/structures/small_signpost_32x32.png",
		"manifest ID reference resolves to its promoted path"
	)
	asserts.equal(
		catalog.id_for_reference("res://assets/sprites/objects/structures/small_signpost_32x32.png"),
		"small_signpost",
		"res:// path reference resolves to its manifest ID"
	)
	asserts.true_value(catalog.load_texture_reference("small_signpost") != null, "manifest ID reference loads texture")
	var audit: Dictionary = catalog.audit_references([
		"small_signpost",
		"res://assets/sprites/objects/structures/dungeon_entry_small_32x32.png",
		"missing_asset_reference"
	])
	asserts.true_value("small_signpost" in audit.used_asset_ids, "asset audit reports used stable IDs")
	asserts.true_value("dungeon_entry_small" in audit.used_asset_ids, "asset audit resolves path references to stable IDs")
	asserts.equal(audit.missing_references, ["missing_asset_reference"], "asset audit reports missing references")
	asserts.true_value("fox_samurai_front_idle" in audit.unused_asset_ids, "asset audit reports unused manifest assets")
	asserts.equal(catalog.character_animation_id("CHR-404", "walk"), "", "unknown character animation metadata has no ID")
	asserts.equal(catalog.path_for("missing_asset"), "", "unknown stable asset ID has no path")
	asserts.true_value(catalog.load_texture("missing_asset") == null, "unknown stable asset ID has no texture")
