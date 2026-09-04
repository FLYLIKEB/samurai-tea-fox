extends PanelContainer
class_name ProximityInteractionPrompt

const PIXEL_FONT_PATH := "res://assets/fonts/galmuri/Galmuri11.ttf"

func configure(title: String, action_text: String, position: Vector2, size: Vector2) -> void:
	name = "InteractionPrompt"
	self.position = position
	self.size = size
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("1b1028", 0.96)
	background.border_color = Color("d5a84a")
	background.set_border_width_all(3)
	background.set_corner_radius_all(3)
	background.content_margin_left = 3
	background.content_margin_right = 3
	background.content_margin_top = 1
	background.content_margin_bottom = 1
	add_theme_stylebox_override("panel", background)
	var label := Label.new()
	label.text = "%s\n%s" % [title, action_text]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pixel_font := _load_pixel_font()
	if pixel_font != null:
		label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("ffe7a3"))
	label.add_theme_color_override("font_shadow_color", Color("1a1024"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)

func _load_pixel_font() -> Font:
	if not ResourceLoader.exists(PIXEL_FONT_PATH, "Font"):
		return null
	return ResourceLoader.load(PIXEL_FONT_PATH, "Font") as Font
