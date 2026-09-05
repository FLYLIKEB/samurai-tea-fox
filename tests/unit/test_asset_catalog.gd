extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")

func run(asserts) -> void:
	var catalog := AssetCatalog.new()
	var result := catalog.load_manifest()
	asserts.true_value(result.ok, "authoritative asset manifest loads")
	for asset_id in catalog.definitions:
		asserts.true_value(
			catalog.load_texture(String(asset_id)) != null,
			"registered runtime asset loads as Texture2D: %s" % asset_id
		)
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
		catalog.character_animation_id("CHR-8", "attack"),
		"chr_8_fox_samurai_attack",
		"character animation metadata resolves the player attack asset ID"
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
	var map_result: Dictionary = catalog.load_content_image_map()
	asserts.true_value(map_result.ok, "content image map loads after the asset manifest")
	asserts.equal(
		catalog.content_asset_id("items", "wood"),
		"item_wood_icon",
		"runtime-approved dedicated item image audit is exposed to runtime lookups"
	)
	asserts.equal(
		catalog.content_asset_id("items", "stone_axe"),
		"item_stone_axe_icon",
		"stone axe resolves to its dedicated runtime icon instead of a semantic fallback"
	)
	asserts.equal(
		catalog.path_for(catalog.content_asset_id("items", "stone_axe")),
		"res://assets/sprites/items/stone_axe_32x32.png",
		"stone axe dedicated icon resolves to the promoted 32x32 runtime path"
	)
	asserts.equal(
		catalog.content_asset_id("items", "traveler_quilted_clothes"),
		"item_traveler_quilted_clothes_icon",
		"traveler armor resolves to its dedicated runtime icon"
	)
	asserts.equal(
		catalog.content_asset_id("items", "mountain_wind_layered_clothes"),
		"item_mountain_wind_layered_clothes_icon",
		"mountain armor resolves to its dedicated runtime icon"
	)
	asserts.equal(
		catalog.content_asset_id("items", "snow_bamboo_overcoat"),
		"item_snow_bamboo_overcoat_icon",
		"snow armor resolves to its dedicated runtime icon"
	)
	asserts.equal(
		catalog.content_asset_id("monsters", "road_bandit"),
		"monster_road_bandit_front_idle",
		"monster stable ID resolves by the manifest convention"
	)
	asserts.true_value(catalog.has("campfire_sleep_facility_off"), "sleep facility off sprite stable asset ID is registered")
	asserts.true_value(catalog.has("campfire_sleep_facility_on"), "sleep facility on sprite stable asset ID is registered")
	asserts.true_value(catalog.has("sleep_available_indicator"), "sleep interaction indicator stable asset ID is registered")
	asserts.equal(
		catalog.content_asset_id("items", "portable_brazier"),
		"campfire_sleep_facility_off",
		"portable brazier resolves to the dedicated sleep facility sprite"
	)
	asserts.equal(
		catalog.content_asset_id("facility_interactions", "portable_brazier:sleep_lit"),
		"campfire_sleep_facility_on",
		"sleep facility lit state resolves to the dedicated sprite"
	)
	asserts.equal(
		catalog.content_asset_id("facility_interactions", "portable_brazier:sleep_available_indicator"),
		"sleep_available_indicator",
		"sleep interaction resolves to the dedicated indicator"
	)
	asserts.equal(
		catalog.path_for("campfire_sleep_facility_off"),
		"res://assets/sprites/facilities/sleep/campfire_sleep_facility_off_64x64.png",
		"sleep facility off sprite resolves to the promoted runtime path"
	)
	asserts.equal(
		catalog.path_for("sleep_available_indicator"),
		"res://assets/ui/interaction/sleep_available_indicator_32x32.png",
		"sleep interaction indicator resolves to the promoted runtime path"
	)
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
