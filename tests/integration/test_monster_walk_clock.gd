extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(1))
	var actor = load("res://src/combat/combat_dummy.gd").new()
	for node_name in ["Sprite2D", "Body", "Headband", "HealthFill"]:
		var child = Sprite2D.new() if node_name == "Sprite2D" else Polygon2D.new()
		child.name = node_name
		actor.add_child(child)
	root.add_child(actor)
	actor.set_physics_process(false)
	assert(actor._walk_animator_ready, "Monster uses shared player animator")
	actor._grid_step_direction = Vector2.LEFT
	actor._grid_step_active = true
	actor._update_walk_animation(Vector2i.LEFT, true)
	actor._physics_process(0.13)
	assert(actor.sprite.frame_coords == Vector2i(1, 1), "Movement advances shared animation clock")
	actor._grid_step_active = false
	actor._update_walk_animation(Vector2i.LEFT, false)
	assert(actor.sprite.frame_coords == Vector2i(0, 1), "Stop retains facing")
	var catalog = load("res://src/core/data/asset_catalog.gd").new()
	catalog.load_manifest()
	var ids = ["abandoned_mine_samurai", "agarwood_thief", "ash_crow_flock", "empty_armor_yokai", "foxfire", "frost_lantern_yokai", "monster_16", "monster_17", "monster_18", "monster_19", "monster_20", "monster_21", "moss_tree_yokai", "mountain_boar", "road_bandit", "snow_path_assassin", "snow_wolf", "stonebound_yokai", "swamp_snake", "wandering_ronin", "wild_dog"]
	for id in ids:
		actor.monster_id = id
		actor._apply_sprite()
		assert(actor._walk_animator_ready, "Every monster resolves its own animation: " + id)
		for direction in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			actor._grid_step_direction = Vector2(direction)
			actor._grid_step_active = true
			actor._update_walk_animation(direction, true)
			actor._physics_process(0.13)
			assert(actor.sprite.frame_coords.x == 1)
			actor._grid_step_active = false
			actor._update_walk_animation(direction, false)
	actor.queue_free()
	print("PASS monster shared animation clock")
	quit(0)
