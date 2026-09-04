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
	var overlay := main.get_node_or_null("WorldToneOverlay") as CanvasLayer
	var hud := main.get_node_or_null("GameHud") as CanvasLayer
	if overlay == null:
		failures.append("main scene owns a world tone overlay")
	if hud == null:
		failures.append("main scene owns a HUD CanvasLayer")
	if overlay != null and hud != null and overlay.layer >= hud.layer:
		failures.append("world tone overlay renders below HUD CanvasLayer")
	if overlay != null:
		if not overlay.has_method("tone_rect"):
			failures.append("world tone overlay exposes its passive tone rect")
		else:
			var rect := overlay.tone_rect() as ColorRect
			if rect == null:
				failures.append("world tone overlay creates a tone rect")
			elif rect.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				failures.append("world tone overlay does not block pointer input")
			elif rect.focus_mode != Control.FOCUS_NONE:
				failures.append("world tone overlay does not steal focus")
			elif rect.color.a <= 0.0:
				failures.append("world tone overlay initializes visibly from its default phase")
	main.queue_free()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("World tone overlay scene integration passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
