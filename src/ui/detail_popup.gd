extends ColorRect

signal dismissed

const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

func setup(title: String, content: Control, popup_size: Vector2, panel_style: StyleBox, popup_theme: Theme = null) -> void:
	name = "DetailPopup"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.02, 0.015, 0.01, 0.72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.name = "PopupCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "PopupPanel"
	panel.custom_minimum_size = popup_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", panel_style)
	if popup_theme != null:
		panel.theme = popup_theme
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "PopupRows"
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	var header := HBoxContainer.new()
	header.name = "PopupHeader"
	rows.add_child(header)
	var heading := UiContentBounds.fit_label(Label.new())
	heading.text = title
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close := UiContentBounds.fit_button(Button.new())
	close.name = "CloseDetailPopupButton"
	close.text = "닫기"
	close.custom_minimum_size = Vector2(54, 30)
	close.pressed.connect(dismiss)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.name = "PopupScroll"
	scroll.custom_minimum_size = Vector2(popup_size.x - 12.0, popup_size.y - 44.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	rows.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

func dismiss() -> void:
	dismissed.emit()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
