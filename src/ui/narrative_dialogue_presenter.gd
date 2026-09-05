extends Control
class_name NarrativeDialoguePresenter

const GameCommand = preload("res://src/core/commands/game_command.gd")
const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")

const BACKGROUND_FIRST_RUN_PROLOGUE := "prologue_first_run_father_muchau_teahouse"
const PORTRAIT_FATHER := "portrait_chr_1_kitsune_father"
const PORTRAIT_MUCHAU := "portrait_chr_8_muchau"
const PORTRAIT_SEN_RIKYU := "portrait_chr_5_sen_rikyu"
const PORTRAIT_BY_CHARACTER := {
	"CHR-1": PORTRAIT_FATHER,
	"CHR-2": "portrait_chr_2_wasteland_daimyo",
	"CHR-3": "portrait_chr_3_furuta_oribe",
	"CHR-4": "portrait_chr_4_snow_monk",
	"CHR-5": PORTRAIT_SEN_RIKYU,
	"CHR-6": "portrait_chr_6_yokai_tea_master",
	"CHR-7": "portrait_chr_7_mountain_potter",
	"CHR-8": PORTRAIT_MUCHAU,
	"CHR-9": "portrait_chr_9_wandering_tea_merchant",
}
const PAIRED_RIGHT_PORTRAIT_BY_SPEAKER := {
	"CHR-5": PORTRAIT_SEN_RIKYU
}
const PAIRED_PRESENTATION_KINDS := [
	"father_farewell_then_border_cup",
	"father_dream",
	"father_scent_memory"
]
const PANEL_SIZE := Vector2(560, 118)
const PORTRAIT_SIZE := Vector2(96, 96)
const PORTRAIT_FRAME_SIZE := Vector2(104, 104)
const PORTRAIT_INSET := 4.0
const PANEL_BOTTOM_OFFSET := 12.0
const EDGE_GAP := 4.0

signal command_issued(command)
signal continue_requested(payload)
signal choice_requested(payload)
signal skip_requested(payload)

var texture_loader: Callable
var speaker_label_resolver: Callable
var narrative_panel: PanelContainer
var background: TextureRect
var left_portrait_frame: PanelContainer
var right_portrait_frame: PanelContainer
var left_portrait: TextureRect
var right_portrait: TextureRect
var options_container: HBoxContainer
var _labels: Dictionary = {}
var _current_model: Dictionary = {}

func configure(load_texture_callback: Callable, speaker_label_callback: Callable) -> void:
	texture_loader = load_texture_callback
	speaker_label_resolver = speaker_label_callback

func build() -> void:
	if narrative_panel != null:
		return
	name = "NarrativeOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	background = TextureRect.new()
	background.name = "NarrativeBackground"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	left_portrait_frame = _portrait_frame("LeftPortraitFrame")
	add_child(left_portrait_frame)
	left_portrait = _portrait_rect("LeftPortrait")
	add_child(left_portrait)
	right_portrait_frame = _portrait_frame("RightPortraitFrame")
	add_child(right_portrait_frame)
	right_portrait = _portrait_rect("RightPortrait")
	add_child(right_portrait)

	narrative_panel = _dialogue_panel(PANEL_SIZE)
	narrative_panel.name = "NarrativePanel"
	narrative_panel.visible = false
	add_child(narrative_panel)
	_build_panel_rows(narrative_panel)

