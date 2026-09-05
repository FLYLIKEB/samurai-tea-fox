extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")

const ROUTE_OFFSETS := [
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP
]

var has_pointer_move_target := false
var pointer_move_target_world := Vector2.ZERO
var pointer_move_route: Array = []
var pending_pointer_interaction_target_id := ""
var pending_pointer_interaction_cell := Vector2i.ZERO

func begin_route(
		world_data,
		from_cell: Vector2i,
		destination_cell: Vector2i,
		target_id: String,
		target_cell: Vector2i,
		target_footprint_cells: Array,
		world_position_for_cell_center: Callable
) -> Dictionary:
	var route := find_walkable_route(world_data, from_cell, destination_cell, target_footprint_cells)
	if route.is_empty():
		clear()
		return {"ok": false, "route": []}
	_apply_route(route, target_id, target_cell, world_position_for_cell_center)
	return {"ok": true, "route": route.duplicate()}

func find_walkable_route(world_data, from_cell: Vector2i, destination_cell: Vector2i, target_footprint_cells: Array) -> Array:
	if from_cell == destination_cell:
		return [destination_cell]
	if world_data == null:
		return []
	var blocked := {}
	for cell in target_footprint_cells:
		blocked[_cell_key(Vector2i(cell))] = true
	blocked.erase(_cell_key(destination_cell))
	var queue: Array = [from_cell]
	var previous := {_cell_key(from_cell): ""}
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for offset in ROUTE_OFFSETS:
			var next: Vector2i = current + offset
			var key := _cell_key(next)
			if previous.has(key) or blocked.has(key):
				continue
			if not world_data.contains(next) or not world_data.is_walkable(next):
				continue
			previous[key] = _cell_key(current)
			queue.append(next)
			if next == destination_cell:
				return _reconstruct_route(previous, _cell_key(from_cell), key)
	return []

func submit_direct_movement(target_world_position: Vector2) -> void:
	pointer_move_target_world = target_world_position
	has_pointer_move_target = true

func movement_command(
		player_position: Vector2,
		stop_distance_pixels: float,
		world_position_for_cell_center: Callable,
		complete_pending_interaction: Callable
) -> GameCommand:
	if not has_pointer_move_target:
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	var delta: Vector2 = pointer_move_target_world - player_position
	if delta.length() <= stop_distance_pixels:
		if not pointer_move_route.is_empty():
			pointer_move_route.pop_front()
			if not pointer_move_route.is_empty():
				pointer_move_target_world = world_position_for_cell_center.call(Vector2i(pointer_move_route[0]))
				return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
		var target_id := pending_pointer_interaction_target_id
		var target_cell := pending_pointer_interaction_cell
		clear()
		complete_pending_interaction.call(target_id, target_cell)
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	var direction := Vector2i(
		0 if absf(delta.x) <= stop_distance_pixels else int(signf(delta.x)),
		0 if absf(delta.y) <= stop_distance_pixels else int(signf(delta.y))
	)
	if direction == Vector2i.ZERO:
		clear()
	return GameCommand.new(GameCommand.Type.MOVE, direction)

func clear() -> void:
	has_pointer_move_target = false
	pointer_move_target_world = Vector2.ZERO
	pointer_move_route.clear()
	pending_pointer_interaction_target_id = ""
	pending_pointer_interaction_cell = Vector2i.ZERO

func _apply_route(route: Array, target_id: String, target_cell: Vector2i, world_position_for_cell_center: Callable) -> void:
	pointer_move_route = route.duplicate()
	pointer_move_target_world = world_position_for_cell_center.call(Vector2i(route[0]))
	has_pointer_move_target = true
	pending_pointer_interaction_target_id = target_id
	pending_pointer_interaction_cell = target_cell

func _reconstruct_route(previous: Dictionary, from_key: String, destination_key: String) -> Array:
	var route: Array = []
	var cursor := destination_key
	while cursor != from_key:
		var parts := cursor.split(",")
		route.push_front(Vector2i(int(parts[0]), int(parts[1])))
		cursor = String(previous[cursor])
	return route

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
