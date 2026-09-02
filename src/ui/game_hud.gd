extends CanvasLayer
class_name GameHud

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")

const FONT_GALMURI := "res://assets/fonts/galmuri/Galmuri11.ttf"
const ICON_HP := "res://assets/ui/icons/hp_heart_32.png"
const ICON_KI := "res://assets/ui/icons/tea_cup_32.png"
const ICON_KOKORO := "res://assets/ui/icons/tea_leaf_32.png"
const ICON_MAP := "res://assets/ui/icons/map_pin_32.png"
const ICON_BAG := "res://assets/ui/icons/atlas/bag.png"
const ICON_ABILITY := "res://assets/ui/icons/atlas/talisman.png"
const ICON_DODGE := "res://assets/ui/icons/atlas/dash_streaks.png"
const ICON_ATTACK := "res://assets/ui/icons/atlas/attack_sword.png"
const ICON_TEA := "res://assets/ui/icons/atlas/tea_action_cup.png"
const ICON_CONSUMABLE := "res://assets/ui/icons/atlas/gourd.png"
const BUTTON_DPAD := "res://assets/ui/controls/dpad.png"

const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"

signal mobile_command_issued(command)

signal movement_button_changed(direction: Vector2i)

var player
var world: Dictionary = {}
var render_result: Dictionary = {}
var catalog
var inventory
var tea_service
var time_state
var _labels: Dictionary = {}
var _panels: Dictionary = {}
var _mobile_adapter := MobileCommandAdapter.new()
var _built := false
var _theme: Theme
var _time_refresh_elapsed := 0.0
var _action_grid: GridContainer

func _ready() -> void:
	_build()
	_bind_runtime_signals()
	_update()

func configure(player_node, generated_world: Dictionary, generated_render_result: Dictionary, runtime_context := {}) -> void:
	_unbind_runtime_signals()
	player = player_node
	world = generated_world.duplicate(true)
	render_result = generated_render_result.duplicate(true)
	if typeof(runtime_context) == TYPE_DICTIONARY:
		catalog = runtime_context.get("catalog", null)
		inventory = runtime_context.get("inventory", null)
		tea_service = runtime_context.get("tea_service", null)
		time_state = runtime_context.get("time_state", null)
	_build()
	_rebuild_action_buttons()
	_apply_safe_area_layout()
	_bind_runtime_signals()
	_update()

func runtime_read_model() -> Dictionary:
	var resources = _object_property(player, "resources")
	var phase_name := String(_object_property(time_state, "phase", "day"))
	return {
		"hp": int(_object_property(resources, "hp", 0)),
		"hp_max": int(_object_property(resources, "hp_max", 0)),
		"ki": int(_object_property(resources, "ki", 0)),
		"ki_max": int(_object_property(resources, "ki_max", 0)),
		"kokoro": int(_object_property(resources, "kokoro", 0)),
		"kokoro_max": int(_object_property(resources, "kokoro_max", 0)),
		"inventory_slot_count": _inventory_slot_count(),
		"inventory_used_slots": _inventory_used_slots(),
		"tea_quickslot_count": _tea_quickslot_count(),
		"tea_ready_slots": _tea_ready_slots(),
		"consumable_ready": _consumable_ready(),
		"ability_slot_count": _balance_integer(BALANCE_ABILITY_SLOTS_ID),
		"time_phase": phase_name,
		"time_phase_label": _time_phase_label(phase_name),
		"time_progress_percent": _time_progress_percent(),
		"biome_label": _biome_label(String(world.get("biome_id", "common_region"))),
		"terrain_count": _render_count("terrain"),
		"object_count": _render_count("entities") + _render_count("Landmarks")
	}

func press_mobile_button(button_id: String, direction := Vector2i.ZERO, slot := 0) -> bool:
	var command = _mobile_adapter.command_for_button(button_id, direction, slot)
	if not command is GameCommand:
		return false
	mobile_command_issued.emit(command)
	return true

