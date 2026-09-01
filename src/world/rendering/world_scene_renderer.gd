extends RefCounted
class_name WorldSceneRenderer

const WorldData = preload("res://src/world/data/world_data.gd")

const TERRAIN_LAYER := "TerrainTileMap"
const FACILITY_LAYER := "Facilities"
const ENTITY_LAYER := "Entities"
const LANDMARK_LAYER := "Landmarks"

var _texture_cache: Dictionary = {}

func render(root: Node2D, renderer_input: Dictionary, owner_sources := {}, origin := Vector2.ZERO) -> Dictionary:
	if root == null:
		return {"ok": false, "error": "missing_world_visual_root"}
	if typeof(renderer_input) != TYPE_DICTIONARY or not renderer_input.get("read_only", false):
		return {"ok": false, "error": "invalid_renderer_input"}

	_clear_children(root)
	root.position = origin

	var tile_size := int(renderer_input.get("tile_size", 32))
	var rendered_counts := {}
	var terrain_layer := _add_tilemap_layer(root, TERRAIN_LAYER, -100)
	var facility_layer := _add_layer(root, FACILITY_LAYER, -20)
	var entity_layer := _add_layer(root, ENTITY_LAYER, -10)
	var landmark_layer := _add_layer(root, LANDMARK_LAYER, -5)

	for layer in renderer_input.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		if layer_id == WorldData.LAYER_TERRAIN:
			rendered_counts[layer_id] = _render_tilemap_cells(terrain_layer, layer.get("cells", []), tile_size)
		else:
			var target := _target_layer(layer_id, facility_layer, entity_layer)
			if target == null:
				continue
			rendered_counts[layer_id] = _render_cells(target, layer.get("cells", []), tile_size, owner_sources)

	rendered_counts[LANDMARK_LAYER] = _render_landmarks(
		landmark_layer,
		renderer_input.get("required_landmarks", []),
		tile_size,
		owner_sources
	)
	return {"ok": true, "counts": rendered_counts}

func _render_tilemap_cells(tilemap_layer: TileMapLayer, cells: Array, tile_size: int) -> int:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	var source_index_by_path := {}
	var source_meta_by_path := {}
	var rendered := 0

	for cell in cells:
		var source_id := String(cell.get("source_id", ""))
		var path := _resource_path(source_id)
		if path.is_empty():
			continue
		if not source_index_by_path.has(path):
			var meta := _add_tileset_source(tile_set, path, tile_size)
			if not meta.ok:
				continue
			source_index_by_path[path] = meta.source_index
			source_meta_by_path[path] = meta
		var position := _position_from_dictionary(cell.get("position", {}))
		var source_meta: Dictionary = source_meta_by_path[path]
		var atlas_coords := _atlas_coords_for_position(position, int(source_meta.columns), int(source_meta.rows))
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
	if source_id.begins_with("res://"):
		return source_id
	if source_id.begins_with("assets/"):
		return "res://%s" % source_id
	return ""

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
