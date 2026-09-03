extends RefCounted
class_name WorldSceneRenderer

const WorldData = preload("res://src/world/data/world_data.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")

const TERRAIN_LAYER := "TerrainTileMap"
const TERRAIN_FOOTPRINT_LAYER := "TerrainFootprints"
const FACILITY_LAYER := "Facilities"
const ENTITY_LAYER := "Entities"
const LANDMARK_LAYER := "Landmarks"

const ADJACENT_NORTH := 1
const ADJACENT_EAST := 2
const ADJACENT_SOUTH := 4
const ADJACENT_WEST := 8

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

	var tile_size := int(renderer_input.get("tile_size", 32))
	var rendered_counts := {}
	var terrain_layer := _add_tilemap_layer(root, TERRAIN_LAYER, -100)
	var terrain_footprint_layer := _add_layer(root, TERRAIN_FOOTPRINT_LAYER, -90)
	var facility_layer := _add_layer(root, FACILITY_LAYER, -20)
	var entity_layer := _add_layer(root, ENTITY_LAYER, -10)
	var landmark_layer := _add_layer(root, LANDMARK_LAYER, -5)

	for layer in renderer_input.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		if layer_id == WorldData.LAYER_TERRAIN:
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
			rendered_counts[layer_id] = _render_footprint_cells(target, layer.get("cells", []), tile_size, owner_sources)

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

func _render_tilemap_cells(tilemap_layer: TileMapLayer, footprint_layer: Node2D, cells: Array, tile_size: int) -> int:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_index_by_path := {}
	var source_meta_by_path := {}
	var terrain_index := _terrain_cell_index(cells)
	var rendered := 0

	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		var path := _resource_path(source_id)
		if path.is_empty():
			continue
		if _source_is_multicell_footprint(path, tile_size):
			if _render_original_sprite(footprint_layer, path, _position_from_dictionary(cell.get("position", {})), tile_size):
				rendered += 1
			continue
		if not source_index_by_path.has(path):
			var meta := _add_tileset_source(tile_set, path, tile_size)
			if not meta.ok:
				continue
			source_index_by_path[path] = meta.source_index
			source_meta_by_path[path] = meta
		var position := _position_from_dictionary(cell.get("position", {}))
		var source_meta: Dictionary = source_meta_by_path[path]
		var mask := _adjacency_mask_for_cell(position, source_id, terrain_index)
		var atlas_coords := _atlas_coords_for_adjacency(mask, int(source_meta.columns), int(source_meta.rows))
		tilemap_layer.set_cell(position, int(source_index_by_path[path]), atlas_coords, 0)
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

func _render_footprint_cells(parent: Node2D, cells: Array, tile_size: int, owner_sources: Dictionary) -> int:
	var rendered := 0
	var seen_owners := {}
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
			continue
		if _render_original_sprite(parent, _resource_path(source_id), position, tile_size):
			rendered += 1
	for key in seen_owners:
		var parts := String(key).split("|", false)
		if parts.size() < 2:
			continue
		if _render_original_sprite(parent, _resource_path(parts[1]), seen_owners[key], tile_size):
			rendered += 1
	return rendered

func _render_original_sprite(parent: Node2D, path: String, position: Vector2i, tile_size: int) -> bool:
	if path.is_empty():
		return false
	var texture := _texture_for_path(path)
	if texture == null:
		return false
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = Vector2(
		position.x * tile_size + float(texture.get_width()) * 0.5,
		position.y * tile_size + float(texture.get_height()) * 0.5
	)
	parent.add_child(sprite)
	return true

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
		if _render_original_sprite(parent, _resource_path(source_id), position, tile_size):
			rendered += 1
	return rendered

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
