extends RefCounted
class_name WorldSceneRenderer

const WorldData = preload("res://src/world/data/world_data.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const ProximityInteractionPrompt = preload("res://src/ui/proximity_interaction_prompt.gd")

const TERRAIN_LAYER := "TerrainTileMap"
const TERRAIN_UNDERLAY_LAYER := "TerrainUnderlay"
const PATH_UNDERLAY_LAYER := "PathUnderlay"
const WATER_UNDERLAY_LAYER := "WaterUnderlay"
const TERRAIN_FOOTPRINT_LAYER := "TerrainFootprints"
const FACILITY_LAYER := "Facilities"
const ENTITY_LAYER := "Entities"
const LANDMARK_LAYER := "Landmarks"

const FACILITY_OUTLINE_COLOR := Color("d6a75d")
const ENTRY_OUTLINE_COLOR := Color("c9d7c0")
const TELEPORT_OUTLINE_COLOR := Color("5f879b")
const REPAIRED_TELEPORT_OUTLINE_COLOR := Color("78b889")
const DUNGEON_OUTLINE_COLOR := Color("7a668e")

const ADJACENT_NORTH := 1
const ADJACENT_EAST := 2
const ADJACENT_SOUTH := 4
const ADJACENT_WEST := 8
const RIVER_BASE_SOURCE_ID := "terrain_river_water_01"
const BRIDGE_VERTICAL_SOURCE_ID := "asset_assets_tiles_terrain_bridges_bridge_vertical_32x32_png"
const BRIDGE_HORIZONTAL_SOURCE_ID := "asset_assets_tiles_terrain_bridges_bridge_horizontal_32x32_png"
const TREE_UNDERLAY_SOURCE_ID := "terrain_plains_grass_ground_01"
const GRASS_VARIANT_SOURCE_IDS := [
	"terrain_plains_grass_ground_01",
	"asset_assets_tiles_terrain_plains_grass_ground_02_32x32_png",
	"asset_assets_tiles_terrain_plains_grass_ground_03_32x32_png",
	"terrain_plains_flower_grass_01"
]
const PATH_BASE_SOURCE_ID := "asset_assets_tiles_terrain_paths_road_isolated_32x32_png"
const PATH_MASK_SOURCE_IDS := [
	"asset_assets_tiles_terrain_paths_road_isolated_32x32_png", # 0: isolated
	"asset_assets_tiles_terrain_paths_road_end_north_32x32_png", # 1: north
	"asset_assets_tiles_terrain_paths_road_end_east_32x32_png", # 2: east
	"asset_assets_tiles_terrain_paths_road_corner_ne_32x32_png", # 3: north/east
	"asset_assets_tiles_terrain_paths_road_end_south_32x32_png", # 4: south
	"asset_assets_tiles_terrain_paths_road_straight_vertical_32x32_png", # 5: north/south
	"asset_assets_tiles_terrain_paths_road_corner_se_32x32_png", # 6: east/south
	"asset_assets_tiles_terrain_paths_road_t_junction_nes_32x32_png", # 7: north/east/south
	"asset_assets_tiles_terrain_paths_road_end_west_32x32_png", # 8: west
	"asset_assets_tiles_terrain_paths_road_corner_nw_32x32_png", # 9: north/west
	"asset_assets_tiles_terrain_paths_road_straight_horizontal_32x32_png", # 10: east/west
	"asset_assets_tiles_terrain_paths_road_t_junction_new_32x32_png", # 11: north/east/west
	"asset_assets_tiles_terrain_paths_road_corner_sw_32x32_png", # 12: south/west
	"asset_assets_tiles_terrain_paths_road_t_junction_nsw_32x32_png", # 13: north/south/west
	"asset_assets_tiles_terrain_paths_road_t_junction_esw_32x32_png", # 14: east/south/west
	"asset_assets_tiles_terrain_paths_road_cross_32x32_png" # 15: all directions
]
const TREE_OVERLAY_SOURCE_IDS := {
	"terrain_tree_broadleaf_32x32": true,
	"terrain_tree_pine_32x32": true,
	"terrain_tree_round_32x32": true
}
# Indexed by N/E/S/W bitmask. The promoted river set does not include every
# dead-end cap, so one-way masks intentionally fall back to matching straights.
const RIVER_MASK_SOURCE_IDS := [
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_908_771_144x146_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_29_593_145x148_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_204_59_144x147_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_553_951_148x146_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_29_593_145x148_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_733_594_145x147_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_28_237_145x148_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_204_771_143x146_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_204_59_144x147_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_553_951_148x146_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_205_597_144x145_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_553_951_148x146_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_907_60_144x147_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_732_60_144x148_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_202_420_146x145_resize_32x32_png",
	"asset_assets_tiles_terrain_river_3128fd1e_45b5_438e_a810_c6049fc50f77_crop_29_60_145x148_resize_32x32_png"
]

var _texture_cache: Dictionary = {}
var asset_catalog := AssetCatalog.new()
var _asset_catalog_ready := false

func render(root: Node2D, renderer_input: Dictionary, owner_sources := {}, origin := Vector2.ZERO) -> Dictionary:
	if root == null:
		return {"ok": false, "error": "missing_world_visual_root"}
	if typeof(renderer_input) != TYPE_DICTIONARY or not renderer_input.get("read_only", false):
		return {"ok": false, "error": "invalid_renderer_input"}
	var manifest_result := _ensure_asset_catalog()
	if not manifest_result.ok:
		return manifest_result

	_clear_children(root)
	root.position = origin

	var tile_size := int(renderer_input.get("tile_size", RuntimeConstants.float_value("world.tile_size_pixels")))
	var rendered_counts := {}
	var terrain_underlay_layer := _add_tilemap_layer(root, TERRAIN_UNDERLAY_LAYER, -110)
	var path_underlay_layer := _add_tilemap_layer(root, PATH_UNDERLAY_LAYER, -109)
	var water_underlay_layer := _add_tilemap_layer(root, WATER_UNDERLAY_LAYER, -105)
	var terrain_layer := _add_tilemap_layer(root, TERRAIN_LAYER, -100)
	var terrain_footprint_layer := _add_layer(root, TERRAIN_FOOTPRINT_LAYER, -90)
	var facility_layer := _add_layer(root, FACILITY_LAYER, -20)
	var entity_layer := _add_layer(root, ENTITY_LAYER, -10)
	var landmark_layer := _add_layer(root, LANDMARK_LAYER, -5)

	for layer in renderer_input.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		if layer_id == "base_terrain":
			rendered_counts[layer_id] = _render_tilemap_cells(terrain_underlay_layer, terrain_footprint_layer, layer.get("cells", []), tile_size)
		elif layer_id == WorldData.LAYER_TERRAIN:
			# Keep path fill on its own layer. Replacing the base layer's TileSet here
			# would invalidate every already-written base cell (including river edges).
			_render_path_grass_underlay(path_underlay_layer, layer.get("cells", []), tile_size)
			_render_bridge_water_underlay(water_underlay_layer, layer.get("cells", []), tile_size)
			rendered_counts[layer_id] = _render_tilemap_cells(
				terrain_layer,
				terrain_footprint_layer,
				layer.get("cells", []),
				tile_size
			)
		else:
			var target := _target_layer(layer_id, facility_layer, entity_layer)
			if target == null:
				continue
			var outline_color := FACILITY_OUTLINE_COLOR if layer_id == WorldData.LAYER_FACILITIES else Color.TRANSPARENT
			rendered_counts[layer_id] = _render_footprint_cells(target, layer.get("cells", []), tile_size, owner_sources, outline_color)

	rendered_counts[LANDMARK_LAYER] = _render_landmarks(
		landmark_layer,
		renderer_input.get("required_landmarks", []),
		tile_size,
		owner_sources
	)
	return {
		"ok": true,
		"counts": rendered_counts,
		"asset_report": asset_catalog.audit_references(_collect_source_references(renderer_input, owner_sources))
	}

func _render_path_grass_underlay(tilemap_layer: TileMapLayer, cells: Array, tile_size: int) -> void:
	if tilemap_layer == null:
		return
	var path_positions: Array[Vector2i] = []
	for cell in cells:
		if String(cell.get("source_id", "")) == PATH_BASE_SOURCE_ID:
			path_positions.append(_position_from_dictionary(cell.get("position", {})))
	if path_positions.is_empty():
		return
	var path := _resource_path(TREE_UNDERLAY_SOURCE_ID)
	if path.is_empty():
		return
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_meta := _add_tileset_source(tile_set, path, tile_size)
	if not source_meta.ok:
		return
	tilemap_layer.tile_set = tile_set
	for position in path_positions:
		tilemap_layer.set_cell(position, int(source_meta.source_index), Vector2i.ZERO, 0)

func _render_bridge_water_underlay(tilemap_layer: TileMapLayer, cells: Array, tile_size: int) -> void:
	if tilemap_layer == null:
		return
	var bridge_positions: Array[Vector2i] = []
	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		if source_id == BRIDGE_VERTICAL_SOURCE_ID or source_id == BRIDGE_HORIZONTAL_SOURCE_ID:
			bridge_positions.append(_position_from_dictionary(cell.get("position", {})))
	if bridge_positions.is_empty():
		return
	# Keep the layer order as base grass -> water -> bridge sprite.
	var path := _resource_path(RIVER_BASE_SOURCE_ID)
	if path.is_empty():
		return
	var tile_set := tilemap_layer.tile_set if tilemap_layer.tile_set != null else TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_meta := _add_tileset_source(tile_set, path, tile_size)
	if not source_meta.ok:
		return
	tilemap_layer.tile_set = tile_set
	for position in bridge_positions:
		tilemap_layer.set_cell(position, int(source_meta.source_index), Vector2i.ZERO, 0)

func _render_water_grass_underlay(tilemap_layer: TileMapLayer, cells: Array, tile_size: int) -> void:
	if tilemap_layer == null:
		return
	var water_positions: Array[Vector2i] = []
	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		if _is_water_terrain_source(source_id):
			water_positions.append(_position_from_dictionary(cell.get("position", {})))
	if water_positions.is_empty():
		return
	var path := _resource_path(TREE_UNDERLAY_SOURCE_ID)
	if path.is_empty():
		return
	var tile_set := tilemap_layer.tile_set if tilemap_layer.tile_set != null else TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_meta := _add_tileset_source(tile_set, path, tile_size)
	if not source_meta.ok:
		return
	tilemap_layer.tile_set = tile_set
	for position in water_positions:
		tilemap_layer.set_cell(position, int(source_meta.source_index), Vector2i.ZERO, 0)

func _is_water_terrain_source(source_id: String) -> bool:
	var normalized := source_id.to_lower()
	return normalized.contains("water") or normalized.contains("river") or normalized.contains("stream")

func _render_tilemap_cells(tilemap_layer: TileMapLayer, footprint_layer: Node2D, cells: Array, tile_size: int) -> int:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_index_by_path := {}
	var source_meta_by_path := {}
	var terrain_index := _terrain_cell_index(cells)
	var rendered := 0

	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		var position := _position_from_dictionary(cell.get("position", {}))
		var mask := _adjacency_mask_for_cell(position, source_id, terrain_index)
		var tree_overlay_source_id := _tree_overlay_source_id(source_id)
		var render_source_id := TREE_UNDERLAY_SOURCE_ID if not tree_overlay_source_id.is_empty() else _terrain_source_for_adjacency(source_id, mask)
		if source_id == TREE_UNDERLAY_SOURCE_ID:
			render_source_id = _grass_variant_source_id(position)
		var path := _resource_path(render_source_id)
		if path.is_empty():
			continue
		if _source_is_multicell_footprint(path, tile_size):
			if _render_original_sprite(footprint_layer, path, position, tile_size):
				rendered += 1
			continue
		if not source_index_by_path.has(path):
			var meta := _add_tileset_source(tile_set, path, tile_size)
			if not meta.ok:
				continue
			source_index_by_path[path] = meta.source_index
			source_meta_by_path[path] = meta
		var source_meta: Dictionary = source_meta_by_path[path]
		var atlas_coords := _explicit_atlas_coords(cell.get("atlas_coords", {}), int(source_meta.columns), int(source_meta.rows))
		if atlas_coords == Vector2i(-1, -1):
			atlas_coords = Vector2i.ZERO if render_source_id != source_id else _atlas_coords_for_adjacency(mask, int(source_meta.columns), int(source_meta.rows))
		tilemap_layer.set_cell(position, int(source_index_by_path[path]), atlas_coords, 0)
		if not tree_overlay_source_id.is_empty():
			_render_original_sprite(footprint_layer, _resource_path(tree_overlay_source_id), position, tile_size)
		rendered += 1

	tilemap_layer.tile_set = tile_set
	return rendered

func _add_tileset_source(tile_set: TileSet, path: String, tile_size: int) -> Dictionary:
	if not (ResourceLoader.exists(path, "Texture2D") or FileAccess.file_exists(path)):
		return {"ok": false}
	var texture := _texture_cache.get(path) as Texture2D
	if texture == null:
		texture = _load_texture(path)
		if texture == null:
			return {"ok": false}
		_texture_cache[path] = texture

	var columns: int = max(1, int(texture.get_width() / tile_size))
	var rows: int = max(1, int(texture.get_height() / tile_size))
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	for y in range(rows):
		for x in range(columns):
			source.create_tile(Vector2i(x, y))
	var source_index := tile_set.add_source(source)
	return {"ok": true, "source_index": source_index, "columns": columns, "rows": rows}

func _render_footprint_cells(parent: Node2D, cells: Array, tile_size: int, owner_sources: Dictionary, outline_color := Color.TRANSPARENT) -> int:
	var rendered := 0
	var seen_owners := {}
	var owner_rotations := {}
	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		if source_id.is_empty():
			source_id = String(owner_sources.get(String(cell.get("owner_id", "")), ""))
		if source_id.is_empty():
			continue
		var owner_id := String(cell.get("owner_id", ""))
		var position := _position_from_dictionary(cell.get("position", {}))
		if not owner_id.is_empty():
			var key := "%s|%s" % [owner_id, source_id]
			if seen_owners.has(key):
				var current: Vector2i = seen_owners[key]
				seen_owners[key] = Vector2i(mini(current.x, position.x), mini(current.y, position.y))
				continue
			seen_owners[key] = position
			owner_rotations[owner_id] = float(cell.get("rotation_degrees", 0.0))
			continue
		if _render_original_sprite(parent, _resource_path(source_id), position, tile_size, outline_color):
			rendered += 1
	for key in seen_owners:
		var parts := String(key).split("|", false)
		if parts.size() < 2:
			continue
		if _render_original_sprite(parent, _resource_path(parts[1]), seen_owners[key], tile_size, outline_color, float(owner_rotations.get(parts[0], 0.0))):
			rendered += 1
	return rendered

func _render_original_sprite(parent: Node2D, path: String, position: Vector2i, tile_size: int, outline_color := Color.TRANSPARENT, rotation_degrees := 0.0) -> bool:
	if path.is_empty():
		return false
	var texture := _texture_for_path(path)
	if texture == null:
		return false
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	var footprint_size := texture.get_size()
	if is_equal_approx(absf(rotation_degrees), 90.0) or is_equal_approx(absf(rotation_degrees), 270.0):
		footprint_size = Vector2(texture.get_height(), texture.get_width())
	sprite.position = Vector2(
		position.x * tile_size + footprint_size.x * 0.5,
		position.y * tile_size + footprint_size.y * 0.5
	)
	sprite.rotation_degrees = rotation_degrees
	parent.add_child(sprite)
	if outline_color.a > 0.0:
		_add_special_outline(sprite, texture.get_size(), outline_color)
	return true

func _add_special_outline(sprite: Sprite2D, texture_size: Vector2, color: Color) -> void:
	var half_size := texture_size * 0.5
	var outline := Line2D.new()
	outline.name = "SpecialOutline"
	outline.points = PackedVector2Array([
		Vector2(-half_size.x + 1.0, -half_size.y + 1.0),
		Vector2(half_size.x - 1.0, -half_size.y + 1.0),
		Vector2(half_size.x - 1.0, half_size.y - 1.0),
		Vector2(-half_size.x + 1.0, half_size.y - 1.0)
	])
	outline.closed = true
	outline.width = 2.0
	outline.default_color = color
	outline.antialiased = false
	outline.z_index = 1
	sprite.add_child(outline)

func _texture_for_path(path: String) -> Texture2D:
	if path.is_empty() or not (ResourceLoader.exists(path, "Texture2D") or FileAccess.file_exists(path)):
		return null
	var texture := _texture_cache.get(path) as Texture2D
	if texture == null:
		texture = _load_texture(path)
		if texture == null:
			return null
		_texture_cache[path] = texture
	return texture

func _source_is_multicell_footprint(path: String, tile_size: int) -> bool:
	if _source_is_atlas_variants(path):
		return false
	var texture := _texture_for_path(path)
	return texture != null and (texture.get_width() > tile_size or texture.get_height() > tile_size)

func _source_is_atlas_variants(path: String) -> bool:
	var lower := path.to_lower()
	return "tileset" in lower or "/sheets/" in lower or "/source-atlases/" in lower

func _render_cells(parent: Node2D, cells: Array, tile_size: int, owner_sources: Dictionary) -> int:
	var rendered := 0
	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		if source_id.is_empty():
			source_id = String(owner_sources.get(String(cell.get("owner_id", "")), ""))
		if source_id.is_empty():
			continue
		var position := _position_from_dictionary(cell.get("position", {}))
		var texture := _texture_for_source(source_id, tile_size, position)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.position = Vector2(position.x * tile_size + tile_size * 0.5, position.y * tile_size + tile_size * 0.5)
		parent.add_child(sprite)
		rendered += 1
	return rendered

func _render_landmarks(parent: Node2D, landmarks: Array, tile_size: int, owner_sources: Dictionary) -> int:
	var rendered := 0
	for landmark in landmarks:
		var landmark_id := String(landmark.get("id", ""))
		var landmark_kind := String(landmark.get("kind", landmark.get("type", "")))
		var source_id := String(owner_sources.get(landmark_id, owner_sources.get(landmark_kind, "")))
		if source_id.is_empty():
			continue
		var position := _position_from_dictionary(landmark.get("position", {}))
		var repaired := String(landmark.get("teleport_state", "")) == "repaired"
		var outline_color := REPAIRED_TELEPORT_OUTLINE_COLOR if repaired and landmark_kind == WorldData.LANDMARK_TELEPORT_ZONE else _landmark_outline_color(landmark_kind)
		if _render_original_sprite(parent, _resource_path(source_id), position, tile_size, outline_color):
			if landmark_kind == WorldData.LANDMARK_CORE_DUNGEON:
				_add_interaction_prompt(parent, position, tile_size, "던전 입구", "[E] 입장")
			elif landmark_kind == WorldData.LANDMARK_RUIN:
				_add_interaction_prompt(parent, position, tile_size, "유적", "[E] 이동")
			elif landmark_kind == WorldData.LANDMARK_TELEPORT_ZONE and not repaired and String(landmark.get("teleport_state", "")) == "repairable":
				_add_interaction_prompt(parent, position, tile_size, "텔레포트", "[E] 수리")
			elif landmark_kind == WorldData.LANDMARK_TELEPORT_ZONE and repaired:
				_add_interaction_prompt(parent, position, tile_size, "텔레포트 · 수리됨", "[E] 연결지")
			rendered += 1
	return rendered

func _add_interaction_prompt(parent: Node2D, position: Vector2i, tile_size: int, title: String, action_text: String) -> void:
	var prompt := ProximityInteractionPrompt.new()
	prompt.configure(title, action_text, Vector2(position.x * tile_size - 16.0, position.y * tile_size - 52.0), Vector2(tile_size * 2 + 32.0, 44.0))
	parent.add_child(prompt)

func _landmark_outline_color(landmark_kind: String) -> Color:
	match landmark_kind:
		WorldData.LANDMARK_TELEPORT_ZONE:
			return TELEPORT_OUTLINE_COLOR
		WorldData.LANDMARK_CORE_DUNGEON:
			return DUNGEON_OUTLINE_COLOR
		WorldData.LANDMARK_RUIN:
			return Color(0.72, 0.48, 0.28, 1.0)
		WorldData.LANDMARK_ENTRY:
			return ENTRY_OUTLINE_COLOR
		_:
			return FACILITY_OUTLINE_COLOR

func _texture_for_source(source_id: String, tile_size: int, position: Vector2i) -> Texture2D:
	var path := _resource_path(source_id)
	if path.is_empty() or not (ResourceLoader.exists(path, "Texture2D") or FileAccess.file_exists(path)):
		return null
	var texture := _texture_cache.get(path) as Texture2D
	if texture == null:
		texture = _load_texture(path)
		if texture == null:
			return null
		_texture_cache[path] = texture

	if texture.get_width() <= tile_size and texture.get_height() <= tile_size:
		return texture

	var columns: int = max(1, int(texture.get_width() / tile_size))
	var rows: int = max(1, int(texture.get_height() / tile_size))
	var atlas_coords := _atlas_coords_for_position(position, columns, rows)
	var region := Rect2(
		Vector2(atlas_coords.x * tile_size, atlas_coords.y * tile_size),
		Vector2(tile_size, tile_size)
	)
	var atlas_key := "%s#%d,%d" % [path, atlas_coords.x, atlas_coords.y]
	var atlas := _texture_cache.get(atlas_key) as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = region
		_texture_cache[atlas_key] = atlas
	return atlas

func _atlas_coords_for_adjacency(mask: int, columns: int, rows: int) -> Vector2i:
	var frame_count: int = max(1, columns * rows)
	var frame_index: int = clampi(mask, 0, 15) % frame_count
	return Vector2i(frame_index % columns, int(frame_index / columns))

func _explicit_atlas_coords(value, columns: int, rows: int) -> Vector2i:
	if typeof(value) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var coords := _position_from_dictionary(value)
	if coords.x < 0 or coords.y < 0 or coords.x >= columns or coords.y >= rows:
		return Vector2i(-1, -1)
	return coords

func _terrain_source_for_adjacency(source_id: String, mask: int) -> String:
	if source_id == RIVER_BASE_SOURCE_ID:
		return String(RIVER_MASK_SOURCE_IDS[clampi(mask, 0, RIVER_MASK_SOURCE_IDS.size() - 1)])
	if source_id == PATH_BASE_SOURCE_ID:
		return String(PATH_MASK_SOURCE_IDS[clampi(mask, 0, PATH_MASK_SOURCE_IDS.size() - 1)])
	return source_id

func _grass_variant_source_id(position: Vector2i) -> String:
	var index := absi(position.x * 31 + position.y * 17) % GRASS_VARIANT_SOURCE_IDS.size()
	return String(GRASS_VARIANT_SOURCE_IDS[index])

func _tree_overlay_source_id(source_id: String) -> String:
	return source_id if TREE_OVERLAY_SOURCE_IDS.has(source_id) else ""

func _terrain_cell_index(cells: Array) -> Dictionary:
	var index := {}
	for cell in cells:
		var position := _position_from_dictionary(cell.get("position", {}))
		var source_id := String(cell.get("source_id", ""))
		if source_id.is_empty():
			continue
		index[_position_key(position)] = source_id
	return index

func _adjacency_mask_for_cell(position: Vector2i, source_id: String, terrain_index: Dictionary) -> int:
	var mask := 0
	if _same_terrain_source(position + Vector2i.UP, source_id, terrain_index):
		mask |= ADJACENT_NORTH
	if _same_terrain_source(position + Vector2i.RIGHT, source_id, terrain_index):
		mask |= ADJACENT_EAST
	if _same_terrain_source(position + Vector2i.DOWN, source_id, terrain_index):
		mask |= ADJACENT_SOUTH
	if _same_terrain_source(position + Vector2i.LEFT, source_id, terrain_index):
		mask |= ADJACENT_WEST
	return mask

func _same_terrain_source(position: Vector2i, source_id: String, terrain_index: Dictionary) -> bool:
	return String(terrain_index.get(_position_key(position), "")) == source_id

func _position_key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]

