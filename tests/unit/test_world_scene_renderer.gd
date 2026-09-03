extends RefCounted

const WorldData = preload("res://src/world/data/world_data.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

func run(asserts) -> void:
	_assert_sixteen_adjacency_masks(asserts)
	_assert_tilemap_layer_uses_adjacency_variants(asserts)
	_assert_river_uses_connection_specific_sources(asserts)
	_assert_tree_terrain_renders_grass_underlay(asserts)
	_assert_multicell_footprints_keep_original_texture(asserts)

func _assert_sixteen_adjacency_masks(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var source := "terrain_forest_boundary_tree_tileset"
	for mask in range(16):
		var cells := [{"position": {"x": 0, "y": 0}, "source_id": source}]
		if mask & WorldSceneRenderer.ADJACENT_NORTH:
			cells.append({"position": {"x": 0, "y": -1}, "source_id": source})
		if mask & WorldSceneRenderer.ADJACENT_EAST:
			cells.append({"position": {"x": 1, "y": 0}, "source_id": source})
		if mask & WorldSceneRenderer.ADJACENT_SOUTH:
			cells.append({"position": {"x": 0, "y": 1}, "source_id": source})
		if mask & WorldSceneRenderer.ADJACENT_WEST:
			cells.append({"position": {"x": -1, "y": 0}, "source_id": source})
		cells.append({"position": {"x": 0, "y": -2}, "source_id": "terrain_plains_grass_ground_01"})
		var index := renderer._terrain_cell_index(cells)
		asserts.equal(renderer._adjacency_mask_for_cell(Vector2i.ZERO, source, index), mask, "N/E/S/W mask %d is exact and ignores other terrain" % mask)

func _assert_tilemap_layer_uses_adjacency_variants(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var forest := "terrain_forest_boundary_tree_tileset"
	var ground := "terrain_plains_grass_ground_01"
	var input := {
		"schema_version": 1,
		"read_only": true,
		"tile_size": 32,
		"bounds": {"width": 3, "height": 3},
		"layers": [{
			"id": WorldData.LAYER_TERRAIN,
			"kind": "tile",
			"cells": [
				{"position": {"x": 1, "y": 1}, "source_id": forest},
				{"position": {"x": 1, "y": 0}, "source_id": forest},
				{"position": {"x": 2, "y": 1}, "source_id": forest},
				{"position": {"x": 1, "y": 2}, "source_id": forest},
				{"position": {"x": 0, "y": 1}, "source_id": forest},
				{"position": {"x": 0, "y": 0}, "source_id": ground}
			]
		}],
		"required_landmarks": []
	}
	var result: Dictionary = renderer.render(root, input)
	asserts.true_value(result.ok, "renderer accepts read-only projection")
	asserts.equal(int(result.counts.get(WorldData.LAYER_TERRAIN, 0)), 6, "renderer writes every terrain cell")
	var tilemap := root.get_node_or_null(WorldSceneRenderer.TERRAIN_LAYER) as TileMapLayer
	asserts.true_value(tilemap != null, "terrain renders into TileMapLayer")
	if tilemap != null:
		asserts.equal(tilemap.get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(7, 0), "four-way adjacency uses explicit N/E/S/W bitmask variant modulo available atlas frames")
		asserts.equal(tilemap.get_cell_atlas_coords(Vector2i(1, 0)), Vector2i(4, 0), "south-only neighbor uses south bit variant")
	asserts.true_value("terrain_plains_grass_ground_01" in result.asset_report.used_asset_ids, "renderer asset report resolves manifest ID terrain references")
	root.queue_free()

func _assert_river_uses_connection_specific_sources(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var river := WorldSceneRenderer.RIVER_BASE_SOURCE_ID
	var vertical := renderer._terrain_source_for_adjacency(river, WorldSceneRenderer.ADJACENT_NORTH | WorldSceneRenderer.ADJACENT_SOUTH)
	var horizontal := renderer._terrain_source_for_adjacency(river, WorldSceneRenderer.ADJACENT_EAST | WorldSceneRenderer.ADJACENT_WEST)
	var curve := renderer._terrain_source_for_adjacency(river, WorldSceneRenderer.ADJACENT_NORTH | WorldSceneRenderer.ADJACENT_EAST)
	asserts.true_value(vertical != river, "river terrain swaps the base source for a connection-specific sprite")
	asserts.true_value(horizontal != river, "horizontal river connection uses a promoted variant source")
	asserts.true_value(curve != river, "curved river connection uses a promoted variant source")
	asserts.true_value(vertical != horizontal, "straight river variants differ by connection direction")
	asserts.true_value(curve != vertical and curve != horizontal, "curved river variant differs from straight variants")

func _assert_tree_terrain_renders_grass_underlay(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var tree := "terrain_tree_round_32x32"
	var input := {
		"schema_version": 1,
		"read_only": true,
		"tile_size": 32,
		"bounds": {"width": 1, "height": 1},
		"layers": [{
			"id": WorldData.LAYER_TERRAIN,
			"kind": "tile",
			"cells": [{"position": {"x": 0, "y": 0}, "source_id": tree}]
		}],
		"required_landmarks": []
	}
	var result: Dictionary = renderer.render(root, input)
	asserts.true_value(result.ok, "renderer accepts tree terrain input")
	var tilemap := root.get_node_or_null(WorldSceneRenderer.TERRAIN_LAYER) as TileMapLayer
	var footprints := root.get_node_or_null(WorldSceneRenderer.TERRAIN_FOOTPRINT_LAYER) as Node2D
	asserts.true_value(tilemap != null, "tree terrain keeps a tilemap underlay")
	asserts.true_value(footprints != null, "tree terrain creates an overlay layer")
	if tilemap != null and tilemap.tile_set != null:
		var source_id := tilemap.get_cell_source_id(Vector2i.ZERO)
		var source := tilemap.tile_set.get_source(source_id) as TileSetAtlasSource
		asserts.true_value(source != null and source.texture != null and source.texture.resource_path.ends_with("grass_ground_01_32x32_crop_1_1_30x30_resize_32x32.png"), "tree terrain lays grass under the tree sprite")
	if footprints != null:
		asserts.equal(footprints.get_child_count(), 1, "tree terrain draws one tree overlay sprite")
		var sprite := footprints.get_child(0) as Sprite2D
		asserts.true_value(sprite != null and sprite.texture != null, "tree overlay uses the requested terrain-folder round tree sprite")
	asserts.true_value("terrain_tree_round_32x32" in result.asset_report.used_asset_ids, "tree overlay source is audited as a terrain-folder tree asset")
	root.queue_free()

func _assert_multicell_footprints_keep_original_texture(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var source := "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png"
	var input := {
		"schema_version": 1,
		"read_only": true,
		"tile_size": 32,
		"bounds": {"width": 3, "height": 2},
		"layers": [
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": [
				{"position": {"x": 0, "y": 0}, "source_id": "terrain_plains_grass_ground_01"}
			]},
			{"id": WorldData.LAYER_FACILITIES, "kind": "footprint", "cells": [
				{"position": {"x": 1, "y": 0}, "owner_id": "ruin", "source_id": source},
				{"position": {"x": 2, "y": 0}, "owner_id": "ruin", "source_id": source}
			]}
		],
		"required_landmarks": []
	}
	var result: Dictionary = renderer.render(root, input)
	asserts.true_value(result.ok, "renderer accepts footprint projection")
	asserts.equal(int(result.counts.get(WorldData.LAYER_FACILITIES, 0)), 1, "multi-cell owner renders once")
	var facilities := root.get_node_or_null(WorldSceneRenderer.FACILITY_LAYER) as Node2D
	asserts.true_value(facilities != null, "facility footprint layer exists")
	if facilities != null:
		asserts.equal(facilities.get_child_count(), 1, "multi-cell footprint is not duplicated per occupied cell")
		var sprite := facilities.get_child(0) as Sprite2D
		asserts.true_value(sprite != null and sprite.texture != null, "multi-cell footprint renders as original sprite")
		if sprite != null and sprite.texture != null:
			asserts.equal(sprite.texture.get_width(), 64, "multi-cell footprint preserves original width")
			asserts.equal(sprite.texture.get_height(), 32, "multi-cell footprint preserves original height")
			asserts.equal(sprite.region_enabled, false, "multi-cell footprint is not cropped into a 32x32 atlas region")
	asserts.true_value("asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png" in result.asset_report.used_asset_ids, "renderer asset report resolves manifest ID footprint references")
	root.queue_free()
