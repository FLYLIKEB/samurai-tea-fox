extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")

const CAPTURES := [
	{"name": "desktop_1280x720", "size": Vector2i(1280, 720)},
	{"name": "mobile_360x640", "size": Vector2i(360, 640)}
]
const CAPTURE_DIR := "res://docs/reports/dev-80-status-toast"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	for capture in CAPTURES:
		var result := await _capture_toast(String(capture.name), capture.size)
		if not result.ok:
			push_error(String(result.get("error", "capture failed")))
			quit(1)
			return
	print("Status toast captures saved: %d" % CAPTURES.size())
	quit(0)

func _capture_toast(capture_name: String, viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % capture_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud := GameHud.new()
	viewport.add_child(hud)
	hud.configure(null, {"biome_id": "common_region"}, {"counts": {}}, {})
	hud.show_status_event({
		"type": "item_acquired",
		"ok": true,
		"item_id": "wood",
		"name": "나무",
		"quantity": 1,
		"event_id": capture_name
	})
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	var toast_panel := hud.get_node_or_null("Root/StatusToastPanel") as Control
	var status_panel := hud.get_node_or_null("Root/StatusPanel") as Control
	if toast_panel == null or status_panel == null or not toast_panel.visible:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing visible toast panel" % capture_name}
	var toast_rect := toast_panel.get_global_rect()
	if toast_rect.position.x < 0.0 or toast_rect.position.y < 0.0 or toast_rect.end.x > viewport_size.x or toast_rect.end.y > viewport_size.y:
		viewport.queue_free()
		return {"ok": false, "error": "%s toast outside viewport: %s" % [capture_name, toast_rect]}
	if toast_rect.intersects(status_panel.get_global_rect()):
		viewport.queue_free()
		return {"ok": false, "error": "%s toast overlaps status HUD" % capture_name}
	var snapshot: Dictionary = hud.status_toast_debug_snapshot()
	if String(snapshot.get("label_text", "")) != "나무을(를) 얻었다!":
		viewport.queue_free()
		return {"ok": false, "error": "%s unexpected toast text: %s" % [capture_name, snapshot.get("label_text", "")]}
	if not bool(snapshot.get("icon_visible", false)) or not bool(snapshot.get("icon_has_texture", false)):
		viewport.queue_free()
		return {"ok": false, "error": "%s missing toast icon texture" % capture_name}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "%s produced an empty image" % capture_name}
	var output_path := "%s/%s.png" % [CAPTURE_DIR, capture_name]
	var save_result := image.save_png(output_path)
	viewport.queue_free()
	if save_result != OK:
		return {"ok": false, "error": "%s failed to save %s" % [capture_name, output_path]}
	return {"ok": true, "path": output_path}
