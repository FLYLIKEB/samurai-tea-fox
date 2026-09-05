extends RefCounted

const PointerRouteController = preload("res://src/main/pointer_route_controller.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	_assert_route_preserves_main_traversal_order(asserts)
	_assert_completion_clears_before_callback(asserts)

func _assert_route_preserves_main_traversal_order(asserts) -> void:
	var world := WorldData.new(5, 5, "ground", true)
	world.reserve_entity("blocked", Vector2i(1, 0), Vector2i.ONE, false)
	var controller := PointerRouteController.new()
	var route: Array = controller.find_walkable_route(world, Vector2i.ZERO, Vector2i(2, 0), [])
	asserts.equal(route, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0)], "route search keeps down-left-right-up traversal order")

func _assert_completion_clears_before_callback(asserts) -> void:
	var controller := PointerRouteController.new()
	var completed := []
	var result: Dictionary = controller.begin_route(
		WorldData.new(3, 1, "ground", true),
		Vector2i.ZERO,
		Vector2i(1, 0),
		"resource_0",
		Vector2i(2, 0),
		[Vector2i(2, 0)],
		func(cell: Vector2i) -> Vector2:
			return Vector2(float(cell.x * 32 + 16), 16.0)
	)
	asserts.true_value(result.ok, "route begins for a walkable destination")
	var command = controller.movement_command(
		Vector2(48.0, 16.0),
		4.0,
		func(cell: Vector2i) -> Vector2:
			return Vector2(float(cell.x * 32 + 16), 16.0),
		func(target_id: String, target_cell: Vector2i) -> void:
			completed.append({
				"target_id": target_id,
				"target_cell": target_cell,
				"was_cleared": not controller.has_pointer_move_target
			})
	)
	asserts.equal(command.direction, Vector2i.ZERO, "arrival consumes no extra movement command")
	asserts.equal(completed, [{"target_id": "resource_0", "target_cell": Vector2i(2, 0), "was_cleared": true}], "pending interaction callback sees cleared route state")
