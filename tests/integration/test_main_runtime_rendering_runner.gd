extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		failures.append("main scene loads")
		finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame

	var world_visuals := main.get_node_or_null("WorldVisuals") as Node2D
	if world_visuals == null:
		failures.append("main scene owns a WorldVisuals node")
	else:
		var terrain := world_visuals.get_node_or_null("Terrain") as Node2D
		if terrain == null or terrain.get_child_count() < 100:
			failures.append("generated world terrain is rendered with sprite tiles")
		elif not terrain.get_child(0) is Sprite2D or (terrain.get_child(0) as Sprite2D).texture == null:
			failures.append("terrain sprite has a loaded texture")
		var entities := world_visuals.get_node_or_null("Entities") as Node2D
		if entities == null or entities.get_child_count() == 0:
			failures.append("resource nodes are rendered with object sprites")
		var landmarks := world_visuals.get_node_or_null("Landmarks") as Node2D
		if landmarks == null or landmarks.get_child_count() == 0:
			failures.append("required landmarks are rendered with object sprites")

	var ground := main.get_node_or_null("Ground") as Polygon2D
	if ground != null and ground.visible:
		failures.append("prototype polygon ground is hidden after runtime sprite render")

	var player = main.get_node_or_null("Player")
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D if player != null else null
	if sprite == null or sprite.texture == null:
		failures.append("player sprite remains visible in main scene")

	main.queue_free()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("Main runtime rendering integration passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
