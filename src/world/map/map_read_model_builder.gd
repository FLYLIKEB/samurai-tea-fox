extends RefCounted
class_name MapReadModelBuilder

const WorldData = preload("res://src/world/data/world_data.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
# The runtime camera uses a 640x360 logical viewport at 2x zoom over 32px
# tiles (roughly 10x6 cells). Keep one extra cell of reveal margin so the
# visible screen never ends in undiscovered fog.
const DISCOVERY_RADIUS := 6
const DEFAULT_MINIMAP_WIDTH := 11
const DEFAULT_MINIMAP_HEIGHT := 7
const MARKER_PLAYER := "player"
const MARKER_DUNGEON := "dungeon"
const MARKER_TELEPORT := "teleport"
const MARKER_LANDMARK := "landmark"

var data_version := ""

func configure(new_data_version := "") -> Dictionary:
	data_version = new_data_version
	return {"ok": true}

func build(world_source, run_state = null, player_cell := Vector2i.ZERO, options := {}) -> Dictionary:
	var world_result := _world_dictionary(world_source)
	if not world_result.ok:
		return world_result
	var world: Dictionary = world_result.world
	var bounds: Dictionary = world.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	if width <= 0 or height <= 0:
		return _fail("invalid_world_bounds", "Map read model requires positive world bounds.")
	var discovery := _discovery_cells(run_state, player_cell, int(options.get("discovery_radius", DISCOVERY_RADIUS)))
	var discovered_cells := _visible_cells(world, discovery, false)
	var minimap := _minimap(world, discovery, player_cell, int(options.get("minimap_width", DEFAULT_MINIMAP_WIDTH)), int(options.get("minimap_height", DEFAULT_MINIMAP_HEIGHT)))
	return {
		"ok": true,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"read_only": true,
		"bounds": {"width": width, "height": height},
		"player": {"position": _position_dictionary(player_cell), "marker_type": MARKER_PLAYER},
		"discovered_count": discovered_cells.size(),
		"fog_count": width * height - discovered_cells.size(),
		"cells": discovered_cells,
		"markers": _markers(world, discovery, player_cell),
		"minimap": minimap,
		"full_map_hook": {"type": "show_full_map", "command": "open_map"}
	}

static func discover_cells(existing_discovery: Dictionary, center: Vector2i, radius := DISCOVERY_RADIUS) -> Dictionary:
	var result := _dictionary_value(existing_discovery)
	var cells := _string_set(result.get("discovered_cells", []))
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			cells[_cell_key(Vector2i(x, y))] = true
	var sorted := cells.keys()
	sorted.sort()
	result["discovered_cells"] = sorted
	return result

func _world_dictionary(world_source) -> Dictionary:
	if world_source is WorldData:
		return {"ok": true, "world": world_source.to_dictionary()}
	if typeof(world_source) == TYPE_DICTIONARY:
		if world_source.has("world_data"):
			return {"ok": true, "world": _dictionary_value(world_source.world_data)}
		return {"ok": true, "world": world_source.duplicate(true)}
	return _fail("invalid_world_data", "Map read model requires WorldData or a serialized world dictionary.")

func _discovery_cells(run_state, player_cell: Vector2i, radius: int) -> Dictionary:
	var map_discovery := {}
	if run_state != null:
		if run_state is Dictionary:
			map_discovery = _dictionary_value(run_state.get("map_discovery", {}))
		elif run_state.has_method("get"):
			map_discovery = _dictionary_value(run_state.get("map_discovery"))
	var discovered := _string_set(map_discovery.get("discovered_cells", []))
	for y in range(player_cell.y - radius, player_cell.y + radius + 1):
		for x in range(player_cell.x - radius, player_cell.x + radius + 1):
			discovered[_cell_key(Vector2i(x, y))] = true
	return discovered

func _visible_cells(world: Dictionary, discovery: Dictionary, minimap_only: bool) -> Array:
	var cells := []
	for raw_cell in _array_value(world.get("cells", [])):
		var cell: Dictionary = _dictionary_value(raw_cell)
		var position := _vector_from_dictionary(cell.get("position", {}))
		if not discovery.has(_cell_key(position)):
			continue
		var terrain: Dictionary = _dictionary_value(_dictionary_value(cell.get("layers", {})).get(WorldData.LAYER_TERRAIN, {}))
		cells.append({
			"position": _position_dictionary(position),
			"terrain_id": String(terrain.get("id", "")),
			"walkable": bool(terrain.get("walkable", false)),
			"fog": false,
			"minimap": minimap_only
		})
	cells.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.position.y) == int(right.position.y):
			return int(left.position.x) < int(right.position.x)
		return int(left.position.y) < int(right.position.y)
	)
	return cells

