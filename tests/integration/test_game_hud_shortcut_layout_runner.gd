extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(480, 270), Vector2i(360, 640)]

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for viewport_size in VIEWPORTS:
		await _check_viewport(viewport_size)
	if _failures.is_empty():
		print("HUD shortcut layout checks passed: %d" % VIEWPORTS.size())
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _check_viewport(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	root.add_child(viewport)
	var hud := GameHud.new()
	viewport.add_child(hud)
	await process_frame
	hud._apply_safe_area_layout()
	await process_frame
	var shortcut := hud.get_node_or_null("Root/ShortcutPanel") as Control
	if shortcut == null:
		_failures.append("%s missing shortcut panel" % viewport_size)
	else:
		var shortcut_rect := shortcut.get_global_rect()
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
		if not viewport_rect.encloses(shortcut_rect):
			_failures.append("%s shortcut outside viewport: %s" % [viewport_size, shortcut_rect])
		for path in ["Root/MapPanel", "Root/QuickSlotPanel", "Root/DPadPanel", "Root/ActionPanel"]:
			var other := hud.get_node_or_null(path) as Control
			if other != null and other.visible and shortcut_rect.intersects(other.get_global_rect()):
				_failures.append("%s shortcut overlaps %s" % [viewport_size, path])
	viewport.queue_free()
	await process_frame