func show_read_model(read_model: Dictionary) -> bool:
	build()
	var event_id := String(read_model.get("event_id", ""))
	var node_id := String(read_model.get("node_id", ""))
	if event_id.is_empty() or node_id.is_empty():
		return false
	_current_model = read_model.duplicate(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	background.visible = _uses_background(read_model)
	background.texture = _load_texture(String(_presentation_metadata(read_model).get("background_asset_id", BACKGROUND_FIRST_RUN_PROLOGUE))) if background.visible else null
	_configure_portraits(read_model)
	_set_label("speaker", _speaker_label(String(read_model.get("speaker_id", ""))))
	_set_label("text", String(read_model.get("text", "")))
	_clear_options()
	for option in _array_value(read_model.get("options", [])):
		if typeof(option) == TYPE_DICTIONARY:
			_add_option_button(event_id, node_id, option)
	narrative_panel.visible = true
	return true

func update_read_model(read_model: Dictionary) -> bool:
	return show_read_model(read_model)

func hide_dialogue() -> bool:
	build()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if narrative_panel != null:
		narrative_panel.visible = false
	if background != null:
		background.visible = false
		background.texture = null
	_clear_options()
	_current_model.clear()
	return true

func dialogue_visible() -> bool:
	return visible and narrative_panel != null and narrative_panel.visible

func request_skip() -> void:
	skip_requested.emit(_command_payload(
		String(_current_model.get("event_id", "")),
		String(_current_model.get("node_id", "")),
		""
	))

func apply_layout(viewport_size: Vector2, margin: Vector4) -> void:
	build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 0
	background.offset_top = 0
	background.offset_right = 0
	background.offset_bottom = 0
	_resize_panel(viewport_size, margin)
	var panel_size := _control_layout_size(narrative_panel)
	var panel_top := viewport_size.y - margin.w - PANEL_BOTTOM_OFFSET - panel_size.y
	var portrait_frame_edge := minf(
		PORTRAIT_FRAME_SIZE.x,
		maxf(56.0, panel_top - (margin.y + 44.0) - EDGE_GAP)
	)
	var portrait_frame_size := Vector2(portrait_frame_edge, portrait_frame_edge)
	var portrait_inset := minf(PORTRAIT_INSET, portrait_frame_edge * 0.08)
	var portrait_size := Vector2(
		maxf(1.0, portrait_frame_edge - portrait_inset * 2.0),
		maxf(1.0, portrait_frame_edge - portrait_inset * 2.0)
	)
	var portrait_y := maxf(margin.y + 44.0, panel_top - portrait_frame_size.y - EDGE_GAP)
	var left_frame_position := Vector2(margin.x + 24.0, portrait_y)
	var right_frame_position := Vector2(viewport_size.x - margin.z - portrait_frame_size.x - 24.0, portrait_y)
	_place_portrait(left_portrait, left_portrait_frame, left_frame_position, portrait_frame_size, portrait_size, portrait_inset)
	_place_portrait(right_portrait, right_portrait_frame, right_frame_position, portrait_frame_size, portrait_size, portrait_inset)
	_place_panel(narrative_panel, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -margin.w - PANEL_BOTTOM_OFFSET))

func _build_panel_rows(parent: PanelContainer) -> void:
	var rows := VBoxContainer.new()
	rows.name = "NarrativeRows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 4)
	parent.add_child(rows)
	var speaker_plate := PanelContainer.new()
	speaker_plate.name = "SpeakerPlate"
	speaker_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	speaker_plate.add_theme_stylebox_override("panel", PixelUiTheme.button_style(Color(0.12, 0.08, 0.05, 0.94)))
	_ignore_mouse(speaker_plate)
	rows.add_child(speaker_plate)
	_labels.speaker = _label("", 13)
	_labels.speaker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58, 1.0))
	speaker_plate.add_child(_labels.speaker)
	_labels.text = _label("", 12)
	_labels.text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_labels.text.custom_minimum_size = Vector2(528, 38)
	rows.add_child(_labels.text)
	options_container = HBoxContainer.new()
	options_container.name = "NarrativeOptions"
	_ignore_mouse(options_container)
	options_container.add_theme_constant_override("separation", 6)
	rows.add_child(options_container)

func _add_option_button(event_id: String, node_id: String, option: Dictionary) -> void:
	var option_id := String(option.get("id", ""))
	var payload := _command_payload(event_id, node_id, option_id)
	var button := Button.new()
	button.text = "넘어가기"
	button.tooltip_text = String(option.get("display_text", "넘어가기"))
	button.custom_minimum_size = Vector2(112, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func():
		continue_requested.emit(payload.duplicate(true))
		choice_requested.emit(payload.duplicate(true))
		command_issued.emit(GameCommand.new(GameCommand.Type.NARRATIVE_SELECT_OPTION, Vector2i.ZERO, -1, payload.duplicate(true)))
	)
	options_container.add_child(button)

func _configure_portraits(read_model: Dictionary) -> void:
	var speaker_id := String(read_model.get("speaker_id", ""))
	if _uses_paired_portraits(read_model):
		var right_asset := String(_presentation_metadata(read_model).get(
			"right_portrait_asset_id",
			PAIRED_RIGHT_PORTRAIT_BY_SPEAKER.get(speaker_id, PORTRAIT_MUCHAU)
		))
		_set_portrait(left_portrait, PORTRAIT_FATHER, true)
		_set_portrait(right_portrait, right_asset, true)
		left_portrait.modulate = Color(1, 1, 1, 1) if speaker_id == "CHR-1" else Color(0.70, 0.70, 0.70, 0.72)
		right_portrait.modulate = Color(1, 1, 1, 1) if speaker_id != "CHR-1" else Color(0.70, 0.70, 0.70, 0.72)
		return
	_set_portrait(left_portrait, _portrait_asset_id_for_speaker(speaker_id), true)
	_set_portrait(right_portrait, "", false)
	left_portrait.modulate = Color(1, 1, 1, 1)
	right_portrait.modulate = Color(1, 1, 1, 1)

