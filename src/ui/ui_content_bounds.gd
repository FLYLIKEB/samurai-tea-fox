class_name UiContentBounds
extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")

static func fit_label(label: Label, wrap := false, bounded := false) -> Label:
	label.clip_text = bounded
	if bounded:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func fit_button(button: Button) -> Button:
	button.clip_contents = true
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return button

static func fit_close_button(button: Button) -> Button:
	fit_button(button)
	button.text = "×"
	button.custom_minimum_size = Vector2(38, 38)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", PixelUiTheme.INK_COLOR)
	button.add_theme_color_override("font_hover_color", PixelUiTheme.INK_COLOR)
	button.add_theme_stylebox_override("normal", PixelUiTheme.parchment_button_style())
	button.add_theme_stylebox_override("hover", PixelUiTheme.parchment_button_style())
	return button

static func add_safe_content(parent: Control, content: Control, margins := Vector4(6, 6, 6, 6)) -> MarginContainer:
	if parent is Button:
		fit_button(parent)
	var safe_area := MarginContainer.new()
	safe_area.name = "SafeContent"
	safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area.add_theme_constant_override("margin_left", int(margins.x))
	safe_area.add_theme_constant_override("margin_top", int(margins.y))
	safe_area.add_theme_constant_override("margin_right", int(margins.z))
	safe_area.add_theme_constant_override("margin_bottom", int(margins.w))
	parent.add_child(safe_area)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe_area.add_child(content)
	return safe_area
