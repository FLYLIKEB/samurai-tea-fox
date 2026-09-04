extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")

const CAPTURES := [
	{"name": "desktop_1280x720", "size": Vector2i(1280, 720)},
	{"name": "mobile_360x640", "size": Vector2i(360, 640)}
]
const CAPTURE_DIR := "res://docs/reports/dev-77-portrait-dialogue-ui"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	for capture in CAPTURES:
		var result := await _capture_dialogue(String(capture.name), capture.size)
		if not result.ok:
			push_error(String(result.get("error", "capture failed")))
			quit(1)
			return
	print("DEV-77 portrait dialogue captures saved: %d" % CAPTURES.size())
	quit(0)

func _capture_dialogue(capture_name: String, viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % capture_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud := GameHud.new()
	viewport.add_child(hud)
	hud.configure(null, {"biome_id": "common_region"}, {"counts": {}}, {})
	hud.show_narrative_dialogue({
		"event_id": "repeat_dialogue_check",
		"node_id": "portrait_dialogue_capture",
		"speaker_id": "CHR-9",
		"text": "떠돌이 차 상인의 초상화가 대화창 옆에서 화면 안에 안정적으로 표시된다.",
		"options": [{"id": "continue", "display_text": "계속"}]
	})
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	var panel := hud.get_node_or_null("Root/NarrativeOverlay/NarrativePanel") as Control
	var portrait := hud.get_node_or_null("Root/NarrativeOverlay/LeftPortrait") as TextureRect
	if panel == null or portrait == null or not panel.visible or not portrait.visible:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing visible narrative panel or portrait" % capture_name}
	if not _inside_viewport(panel.get_global_rect(), viewport_size):
		viewport.queue_free()
		return {"ok": false, "error": "%s narrative panel outside viewport: %s" % [capture_name, panel.get_global_rect()]}
	if not _inside_viewport(portrait.get_global_rect(), viewport_size):
		viewport.queue_free()
		return {"ok": false, "error": "%s portrait outside viewport: %s" % [capture_name, portrait.get_global_rect()]}
	if portrait.texture == null or not String(portrait.texture.resource_path).contains("chr_9_wandering_tea_merchant_96x96.png"):
		viewport.queue_free()
		return {"ok": false, "error": "%s missing CHR-9 portrait texture" % capture_name}
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

func _inside_viewport(rect: Rect2, viewport_size: Vector2i) -> bool:
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= float(viewport_size.x) and rect.end.y <= float(viewport_size.y)