func _uses_background(read_model: Dictionary) -> bool:
	return not String(_presentation_metadata(read_model).get("background_asset_id", "")).is_empty() or _uses_paired_portraits(read_model)

func _uses_paired_portraits(read_model: Dictionary) -> bool:
	var metadata := _presentation_metadata(read_model)
	if bool(metadata.get("paired_portraits", false)):
		return true
	var kind := String(read_model.get("presentation_kind", metadata.get("presentation_kind", "")))
	return PAIRED_PRESENTATION_KINDS.has(kind)

func _presentation_metadata(read_model: Dictionary) -> Dictionary:
	var metadata = read_model.get("presentation", read_model.get("presentation_metadata", {}))
	return metadata.duplicate(true) if typeof(metadata) == TYPE_DICTIONARY else {}

func _portrait_asset_id_for_speaker(speaker_id: String) -> String:
	return String(_presentation_metadata(_current_model).get("speaker_portrait_asset_id", PORTRAIT_BY_CHARACTER.get(speaker_id, "")))

func _set_portrait(rect: TextureRect, asset_id: String, should_show: bool) -> void:
	rect.visible = should_show and not asset_id.is_empty()
	rect.texture = _load_texture(asset_id) if rect.visible else null
	var frame := get_node_or_null("%sFrame" % rect.name) as Control
	if frame != null:
		frame.visible = rect.visible

func _place_portrait(rect: TextureRect, frame: Control, frame_position: Vector2, frame_size: Vector2, portrait_size: Vector2, inset: float) -> void:
	rect.custom_minimum_size = portrait_size
	rect.size = portrait_size
	rect.position = frame_position + Vector2.ONE * inset
	frame.custom_minimum_size = frame_size
	frame.size = frame_size
	frame.position = frame_position

func _resize_panel(viewport_size: Vector2, margin: Vector4) -> void:
	var available_width := maxf(1.0, viewport_size.x - margin.x - margin.z)
	var panel_width := minf(PANEL_SIZE.x, available_width)
	panel_width = maxf(240.0, panel_width)
	if panel_width > available_width:
		panel_width = available_width
	var panel_size := Vector2(panel_width, PANEL_SIZE.y)
	narrative_panel.custom_minimum_size = panel_size
	narrative_panel.size = panel_size
	if _labels.has("text") and _labels.text is Control:
		(_labels.text as Control).custom_minimum_size = Vector2(maxf(120.0, panel_width - 32.0), 38.0)

func _place_panel(panel: Control, preset: int, offset: Vector2) -> void:
	var panel_size := _control_layout_size(panel)
	panel.size = panel_size
	panel.set_anchors_preset(preset)
	match preset:
		Control.PRESET_CENTER_BOTTOM:
			panel.offset_left = -panel_size.x * 0.5
			panel.offset_top = offset.y - panel_size.y
			panel.offset_right = panel_size.x * 0.5
			panel.offset_bottom = offset.y

func _control_layout_size(control: Control) -> Vector2:
	var combined := control.get_combined_minimum_size()
	return Vector2(maxf(control.custom_minimum_size.x, combined.x), maxf(control.custom_minimum_size.y, combined.y))

func _portrait_rect(rect_name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = rect_name
	rect.custom_minimum_size = PORTRAIT_SIZE
	rect.size = PORTRAIT_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _portrait_frame(frame_name: String) -> PanelContainer:
	var frame := _dialogue_panel(PORTRAIT_FRAME_SIZE)
	frame.name = frame_name
	return frame

func _dialogue_panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	return panel

func _label(text: String, font_size := 12) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _set_label(id: String, text: String) -> void:
	var label := _labels.get(id) as Label
	if label != null:
		label.text = text

func _speaker_label(speaker_id: String) -> String:
	if speaker_label_resolver.is_valid():
		return String(speaker_label_resolver.call(speaker_id))
	return speaker_id

func _load_texture(reference: String) -> Texture2D:
	if texture_loader.is_valid():
		return texture_loader.call(reference) as Texture2D
	return null

func _clear_options() -> void:
	if options_container == null:
		return
	for child in options_container.get_children():
		if child is Control:
			var control := child as Control
			control.visible = false
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if child is BaseButton:
			(child as BaseButton).disabled = true
		child.queue_free()

func _command_payload(event_id: String, node_id: String, option_id: String) -> Dictionary:
	return {
		"event_id": event_id,
		"node_id": node_id,
		"option_id": option_id
	}

func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
