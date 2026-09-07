extends RefCounted
## Main 장면의 로딩/종료 화면 구성. 런 전환과 타이머의 수명은 Main이 소유한다.

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const LOADING_BACKDROP_PATH := "res://assets/backgrounds/prologue/first_run_father_muchau_teahouse.png"

static func create_loading(scene_root: Node) -> Label:
	if scene_root.get_node_or_null("LoadingOverlay") != null:
		return scene_root.get_node_or_null("LoadingOverlay/LoadingStatusPanel/LoadingStatus") as Label
	var layer := CanvasLayer.new()
	layer.name = "LoadingOverlay"
	layer.layer = 200
	scene_root.add_child(layer)
	var backdrop := TextureRect.new()
	backdrop.name = "LoadingBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = _loading_backdrop_texture()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.focus_mode = Control.FOCUS_NONE
	layer.add_child(backdrop)
	var scrim := ColorRect.new()
	scrim.name = "LoadingScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.015, 0.012, 0.55)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scrim)
	var panel := PanelContainer.new()
	panel.name = "LoadingStatusPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-190.0, 92.0)
	panel.size = Vector2(380.0, 48.0)
	panel.theme = PixelUiTheme.create()
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	layer.add_child(panel)
	var label := Label.new()
	label.name = "LoadingStatus"
	label.text = "준비 중…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size = Vector2(360.0, 28.0)
	label.modulate = Color(1.0, 0.91, 0.68, 1.0)
	panel.add_child(label)
	return label

static func _loading_backdrop_texture() -> Texture2D:
	var image := Image.load_from_file(LOADING_BACKDROP_PATH)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

static func show_ending(scene_root: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "DeathTransition"
	layer.layer = 1000
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.02, 0.015, 0.012, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "THE END"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(0.88, 0.78, 0.55, 1.0))
	layer.add_child(background)
	layer.add_child(label)
	scene_root.add_child(layer)
