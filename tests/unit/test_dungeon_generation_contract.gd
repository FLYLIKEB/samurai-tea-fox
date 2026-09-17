extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DungeonLayoutBuilder = preload("res://src/dungeon/dungeon_layout_builder.gd")
const DungeonSceneCoordinator = preload("res://src/main/dungeon_scene_coordinator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	var builder := DungeonLayoutBuilder.new()
	var common: WorldData = builder.build({"id": "dungeon_4"}, Callable(), 731).layout
	var mountain: WorldData = builder.build({"id": "dungeon_6"}, Callable(), 731).layout
	var repeated: WorldData = builder.build({"id": "dungeon_4"}, Callable(), 731).layout
	asserts.false_value(common.to_dictionary() == mountain.to_dictionary(), "each biome dungeon gets a distinct seeded layout")
	asserts.equal(common.to_dictionary(), repeated.to_dictionary(), "same run seed and dungeon id reproduce the same layout")
	asserts.equal(common.terrain_id_at(Vector2i(1, 1)), DungeonLayoutBuilder.FLOOR_TERRAIN_ID, "generated dungeon keeps its entry on floor terrain")
	asserts.equal(common.terrain_id_at(Vector2i(10, 7)), DungeonLayoutBuilder.FLOOR_TERRAIN_ID, "generated dungeon keeps its boss anchor on floor terrain")

	var catalog := DataCatalog.new()
	var assets := AssetCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "boss mapping loads canonical definitions")
	asserts.true_value(assets.load_manifest().ok, "boss mapping loads the asset manifest")
	var coordinator := DungeonSceneCoordinator.new()
	var boss_asset_ids := {}
	for dungeon in catalog.get_definitions("dungeons"):
		if String(dungeon.get("id", "")) == "final_tea_room":
			continue
		var character_id := coordinator.boss_asset_character_id(catalog, dungeon)
		var asset_id := assets.character_animation_id(character_id, "walk")
		asserts.true_value(not character_id.is_empty(), "%s resolves its boss character" % dungeon.id)
		asserts.true_value(not asset_id.is_empty(), "%s resolves a boss sprite sheet" % dungeon.id)
		boss_asset_ids[asset_id] = true
	asserts.equal(boss_asset_ids.size(), 5, "the five biome dungeons use five distinct boss sprite sheets")
