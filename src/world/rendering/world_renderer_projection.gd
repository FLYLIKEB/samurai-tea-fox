extends RefCounted
class_name WorldRendererProjection

const WorldData = preload("res://src/world/data/world_data.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")

const TERRAIN_SOURCE_IDS := {
	"common_ground": "terrain_plains_grass_ground_01",
	"common_grass": "terrain_plains_grass_ground_01",
	"common_path": "asset_assets_tiles_terrain_paths_road_isolated_32x32_png",
	"common_field": "terrain_plains_flower_grass_01",
	"common_forest": "terrain_plains_grass_ground_01",
	"common_water": "terrain_river_water_01",
	"common_bridge": "asset_assets_tiles_terrain_bridges_bridge_vertical_32x32_png",
	"mountain_slope": "asset_assets_tiles_terrain_mountain_mountain_ground_01_32x32_png",
	"mountain_path": "asset_assets_tiles_terrain_mountain_mountain_trail_01_32x32_png",
	"mountain_cliff": "asset_assets_tiles_terrain_mountain_mountain_cliff_01_32x32_png",
	"mountain_rock": "asset_assets_tiles_terrain_mountain_mountain_rock_01_32x32_png",
	"mountain_conifer_forest": "asset_assets_tiles_terrain_mountain_mountain_ground_01_32x32_png",
	"mountain_valley_water": "terrain_river_water_01",
	"mountain_cave_ground": "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png",
	"wasteland_dry_soil": "asset_assets_tiles_terrain_desert_dry_soil_01_32x32_png",
	"wasteland_cracked_ground": "asset_assets_tiles_terrain_desert_cracked_clay_32x32_png",
	"wasteland_detour_path": "asset_assets_tiles_terrain_desert_sand_ripple_01_32x32_png",
	"wasteland_ruin": "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png",
	"wasteland_dead_tree": "asset_assets_tiles_terrain_desert_dry_soil_01_32x32_png",
	"wasteland_dry_river": "asset_assets_tiles_terrain_desert_dry_scrub_patch_32x32_png",
	"wasteland_camp_trace": "asset_assets_tiles_terrain_desert_bone_scatter_32x32_png",
	"snowfield_snow": "asset_assets_tiles_terrain_snow_snow_ground_01_32x32_png",
	"snowfield_snow_path": "asset_assets_tiles_terrain_snow_snow_ground_03_32x32_png",
	"snowfield_ice": "asset_assets_tiles_terrain_snow_snow_ground_04_32x32_png",
	"snowfield_ice_edge": "asset_assets_tiles_terrain_snow_snow_rock_edge_01_32x32_png",
	"snowfield_pine": "asset_assets_tiles_terrain_snow_snow_ground_01_32x32_png",
	"snowfield_ice_wall": "asset_assets_tiles_terrain_snow_snow_rock_edge_02_32x32_png",
	"snowfield_safe_clearing": "asset_assets_tiles_terrain_snow_snow_mound_32x32_png",
	"rainforest_jungle": "terrain_tree_broadleaf_32x32",
	"rainforest_swamp": "asset_assets_sprites_objects_natural_props_reed_clump_32x32_png",
	"rainforest_river": "terrain_river_water_01",
	"rainforest_vine_path": "terrain_plains_flower_grass_01",
	"rainforest_tea_field": "asset_assets_sprites_objects_crafting_tea_leaf_worktable_32x32_png",
	"rainforest_agarwood_grove": "terrain_plains_flower_grass_01",
	"rainforest_river_bank": "terrain_plains_flower_grass_01",
	"dungeon_floor": "terrain_dungeon_mossy_dojo_tileset",
	"dungeon_wall": "terrain_dungeon_mossy_dojo_tileset",
	"grass": "terrain_plains_grass_ground_01",
	"ground": "terrain_plains_grass_ground_01",
	"water": "terrain_river_water_01"
}

const OWNER_SOURCE_IDS := {
	"large_fenced_house": "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png",
	"large_house_fence_nw": "asset_assets_sprites_objects_structures_wood_fence_corner_32x32_png",
	"large_house_fence_ne": "asset_assets_sprites_objects_structures_wood_fence_corner_32x32_png",
	"large_house_fence_sw": "asset_assets_sprites_objects_structures_wood_fence_corner_32x32_png",
	"large_house_fence_se": "asset_assets_sprites_objects_structures_wood_fence_corner_32x32_png",
	"large_house_fence_n": "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png",
	"large_house_fence_s": "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png",
	"large_house_fence_w": "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png",
	"large_house_fence_e": "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png"
}

