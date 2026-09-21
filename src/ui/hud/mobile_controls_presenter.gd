extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

const ICON_BAG := "asset_assets_ui_icons_atlas_bag_png"
const ICON_ABILITY := "asset_assets_ui_icons_atlas_talisman_png"
const ICON_DODGE := "asset_assets_ui_icons_atlas_dash_streaks_png"
const ICON_ATTACK := "asset_assets_ui_icons_atlas_attack_sword_png"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_CONSUMABLE := "asset_assets_ui_icons_atlas_gourd_png"
const ICON_CRAFTING_SHORTCUT := "res://assets/sprites/objects/crafting/workbench_32x32.png"
const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const BUTTON_DPAD := "asset_assets_ui_controls_dpad_png"
const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"

const DPAD_BOARD_SIZE := Vector2(96, 96)
const ACTION_BUTTON_SIZE := Vector2(48, 48)
const SECONDARY_ACTION_ICON_BUTTON_SIZE := Vector2(20, 20)
const ACTION_PANEL_SIZE := Vector2(132, 126)
const BOTTOM_NAV_PANEL_SIZE := Vector2(340, 84)
const SETTINGS_BUTTON_SIZE := Vector2(60, 38)
const SIDE_SHORTCUT_FRAME_SIZE := Vector2(68, 92)
const ACTION_PANEL_COLUMNS := 2

var _action_grid: GridContainer
var _secondary_action_bar: GridContainer
var _interaction_button: Button
var _texture_resolver: Callable
var _press_mobile_button: Callable
var _movement_changed: Callable
var _tea_quickslot_count: Callable
var _balance_integer: Callable
var _panels := {}

func build(parent: Control, deps: Dictionary) -> Dictionary:
	_texture_resolver = deps.get("texture_resolver", Callable())
	_press_mobile_button = deps.get("press_mobile_button", Callable())
	_movement_changed = deps.get("movement_changed", Callable())
	_tea_quickslot_count = deps.get("tea_quickslot_count", Callable())
	_balance_integer = deps.get("balance_integer", Callable())
	var dpad_panel := _unstyled_panel(DPAD_BOARD_SIZE)
	dpad_panel.name = "DPadPanel"
	parent.add_child(dpad_panel)
	_panels.dpad = dpad_panel
	_build_dpad(dpad_panel)
	var action_panel := _unstyled_panel(ACTION_PANEL_SIZE)
	action_panel.name = "ActionPanel"
	parent.add_child(action_panel)
	_panels.action = action_panel
	_build_actions(action_panel)
	var side_shortcut_frame := TextureRect.new()
	side_shortcut_frame.name = "SideShortcutFrame"
	side_shortcut_frame.custom_minimum_size = SIDE_SHORTCUT_FRAME_SIZE
	side_shortcut_frame.texture = load("res://assets/ui/generated/hud_side_shortcuts_frame.png") as Texture2D
	side_shortcut_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	side_shortcut_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_ignore_mouse(side_shortcut_frame)
	parent.add_child(side_shortcut_frame)
	_panels.side_shortcuts = side_shortcut_frame
	var facilities_button := _button()
	facilities_button.name = "FacilitiesShortcutButton"
	facilities_button.custom_minimum_size = SETTINGS_BUTTON_SIZE
	facilities_button.text = "시설"
	facilities_button.tooltip_text = "시설"
	facilities_button.focus_mode = Control.FOCUS_NONE
	facilities_button.mouse_filter = Control.MOUSE_FILTER_STOP
	facilities_button.add_theme_font_size_override("font_size", 9)
	_apply_empty_button_style(facilities_button)
	facilities_button.pressed.connect(func(): _press("open_facilities"))
	parent.add_child(facilities_button)
	_panels.facilities_shortcut = facilities_button
	var bottom_nav := _panel(BOTTOM_NAV_PANEL_SIZE)
	bottom_nav.name = "BottomNavPanel"
	bottom_nav.clip_contents = true
	bottom_nav.add_theme_stylebox_override("panel", PixelUiTheme.hud_bottom_nav_style())
	parent.add_child(bottom_nav)
	_panels.bottom_nav = bottom_nav
	var bottom_nav_row := HBoxContainer.new()
	bottom_nav_row.name = "BottomNavRow"
	bottom_nav_row.add_theme_constant_override("separation", 5)
	_ignore_mouse(bottom_nav_row)
	bottom_nav.add_child(bottom_nav_row)
	_add_bottom_nav_item(bottom_nav_row, "TeaBrewingNavButton", ICON_TEA_WARE, "다구", "open_tea_brewing")
	_add_bottom_nav_item(bottom_nav_row, "InventoryNavButton", ICON_BAG, "가방", "open_inventory")
	_add_bottom_nav_item(bottom_nav_row, "TeaNavButton", ICON_TEA, "차", "drink_tea")
	_add_bottom_nav_item(bottom_nav_row, "CodexNavButton", ICON_SCROLL, "도감", "open_meta_codex")
	_add_bottom_nav_item(bottom_nav_row, "CraftingNavButton", ICON_CRAFTING_SHORTCUT, "제작", "open_crafting")
	return _panels.duplicate()

