extends RefCounted

const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const ADJACENT_OFFSETS := [
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP
]
const LARGE_HOUSE_DUNGEON_OWNER_IDS := [
	"large_fenced_house",
	"large_house_fence_nw",
	"large_house_fence_ne",
	"large_house_fence_sw",
	"large_house_fence_se",
	"large_house_fence_n",
	"large_house_fence_s",
	"large_house_fence_w",
	"large_house_fence_e"
]

func cells_are_adjacent(first: Vector2i, second: Vector2i) -> bool:
	var offset := second - first
	return absi(offset.x) + absi(offset.y) <= 1

func nearest_walkable_adjacent_cell(world_data, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	var best_cell := target_cell
	var best_distance := 1 << 30
	for offset in ADJACENT_OFFSETS:
		var candidate: Vector2i = target_cell + offset
		if world_data == null or not world_data.contains(candidate) or not world_data.is_walkable(candidate):
			continue
		if is_landmark_footprint_cell(world_data, candidate):
			continue
		var distance := _manhattan_distance(candidate, player_cell)
		if distance < best_distance:
			best_cell = candidate
			best_distance = distance
	return best_cell

func nearest_walkable_adjacent_cell_for_target(world_data, target_id: String, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	var target_cells := target_footprint_cells(world_data, target_id, target_cell)
	var target_cell_lookup := {}
	for footprint_cell in target_cells:
		target_cell_lookup[_cell_key(footprint_cell)] = true
	var best_cell := target_cell
	var best_distance := 1 << 30
	for footprint_cell in target_cells:
		for offset in ADJACENT_OFFSETS:
			var candidate: Vector2i = footprint_cell + offset
			if target_cell_lookup.has(_cell_key(candidate)):
				continue
			if world_data == null or not world_data.contains(candidate) or not world_data.is_walkable(candidate):
				continue
			var distance := _manhattan_distance(candidate, player_cell)
			if distance < best_distance:
				best_cell = candidate
				best_distance = distance
	return best_cell

func interaction_candidate_cells(origin_cell: Vector2i, forward: Vector2i = Vector2i.ZERO) -> Array:
	var candidates := [origin_cell]
	if forward != Vector2i.ZERO:
		candidates.append(origin_cell + forward)
	for adjacent in ADJACENT_OFFSETS:
		var cell: Vector2i = origin_cell + adjacent
		if not candidates.has(cell):
			candidates.append(cell)
	return candidates

func pointer_candidate_cells(clicked_cell: Vector2i) -> Array:
	var cells := [clicked_cell]
	for y in range(-2, 3):
		for x in range(-2, 3):
			if x == 0 and y == 0 or abs(x) + abs(y) > 2:
				continue
			cells.append(clicked_cell + Vector2i(x, y))
	return cells

func player_can_interact_with_target(world_data, in_dungeon_map: bool, player_cell: Vector2i, target_id: String, target_cell: Vector2i) -> bool:
	for footprint_cell in target_footprint_cells(world_data, target_id, target_cell):
		if cells_are_adjacent(player_cell, footprint_cell):
			return true
	return false

func target_footprint_cells(world_data, target_id: String, fallback_cell: Vector2i) -> Array:
	if is_large_house_dungeon_target(target_id):
		var compound_cells := []
		for owner_id in LARGE_HOUSE_DUNGEON_OWNER_IDS:
			compound_cells.append_array(reservation_cells_for_owner(world_data, owner_id))
		if not compound_cells.is_empty():
			return unique_cells(compound_cells)
	return [fallback_cell]

func reservation_cells_for_owner(world_data, owner_id: String) -> Array:
	if world_data == null:
		return []
	var reservation: Dictionary = world_data.get_reservation(owner_id)
	var cells := []
	for cell_value in reservation.get("cells", []):
		cells.append(_vector_from_dictionary(cell_value))
	return cells

func unique_cells(cells: Array) -> Array:
	var seen := {}
	var unique := []
	for cell in cells:
		var key := _cell_key(cell)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(cell)
	return unique

func acquisition_target_near_cell(world_data, in_dungeon_map: bool, origin_cell: Vector2i, forward: Vector2i, is_available_acquisition_target: Callable) -> Dictionary:
	for cell in interaction_candidate_cells(origin_cell, forward):
		var target_id := interaction_target_id_for_cell(world_data, in_dungeon_map, cell, is_available_acquisition_target)
		if not target_id.is_empty() and is_available_acquisition_target.call(target_id):
			return {"target_id": target_id, "cell": cell}
	return {}

func dungeon_ore_target_near_cell(in_dungeon_map: bool, dungeon_resources: Array, acquisition_service, origin_cell: Vector2i, radius: int) -> Dictionary:
	if not in_dungeon_map:
		return {}
	var best := {}
	var best_distance := 1 << 30
	for node in dungeon_resources:
		var target_id := String(node.get("id", ""))
		var cell := _vector_from_dictionary(node.get("position", {}))
		var distance := _manhattan_distance(cell, origin_cell)
		if distance > radius or distance >= best_distance:
			continue
		var gatherable: Dictionary = acquisition_service.gatherable_for(target_id) if acquisition_service != null else {}
		if not gatherable.is_empty() and bool(gatherable.get("depleted", false)):
			continue
		best = {"target_id": target_id, "cell": cell}
		best_distance = distance
	return best

func dungeon_interaction_target_near_cell(world_data, in_dungeon_map: bool, origin_cell: Vector2i, forward: Vector2i) -> Dictionary:
	for cell in interaction_candidate_cells(origin_cell, forward):
		var target_id := dungeon_interaction_target_id_for_cell(world_data, in_dungeon_map, cell)
		if not target_id.is_empty():
			return {"target_id": target_id, "cell": cell}
	for y in range(origin_cell.y - 2, origin_cell.y + 3):
		for x in range(origin_cell.x - 2, origin_cell.x + 3):
			if abs(x - origin_cell.x) + abs(y - origin_cell.y) > 2:
				continue
			var cell := Vector2i(x, y)
			var target_id := dungeon_interaction_target_id_for_cell(world_data, in_dungeon_map, cell)
			if not target_id.is_empty():
				return {"target_id": target_id, "cell": cell}
	return {}

func interaction_target_id_for_cell(world_data, in_dungeon_map: bool, cell: Vector2i, is_available_acquisition_target: Callable) -> String:
	if world_data == null or not world_data.contains(cell):
		return ""
	var dungeon_reservation_id := dungeon_reservation_target_id_for_cell(world_data, cell)
	if not dungeon_reservation_id.is_empty():
		return dungeon_reservation_id
	for target_id_value in world_data.get_interactables(cell):
		var target_id := String(target_id_value)
		if is_landmark_target(in_dungeon_map, target_id):
			return target_id
		if is_available_acquisition_target.call(target_id):
			return target_id
	var landmark_id := landmark_target_id_for_cell(world_data, cell)
	if not landmark_id.is_empty():
		return landmark_id
	return ""

func dungeon_interaction_target_id_for_cell(world_data, in_dungeon_map: bool, cell: Vector2i) -> String:
	if world_data == null or not world_data.contains(cell):
		return ""
	var dungeon_reservation_id := dungeon_reservation_target_id_for_cell(world_data, cell)
	if not dungeon_reservation_id.is_empty():
		return dungeon_reservation_id
	for target_id_value in world_data.get_interactables(cell):
		var target_id := String(target_id_value)
		if is_core_dungeon_target(target_id):
			return target_id
	var landmark_id := landmark_target_id_for_cell(world_data, cell)
	if in_dungeon_map and landmark_id == WorldData.LANDMARK_ENTRY:
		return "dungeon_entry"
	if is_core_dungeon_target(landmark_id):
		return landmark_id
	return ""

func dungeon_reservation_target_id_for_cell(world_data, cell: Vector2i) -> String:
	if world_data == null or not world_data.contains(cell):
		return ""
	for owner_id_value in world_data.get_occupants(cell):
		var owner_id := String(owner_id_value)
		if is_core_dungeon_target(owner_id):
			return owner_id
	return ""

func landmark_target_id_for_cell(world_data, cell: Vector2i) -> String:
	if world_data == null:
		return ""
	for landmark in world_data.get_required_landmarks():
		var origin := _vector_from_dictionary(landmark.get("position", {}))
		var size := Vector2i(2, 2) if String(landmark.get("kind", landmark.get("type", ""))) == WorldData.LANDMARK_CORE_DUNGEON else Vector2i.ONE
		if cell.x >= origin.x and cell.y >= origin.y and cell.x < origin.x + size.x and cell.y < origin.y + size.y:
			return String(landmark.get("id", ""))
	return ""

func is_landmark_footprint_cell(world_data, cell: Vector2i) -> bool:
	return not landmark_target_id_for_cell(world_data, cell).is_empty()

func landmark_target_near_world_position(
		world_data,
		world_position: Vector2,
		tile_size: float,
		world_origin: Vector2,
		max_distance := -1.0
) -> Dictionary:
	if world_data == null:
		return {}
	var distance_limit := tile_size * 1.6 if max_distance < 0.0 else max_distance
	for landmark in world_data.get_required_landmarks():
		var kind := String(landmark.get("kind", landmark.get("type", "")))
		if kind not in [WorldData.LANDMARK_CORE_DUNGEON, WorldData.LANDMARK_BOSS_ANCHOR, WorldData.LANDMARK_TELEPORT_ZONE]:
			continue
		var cell := _vector_from_dictionary(landmark.get("position", {}))
		var center := world_origin + Vector2(
			cell.x * tile_size + tile_size,
			cell.y * tile_size + tile_size
		)
		if world_position.distance_to(center) <= distance_limit:
			return {"target_id": String(landmark.get("id", "")), "cell": cell}
	return {}

func large_house_target_near_world_position(
		generated_world: Dictionary,
		world_position: Vector2,
		tile_size: float,
		world_origin: Vector2,
		max_distance := -1.0
) -> Dictionary:
	var house: Dictionary = generated_world.get("large_house", {})
	if house.is_empty():
		return {}
	var origin := _vector_from_dictionary(house.get("position", {}))
	var center := world_origin + Vector2((origin.x + 1.0) * tile_size, (origin.y + 1.0) * tile_size)
	var distance_limit := tile_size * 2.0 if max_distance < 0.0 else max_distance
	if world_position.distance_to(center) <= distance_limit:
		return {"target_id": WorldGenerator.LARGE_HOUSE_ID, "cell": origin}
	return {}

func is_landmark_target(in_dungeon_map: bool, target_id: String) -> bool:
	return (in_dungeon_map and target_id == "dungeon_entry") \
			or is_core_dungeon_target(target_id) \
			or target_id.begins_with("%s_" % WorldData.LANDMARK_BOSS_ANCHOR) \
			or target_id.begins_with("%s_" % WorldData.LANDMARK_RUIN) \
			or target_id.begins_with("%s_" % WorldData.LANDMARK_TELEPORT_ZONE)

func is_core_dungeon_target(target_id: String) -> bool:
	return target_id.begins_with("%s_" % WorldData.LANDMARK_CORE_DUNGEON) \
		or is_large_house_dungeon_target(target_id)

func is_large_house_dungeon_target(target_id: String) -> bool:
	return target_id == WorldGenerator.LARGE_HOUSE_ID \
		or target_id.begins_with("large_house_fence_")

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _manhattan_distance(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)
