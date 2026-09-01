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
		var terrain := world_visuals.get_node_or_null("TerrainTileMap") as TileMapLayer
		if terrain == null:
			failures.append("generated world terrain is rendered as a TileMapLayer")
		elif terrain.get_used_cells().size() < 100:
			failures.append("generated world terrain tilemap contains generated cells")
		elif terrain.tile_set == null or terrain.tile_set.get_source_count() == 0:
			failures.append("terrain tilemap has a runtime tileset from promoted assets")
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

	var hud := main.get_node_or_null("GameHud")
	if hud == null:
		failures.append("main scene owns a runtime HUD")
	else:
		var status_panel := hud.get_node_or_null("Root/StatusPanel")
		var map_panel := hud.get_node_or_null("Root/MapPanel")
		var quickslot_panel := hud.get_node_or_null("Root/QuickSlotPanel")
		if status_panel == null or map_panel == null or quickslot_panel == null:
			failures.append("runtime HUD shows status, map, and quickslot panels")
		elif _texture_rect_count(status_panel) < 4 or _label_count(status_panel) < 4:
			failures.append("runtime HUD status panel renders icon-backed resource rows")
		elif _texture_rect_count(quickslot_panel) < 4 or _label_count(quickslot_panel) < 4:
			failures.append("runtime HUD quickslots render icon-backed rows")

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

func _texture_rect_count(node: Node) -> int:
	var count := 1 if node is TextureRect and (node as TextureRect).texture != null else 0
	for child in node.get_children():
		count += _texture_rect_count(child)
	return count

func _label_count(node: Node) -> int:
	var count := 1 if node is Label and not (node as Label).text.is_empty() else 0
	for child in node.get_children():
		count += _label_count(child)
	return count
