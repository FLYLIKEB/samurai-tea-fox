extends RefCounted
class_name ConnectivityValidator

const WorldData = preload("res://src/world/data/world_data.gd")

func validate(world: Dictionary) -> Dictionary:
	if world.has("world_data"):
		return validate_world_data(world.world_data)
	if world.has("cells") and world.has("bounds"):
		return validate_world_data(world)

	var required_landmarks := []
	for landmark in world.get("landmarks", []):
		if landmark.get("required", false):
			required_landmarks.append(landmark.id)

	return {
		"valid": not required_landmarks.is_empty(),
		"reachable_required_landmarks": required_landmarks,
		"note": "Initial scaffold validates required landmark presence. Tile connectivity checks belong to the TileMap renderer slice."
	}

func validate_world_data(world_data: Dictionary) -> Dictionary:
	var entry := _entry_landmark(world_data)
	var required_landmarks: Array = world_data.get("required_landmarks", [])
	if entry.is_empty():
		return {
			"valid": false,
			"entry_landmark_id": "",
			"required_landmark_ids": _landmark_ids(required_landmarks),
			"reachable_required_landmarks": [],
			"unreachable_required_landmarks": _landmark_ids(required_landmarks),
			"reason": "missing_entry"
		}

	var reachable := _reachable_cells(world_data, _vector_from_dictionary(entry.position), _cell_index(world_data))
	var reachable_landmarks := []
	var unreachable_landmarks := []
	for landmark in required_landmarks:
		var position := _vector_from_dictionary(landmark.get("position", {}))
		if reachable.has(_key(position)):
			reachable_landmarks.append(landmark.id)
		else:
			unreachable_landmarks.append(landmark.id)

	return {
		"valid": unreachable_landmarks.is_empty() and not required_landmarks.is_empty(),
		"entry_landmark_id": entry.id,
		"required_landmark_ids": _landmark_ids(required_landmarks),
		"reachable_required_landmarks": reachable_landmarks,
		"unreachable_required_landmarks": unreachable_landmarks
	}

func reachable_cell_keys_from_entry(world_data: Dictionary) -> Dictionary:
	var entry := _entry_landmark(world_data)
	if entry.is_empty():
		return {}
	return _reachable_cells(world_data, _vector_from_dictionary(entry.position), _cell_index(world_data))

func validate_access_points(world_data: Dictionary, access_points: Array) -> Dictionary:
	var reachable := reachable_cell_keys_from_entry(world_data)
	var unreachable := []
	for access_point in access_points:
		var position := _vector_from_dictionary(access_point)
		if not reachable.has(_key(position)):
			unreachable.append(access_point.duplicate(true))
	return {
		"valid": unreachable.is_empty(),
		"reachable_access_points": access_points.size() - unreachable.size(),
		"unreachable_access_points": unreachable
	}

func _entry_landmark(world_data: Dictionary) -> Dictionary:
	for landmark in world_data.get("required_landmarks", []):
		if landmark.get("kind", landmark.get("type", "")) == WorldData.LANDMARK_ENTRY:
			return landmark
	return {}

func _reachable_cells(world_data: Dictionary, start: Vector2i, cells_by_position: Dictionary) -> Dictionary:
	var reachable := {}
	if not _is_walkable(world_data, start, cells_by_position):
		return reachable

	var queue := [start]
	reachable[_key(start)] = true
	var index := 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next_position: Vector2i = current + offset
			var key := _key(next_position)
			if reachable.has(key) or not _is_walkable(world_data, next_position, cells_by_position):
				continue
			reachable[key] = true
			queue.append(next_position)
	return reachable

func _is_walkable(world_data: Dictionary, position: Vector2i, cells_by_position: Dictionary) -> bool:
	var bounds: Dictionary = world_data.get("bounds", {})
	if position.x < 0 or position.y < 0 or position.x >= int(bounds.get("width", 0)) or position.y >= int(bounds.get("height", 0)):
		return false
	var cell: Dictionary = cells_by_position.get(_key(position), {})
	if cell.is_empty():
		return false
	var layers: Dictionary = cell.get("layers", {})
	var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
	return bool(terrain.get("walkable", false)) and layers.get(WorldData.LAYER_ENTITIES, []).is_empty() and layers.get(WorldData.LAYER_FACILITIES, []).is_empty()

func _cell_index(world_data: Dictionary) -> Dictionary:
	var cells_by_position := {}
	for cell in world_data.get("cells", []):
		var cell_position := _vector_from_dictionary(cell.get("position", {}))
		cells_by_position[_key(cell_position)] = cell
	return cells_by_position

func _landmark_ids(landmarks: Array) -> Array:
	var ids := []
	for landmark in landmarks:
		ids.append(landmark.get("id", ""))
	return ids

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]