func _atlas_coords_for_position(position: Vector2i, columns: int, rows: int) -> Vector2i:
	var frame_count: int = max(1, columns * rows)
	var frame_index: int = abs(position.x * 928371 + position.y * 364479) % frame_count
	return Vector2i(frame_index % columns, int(frame_index / columns))

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _resource_path(source_id: String) -> String:
	return asset_catalog.path_for_reference(source_id) if _asset_catalog_ready else _normalize_asset_reference(source_id)

func _normalize_asset_reference(source_id: String) -> String:
	if source_id.begins_with("res://assets/"):
		return source_id
	if source_id.begins_with("assets/"):
		return "res://%s" % source_id
	return ""

func _ensure_asset_catalog() -> Dictionary:
	if _asset_catalog_ready:
		return {"ok": true}
	var result: Dictionary = asset_catalog.load_manifest()
	if result.ok:
		_asset_catalog_ready = true
	return result

func _collect_source_references(renderer_input: Dictionary, owner_sources: Dictionary) -> Array:
	var references := []
	for source in owner_sources.values():
		references.append(String(source))
	for layer in renderer_input.get("layers", []):
		for cell in layer.get("cells", []):
			if cell.has("source_id"):
				references.append(String(cell.source_id))
	for landmark in renderer_input.get("required_landmarks", []):
		var landmark_id := String(landmark.get("id", ""))
		var landmark_kind := String(landmark.get("kind", landmark.get("type", "")))
		if owner_sources.has(landmark_id):
			references.append(String(owner_sources[landmark_id]))
		elif owner_sources.has(landmark_kind):
			references.append(String(owner_sources[landmark_kind]))
	return references

func _target_layer(layer_id: String, facility_layer: Node2D, entity_layer: Node2D) -> Node2D:
	match layer_id:
		WorldData.LAYER_FACILITIES:
			return facility_layer
		WorldData.LAYER_ENTITIES:
			return entity_layer
		_:
			return null

func _add_layer(root: Node2D, layer_name: String, z: int) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.z_index = z
	root.add_child(layer)
	return layer

func _add_tilemap_layer(root: Node2D, layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = z
	root.add_child(layer)
	return layer

func _clear_children(root: Node) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func _position_from_dictionary(position: Dictionary) -> Vector2i:
	return Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