const FACILITY_SOURCE_BY_BIOME_TERM := {
	"mountain_region|광산": "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png",
	"mountain_region|산사": "asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png",
	"mountain_region|폐광": "asset_assets_sprites_objects_mining_timber_support_1x2_32x64_png",
	"mountain_region|산중 찻집": "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png",
	"wasteland|폐촌": "asset_assets_sprites_objects_structures_small_storage_shed_64x64_png",
	"wasteland|버려진 초소": "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png",
	"wasteland|무너진 다실": "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png",
	"wasteland|전쟁터 흔적": "asset_assets_tiles_terrain_desert_bone_scatter_32x32_png",
	"snowfield|산장": "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png",
	"snowfield|온천": "asset_assets_sprites_objects_shrine_props_stone_water_basin_32x32_png",
	"snowfield|설원 사당": "asset_assets_sprites_objects_structures_shrine_torii_gate_2x2_64x64_png",
	"snowfield|얼어붙은 광산": "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png",
	"rainforest|차 재배지": "asset_assets_sprites_objects_crafting_tea_leaf_worktable_32x32_png",
	"rainforest|강변 취락": "asset_assets_sprites_objects_structures_small_wood_house_2x2_64x64_png",
	"rainforest|숲속 다실": "asset_assets_sprites_objects_crafting_tea_table_2x2_64x64_png",
	"rainforest|향 문화 공간": "asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png"
}

const RESOURCE_SOURCE_BY_BIOME_RESOURCE := {
	"common_region|stone": "small_rock_resource",
	"mountain_region|stone": "asset_assets_tiles_terrain_mountain_mountain_rock_01_32x32_png",
	"wasteland|item_28": "asset_assets_sprites_objects_mining_iron_ore_32x32_png",
	"snowfield|wood": "terrain_tree_pine_32x32",
	"rainforest|item_5": "terrain_tree_round_32x32",
	"rainforest|wood": "terrain_tree_round_32x32",
	"rainforest|clay": "asset_assets_sprites_objects_natural_props_reed_clump_32x32_png"
}

const TREE_SOURCE_BY_TERRAIN := {
	"common_forest": "terrain_tree_broadleaf_32x32",
	"mountain_conifer_forest": "terrain_tree_pine_32x32",
	"wasteland_dead_tree": "terrain_tree_round_32x32",
	"snowfield_pine": "terrain_tree_pine_32x32",
	"rainforest_agarwood_grove": "terrain_tree_round_32x32"
}

func project(world_data: Dictionary, progression_projection := {}) -> Dictionary:
	var bounds: Dictionary = world_data.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	var terrain_cells := []
	var base_terrain_cells := []
	var facility_cells := []
	var entity_cells := []
	var interactable_cells := []
	var owner_source_ids := _owner_source_ids(world_data)
	var base_source_id := _terrain_source_id(String(world_data.get("base_terrain_id", world_data.get("default_terrain_id", ""))))
	for y in range(height):
		for x in range(width):
			base_terrain_cells.append({"position": {"x": x, "y": y}, "source_id": base_source_id})

	for cell in world_data.get("cells", []):
		var position: Dictionary = cell.get("position", {})
		var vector := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		if vector.x < 0 or vector.y < 0 or vector.x >= width or vector.y >= height:
			continue

		var layers: Dictionary = cell.get("layers", {})
		var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
		var terrain_cell := {
			"position": position.duplicate(true),
			"source_id": _terrain_source_id_for_cell(terrain, vector, world_data)
		}
		var atlas_coords = terrain.get("atlas_coords", null)
		if typeof(atlas_coords) == TYPE_DICTIONARY:
			terrain_cell["atlas_coords"] = atlas_coords.duplicate(true)
		terrain_cells.append(terrain_cell)
		_add_owner_cells(facility_cells, position, layers.get(WorldData.LAYER_FACILITIES, []), owner_source_ids)
		_add_owner_cells(entity_cells, position, layers.get(WorldData.LAYER_ENTITIES, []), owner_source_ids)
		_add_owner_cells(interactable_cells, position, layers.get(WorldData.LAYER_INTERACTABLES, []), owner_source_ids)

	return {
		"schema_version": 1,
		"read_only": true,
		"tile_size": int(world_data.get("tile_size", RuntimeConstants.float_value("world.tile_size_pixels"))),
		"bounds": bounds.duplicate(true),
		"layers": [
			{"id": "base_terrain", "kind": "tile", "cells": base_terrain_cells},
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": terrain_cells},
			{"id": WorldData.LAYER_FACILITIES, "kind": "footprint", "cells": facility_cells},
			{"id": WorldData.LAYER_ENTITIES, "kind": "footprint", "cells": entity_cells},
			{"id": WorldData.LAYER_INTERACTABLES, "kind": "interaction", "cells": interactable_cells}
		],
		"required_landmarks": _project_landmarks(world_data, progression_projection)
	}

func _project_landmarks(world_data: Dictionary, progression_projection) -> Array:
	var landmarks: Array = world_data.get("required_landmarks", []).duplicate(true)
	if typeof(progression_projection) != TYPE_DICTIONARY:
		return landmarks
	var teleport_states: Dictionary = progression_projection.get("teleport_states", {})
	for landmark in landmarks:
		if String(landmark.get("kind", landmark.get("type", ""))) != WorldData.LANDMARK_TELEPORT_ZONE:
			continue
		var metadata: Dictionary = landmark.get("metadata", {})
		var biome_id := String(metadata.get("teleport_biome_id", metadata.get("biome_id", "")))
		if biome_id.is_empty() or not teleport_states.has(biome_id):
			continue
		landmark["teleport_biome_id"] = biome_id
		landmark["teleport_state"] = String(teleport_states[biome_id])
	return landmarks

