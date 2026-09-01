extends RefCounted

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func run(asserts) -> void:
	_add_release_and_queries(asserts)
	_walkability_and_footprint_collision(asserts)
	_invalid_footprint_size_rejected(asserts)
	_connected_required_landmarks(asserts)
	_disconnected_required_landmarks(asserts)
	_renderer_projection_boundaries(asserts)

func _add_release_and_queries(asserts) -> void:
	var world := WorldData.new(4, 4, "grass", true)
	var added := world.reserve_facility("tea_table", Vector2i(1, 1), Vector2i(2, 1), true)

	asserts.true_value(added.ok, "facility footprint reserves")
	asserts.true_value(world.is_occupied(Vector2i(1, 1)), "reserved facility occupies origin")
	asserts.true_value(world.is_occupied(Vector2i(2, 1)), "reserved facility occupies full footprint")
	asserts.false_value(world.is_walkable(Vector2i(1, 1)), "reserved facility blocks walkability")
	asserts.equal(world.get_interactables(Vector2i(2, 1)), ["tea_table"], "interactable query returns footprint owner")
	asserts.equal(world.get_reservation("tea_table").metadata, {}, "reservation query returns detached public snapshot")
	asserts.true_value(world.release_footprint("tea_table"), "release removes reservation")
	asserts.false_value(world.is_occupied(Vector2i(1, 1)), "released origin is not occupied")
	asserts.true_value(world.is_walkable(Vector2i(1, 1)), "released cell is walkable again")
	asserts.equal(world.get_interactables(Vector2i(2, 1)), [], "release removes interactable owner")

func _walkability_and_footprint_collision(asserts) -> void:
	var world := WorldData.new(5, 5, "grass", true)
	world.set_terrain(Vector2i(0, 0), "water", false)
	var first := world.reserve_entity("fox", Vector2i(2, 2))
	var collision := world.reserve_facility("kiln", Vector2i(2, 2), Vector2i(2, 2))
	var outside := world.reserve_entity("outside", Vector2i(4, 4), Vector2i(2, 1))

	asserts.false_value(world.is_walkable(Vector2i(0, 0)), "terrain walkability blocks water")
	asserts.true_value(first.ok, "entity reserves walkable cell")
	asserts.false_value(collision.ok, "facility cannot overlap entity footprint")
	asserts.equal(collision.reason, "blocked", "collision reports blocked reason")
	asserts.false_value(outside.ok, "footprint cannot reserve outside bounds")
	asserts.equal(outside.position, {"x": 5, "y": 4}, "out-of-bounds collision reports first blocked cell")

func _invalid_footprint_size_rejected(asserts) -> void:
	var world := WorldData.new(5, 5, "grass", true)
	var zero_width := world.reserve_entity("zero_width", Vector2i(1, 1), Vector2i(0, 1))
	var zero_height := world.reserve_entity("zero_height", Vector2i(1, 1), Vector2i(1, 0))
	var negative_width := world.reserve_entity("negative_width", Vector2i(1, 1), Vector2i(-1, 1))
	var negative_height := world.reserve_entity("negative_height", Vector2i(1, 1), Vector2i(1, -1))

	asserts.false_value(world.can_reserve_footprint(Vector2i(1, 1), Vector2i.ZERO), "can_reserve_footprint rejects zero size")
	asserts.false_value(world.can_reserve_footprint(Vector2i(1, 1), Vector2i(0, 1)), "can_reserve_footprint rejects zero width")
	asserts.false_value(world.can_reserve_footprint(Vector2i(1, 1), Vector2i(1, 0)), "can_reserve_footprint rejects zero height")
	asserts.false_value(world.can_reserve_footprint(Vector2i(1, 1), Vector2i(-1, 1)), "can_reserve_footprint rejects negative width")
	asserts.false_value(world.can_reserve_footprint(Vector2i(1, 1), Vector2i(1, -1)), "can_reserve_footprint rejects negative height")
	asserts.equal(zero_width.reason, "invalid_size", "reserve rejects zero width")
	asserts.equal(zero_height.reason, "invalid_size", "reserve rejects zero height")
	asserts.equal(negative_width.reason, "invalid_size", "reserve rejects negative width")
	asserts.equal(negative_height.reason, "invalid_size", "reserve rejects negative height")

func _connected_required_landmarks(asserts) -> void:
	var world := WorldData.new(5, 3, "grass", true)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 1))
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_0", Vector2i(4, 1))
	world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_0", Vector2i(2, 2))
	var validation := ConnectivityValidator.new().validate_world_data(world.to_dictionary())

	asserts.true_value(validation.valid, "open grid connects all required landmarks")
	asserts.equal(validation.entry_landmark_id, "entry_0", "connectivity records entry landmark")
	asserts.equal(validation.unreachable_required_landmarks, [], "connected grid has no unreachable landmarks")

func _disconnected_required_landmarks(asserts) -> void:
	var world := WorldData.new(5, 3, "grass", true)
	for y in range(3):
		world.set_terrain(Vector2i(2, y), "stone_wall", false)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 1))
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_0", Vector2i(4, 1))
	var validation := ConnectivityValidator.new().validate_world_data(world.to_dictionary())

	asserts.false_value(validation.valid, "wall disconnects required landmark")
	asserts.equal(validation.reachable_required_landmarks, ["entry_0"], "entry remains reachable")
	asserts.equal(validation.unreachable_required_landmarks, ["core_0"], "blocked landmark is reported")

func _renderer_projection_boundaries(asserts) -> void:
	var world := WorldData.new(3, 2, "grass", true)
	world.reserve_facility("drying_rack", Vector2i(1, 0), Vector2i(1, 2), true)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 0))
	world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_0", Vector2i(2, 1), {"biome_id": "common_region"})
	var world_data := world.to_dictionary()
	world_data.cells.append({
		"position": {"x": 9, "y": 9},
		"layers": {
			WorldData.LAYER_TERRAIN: {"id": "bad", "render_id": "bad", "walkable": true},
			WorldData.LAYER_FACILITIES: [],
			WorldData.LAYER_ENTITIES: [],
			WorldData.LAYER_INTERACTABLES: []
		}
	})

	var projection := WorldRendererProjection.new().project(world_data, {
		"teleport_states": {"common_region": "repairable"}
	})
	var terrain_layer: Dictionary = projection.layers[0]
	var facility_layer: Dictionary = projection.layers[1]
	projection.bounds.width = 99

	asserts.true_value(projection.read_only, "renderer projection is marked read-only")
	asserts.equal(terrain_layer.cells.size(), 6, "projection includes only in-bounds terrain cells")
	asserts.equal(facility_layer.cells.size(), 2, "projection exposes facility footprint cells")
	asserts.equal(projection.required_landmarks[1].teleport_biome_id, "common_region", "projection maps teleport landmark through stable biome id")
	asserts.equal(projection.required_landmarks[1].teleport_state, "repairable", "projection attaches run teleport state")
	asserts.equal(world_data.bounds.width, 3, "projection duplicates source boundaries")