func rebuild_actions() -> void:
	_rebuild_action_buttons()

func panel(id: String) -> Control:
	return _panels.get(id) as Control

func _build_dpad(parent: PanelContainer) -> void:
	var board := Control.new()
	board.name = "DPadBoard"
	board.custom_minimum_size = DPAD_BOARD_SIZE
	_ignore_mouse(board)
	parent.add_child(board)
	var plate := TextureRect.new()
	plate.name = "DPadPlate"
	plate.texture = _load_texture(BUTTON_DPAD)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plate)
	var cell := DPAD_BOARD_SIZE.x / 3.0
	_add_direction_button(board, "DPadUp", Rect2(cell, 0, cell, cell), Vector2i.UP, "위")
	_add_direction_button(board, "DPadDown", Rect2(cell, cell * 2.0, cell, cell), Vector2i.DOWN, "아래")
	_add_direction_button(board, "DPadLeft", Rect2(0, cell, cell, cell), Vector2i.LEFT, "왼쪽")
	_add_direction_button(board, "DPadRight", Rect2(cell * 2.0, cell, cell, cell), Vector2i.RIGHT, "오른쪽")
	_add_direction_button(board, "DPadStop", Rect2(cell, cell, cell, cell), Vector2i.ZERO, "정지")

func _build_actions(parent: PanelContainer) -> void:
	_block_mouse(parent)
	var action_rows := VBoxContainer.new()
	action_rows.name = "ActionRows"
	_ignore_mouse(action_rows)
	action_rows.add_theme_constant_override("separation", 4)
	parent.add_child(action_rows)
	var menu_row := HBoxContainer.new()
	menu_row.name = "ActionMenuBar"
	_ignore_mouse(menu_row)
	menu_row.add_theme_constant_override("separation", 4)
	action_rows.add_child(menu_row)
	_secondary_action_bar = GridContainer.new()
	_secondary_action_bar.name = "SecondaryActionBar"
	_secondary_action_bar.columns = 5
	_ignore_mouse(_secondary_action_bar)
	_secondary_action_bar.add_theme_constant_override("h_separation", 3)
	_secondary_action_bar.add_theme_constant_override("v_separation", 3)
	menu_row.add_child(_secondary_action_bar)
	_action_grid = GridContainer.new()
	_action_grid.name = "ActionGrid"
	_ignore_mouse(_action_grid)
	_action_grid.columns = ACTION_PANEL_COLUMNS
	_action_grid.add_theme_constant_override("h_separation", 4)
	_action_grid.add_theme_constant_override("v_separation", 4)
	action_rows.add_child(_action_grid)
	_rebuild_action_buttons()

func _rebuild_action_buttons() -> void:
	if _action_grid == null:
		return
	if _secondary_action_bar != null:
		_clear_container_children(_secondary_action_bar)
		for slot in range(1, _tea_slots()):
			_add_icon_action(_secondary_action_bar, "QuickTeaButton" if slot == 0 else "QuickTeaButton%d" % (slot + 1), ICON_TEA, "차 %d 사용" % (slot + 1), "drink_tea", Vector2i.ZERO, slot)
		_add_icon_action(_secondary_action_bar, "QuickConsumableButton", ICON_CONSUMABLE, "소모품 사용", "use_consumable", Vector2i.ZERO, 0)
		for slot in range(_ability_slots()):
			_add_icon_action(_secondary_action_bar, "QuickAbilityButton" if slot == 0 else "QuickAbilityButton%d" % (slot + 1), ICON_ABILITY, "요술 %d 사용" % (slot + 1), "cast_ability", Vector2i.ZERO, slot)
	_clear_container_children(_action_grid)
	_add_text_action(_action_grid, "AttackButton", ICON_ATTACK, "공격", "attack", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "DodgeButton", ICON_DODGE, "회피", "dodge", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "TeaButton", ICON_TEA, "차", "drink_tea", Vector2i.ZERO, 0)
	_interaction_button = _add_interaction_action(_action_grid)
	var action_panel := _panels.get("action") as Control
	if action_panel != null:
		action_panel.custom_minimum_size = ACTION_PANEL_SIZE
		action_panel.size = ACTION_PANEL_SIZE