func _markers(world: Dictionary, discovery: Dictionary, player_cell: Vector2i) -> Array:
	var markers := [{"id": "player", "marker_type": MARKER_PLAYER, "position": _position_dictionary(player_cell), "known": true}]
	for landmark_value in _array_value(world.get("required_landmarks", [])):
		var landmark := _dictionary_value(landmark_value)
		var position := _vector_from_dictionary(landmark.get("position", {}))
		if not bool(landmark.get("required", false)) and not discovery.has(_cell_key(position)):
			continue
		markers.append({
			"id": String(landmark.get("id", "")),
			"marker_type": _marker_type_for_landmark(String(landmark.get("type", landmark.get("kind", "")))),
			"landmark_type": String(landmark.get("type", landmark.get("kind", ""))),
			"position": _position_dictionary(position),
			"known": true,
			"discovered": discovery.has(_cell_key(position)),
			"metadata": _dictionary_value(landmark.get("metadata", {}))
		})
	markers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.id) < String(right.id)
	)
	return markers

func _minimap(world: Dictionary, discovery: Dictionary, player_cell: Vector2i, max_width: int, max_height: int) -> Dictionary:
	var bounds: Dictionary = world.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	max_width = clampi(max_width, 3, 21)
	max_height = clampi(max_height, 3, 15)
	var origin := Vector2i(
		clampi(player_cell.x - max_width / 2, 0, max(0, width - max_width)),
		clampi(player_cell.y - max_height / 2, 0, max(0, height - max_height))
	)
	var size := Vector2i(mini(max_width, width), mini(max_height, height))
	var cells := []
	var cell_by_key := {}
	for cell in _array_value(world.get("cells", [])):
		var normalized := _dictionary_value(cell)
		var position := _vector_from_dictionary(normalized.get("position", {}))
		cell_by_key[_cell_key(position)] = normalized
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var position := Vector2i(x, y)
			var key := _cell_key(position)
			var fog := not discovery.has(key)
			var terrain_id := ""
			if not fog and cell_by_key.has(key):
				var terrain: Dictionary = _dictionary_value(_dictionary_value(cell_by_key[key].get("layers", {})).get(WorldData.LAYER_TERRAIN, {}))
				terrain_id = String(terrain.get("id", ""))
			cells.append({"position": _position_dictionary(position), "terrain_id": terrain_id, "fog": fog})
	return {
		"origin": _position_dictionary(origin),
		"size": {"width": size.x, "height": size.y},
		"max_size": {"width": max_width, "height": max_height},
		"cell_count": cells.size(),
		"cells": cells,
		"markers": _markers_in_rect(_markers(world, discovery, player_cell), origin, size)
	}

func _markers_in_rect(markers: Array, origin: Vector2i, size: Vector2i) -> Array:
	var visible := []
	for marker in markers:
		var position := _vector_from_dictionary(_dictionary_value(marker).get("position", {}))
		if position.x >= origin.x and position.y >= origin.y and position.x < origin.x + size.x and position.y < origin.y + size.y:
			visible.append(_dictionary_value(marker))
	return visible

func _marker_type_for_landmark(landmark_type: String) -> String:
	match landmark_type:
		WorldData.LANDMARK_CORE_DUNGEON:
			return MARKER_DUNGEON
		WorldData.LANDMARK_TELEPORT_ZONE:
			return MARKER_TELEPORT
		_:
			return MARKER_LANDMARK

static func _string_set(value) -> Dictionary:
	var result := {}
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			if typeof(entry) == TYPE_DICTIONARY:
				result[_cell_key(_vector_from_dictionary(entry))] = true
			else:
				result[String(entry)] = true
	return result

static func _cell_key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]

static func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

static func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