func _process(delta: float) -> void:
	if time_state == null:
		return
	_time_refresh_elapsed += maxf(delta, 0.0)
	if _time_refresh_elapsed < 0.25:
		return
	_time_refresh_elapsed = 0.0
	_update()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and _built:
		_apply_safe_area_layout()

func _build() -> void:
	if _built:
		return
	_built = true
	_theme = _pixel_theme()

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(root)
	root.theme = _theme
	add_child(root)

	var status_panel := _panel(Vector2(166, 82))
	status_panel.name = "StatusPanel"
	root.add_child(status_panel)
	_panels.status = status_panel
	var status_rows := VBoxContainer.new()
	_ignore_mouse(status_rows)
	status_rows.add_theme_constant_override("separation", 4)
	status_panel.add_child(status_rows)
	_labels.hp = _add_icon_row(status_rows, ICON_HP, "HP")
	_labels.ki = _add_icon_row(status_rows, ICON_KI, "기운")
	_labels.kokoro = _add_icon_row(status_rows, ICON_KOKORO, "心")

	var map_panel := _panel(Vector2(202, 78))
	map_panel.name = "MapPanel"
	root.add_child(map_panel)
	_panels.map = map_panel
	var map_rows := VBoxContainer.new()
	_ignore_mouse(map_rows)
	map_rows.add_theme_constant_override("separation", 3)
	map_panel.add_child(map_rows)
	_labels.map_title = _add_icon_row(map_rows, ICON_MAP, "초록 평원")
	_labels.time = _add_icon_row(map_rows, "res://assets/ui/icons/atlas/moon.png", "낮 0%")
	_labels.map_stats = _label("타일 0 · 사물 0", 11)
	map_rows.add_child(_labels.map_stats)

	var quickslot_panel := _panel(Vector2(304, 42))
	quickslot_panel.name = "QuickSlotPanel"
	root.add_child(quickslot_panel)
	_panels.quickslot = quickslot_panel
	var quick_rows := HBoxContainer.new()
	_ignore_mouse(quick_rows)
	quick_rows.add_theme_constant_override("separation", 6)
	quickslot_panel.add_child(quick_rows)
	_labels.inventory = _add_icon_row(quick_rows, ICON_BAG, "가방")
	_labels.tea_slots = _add_icon_row(quick_rows, ICON_KI, "차")
	_labels.consumable = _add_icon_row(quick_rows, ICON_CONSUMABLE, "소모")
	_labels.abilities = _add_icon_row(quick_rows, ICON_ABILITY, "요술")

	var dpad_panel := _panel(Vector2(132, 132))
	dpad_panel.name = "DPadPanel"
	root.add_child(dpad_panel)
	_panels.dpad = dpad_panel
	_build_dpad(dpad_panel)

	var action_panel := _panel(Vector2(294, 108))
	action_panel.name = "ActionPanel"
	root.add_child(action_panel)
	_panels.action = action_panel
	_build_actions(action_panel)

	_apply_safe_area_layout()

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update() -> void:
	if not _built:
		return
	var model := runtime_read_model()
	_set_label("hp", "HP %d / %d" % [model.hp, model.hp_max])
	_set_label("ki", "기운 %d / %d" % [model.ki, model.ki_max])
	_set_label("kokoro", "心 %d / %d" % [model.kokoro, model.kokoro_max])
	_set_label("map_title", model.biome_label)
	_set_label("time", "%s %d%%" % [model.time_phase_label, model.time_progress_percent])
	var time_label := _labels.get("time") as Label
	if time_label != null:
		time_label.get_parent().visible = time_state != null
	var map_panel := _panels.get("map") as Control
	var map_height := 78.0 if time_state != null else 54.0
	if map_panel != null and not is_equal_approx(map_panel.custom_minimum_size.y, map_height):
		map_panel.custom_minimum_size.y = map_height
		_apply_safe_area_layout()
	_set_label("map_stats", "타일 %d · 사물 %d" % [model.terrain_count, model.object_count])
	_set_label("inventory", "%d / %d" % [model.inventory_used_slots, model.inventory_slot_count])
	_set_label("tea_slots", "%d / %d" % [model.tea_ready_slots, model.tea_quickslot_count])
	_set_label("consumable", "준비" if model.consumable_ready else "없음")
	_set_label("abilities", "요술 %d" % model.ability_slot_count)

