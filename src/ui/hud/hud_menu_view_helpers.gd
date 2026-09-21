extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

var texture_resolver: Callable

func label(text: String, font_size := 12) -> Label:
	var result := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(result)
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	return result

func button() -> Button:
	return UiContentBounds.fit_button(Button.new())

func section_label(text: String) -> Label:
	return wrapped_label(text, 11)

func wrapped_label(text: String, font_size := 12) -> Label:
	var result := label(text, font_size)
	UiContentBounds.fit_label(result, true, true)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func card_frame(content: Control, selected := false, centered := false) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = content.custom_minimum_size + Vector2(6, 6)
	_ignore_mouse(frame)
	frame.add_theme_stylebox_override("panel", menu_card_style(selected))
	if centered:
		var center := CenterContainer.new()
		center.name = "ContentCenter"
		_ignore_mouse(center)
		frame.add_child(center)
		center.add_child(content)
	else:
		frame.add_child(content)
	return frame

func detail_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "DetailCard"
	card.custom_minimum_size = Vector2(288, 42)
	_ignore_mouse(card)
	var card_style := menu_card_style(false)
	card_style.content_margin_left += 6.0
	card_style.content_margin_top += 4.0
	card_style.content_margin_right += 6.0
	card_style.content_margin_bottom += 4.0
	card.add_theme_stylebox_override("panel", card_style)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 3)
	card.add_child(rows)
	rows.add_child(section_label(title))
	return card

func detail_card_with_text(title: String, text: String) -> PanelContainer:
	var card := detail_card(title)
	var rows := card.get_node("Rows") as VBoxContainer
	rows.add_child(section_label(text))
	return card

func icon_text_row(icon_reference: String, text: String, font_size := 11) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "IconTextRow"
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 6)
	row.add_child(item_icon_rect(icon_reference, Vector2(24, 24)))
	var text_label := label(text, font_size)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_label)
	return row

func item_icon_rect(icon_reference: String, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load_texture(icon_reference)
	_ignore_mouse(icon)
	return icon

func command_button(text: String, command, emit_command: Callable, min_size: Vector2, focus_mode: int, icon_reference := "", tooltip := "") -> Button:
	var result := command_button_base(text, min_size, focus_mode, icon_reference, tooltip)
	result.pressed.connect(func(): emit_command.call(command))
	return result

func command_button_base(text: String, min_size: Vector2, focus_mode: int, icon_reference := "", tooltip := "") -> Button:
	var result := button()
	result.text = text
	result.custom_minimum_size = min_size
	result.focus_mode = focus_mode
	result.mouse_filter = Control.MOUSE_FILTER_STOP
	result.tooltip_text = tooltip
	if not icon_reference.is_empty():
		result.icon = load_texture(icon_reference)
		result.expand_icon = true
		result.add_theme_constant_override("icon_max_width", 18)
	return result

func button_style(color: Color, rounded := false) -> StyleBoxFlat:
	return PixelUiTheme.button_style(color, rounded)

func menu_card_style(selected := false) -> StyleBoxTexture:
	return PixelUiTheme.parchment_card_style(selected)

func crafting_card_style(row_model: Dictionary) -> StyleBoxTexture:
	var selected := bool(row_model.get("selected", false))
	var style := menu_card_style(selected)
	if bool(row_model.get("craftable", false)):
		style = menu_card_style(true)
	elif String(row_model.get("reason", "")) == "missing_materials":
		style.modulate_color = Color(0.88, 0.62, 0.54, 1.0)
	return style

func load_texture(reference: String) -> Texture2D:
	if reference.is_empty() or not texture_resolver.is_valid():
		return null
	return texture_resolver.call(reference) as Texture2D

func ignore_mouse(control: Control) -> void:
	_ignore_mouse(control)

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)
