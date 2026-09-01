extends RefCounted
class_name WorldData

const LAYER_TERRAIN := "terrain"
const LAYER_FACILITIES := "facilities"
const LAYER_ENTITIES := "entities"
const LAYER_INTERACTABLES := "interactables"

const LANDMARK_ENTRY := "entry"
const LANDMARK_CORE_DUNGEON := "core_dungeon"
const LANDMARK_TELEPORT_ZONE := "teleport_zone"

const REQUIRED_LANDMARK_TYPES := [
	LANDMARK_ENTRY,
	LANDMARK_CORE_DUNGEON,
	LANDMARK_TELEPORT_ZONE
]

var width := 0
var height := 0
var tile_size := 32
var default_terrain_id := "ground"

var _cells: Dictionary = {}
var _reservations: Dictionary = {}
var _landmarks: Array = []

func _init(map_width := 0, map_height := 0, terrain_id := "ground", default_walkable := true) -> void:
	if map_width > 0 and map_height > 0:
		setup(map_width, map_height, terrain_id, default_walkable)

func setup(map_width: int, map_height: int, terrain_id := "ground", default_walkable := true) -> void:
	width = max(0, map_width)
	height = max(0, map_height)
	default_terrain_id = terrain_id
	_cells.clear()
	_reservations.clear()
	_landmarks.clear()

	for y in range(height):
		for x in range(width):
			var position := Vector2i(x, y)
			_cells[_key(position)] = _new_cell(position, terrain_id, default_walkable)

func set_terrain(position: Vector2i, terrain_id: String, walkable: bool, render_id := "") -> bool:
	if not contains(position):
		return false
	var cell := _cell(position)
	cell.layers[LAYER_TERRAIN] = {
		"id": terrain_id,
		"render_id": render_id if render_id != "" else terrain_id,
		"walkable": walkable
	}
	return true

