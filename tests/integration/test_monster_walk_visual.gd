extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(1))
	root.size = Vector2i(1120, 640)
	root.content_scale_size = Vector2i(1120, 640)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/asset-manifest.json"))
	var actors = []
	for entry in manifest.assets:
		var id = String(entry.id)
		if not id.begins_with("monster_") or not id.ends_with("_front_idle"):
			continue
		var actor = load("res://src/combat/combat_dummy.gd").new()
		actor.monster_id = id.trim_prefix("monster_").trim_suffix("_front_idle")
		for node_name in ["Sprite2D", "Body", "Headband", "HealthFill"]:
			var child = Sprite2D.new() if node_name == "Sprite2D" else Polygon2D.new()
			child.name = node_name
			actor.add_child(child)
		actor.position = Vector2(80 + (actors.size() % 7)*160, 80 + (actors.size()/7)*180)
		actor.scale = Vector2(3,3)
		root.add_child(actor)
		actor.set_physics_process(false)
		actors.append(actor)
	for direction in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		for actor in actors:
			actor._grid_step_direction = Vector2(direction)
			actor._grid_step_active = true
			actor._update_walk_animation(direction, true)
			actor._physics_process(0.13)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/monster-runtime-%s.png" % actors[0]._direction_name(direction))
	print("PASS actual CombatDummy render in all four directions")
	quit(0)
