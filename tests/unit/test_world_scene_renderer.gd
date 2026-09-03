extends RefCounted

const WorldData = preload("res://src/world/data/world_data.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

func run(asserts) -> void:
	_assert_sixteen_adjacency_masks(asserts)
	_assert_tilemap_layer_uses_adjacency_variants(asserts)
	_assert_river_uses_connection_specific_sources(asserts)
	_assert_tree_footprints_overlay_base_terrain(asserts)
	_assert_multicell_footprints_keep_original_texture(asserts)
	_assert_special_objects_have_role_colored_outlines(asserts)

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

func _assert_tree_footprints_overlay_base_terrain(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var root := Node2D.new()
	var tree := "asset_assets_sprites_objects_natural_props_broadleaf_tree_small_32x32_png"
	var ground := "terrain_plains_grass_ground_01"
	var input := {
		"schema_version": 1,
		"read_only": true,
		"tile_size": 32,
		"bounds": {"width": 1, "height": 1},
		"layers": [
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": [
				{"position": {"x": 0, "y": 0}, "source_id": ground}
			]},
			{"id": WorldData.LAYER_ENTITIES, "kind": "footprint", "cells": [
				{"position": {"x": 0, "y": 0}, "owner_id": "terrain_tree_0_0", "source_id": tree}
			]}
		],
		"required_landmarks": []
	}
	var result: Dictionary = renderer.render(root, input)
	asserts.true_value(result.ok, "renderer accepts tree-over-ground projection")
	asserts.equal(int(result.counts.get(WorldData.LAYER_TERRAIN, 0)), 1, "renderer keeps the base terrain tile behind a tree")
	asserts.equal(int(result.counts.get(WorldData.LAYER_ENTITIES, 0)), 1, "renderer draws the tree object on the entity layer")
	var tilemap := root.get_node_or_null(WorldSceneRenderer.TERRAIN_LAYER) as TileMapLayer
	asserts.true_value(tilemap != null, "tree projection still creates terrain tilemap")
	if tilemap != null:
		asserts.equal(tilemap.get_cell_source_id(Vector2i.ZERO), 0, "ground tile remains present below tree object")
	var entities := root.get_node_or_null(WorldSceneRenderer.ENTITY_LAYER) as Node2D
	asserts.true_value(entities != null and entities.get_child_count() == 1, "tree object renders once above terrain")
	asserts.true_value(tree in result.asset_report.used_asset_ids, "renderer asset report resolves tree object reference")
	asserts.true_value(ground in result.asset_report.used_asset_ids, "renderer asset report resolves ground tile reference")
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

func _assert_special_objects_have_role_colored_outlines(asserts) -> void:
	var renderer := WorldSceneRenderer.new()
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	renderer._add_special_outline(sprite, Vector2(32, 32), WorldSceneRenderer.TELEPORT_OUTLINE_COLOR)
	var outline := sprite.get_node_or_null("SpecialOutline") as Line2D
	asserts.true_value(outline != null, "special object receives a visible outline")
	if outline != null:
		asserts.equal(outline.default_color, WorldSceneRenderer.TELEPORT_OUTLINE_COLOR, "special object outline keeps its role color")
		asserts.equal(outline.width, 2.0, "special object outline stays crisp at pixel scale")
	sprite.free()
