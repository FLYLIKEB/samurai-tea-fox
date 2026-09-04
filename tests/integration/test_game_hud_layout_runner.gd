extends SceneTree

const VIEWPORTS := [
	{"name": "desktop", "size": Vector2i(1280, 720)},
	{"name": "narrow_landscape", "size": Vector2i(480, 270)},
	{"name": "mobile_portrait", "size": Vector2i(360, 640)}
]

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for viewport in VIEWPORTS:
		await _assert_layout_for_viewport(String(viewport.name), viewport.size)
	if _failures.is_empty():
		print("HUD layout viewport checks passed: %d" % VIEWPORTS.size())
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _assert_layout_for_viewport(viewport_name: String, viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % viewport_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		_failures.append("%s main scene did not load" % viewport_name)
		viewport.queue_free()
		return
	var main := packed_scene.instantiate()
	viewport.add_child(main)
	await process_frame
	await process_frame
	await physics_frame
	for _index in range(90):
		if main.get_node_or_null("LoadingOverlay") == null:
			break
		await process_frame
	var hud = main.get_node_or_null("GameHud")
	if hud == null:
		_failures.append("%s missing GameHud" % viewport_name)
		viewport.queue_free()
		await process_frame
		return
	if hud.has_method("narrative_dialogue_visible") and hud.narrative_dialogue_visible():
		hud.hide_narrative_dialogue()
		await process_frame
	hud._apply_safe_area_layout()
	await process_frame
	_assert_visible_rect_inside(viewport_name, hud, "Root/StatusPanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/StatusPanel/StatusBody/StatusRows/EquipmentStrip", viewport_size)
	_assert_rect_inside_node(viewport_name, hud, "Root/StatusPanel/StatusBody/StatusRows/EquipmentStrip", "Root/StatusPanel")
	_assert_visible_rect_inside(viewport_name, hud, "Root/QuickSlotPanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/MapPanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/EnemyPanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/DPadPanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/ActionPanel", viewport_size)
	_assert_no_overlap(viewport_name, hud, "Root/StatusPanel", "Root/QuickSlotPanel")
	_assert_no_overlap(viewport_name, hud, "Root/QuickSlotPanel", "Root/MapPanel")
	_assert_no_overlap(viewport_name, hud, "Root/StatusPanel", "Root/MapPanel")
	_assert_no_overlap(viewport_name, hud, "Root/EnemyPanel", "Root/StatusPanel")
	_assert_no_overlap(viewport_name, hud, "Root/EnemyPanel", "Root/QuickSlotPanel")
	_assert_no_overlap(viewport_name, hud, "Root/EnemyPanel", "Root/MapPanel")
	_assert_no_overlap(viewport_name, hud, "Root/EnemyPanel", "Root/DPadPanel")
	_assert_no_overlap(viewport_name, hud, "Root/EnemyPanel", "Root/ActionPanel")
	_assert_no_overlap(viewport_name, hud, "Root/DPadPanel", "Root/QuickSlotPanel")
	_assert_no_overlap(viewport_name, hud, "Root/DPadPanel", "Root/ActionPanel")
	var menu_button := hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/ActionMenuButton") as Button
	if menu_button == null:
		_failures.append("%s missing action menu button" % viewport_name)
	else:
		menu_button.pressed.emit()
		await process_frame
		hud._apply_safe_area_layout()
		await process_frame
		_assert_visible_rect_inside(viewport_name, hud, "Root/ActionMenuPanel", viewport_size)
		_assert_no_overlap(viewport_name, hud, "Root/ActionMenuPanel", "Root/MapPanel")
		_assert_no_overlap(viewport_name, hud, "Root/ActionMenuPanel", "Root/ActionPanel")
		_assert_no_overlap(viewport_name, hud, "Root/ActionMenuPanel", "Root/QuickSlotPanel")
		var scroll := hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll") as Control
		if scroll == null:
			_failures.append("%s missing action menu scroll" % viewport_name)
		elif scroll.custom_minimum_size.y > _rect(hud.get_node("Root/ActionMenuPanel")).size.y:
			_failures.append("%s action menu scroll exceeds panel height" % viewport_name)
	hud.show_narrative_dialogue({
		"event_id": "repeat_dialogue_check",
		"node_id": "portrait_layout",
		"speaker_id": "CHR-9",
		"text": "떠돌이 차 상인의 초상화가 화면 안에서 읽힌다.",
		"options": [{"id": "continue", "display_text": "계속"}]
	})
	await process_frame
	hud._apply_safe_area_layout()
	await process_frame
	_assert_visible_rect_inside(viewport_name, hud, "Root/NarrativeOverlay/NarrativePanel", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/NarrativeOverlay/LeftPortraitFrame", viewport_size)
	_assert_visible_rect_inside(viewport_name, hud, "Root/NarrativeOverlay/LeftPortrait", viewport_size)
	_assert_no_overlap(viewport_name, hud, "Root/NarrativeOverlay/LeftPortraitFrame", "Root/NarrativeOverlay/NarrativePanel")
	_assert_no_overlap(viewport_name, hud, "Root/NarrativeOverlay/LeftPortraitFrame", "Root/NarrativeOverlay/RightPortraitFrame")
	viewport.queue_free()
	await process_frame

func _assert_visible_rect_inside(viewport_name: String, root_node: Node, path: String, viewport_size: Vector2i) -> void:
	var node := root_node.get_node_or_null(path) as Control
	if node == null:
		_failures.append("%s missing %s" % [viewport_name, path])
		return
	if not node.visible:
		return
	var rect := _rect(node)
	if rect.position.x < -0.01 or rect.position.y < -0.01 or rect.end.x > float(viewport_size.x) + 0.01 or rect.end.y > float(viewport_size.y) + 0.01:
		_failures.append("%s %s outside viewport: %s within %s" % [viewport_name, path, rect, viewport_size])

func _assert_rect_inside_node(viewport_name: String, root_node: Node, child_path: String, parent_path: String) -> void:
	var child := root_node.get_node_or_null(child_path) as Control
	var parent := root_node.get_node_or_null(parent_path) as Control
	if child == null or parent == null or not child.visible or not parent.visible:
		return
	var child_rect := _rect(child)
	var parent_rect := _rect(parent)
	if (
		child_rect.position.x < parent_rect.position.x - 0.01
		or child_rect.position.y < parent_rect.position.y - 0.01
		or child_rect.end.x > parent_rect.end.x + 0.01
		or child_rect.end.y > parent_rect.end.y + 0.01
	):
		_failures.append("%s %s outside %s: %s within %s" % [viewport_name, child_path, parent_path, child_rect, parent_rect])

func _assert_no_overlap(viewport_name: String, root_node: Node, first_path: String, second_path: String) -> void:
	var first := root_node.get_node_or_null(first_path) as Control
	var second := root_node.get_node_or_null(second_path) as Control
	if first == null or second == null or not first.visible or not second.visible:
		return
	if _rect(first).intersects(_rect(second)):
		_failures.append("%s overlap: %s %s with %s %s" % [viewport_name, first_path, _rect(first), second_path, _rect(second)])

func _rect(node: Control) -> Rect2:
	return node.get_global_rect()
