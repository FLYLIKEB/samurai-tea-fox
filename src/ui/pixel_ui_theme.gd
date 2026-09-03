class_name PixelUiTheme
extends RefCounted

const FONT_GALMURI := "res://assets/fonts/galmuri/Galmuri11.ttf"
const BORDER_COLOR := Color(0.73, 0.55, 0.31, 0.95)

static func create() -> Theme:
	var theme := Theme.new()
	var font := _load_font()
	if font != null:
		theme.default_font = font
	theme.default_font_size = 12
	theme.set_color("font_color", "Button", Color(0.93, 0.83, 0.63, 1.0))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.79, 1.0))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 0.95, 0.79, 1.0))
	theme.set_color("font_disabled_color", "Button", Color(0.54, 0.50, 0.42, 1.0))
	theme.set_stylebox("normal", "Button", button_style(Color(0.10, 0.08, 0.06, 0.86)))
	theme.set_stylebox("hover", "Button", button_style(Color(0.16, 0.12, 0.08, 0.92)))
	theme.set_stylebox("pressed", "Button", button_style(Color(0.77, 0.54, 0.25, 0.96)))
	theme.set_stylebox("focus", "Button", button_style(Color(0.16, 0.12, 0.08, 0.92)))
	theme.set_stylebox("disabled", "Button", button_style(Color(0.055, 0.049, 0.038, 0.60)))
	return theme

static func button_style(color: Color, rounded := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = BORDER_COLOR
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 3
	style.content_margin_top = 3
	style.content_margin_right = 3
	style.content_margin_bottom = 3
	if rounded:
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_right = 12
		style.corner_radius_bottom_left = 12
	return style

static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.049, 0.038, 0.90)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

static func _load_font() -> Font:
	if not ResourceLoader.exists(FONT_GALMURI):
		return null
	var font := ResourceLoader.load(FONT_GALMURI) as Font
	if font is FontFile:
		var font_file := font as FontFile
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font
