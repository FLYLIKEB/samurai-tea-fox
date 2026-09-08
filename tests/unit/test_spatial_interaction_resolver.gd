extends RefCounted

const SpatialInteractionResolver = preload("res://src/world/interactions/spatial_interaction_resolver.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

class AcquisitionProbe:
	extends RefCounted

	func gatherable_for(_target_id: String) -> Dictionary:
		return {"depleted": false}

func run(asserts) -> void:
	_assert_starting_home_is_not_a_dungeon_target(asserts)
	_assert_starting_home_uses_reserved_footprint(asserts)
	_assert_world_position_hits_match_main_centers(asserts)
	_assert_acquisition_lookup_prefers_forward_cell(asserts)
	_assert_dungeon_lookup_prefers_forward_cell(asserts)
	_assert_dungeon_ore_lookup_prefers_forward_cell(asserts)

func _assert_starting_home_is_not_a_dungeon_target(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	asserts.false_value(resolver.is_core_dungeon_target(WorldGenerator.LARGE_HOUSE_ID), "starting home is never treated as a dungeon target")
	asserts.false_value(resolver.is_core_dungeon_target("large_house_fence_n"), "starting-home fences are never treated as dungeon targets")
	asserts.true_value(resolver.is_core_dungeon_target("core_dungeon_0"), "core dungeon landmark remains a dungeon target")
	asserts.true_value(resolver.is_landmark_target(false, "portable_brazier@3,3"), "portable brazier interaction routes to pickup")

func _assert_starting_home_uses_reserved_footprint(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(6, 6, "ground", true)
	asserts.true_value(world.reserve_entity(WorldGenerator.LARGE_HOUSE_ID, Vector2i(2, 2), Vector2i(2, 2), false).ok, "starting home fixture reserves its footprint")
	asserts.equal(resolver.target_footprint_cells(world, WorldGenerator.LARGE_HOUSE_ID, Vector2i.ZERO), [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)], "starting home interaction uses all reserved cells")
	asserts.true_value(resolver.is_landmark_target(false, WorldGenerator.LARGE_HOUSE_ID), "starting home routes through landmark interaction")

func _assert_world_position_hits_match_main_centers(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var world := WorldData.new(8, 8, "ground", true)
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_dungeon_0", Vector2i(2, 2))
	var landmark_hit: Dictionary = resolver.landmark_target_near_world_position(world, Vector2(96.0, 96.0), 32.0, Vector2.ZERO)
	asserts.equal(landmark_hit, {"target_id": "core_dungeon_0", "cell": Vector2i(2, 2)}, "core dungeon click keeps the existing center offset")

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

func _assert_dungeon_ore_lookup_prefers_forward_cell(asserts) -> void:
	var resolver := SpatialInteractionResolver.new()
	var resources := [
		{"id": "side_ore", "position": {"x": 1, "y": 2}},
		{"id": "blocking_stone", "position": {"x": 3, "y": 2}},
	]
	var hit: Dictionary = resolver.dungeon_ore_target_near_cell(true, resources, AcquisitionProbe.new(), Vector2i(2, 2), 1, Vector2i.RIGHT)
	asserts.equal(hit, {"target_id": "blocking_stone", "cell": Vector2i(3, 2)}, "dungeon ore lookup prefers the resource directly ahead over an equally near side resource")
