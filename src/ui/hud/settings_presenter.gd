extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

const ACTION_MENU_PANEL_SIZE := Vector2(280, 180)
const SETTINGS_BUTTON_SIZE := Vector2(60, 38)

var _action_menu_open := false
var _action_menu_panel: PanelContainer
var _settings_button: Button
var _request_layout: Callable
var _return_to_start: Callable

func build(parent: Control, deps: Dictionary) -> Dictionary:
	_request_layout = deps.get("request_layout", Callable())
	_return_to_start = deps.get("return_to_start", Callable())
	_action_menu_panel = _panel(ACTION_MENU_PANEL_SIZE)
	_action_menu_panel.name = "ActionMenuPanel"
	_action_menu_panel.visible = false
	parent.add_child(_action_menu_panel)
	_build_settings_panel(_action_menu_panel)
	_settings_button = _button()
	_settings_button.name = "SettingsButton"
	_settings_button.custom_minimum_size = SETTINGS_BUTTON_SIZE
	_settings_button.text = "설정"
	_settings_button.tooltip_text = "설정"
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_button.add_theme_font_size_override("font_size", 9)
	_apply_empty_button_style(_settings_button)
	_settings_button.pressed.connect(toggle)
	parent.add_child(_settings_button)
	return {"action_menu": _action_menu_panel, "settings": _settings_button}

func is_open() -> bool:
	return _action_menu_open

func set_open(value: bool) -> void:
	_action_menu_open = value
	if _action_menu_panel != null:
		_action_menu_panel.visible = _action_menu_open
	if _request_layout.is_valid():
		_request_layout.call()

func toggle() -> void:
	set_open(not _action_menu_open)

func panel(id: String) -> Control:
	match id:
		"action_menu":
			return _action_menu_panel
		"settings":
			return _settings_button
		_:
			return null

func _build_settings_panel(parent: PanelContainer) -> void:
	_block_mouse(parent)
	var rows := VBoxContainer.new()
	rows.name = "SettingsRows"
	rows.add_theme_constant_override("separation", 10)
	parent.add_child(rows)
	var title := _label("설정", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	rows.add_child(_label("게임 음량", 11))
	var volume := HSlider.new()
	volume.name = "GameVolumeSlider"
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 5.0
	var master_bus := AudioServer.get_bus_index("Master")
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus)) * 100.0 if master_bus >= 0 else 100.0
	volume.value_changed.connect(_set_game_volume)
	rows.add_child(volume)
	var home_button := _button()
	home_button.name = "ReturnHomeButton"
	home_button.text = "홈 화면으로 돌아가기"
	home_button.custom_minimum_size = Vector2(0, 38)
	home_button.pressed.connect(func():
		if _return_to_start.is_valid():
			_return_to_start.call()
	)
	rows.add_child(home_button)
	var close_button := _button()
	close_button.name = "CloseSettingsButton"
	close_button.text = "닫기"
	close_button.custom_minimum_size = Vector2(0, 34)
	close_button.pressed.connect(toggle)
	rows.add_child(close_button)

func _set_game_volume(percent: float) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	AudioServer.set_bus_mute(master_bus, percent <= 0.0)
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(percent / 100.0, 0.0001)))

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	return panel

func _button() -> Button:
	return UiContentBounds.fit_button(Button.new())

func _label(text: String, font_size := 12) -> Label:
	var label := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _apply_empty_button_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _block_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
