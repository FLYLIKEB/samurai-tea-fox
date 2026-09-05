extends RefCounted

const SpatialInteractionResolver = preload("res://src/main/spatial_interaction_resolver.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func run(asserts) -> void:
	_assert_large_house_footprint_uses_reserved_cells(asserts)
	_assert_world_position_hits_match_main_centers(asserts)
	_assert_acquisition_lookup_prefers_forward_cell(asserts)
	_assert_dungeon_lookup_prefers_forward_cell(asserts)

func _assert_large_house_footprint_uses_reserved_cells(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(8, 8, "ground", true)
	world.reserve_entity(WorldGenerator.LARGE_HOUSE_ID, Vector2i(3, 3), Vector2i(2, 2), true)
	world.reserve_entity("large_house_fence_n", Vector2i(3, 2), Vector2i(2, 1), true)
	var cells: Array = resolver.target_footprint_cells(world, WorldGenerator.LARGE_HOUSE_ID, Vector2i(3, 3))
	asserts.equal(cells, [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 2), Vector2i(4, 2)], "large house target footprint preserves reservation insertion order")
	asserts.equal(resolver.nearest_walkable_adjacent_cell_for_target(world, WorldGenerator.LARGE_HOUSE_ID, Vector2i(3, 3), Vector2i(1, 3)), Vector2i(2, 3), "large house approach uses the nearest walkable non-footprint cell")
	asserts.true_value(resolver.player_can_interact_with_target(world, false, Vector2i(2, 3), WorldGenerator.LARGE_HOUSE_ID, Vector2i(3, 3)), "player can interact from any adjacent footprint edge")

func _assert_world_position_hits_match_main_centers(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(8, 8, "ground", true)
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_dungeon_0", Vector2i(2, 2))
	var landmark_hit: Dictionary = resolver.landmark_target_near_world_position(world, Vector2(96.0, 96.0), 32.0, Vector2.ZERO)
	asserts.equal(landmark_hit, {"target_id": "core_dungeon_0", "cell": Vector2i(2, 2)}, "core dungeon click keeps the existing center offset")
	var house_hit: Dictionary = resolver.large_house_target_near_world_position({"large_house": {"position": {"x": 4, "y": 1}}}, Vector2(160.0, 64.0), 32.0, Vector2.ZERO)
	asserts.equal(house_hit, {"target_id": WorldGenerator.LARGE_HOUSE_ID, "cell": Vector2i(4, 1)}, "large house hit uses generated world and explicit origin")

func _assert_acquisition_lookup_prefers_forward_cell(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(5, 5, "ground", true)
	world.reserve_entity("down_resource", Vector2i(2, 3), Vector2i.ONE, true)
	world.reserve_entity("right_resource", Vector2i(3, 2), Vector2i.ONE, true)
	var hit: Dictionary = resolver.acquisition_target_near_cell(
		world,
		false,
		Vector2i(2, 2),
		Vector2i.RIGHT,
		func(_target_id: String) -> bool:
			return true
	)
	asserts.equal(hit, {"target_id": "right_resource", "cell": Vector2i(3, 2)}, "acquisition lookup checks facing cell before default adjacent order")

func _assert_dungeon_lookup_prefers_forward_cell(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(5, 5, "ground", true)
	world.reserve_entity("core_dungeon_down", Vector2i(2, 3), Vector2i.ONE, true)
	world.reserve_entity("core_dungeon_up", Vector2i(2, 1), Vector2i.ONE, true)
	var hit: Dictionary = resolver.dungeon_interaction_target_near_cell(world, false, Vector2i(2, 2), Vector2i.UP)
	asserts.equal(hit, {"target_id": "core_dungeon_up", "cell": Vector2i(2, 1)}, "dungeon lookup checks facing cell before default adjacent order")
