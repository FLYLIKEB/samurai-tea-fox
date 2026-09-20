class_name PixelUiTheme
extends RefCounted

const FONT_GALMURI := "res://assets/fonts/galmuri/Galmuri11.ttf"
const BORDER_COLOR := Color(0.78, 0.58, 0.32, 1.0)
const INK_COLOR := Color(0.18, 0.12, 0.075, 1.0)
const MENU_PANEL_TEXTURE := "res://assets/ui/generated/menu_panel_hanji.png"
const CARD_TEXTURE := "res://assets/ui/generated/card_frame_hanji.png"
const CARD_SELECTED_TEXTURE := "res://assets/ui/generated/card_frame_selected.png"
const BUTTON_TEXTURE := "res://assets/ui/generated/button_frame_hanji.png"
const BUTTON_SELECTED_TEXTURE := "res://assets/ui/generated/button_frame_selected.png"

static func create() -> Theme:
	var theme := Theme.new()
	var font := _load_font()
	if font != null:
		theme.default_font = font
	theme.default_font_size = 12
	theme.set_color("font_color", "Label", Color(0.93, 0.83, 0.63, 1.0))
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

static func create_parchment() -> Theme:
	var theme := create()
	theme.set_color("font_color", "Label", INK_COLOR)
	theme.set_color("font_color", "Button", INK_COLOR)
	theme.set_color("font_hover_color", "Button", Color(0.10, 0.19, 0.10, 1.0))
	theme.set_color("font_pressed_color", "Button", INK_COLOR)
	theme.set_color("font_disabled_color", "Button", Color(0.38, 0.32, 0.24, 0.72))
	theme.set_stylebox("normal", "Button", parchment_button_style())
	theme.set_stylebox("hover", "Button", parchment_button_style(true))
	theme.set_stylebox("pressed", "Button", parchment_button_style(true))
	theme.set_stylebox("focus", "Button", parchment_button_style(true))
	var disabled := parchment_button_style()
	disabled.modulate_color = Color(0.70, 0.66, 0.58, 0.72)
	theme.set_stylebox("disabled", "Button", disabled)
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
	style.bg_color = Color(0.045, 0.041, 0.034, 0.96)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.shadow_color = Color(0.01, 0.008, 0.006, 0.72)
	style.shadow_size = 2
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

static func parchment_panel_style() -> StyleBoxTexture:
	return _texture_style(MENU_PANEL_TEXTURE, Vector4(20, 20, 20, 20), Vector4(24, 36, 24, 24))

static func parchment_card_style(selected := false) -> StyleBoxTexture:
	return _texture_style(CARD_SELECTED_TEXTURE if selected else CARD_TEXTURE, Vector4(11, 10, 11, 10), Vector4(6, 5, 6, 5))

static func parchment_button_style(selected := false) -> StyleBoxTexture:
	return _texture_style(BUTTON_SELECTED_TEXTURE if selected else BUTTON_TEXTURE, Vector4(10, 7, 10, 7), Vector4(4, 3, 4, 3))

static func _texture_style(path: String, texture_margins: Vector4, content_margins: Vector4) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path) as Texture2D
	style.texture_margin_left = texture_margins.x
	style.texture_margin_top = texture_margins.y
	style.texture_margin_right = texture_margins.z
	style.texture_margin_bottom = texture_margins.w
	style.content_margin_left = content_margins.x
	style.content_margin_top = content_margins.y
	style.content_margin_right = content_margins.z
	style.content_margin_bottom = content_margins.w
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
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