func _add_bottom_nav_item(parent: Container, name: String, icon_path: String, text: String, button_id: String) -> void:
	var button := _button()
	button.name = name
	button.custom_minimum_size = Vector2(48, 38)
	button.text = ""
	button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_empty_button_style(button)
	button.pressed.connect(func(): _press(button_id))
	parent.add_child(button)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _load_texture(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	icon.position = Vector2(-7, 2)
	icon.size = Vector2(14, 14)
	_ignore_mouse(icon)
	button.add_child(icon)
	var label := _label(text, 9)
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -20
	label.offset_bottom = -6
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", PixelUiTheme.INK_COLOR)
	_ignore_mouse(label)
	button.add_child(label)

func _add_direction_button(parent: Control, name: String, rect: Rect2, direction: Vector2i, tooltip: String) -> void:
	var button := _button()
	button.name = name
	button.position = rect.position
	button.size = rect.size
	button.tooltip_text = tooltip
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)
	var feedback := Panel.new()
	feedback.name = "PressFeedback"
	feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback.add_theme_stylebox_override("panel", _dpad_feedback_style(Color(0.92, 0.68, 0.32, 0.62)))
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.visible = false
	button.add_child(feedback)
	button.button_down.connect(func():
		feedback.visible = true
		_emit_movement(direction)
	)
	button.button_up.connect(func():
		feedback.visible = false
		_emit_movement(Vector2i.ZERO)
	)
	button.focus_exited.connect(func():
		feedback.visible = false
		_emit_movement(Vector2i.ZERO)
	)

func _add_text_action(parent: Container, name: String, icon_path: String, text: String, button_id: String, direction: Vector2i, slot: int) -> void:
	var button := _button()
	button.name = name
	button.custom_minimum_size = ACTION_BUTTON_SIZE
	button.text = ""
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _circle_button_style(Color(0.08, 0.07, 0.055, 0.96)))
	button.add_theme_stylebox_override("hover", _circle_button_style(Color(0.20, 0.15, 0.08, 0.98)))
	button.add_theme_stylebox_override("pressed", _circle_button_style(Color(0.77, 0.54, 0.25, 1.0)))
	button.pressed.connect(func(): _press(button_id, direction, slot))
	parent.add_child(button)

func _add_interaction_action(parent: Container) -> Button:
	var button := _button()
	button.name = "InteractionButton"
	button.custom_minimum_size = ACTION_BUTTON_SIZE
	button.text = "상호\n작용"
	button.tooltip_text = "가까운 유적·텔레포트와 상호작용"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _circle_button_style(Color(0.10, 0.22, 0.16, 0.92)))
	button.add_theme_stylebox_override("hover", _circle_button_style(Color(0.16, 0.38, 0.25, 0.96)))
	button.add_theme_stylebox_override("pressed", _circle_button_style(Color(0.35, 0.68, 0.42, 0.98)))
	button.pressed.connect(func(): _press("interact"))
	parent.add_child(button)
	return button

func _add_icon_action(parent: Container, name: String, icon_path: String, tooltip: String, button_id: String, direction: Vector2i, slot: int) -> void:
	var button := _button()
	button.name = name
	button.custom_minimum_size = SECONDARY_ACTION_ICON_BUTTON_SIZE
	button.text = ""
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 15)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_stylebox_override("normal", PixelUiTheme.hud_action_style())
	button.add_theme_stylebox_override("hover", PixelUiTheme.hud_action_style(Color(1.0, 0.90, 0.72, 1.0)))
	button.add_theme_stylebox_override("pressed", PixelUiTheme.hud_action_style(Color(1.0, 0.82, 0.54, 1.0)))
	button.pressed.connect(func(): _press(button_id, direction, slot))
	parent.add_child(button)

func _press(button_id: String, direction := Vector2i.ZERO, slot := 0) -> void:
	if _press_mobile_button.is_valid():
		_press_mobile_button.call(button_id, direction, slot)

func _emit_movement(direction: Vector2i) -> void:
	if _movement_changed.is_valid():
		_movement_changed.call(direction)

func _tea_slots() -> int:
	return int(_tea_quickslot_count.call()) if _tea_quickslot_count.is_valid() else 0

func _ability_slots() -> int:
	return int(_balance_integer.call(BALANCE_ABILITY_SLOTS_ID)) if _balance_integer.is_valid() else 0

func _load_texture(reference: String) -> Texture2D:
	return _texture_resolver.call(reference) as Texture2D if _texture_resolver.is_valid() else null

func _circle_button_style(color: Color) -> StyleBoxTexture:
	var tint := Color.WHITE
	if color.g > color.r * 1.5:
		tint = Color(0.72, 1.0, 0.78, 1.0)
	elif color.r > 0.5:
		tint = Color(1.0, 0.82, 0.54, 1.0)
	elif color.r > 0.15:
		tint = Color(1.0, 0.90, 0.72, 1.0)
	return PixelUiTheme.hud_action_style(tint)

func _dpad_feedback_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 0.84, 0.50, minf(color.a + 0.28, 1.0))
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _apply_empty_button_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _panel(size: Vector2) -> PanelContainer:
	return _styled_panel(size, PixelUiTheme.panel_style())

func _unstyled_panel(size: Vector2) -> PanelContainer:
	return _styled_panel(size, StyleBoxEmpty.new())

func _styled_panel(size: Vector2, style: StyleBox) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _button() -> Button:
	return UiContentBounds.fit_button(Button.new())

func _label(text: String, font_size := 12) -> Label:
	var label := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _clear_container_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _block_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
