extends SceneTree

const DEFAULT_CAPTURE_PATH := "user://dev13_game_hud_capture.png"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var capture_size := _capture_size()
	var capture_viewport := SubViewport.new()
	capture_viewport.name = "HudCaptureViewport"
	capture_viewport.size = capture_size
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("main scene loads for HUD capture")
		quit(1)
		return
	var main := packed_scene.instantiate()
	capture_viewport.add_child(main)
	await process_frame
	await process_frame
	await physics_frame
	for _index in range(90):
		if main.get_node_or_null("LoadingOverlay") == null:
			break
		await process_frame
	await physics_frame
	var hud = main.get_node_or_null("GameHud")
	if hud != null and hud.has_method("narrative_dialogue_visible") and hud.narrative_dialogue_visible():
		hud.hide_narrative_dialogue()
		await process_frame
		await process_frame
		await physics_frame
	var viewport_texture := capture_viewport.get_texture()
	if viewport_texture == null:
		push_error("HUD capture requires a rendering display driver; headless dummy renderer has no viewport texture.")
		capture_viewport.queue_free()
		quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("HUD capture produced an empty viewport image.")
		capture_viewport.queue_free()
		quit(2)
		return
	var capture_path := OS.get_environment("HUD_CAPTURE_PATH")
	if capture_path.is_empty():
		capture_path = DEFAULT_CAPTURE_PATH
	var result := image.save_png(capture_path)
	capture_viewport.queue_free()
	if result != OK:
		push_error("HUD capture save failed: %s" % capture_path)
		quit(1)
		return
	print("HUD capture saved: %s" % capture_path)
	quit(0)

func _capture_size() -> Vector2i:
	var requested := OS.get_environment("HUD_CAPTURE_SIZE")
	if requested.is_empty() or not requested.contains("x"):
		return Vector2i(640, 360)
	var parts := requested.split("x", false)
	if parts.size() != 2:
		return Vector2i(640, 360)
	var width: int = max(1, int(parts[0]))
	var height: int = max(1, int(parts[1]))
	return Vector2i(width, height)