func _add_owner_cells(output: Array, position: Dictionary, owners: Array, owner_source_ids: Dictionary) -> void:
	for owner_id in owners:
		var cell := {
			"position": position.duplicate(true),
			"owner_id": owner_id
		}
		var source_id := String(owner_source_ids.get(String(owner_id), ""))
		if not source_id.is_empty():
			cell["source_id"] = source_id
		var metadata: Dictionary = _owner_metadata.get(String(owner_id), {})
		if metadata.has("rotation_degrees"):
			cell["rotation_degrees"] = float(metadata.get("rotation_degrees", 0.0))
		output.append(cell)

var _owner_metadata: Dictionary = {}

func _owner_source_ids(world_data: Dictionary) -> Dictionary:
	var sources := {}
	_owner_metadata = {}
	for reservation in world_data.get("reservations", []):
		var owner_id := String(reservation.get("owner_id", ""))
		var metadata: Dictionary = reservation.get("metadata", {})
		var source_id := _owner_source_id(owner_id, metadata)
		if not owner_id.is_empty() and not source_id.is_empty():
			sources[owner_id] = source_id
		if not owner_id.is_empty():
			_owner_metadata[owner_id] = metadata.duplicate(true)
	return sources

func _terrain_source_id(terrain_id: String) -> String:
	return String(TERRAIN_SOURCE_IDS.get(terrain_id, terrain_id))

func _terrain_source_id_for_cell(terrain: Dictionary, position: Vector2i, world_data: Dictionary) -> String:
	var terrain_id := String(terrain.get("id", ""))
	if terrain_id == "common_bridge":
		return _bridge_source_id(position, world_data)
	if terrain_id == "mountain_cliff" and _is_map_edge(position, world_data):
		return "asset_assets_tiles_sheets_biome_atlases_biome_tile_map_light_object_biome_map_atlas_crop_147_91_35x34_resize_32x32_png"
	return _terrain_source_id(terrain_id)

func _bridge_source_id(position: Vector2i, world_data: Dictionary) -> String:
	var water_north_south := _terrain_id_at(world_data, position + Vector2i.UP) == "common_water" or _terrain_id_at(world_data, position + Vector2i.DOWN) == "common_water"
	var water_east_west := _terrain_id_at(world_data, position + Vector2i.LEFT) == "common_water" or _terrain_id_at(world_data, position + Vector2i.RIGHT) == "common_water"
	if water_north_south and not water_east_west:
		return "asset_assets_tiles_terrain_bridges_bridge_horizontal_32x32_png"
	return "asset_assets_tiles_terrain_bridges_bridge_vertical_32x32_png"

func _terrain_id_at(world_data: Dictionary, position: Vector2i) -> String:
	for cell in world_data.get("cells", []):
		var raw_position: Dictionary = cell.get("position", {})
		if int(raw_position.get("x", -1)) != position.x or int(raw_position.get("y", -1)) != position.y:
			continue
		var terrain: Dictionary = cell.get("layers", {}).get(WorldData.LAYER_TERRAIN, {})
		return String(terrain.get("id", ""))
	return ""

func _is_map_edge(position: Vector2i, world_data: Dictionary) -> bool:
	var bounds: Dictionary = world_data.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	return position.x == 0 or position.y == 0 or position.x == width - 1 or position.y == height - 1

func _owner_source_id(owner_id: String, metadata: Dictionary) -> String:
	var explicit := String(metadata.get("source_id", ""))
	if not explicit.is_empty():
		return explicit
	if String(metadata.get("terrain_overlay", "")) == "tree":
		return String(TREE_SOURCE_BY_TERRAIN.get(String(metadata.get("terrain_id", "")), ""))
	if String(metadata.get("terrain_overlay", "")) == "path_fence":
		return "asset_assets_sprites_objects_structures_wood_fence_horizontal_1x2_64x32_png"
	var facility_key := "%s|%s" % [String(metadata.get("biome_rule_id", "")), String(metadata.get("facility_term", ""))]
	if FACILITY_SOURCE_BY_BIOME_TERM.has(facility_key):
		return String(FACILITY_SOURCE_BY_BIOME_TERM[facility_key])
	var resource_key := "%s|%s" % [String(metadata.get("biome_rule_id", "")), String(metadata.get("resource_id", ""))]
	if RESOURCE_SOURCE_BY_BIOME_RESOURCE.has(resource_key):
		return String(RESOURCE_SOURCE_BY_BIOME_RESOURCE[resource_key])
	if owner_id.begins_with("resource_"):
		match String(metadata.get("biome_rule_id", "")):
			"common_region":
				return "small_rock_resource"
			"mountain_region":
				return "asset_assets_tiles_terrain_mountain_mountain_rock_01_32x32_png"
			"wasteland":
				return "asset_assets_sprites_objects_mining_iron_ore_32x32_png"
			"snowfield":
				return "terrain_tree_pine_32x32"
			"rainforest":
				return "terrain_tree_round_32x32"
	if OWNER_SOURCE_IDS.has(owner_id):
		return String(OWNER_SOURCE_IDS[owner_id])
	return ""