func _bind_runtime_signals() -> void:
	var resources = _object_property(player, "resources")
	_connect_runtime_signal(resources, &"hp_changed", Callable(self, "_on_resources_changed"))
	_connect_runtime_signal(resources, &"ki_changed", Callable(self, "_on_resources_changed"))
	_connect_runtime_signal(resources, &"kokoro_changed", Callable(self, "_on_resources_changed"))
	_connect_runtime_signal(inventory, &"changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(tea_service, &"changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(time_state, &"phase_changed", Callable(self, "_on_phase_changed"))

func _unbind_runtime_signals() -> void:
	var resources = _object_property(player, "resources")
	_disconnect_runtime_signal(resources, &"hp_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(resources, &"ki_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(resources, &"kokoro_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(inventory, &"changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(tea_service, &"changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(time_state, &"phase_changed", Callable(self, "_on_phase_changed"))

func _connect_runtime_signal(source, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _disconnect_runtime_signal(source, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)

func _on_resources_changed(_previous, _current, _maximum) -> void:
	_update()

func _on_snapshot_changed(_snapshot) -> void:
	_update()

func _on_phase_changed(_previous, _current) -> void:
	_time_refresh_elapsed = 0.0
	_update()

func _build_dpad(parent: PanelContainer) -> void:
	var board := Control.new()
	board.name = "DPadBoard"
	board.custom_minimum_size = Vector2(120, 120)
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
	_add_direction_button(board, "DPadUp", Rect2(40, 0, 40, 40), Vector2i.UP, "위")
	_add_direction_button(board, "DPadDown", Rect2(40, 80, 40, 40), Vector2i.DOWN, "아래")
	_add_direction_button(board, "DPadLeft", Rect2(0, 40, 40, 40), Vector2i.LEFT, "왼쪽")
	_add_direction_button(board, "DPadRight", Rect2(80, 40, 40, 40), Vector2i.RIGHT, "오른쪽")
	_add_direction_button(board, "DPadStop", Rect2(40, 40, 40, 40), Vector2i.ZERO, "정지")

func _build_actions(parent: PanelContainer) -> void:
	_action_grid = GridContainer.new()
	_action_grid.name = "ActionGrid"
	_ignore_mouse(_action_grid)
	_action_grid.columns = 4
	_action_grid.add_theme_constant_override("h_separation", 6)
	_action_grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(_action_grid)
	_rebuild_action_buttons()

func _rebuild_action_buttons() -> void:
	if _action_grid == null:
		return
	for child in _action_grid.get_children():
		child.free()
	_add_text_action(_action_grid, "AttackButton", ICON_ATTACK, "공격", "attack", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "DodgeButton", ICON_DODGE, "회피", "dodge", Vector2i.ZERO, 0)
	for slot in range(_tea_quickslot_count()):
		_add_text_action(_action_grid, "TeaButton%d" % (slot + 1), ICON_TEA, "차%d" % (slot + 1), "drink_tea", Vector2i.ZERO, slot)
	_add_text_action(_action_grid, "ConsumableButton", ICON_CONSUMABLE, "소모", "use_consumable", Vector2i.ZERO, 0)
	for slot in range(_balance_integer(BALANCE_ABILITY_SLOTS_ID)):
		_add_text_action(_action_grid, "AbilityButton%d" % (slot + 1), ICON_ABILITY, "요술%d" % (slot + 1), "cast_ability", Vector2i.ZERO, slot)
	_add_text_action(_action_grid, "InventoryButton", ICON_BAG, "가방", "open_inventory", Vector2i.ZERO, 0)
	var row_count := maxi(1, int(ceil(float(_action_grid.get_child_count()) / float(_action_grid.columns))))
	var action_size := Vector2(294, 12 + row_count * 44 + (row_count - 1) * 6)
	var action_panel := _panels.get("action") as Control
	if action_panel != null:
		action_panel.custom_minimum_size = action_size
		action_panel.size = action_size

func _add_direction_button(parent: Control, name: String, rect: Rect2, direction: Vector2i, tooltip: String) -> void:
	var button := Button.new()
	button.name = name
	button.position = rect.position
	button.size = rect.size
	button.tooltip_text = tooltip
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.button_down.connect(func(): movement_button_changed.emit(direction))
	button.button_up.connect(func(): movement_button_changed.emit(Vector2i.ZERO))
	button.focus_exited.connect(func(): movement_button_changed.emit(Vector2i.ZERO))
	parent.add_child(button)

func _add_text_action(parent: Container, name: String, icon_path: String, text: String, button_id: String, direction: Vector2i, slot: int) -> void:
	var button := Button.new()
	button.name = name
	button.custom_minimum_size = Vector2(66, 44)
	button.text = text
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.08, 0.06, 0.92)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.12, 0.08, 0.95)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.23, 0.17, 0.10, 0.98)))
	button.pressed.connect(func(): press_mobile_button(button_id, direction, slot))
	parent.add_child(button)