func contains(position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < width and position.y < height

func is_walkable(position: Vector2i) -> bool:
	if not contains(position):
		return false
	var cell := _cell(position)
	return bool(cell.layers[LAYER_TERRAIN].walkable) and cell.layers[LAYER_ENTITIES].is_empty() and cell.layers[LAYER_FACILITIES].is_empty()

func is_occupied(position: Vector2i) -> bool:
	if not contains(position):
		return false
	var cell := _cell(position)
	return not cell.layers[LAYER_ENTITIES].is_empty() or not cell.layers[LAYER_FACILITIES].is_empty()

func get_occupants(position: Vector2i) -> Array:
	if not contains(position):
		return []
	var cell := _cell(position)
	var occupants := []
	occupants.append_array(cell.layers[LAYER_FACILITIES])
	occupants.append_array(cell.layers[LAYER_ENTITIES])
	return occupants

func get_interactables(position: Vector2i) -> Array:
	if not contains(position):
		return []
	return _cell(position).layers[LAYER_INTERACTABLES].duplicate(true)

func get_reservation(owner_id: String) -> Dictionary:
	return _reservations.get(owner_id, {}).duplicate(true)

func can_reserve_footprint(origin: Vector2i, size: Vector2i) -> bool:
	if not _is_valid_footprint_size(size):
		return false
	return _first_blocking_cell(origin, size) == Vector2i(-1, -1)

func reserve_entity(owner_id: String, origin: Vector2i, size := Vector2i.ONE, interactable := false, metadata := {}) -> Dictionary:
	return reserve_footprint(owner_id, "entity", origin, size, LAYER_ENTITIES, interactable, metadata)

func reserve_facility(owner_id: String, origin: Vector2i, size := Vector2i.ONE, interactable := true, metadata := {}) -> Dictionary:
	return reserve_footprint(owner_id, "facility", origin, size, LAYER_FACILITIES, interactable, metadata)

func reserve_footprint(owner_id: String, kind: String, origin: Vector2i, size: Vector2i, layer: String, interactable := false, metadata := {}) -> Dictionary:
	if owner_id == "":
		return {"ok": false, "reason": "missing_owner_id"}
	if _reservations.has(owner_id):
		return {"ok": false, "reason": "owner_already_reserved"}
	if not _is_valid_footprint_size(size):
		return {"ok": false, "reason": "invalid_size"}
	if layer != LAYER_ENTITIES and layer != LAYER_FACILITIES:
		return {"ok": false, "reason": "invalid_layer"}

	var blocked := _first_blocking_cell(origin, size)
	if blocked != Vector2i(-1, -1):
		return {"ok": false, "reason": "blocked", "position": _position_dictionary(blocked)}

	var cells := _footprint_cells(origin, size)
	var reservation := {
		"owner_id": owner_id,
		"kind": kind,
		"origin": _position_dictionary(origin),
		"size": {"x": size.x, "y": size.y},
		"layer": layer,
		"interactable": interactable,
		"metadata": metadata.duplicate(true),
		"cells": []
	}

	for position in cells:
		var cell := _cell(position)
		cell.layers[layer].append(owner_id)
		reservation.cells.append(_position_dictionary(position))
		if interactable:
			cell.layers[LAYER_INTERACTABLES].append(owner_id)

	_reservations[owner_id] = reservation
	return {"ok": true, "reservation": reservation.duplicate(true)}

func release_footprint(owner_id: String) -> bool:
	if not _reservations.has(owner_id):
		return false
	var reservation: Dictionary = _reservations[owner_id]
	for cell_position in reservation.cells:
		var position := _vector_from_dictionary(cell_position)
		if not contains(position):
			continue
		var cell := _cell(position)
		cell.layers[reservation.layer].erase(owner_id)
		cell.layers[LAYER_INTERACTABLES].erase(owner_id)
	_reservations.erase(owner_id)
	return true

func add_required_landmark(landmark_type: String, landmark_id: String, position: Vector2i, metadata := {}) -> Dictionary:
	if not REQUIRED_LANDMARK_TYPES.has(landmark_type):
		return {"ok": false, "reason": "invalid_landmark_type"}
	if landmark_id == "":
		return {"ok": false, "reason": "missing_landmark_id"}
	if not contains(position):
		return {"ok": false, "reason": "out_of_bounds"}

	_landmarks.append({
		"id": landmark_id,
		"kind": landmark_type,
		"type": landmark_type,
		"position": _position_dictionary(position),
		"required": true,
		"metadata": metadata.duplicate(true)
	})
	return {"ok": true}

func get_required_landmarks() -> Array:
	return _landmarks.duplicate(true)

func to_dictionary() -> Dictionary:
	return {
		"schema_version": 1,
		"bounds": {"width": width, "height": height},
		"tile_size": tile_size,
		"layers": [LAYER_TERRAIN, LAYER_FACILITIES, LAYER_ENTITIES, LAYER_INTERACTABLES],
		"cells": _serialized_cells(),
		"reservations": _serialized_reservations(),
		"required_landmarks": get_required_landmarks()
	}

static func from_dictionary(data: Dictionary):
	var bounds: Dictionary = data.get("bounds", {})
	var world_script = load("res://src/world/data/world_data.gd")
	var world_data = world_script.new(int(bounds.get("width", 0)), int(bounds.get("height", 0)))
	world_data.tile_size = int(data.get("tile_size", 32))
	world_data._landmarks = data.get("required_landmarks", []).duplicate(true)

	for serialized_cell in data.get("cells", []):
		var position := _static_vector_from_dictionary(serialized_cell.get("position", {}))
		if world_data.contains(position):
			world_data._cells[world_data._key(position)] = serialized_cell.duplicate(true)

	for reservation in data.get("reservations", []):
		var owner_id := String(reservation.get("owner_id", ""))
		if owner_id != "":
			world_data._reservations[owner_id] = reservation.duplicate(true)

	return world_data

func _first_blocking_cell(origin: Vector2i, size: Vector2i) -> Vector2i:
	for position in _footprint_cells(origin, size):
		if not contains(position):
			return position
		if is_occupied(position):
			return position
	return Vector2i(-1, -1)

func _is_valid_footprint_size(size: Vector2i) -> bool:
	return size.x > 0 and size.y > 0

func _footprint_cells(origin: Vector2i, size: Vector2i) -> Array:
	var cells := []
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			cells.append(Vector2i(x, y))
	return cells

func _serialized_cells() -> Array:
	var serialized := []
	for y in range(height):
		for x in range(width):
			serialized.append(_cell(Vector2i(x, y)).duplicate(true))
	return serialized

func _serialized_reservations() -> Array:
	var serialized := []
	var owner_ids := _reservations.keys()
	owner_ids.sort()
	for owner_id in owner_ids:
		serialized.append(_reservations[owner_id].duplicate(true))
	return serialized

func _new_cell(position: Vector2i, terrain_id: String, walkable: bool) -> Dictionary:
	return {
		"position": _position_dictionary(position),
		"layers": {
			LAYER_TERRAIN: {
				"id": terrain_id,
				"render_id": terrain_id,
				"walkable": walkable
			},
			LAYER_FACILITIES: [],
			LAYER_ENTITIES: [],
			LAYER_INTERACTABLES: []
		}
	}

func _cell(position: Vector2i) -> Dictionary:
	return _cells[_key(position)]

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]

func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return _static_vector_from_dictionary(data)

static func _static_vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
