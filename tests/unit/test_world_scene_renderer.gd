extends RefCounted

const WorldData = preload("res://src/world/data/world_data.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

func run(asserts) -> void:
	_assert_sixteen_adjacency_masks(asserts)
	_assert_tilemap_layer_uses_adjacency_variants(asserts)
	_assert_multicell_footprints_keep_original_texture(asserts)

func _assert_sixteen_adjacency_masks(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var source := "assets/tiles/terrain/forest/forest_boundary_tree_tileset_8x32.png"
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
		cells.append({"position": {"x": 0, "y": -2}, "source_id": "assets/tiles/terrain/plains/grass_ground_01_32x32.png"})
		var index := renderer._terrain_cell_index(cells)
		asserts.equal(renderer._adjacency_mask_for_cell(Vector2i.ZERO, source, index), mask, "N/E/S/W mask %d is exact and ignores other terrain" % mask)

func _assert_tilemap_layer_uses_adjacency_variants(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var forest := "assets/tiles/terrain/forest/forest_boundary_tree_tileset_8x32.png"
	var ground := "assets/tiles/terrain/plains/grass_ground_01_32x32.png"
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
	root.queue_free()

func _assert_multicell_footprints_keep_original_texture(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var source := "assets/sprites/objects/structures/ruined_wall_1x2_64x32.png"
	var input := {
		"schema_version": 1,
		"read_only": true,
		"tile_size": 32,
		"bounds": {"width": 3, "height": 2},
		"layers": [
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": [
				{"position": {"x": 0, "y": 0}, "source_id": "assets/tiles/terrain/plains/grass_ground_01_32x32.png"}
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
	root.queue_free()