func _apply_safe_area_layout() -> void:
	var margin := _safe_margin()
	_place_panel(_panels.status, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y))
	_place_panel(_panels.map, Control.PRESET_TOP_RIGHT, Vector2(-margin.z, margin.y))
	_place_panel(_panels.quickslot, Control.PRESET_CENTER_TOP, Vector2(0, margin.y + 88.0))
	_place_panel(_panels.dpad, Control.PRESET_BOTTOM_LEFT, Vector2(margin.x, -margin.w))
	_place_panel(_panels.action, Control.PRESET_BOTTOM_RIGHT, Vector2(-margin.z, -margin.w))

func _place_panel(panel, preset: int, offset: Vector2) -> void:
	if not panel is Control:
		return
	var control := panel as Control
	var panel_size := control.custom_minimum_size
	control.size = panel_size
	control.set_anchors_preset(preset)
	match preset:
		Control.PRESET_TOP_LEFT:
			control.offset_left = offset.x
			control.offset_top = offset.y
			control.offset_right = offset.x + panel_size.x
			control.offset_bottom = offset.y + panel_size.y
		Control.PRESET_TOP_RIGHT:
			control.offset_left = offset.x - panel_size.x
			control.offset_top = offset.y
			control.offset_right = offset.x
			control.offset_bottom = offset.y + panel_size.y
		Control.PRESET_CENTER_TOP:
			control.offset_left = -panel_size.x * 0.5
			control.offset_top = offset.y
			control.offset_right = panel_size.x * 0.5
			control.offset_bottom = offset.y + panel_size.y
		Control.PRESET_BOTTOM_LEFT:
			control.offset_left = offset.x
			control.offset_top = offset.y - panel_size.y
			control.offset_right = offset.x + panel_size.x
			control.offset_bottom = offset.y
		Control.PRESET_BOTTOM_RIGHT:
			control.offset_left = offset.x - panel_size.x
			control.offset_top = offset.y - panel_size.y
			control.offset_right = offset.x
			control.offset_bottom = offset.y
		Control.PRESET_CENTER_BOTTOM:
			control.offset_left = -panel_size.x * 0.5
			control.offset_top = offset.y - panel_size.y
			control.offset_right = panel_size.x * 0.5
			control.offset_bottom = offset.y

func _safe_margin() -> Vector4:
	var fallback := Vector4(12, 12, 12, 12)
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return fallback
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return fallback
	return Vector4(
		maxf(fallback.x, float(safe.position.x)),
		maxf(fallback.y, float(safe.position.y)),
		maxf(fallback.z, maxf(0.0, viewport_size.x - float(safe.position.x + safe.size.x))),
		maxf(fallback.w, maxf(0.0, viewport_size.y - float(safe.position.y + safe.size.y)))
	)

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel

func _add_icon_row(parent: Container, icon_path: String, text: String) -> Label:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon := TextureRect.new()
	_ignore_mouse(icon)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(icon_path)
	row.add_child(icon)
	var value := _label(text)
	row.add_child(value)
	return value

func _label(text: String, font_size := 13) -> Label:
	var label := Label.new()
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.93, 0.83, 0.63, 1.0))
	return label

func _set_label(id: String, text: String) -> void:
	var label := _labels.get(id) as Label
	if label != null:
		label.text = text

func _pixel_theme() -> Theme:
	var theme := Theme.new()
	var font := _load_font(FONT_GALMURI)
	if font != null:
		theme.default_font = font
	theme.default_font_size = 13
	return theme

func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var font := ResourceLoader.load(path) as Font
	if font is FontFile:
		var font_file := font as FontFile
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.049, 0.038, 0.86)
	style.border_color = Color(0.73, 0.55, 0.31, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.73, 0.55, 0.31, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 3
	style.content_margin_top = 3
	style.content_margin_right = 3
	style.content_margin_bottom = 3
	return style

func _biome_label(id: String) -> String:
	match id:
		"common_region":
			return "초록 평원"
		"mountain_region":
			return "산악 지대"
		"snowfield":
			return "설원"
		"rainforest":
			return "열대 우림"
		"wasteland":
			return "황무지"
		_:
			return id

func _time_phase_label(id: String) -> String:
	match id:
		"day":
			return "낮"
		"dusk":
			return "해질녘"
		"night":
			return "밤"
		"late_night":
			return "깊은 밤"
		_:
			return id

func _render_count(key: String) -> int:
	var counts: Dictionary = render_result.get("counts", {})
	return int(counts.get(key, 0))

func _inventory_slot_count() -> int:
	return int(_object_property(inventory, "slot_count", 0))

func _inventory_used_slots() -> int:
	var slots = _object_property(inventory, "slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return 0
	var count := 0
	for slot in slots:
		if typeof(slot) == TYPE_DICTIONARY and not slot.is_empty():
			count += 1
	return count

func _tea_quickslot_count() -> int:
	return int(_object_property(tea_service, "quickslot_count", 0))

func _tea_ready_slots() -> int:
	var slots = _object_property(tea_service, "quick_slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return 0
	var count := 0
	for slot in slots:
		if typeof(slot) == TYPE_DICTIONARY and not slot.is_empty():
			count += 1
	return count

func _balance_integer(id: String) -> int:
	if catalog == null or not catalog.has_method("find_by_id"):
		return 0
	var definition: Dictionary = catalog.find_by_id("balance", id)
	return int(definition.get("value", 0))

func _consumable_ready() -> bool:
	var slots = _object_property(inventory, "slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return false
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY or int(slot.get("quantity", 0)) <= 0:
			continue
		var item_id := String(slot.get("item_id", ""))
		var definition := {}
		if inventory != null and inventory.has_method("definition_for"):
			definition = inventory.definition_for(item_id)
		elif catalog != null and catalog.has_method("find_by_id"):
			definition = catalog.find_by_id("items", item_id)
		if String(definition.get("type", "")) == "소모품":
			return true
	return false

func _time_progress_percent() -> int:
	if time_state == null:
		return 0
	var phase := StringName(_object_property(time_state, "phase", "day"))
	var elapsed := float(_object_property(time_state, "phase_elapsed_seconds", 0.0))
	var config = _object_property(time_state, "config")
	if config == null or not config.has_method("phase_duration_seconds"):
		return 0
	var duration := float(config.phase_duration_seconds(phase))
	if duration <= 0.0:
		return 0
	return clampi(int(round((elapsed / duration) * 100.0)), 0, 100)

func _object_property(object, property: String, fallback = null):
	if object == null or not object.has_method("get"):
		return fallback
	var value = object.get(property)
	return fallback if value == null else value

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
