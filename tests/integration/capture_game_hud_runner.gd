extends SceneTree

const DEFAULT_CAPTURE_PATH := "user://dev13_game_hud_capture.png"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(640, 360)
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("main scene loads for HUD capture")
		quit(1)
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await physics_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("HUD capture requires a rendering display driver; headless dummy renderer has no viewport texture.")
		main.queue_free()
		quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("HUD capture produced an empty viewport image.")
		main.queue_free()
		quit(2)
		return
	var capture_path := OS.get_environment("HUD_CAPTURE_PATH")
	if capture_path.is_empty():
		capture_path = DEFAULT_CAPTURE_PATH
	var result := image.save_png(capture_path)
	main.queue_free()
	if result != OK:
		push_error("HUD capture save failed: %s" % capture_path)
		quit(1)
		return
	print("HUD capture saved: %s" % capture_path)
	quit(0)
