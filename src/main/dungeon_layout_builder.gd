extends RefCounted
class_name DungeonLayoutBuilder

const WorldData = preload("res://src/world/data/world_data.gd")

const WIDTH := 12
const HEIGHT := 9
const ENTRY_CELL := Vector2i(1, 1)
const TERRAIN_SOURCE_ID := "terrain_plains_grass_ground_01"
const FLOOR_TERRAIN_ID := "dungeon_floor"
const WALL_TERRAIN_ID := "dungeon_wall"
const GATHERABLE_KIND := "gatherable"
const IRON_SOURCE_ID := "asset_assets_sprites_objects_mining_iron_ore_32x32_png"
const STONE_SOURCE_ID := "small_rock_resource"
const BOSS_OWNER_ID := "dungeon_boss"
const MAX_RESOURCE_COUNT := 18
const FLOOR_ATLAS_COORDS := [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)
]
const ENEMY_SPECS := [
	{"id": "dungeon_enemy_0", "cell": Vector2i(7, 2)},
	{"id": "dungeon_enemy_1", "cell": Vector2i(9, 5)},
	{"id": "dungeon_enemy_2", "cell": Vector2i(5, 7)},
	{"id": BOSS_OWNER_ID, "cell": Vector2i(10, 7)}
]

func build(definition: Dictionary, node_kind_resolver := Callable()) -> Dictionary:
	var layout := WorldData.new(WIDTH, HEIGHT, TERRAIN_SOURCE_ID, true)
	layout.add_required_landmark(WorldData.LANDMARK_ENTRY, "dungeon_entry", ENTRY_CELL, {"dungeon_id": String(definition.get("id", ""))})
	_apply_terrain(layout)
	var resources := _reserve_resources(layout, node_kind_resolver)
	_reserve_enemies(layout)
	return {
		"ok": true,
		"layout": layout,
		"resources": resources,
		"enemy_specs": ENEMY_SPECS.duplicate(true)
	}

func atlas_coords_for_cell(cell: Vector2i, bounds: Vector2i) -> Vector2i:
	if cell.y == 0:
		return Vector2i(cell.x % 8, 1)
	if cell.y == bounds.y - 1:
		return Vector2i(cell.x % 8, 4)
	if cell.x == 0:
		return Vector2i(0, 2 + cell.y % 2)
	if cell.x == bounds.x - 1:
		return Vector2i(7, 2 + cell.y % 2)
	var variant_index := absi(cell.x * 31 + cell.y * 17 + cell.x * cell.y * 7) % FLOOR_ATLAS_COORDS.size()
	return FLOOR_ATLAS_COORDS[variant_index]

func cell_is_blocked(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.y == 0 or cell.x == WIDTH - 1 or cell.y == HEIGHT - 1:
		return cell != ENTRY_CELL
	if cell in _enemy_cells():
		return false
	if cell.x in [3, 6, 9] and cell.y in [2, 3, 5, 6]:
		return true
	if cell.y == 4 and cell.x in [4, 5, 7, 8]:
		return true
	return false

func _apply_terrain(layout: WorldData) -> void:
	var bounds := Vector2i(layout.width, layout.height)
	for y in range(layout.height):
		for x in range(layout.width):
			var cell := Vector2i(x, y)
			var blocked := cell_is_blocked(cell)
			layout.set_terrain(cell, WALL_TERRAIN_ID if blocked else FLOOR_TERRAIN_ID, not blocked, atlas_coords_for_cell(cell, bounds))

func _reserve_resources(layout: WorldData, node_kind_resolver: Callable) -> Array:
	var resources := []
	var resource_index := 0
	for resource_cell in _resource_candidates(layout):
		if resource_index >= MAX_RESOURCE_COUNT:
			break
		var is_stone := resource_index % 3 == 1
		var resource_id := "dungeon_stone_%d" % resource_index if is_stone else "dungeon_iron_ore_%d" % resource_index
		var item_id := "stone" if is_stone else "iron_ore"
		var source_id := STONE_SOURCE_ID if is_stone else IRON_SOURCE_ID
		var reservation := layout.reserve_entity(resource_id, resource_cell, Vector2i.ONE, true, {
			"source_id": source_id,
			"interaction_kind": GATHERABLE_KIND,
			"definition_id": resource_id
		})
		if reservation.ok:
			resources.append({
				"id": resource_id,
				"resource_id": item_id,
				"position": {"x": resource_cell.x, "y": resource_cell.y},
				"source_id": source_id,
				"material_tag": "stone",
				"node_kind": _node_kind(item_id, node_kind_resolver)
			})
			resource_index += 1
	return resources

func _resource_candidates(layout: WorldData) -> Array[Vector2i]:
	var reserved := _enemy_cells()
	var candidates: Array[Vector2i] = []
	for y in range(1, layout.height - 1):
		for x in range(1, layout.width - 1):
			var candidate := Vector2i(x, y)
			if candidate == ENTRY_CELL or reserved.has(candidate) or not layout.is_walkable(candidate):
				continue
			candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi(a.x * 37 + a.y * 19) < absi(b.x * 37 + b.y * 19)
	)
	return candidates

func _reserve_enemies(layout: WorldData) -> void:
	for enemy in ENEMY_SPECS:
		var owner_id := String(enemy.id)
		layout.reserve_entity(owner_id, enemy.cell, Vector2i.ONE, false, {"role": "boss" if owner_id == BOSS_OWNER_ID else "dungeon_enemy"})

func _enemy_cells() -> Dictionary:
	var cells := {}
	for enemy in ENEMY_SPECS:
		cells[enemy.cell] = true
	return cells

func _node_kind(item_id: String, node_kind_resolver: Callable) -> String:
	if node_kind_resolver.is_valid():
		return String(node_kind_resolver.call(item_id, "mine"))
	return ""
