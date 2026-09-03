extends CanvasLayer
class_name GameHud

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")

const FONT_GALMURI := "res://assets/fonts/galmuri/Galmuri11.ttf"
const ICON_HP := "ui_hp_heart_icon"
const ICON_KI := "ui_tea_cup_icon"
const ICON_KOKORO := "ui_tea_leaf_icon"
const ICON_MAP := "ui_map_pin_icon"
const ICON_BAG := "asset_assets_ui_icons_atlas_bag_png"
const ICON_ABILITY := "asset_assets_ui_icons_atlas_talisman_png"
const ICON_DODGE := "asset_assets_ui_icons_atlas_dash_streaks_png"
const ICON_ATTACK := "asset_assets_ui_icons_atlas_attack_sword_png"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_CONSUMABLE := "asset_assets_ui_icons_atlas_gourd_png"
const ICON_MOON := "asset_assets_ui_icons_atlas_moon_png"
const BUTTON_DPAD := "asset_assets_ui_controls_dpad_png"

const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"

signal mobile_command_issued(command)

signal movement_button_changed(direction: Vector2i)

var player
var world: Dictionary = {}
var render_result: Dictionary = {}
var catalog
var inventory
var inventory_command_runtime
var map_read_model_builder
var world_data
var run_state
var tea_service
var asset_catalog := AssetCatalog.new()
var _asset_catalog_ready := false
var _crafting_filter := "all"
var _selected_recipe_id := ""
var tea_brewing_command_runtime
var meta_codex_command_runtime
var crafting_service
var crafting_context: Dictionary = {}
var time_state
var _labels: Dictionary = {}
var _panels: Dictionary = {}
var _mobile_adapter := MobileCommandAdapter.new()
var _built := false
var _theme: Theme
var _time_refresh_elapsed := 0.0
var _action_grid: GridContainer
var _menu_content: VBoxContainer
var _open_menu_id := ""

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
		inventory_command_runtime = runtime_context.get("inventory_command_runtime", null)
		map_read_model_builder = runtime_context.get("map_read_model_builder", null)
		world_data = runtime_context.get("world_data", null)
		run_state = runtime_context.get("run_state", null)
		tea_service = runtime_context.get("tea_service", null)
		tea_brewing_command_runtime = runtime_context.get("tea_brewing_command_runtime", null)
		meta_codex_command_runtime = runtime_context.get("meta_codex_command_runtime", null)
		crafting_service = runtime_context.get("crafting_service", null)
		crafting_context = runtime_context.get("crafting_context", {}).duplicate(true)
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
		"object_count": _render_count("entities") + _render_count("Landmarks"),
		"minimap": _minimap_read_model()
	}

func press_mobile_button(button_id: String, direction := Vector2i.ZERO, slot := 0) -> bool:
	var command = _mobile_adapter.command_for_button(button_id, direction, slot)
	if not command is GameCommand:
		return false
	mobile_command_issued.emit(command)
	return true

func show_inventory_menu() -> bool:
	_open_menu_id = "inventory"
	_show_menu("인벤토리", _inventory_rows())
	return true

func show_crafting_menu() -> bool:
	_open_menu_id = "crafting"
	_show_menu("제작법", _crafting_rows())
	return true

func show_facilities_menu() -> bool:
	_open_menu_id = "facilities"
	_show_menu("시설", _facility_rows())
	return true

func show_tea_brewing_menu() -> bool:
	_open_menu_id = "tea_brewing"
	_show_menu("차 우리기", _tea_brewing_rows())
	return true

func show_meta_codex_menu() -> bool:
	_open_menu_id = "meta_codex"
	_show_menu("도감", _meta_codex_rows())
	return true

func show_map_menu() -> bool:
	_open_menu_id = "map"
	_show_menu("지도", _map_rows())
	return true

func hide_menu() -> bool:
	_open_menu_id = ""
	var panel := _panels.get("menu") as Control
	if panel != null:
		panel.visible = false
	return true

func active_menu_id() -> String:
	return _open_menu_id

func show_command_feedback(message: String) -> void:
	var feedback := _labels.get("menu_feedback") as Label
	if feedback != null:
		feedback.text = message
	if not _open_menu_id.is_empty():
		_refresh_open_menu()

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
	_labels.time = _add_icon_row(map_rows, ICON_MOON, "낮 0%")
	_labels.map_stats = _label("타일 0 · 사물 0", 11)
	map_rows.add_child(_labels.map_stats)
	_labels.minimap = _label("", 9)
	map_rows.add_child(_labels.minimap)

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

	var menu_panel := _panel(Vector2(244, 184))
	menu_panel.name = "MenuPanel"
	menu_panel.visible = false
	root.add_child(menu_panel)
	_panels.menu = menu_panel
	_build_menu_panel(menu_panel)

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
	var map_height := 118.0 if time_state != null else 94.0
	if map_panel != null and not is_equal_approx(map_panel.custom_minimum_size.y, map_height):
		map_panel.custom_minimum_size.y = map_height
		_apply_safe_area_layout()
	var minimap: Dictionary = model.get("minimap", {})
	_set_label("map_stats", "발견 %d · 표식 %d" % [int(minimap.get("discovered_count", 0)), int(minimap.get("marker_count", 0))] if bool(minimap.get("ok", false)) else "타일 %d · 사물 %d" % [model.terrain_count, model.object_count])
	_set_label("minimap", _minimap_text(minimap.get("minimap", {})) if bool(minimap.get("ok", false)) else "")
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
	_connect_runtime_signal(inventory_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(tea_service, &"changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(tea_brewing_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(meta_codex_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
	_connect_runtime_signal(time_state, &"phase_changed", Callable(self, "_on_phase_changed"))

func _unbind_runtime_signals() -> void:
	var resources = _object_property(player, "resources")
	_disconnect_runtime_signal(resources, &"hp_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(resources, &"ki_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(resources, &"kokoro_changed", Callable(self, "_on_resources_changed"))
	_disconnect_runtime_signal(inventory, &"changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(inventory_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(tea_service, &"changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(tea_brewing_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
	_disconnect_runtime_signal(meta_codex_command_runtime, &"read_model_changed", Callable(self, "_on_snapshot_changed"))
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
	_refresh_open_menu()

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
	_add_text_action(_action_grid, "TeaBrewingButton", ICON_TEA, "우리기", "open_tea_brewing", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "MetaCodexButton", ICON_BAG, "도감", "open_meta_codex", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "MapButton", ICON_MAP, "지도", "open_map", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "CraftingButton", ICON_CONSUMABLE, "제작", "open_crafting", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "FacilitiesButton", ICON_MAP, "시설", "open_facilities", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "SleepButton", ICON_TEA, "수면", "sleep", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "DungeonButton", ICON_ATTACK, "던전", "complete_dungeon", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "TeleportRepairButton", ICON_MAP, "수리", "repair_teleport", Vector2i.ZERO, 0)
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

func _build_menu_panel(parent: PanelContainer) -> void:
	var rows := VBoxContainer.new()
	rows.name = "MenuRows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 4)
	parent.add_child(rows)
	var header := HBoxContainer.new()
	_ignore_mouse(header)
	header.add_theme_constant_override("separation", 8)
	rows.add_child(header)
	_labels.menu_title = _label("메뉴", 14)
	header.add_child(_labels.menu_title)
	var spacer := Control.new()
	_ignore_mouse(spacer)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.name = "CloseMenuButton"
	close.text = "닫기"
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	close.pressed.connect(func(): mobile_command_issued.emit(GameCommand.new(GameCommand.Type.HIDE_MENU)))
	header.add_child(close)
	_menu_content = VBoxContainer.new()
	_menu_content.name = "MenuContent"
	_ignore_mouse(_menu_content)
	_menu_content.add_theme_constant_override("separation", 3)
	rows.add_child(_menu_content)
	_labels.menu_feedback = _label("", 11)
	rows.add_child(_labels.menu_feedback)

func _show_menu(title: String, rows: Array) -> void:
	_build()
	var panel := _panels.get("menu") as Control
	if panel == null or _menu_content == null:
		return
	_set_label("menu_title", title)
	for child in _menu_content.get_children():
		child.free()
	if rows.is_empty():
		_menu_content.add_child(_label("표시할 항목 없음", 11))
	else:
		for row in rows:
			_menu_content.add_child(row)
	panel.visible = true
	_apply_safe_area_layout()

func _refresh_open_menu() -> void:
	match _open_menu_id:
		"inventory":
			_show_menu("인벤토리", _inventory_rows())
		"crafting":
			_show_menu("제작법", _crafting_rows())
		"facilities":
			_show_menu("시설", _facility_rows())
		"tea_brewing":
			_show_menu("차 우리기", _tea_brewing_rows())
		"meta_codex":
			_show_menu("도감", _meta_codex_rows())
		"map":
			_show_menu("지도", _map_rows())

func _inventory_rows() -> Array:
	var rows: Array = []
	if inventory_command_runtime != null and inventory_command_runtime.has_method("read_model"):
		var model: Dictionary = inventory_command_runtime.read_model()
		rows.append(_label("가방 %d/%d · 필터 %s" % [int(model.capacity.used), int(model.capacity.total), String(model.filter_kind)], 11))
		var toolbar := HBoxContainer.new()
		_ignore_mouse(toolbar)
		toolbar.add_theme_constant_override("separation", 4)
		toolbar.add_child(_inventory_command_button("이전", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.LEFT)))
		toolbar.add_child(_inventory_command_button("다음", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.RIGHT)))
		toolbar.add_child(_inventory_command_button("정렬", GameCommand.new(GameCommand.Type.INVENTORY_SORT)))
		for kind in model.available_filters:
			toolbar.add_child(_inventory_command_button(String(kind), GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, {"kind": kind})))
		rows.append(toolbar)
		var visible_rows: Array = model.slots
		var page_start := _inventory_page_start(visible_rows, int(model.get("selected_slot_index", -1)), 6)
		var page_end := mini(visible_rows.size(), page_start + 6)
		for row_index in range(page_start, page_end):
			var row: Dictionary = visible_rows[row_index]
			var line := HBoxContainer.new()
			_ignore_mouse(line)
			line.add_theme_constant_override("separation", 4)
			var prefix := "▶ " if bool(row.get("selected", false)) else ""
			line.add_child(_label("%s%s" % [prefix, String(row.get("label", ""))], 11))
			line.add_child(_inventory_command_button("선택", GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, int(row.slot_index), {"slot_index": int(row.slot_index)})))
			if bool(row.get("can_use", false)):
				line.add_child(_inventory_command_button("사용", GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, int(row.slot_index), {"slot_index": int(row.slot_index)})))
			if bool(row.get("can_equip", false)):
				line.add_child(_inventory_command_button("장착", GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, int(row.slot_index), {"slot_index": int(row.slot_index)})))
			rows.append(line)
		if visible_rows.size() > 6:
			rows.append(_label("%d-%d / %d" % [page_start + 1, page_end, visible_rows.size()], 11))
		return rows
	rows.append(_label("인벤토리 read model 없음", 11))
	return rows

func _inventory_command_button(text: String, command: GameCommand) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 28)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): mobile_command_issued.emit(command))
	return button

func _inventory_page_start(rows: Array, selected_slot_index: int, page_size: int) -> int:
	if rows.size() <= page_size:
		return 0
	var selected_position := -1
	for index in range(rows.size()):
		if int(rows[index].get("slot_index", -1)) == selected_slot_index:
			selected_position = index
			break
	if selected_position < 0:
		return 0
	return clampi(selected_position - 2, 0, rows.size() - page_size)

func _tea_brewing_rows() -> Array:
	var rows: Array = []
	if tea_brewing_command_runtime == null or not tea_brewing_command_runtime.has_method("read_model"):
		rows.append(_label("차 우리기 read model 없음", 11))
		return rows
	var model: Dictionary = tea_brewing_command_runtime.read_model()
	rows.append(_label("찻잎 %d · 다구 %d · 휴대칸 %d · 장소 %s" % [
		_array_value(model.get("leaves", [])).size(),
		_array_value(model.get("vessels", [])).size(),
		_array_value(model.get("quickslots", [])).size(),
		"가능" if bool(model.get("has_brewing_location", false)) else "제한"
	], 11))
	rows.append(_tea_brewing_toolbar())
	rows.append(_label("찻잎", 11))
	var leaves := _array_value(model.get("leaves", []))
	var leaf_page := _tea_brewing_page_start(leaves, "id", String(model.get("selected_leaf_id", "")), 4)
	for leaf in leaves.slice(leaf_page, leaf_page + 4):
		rows.append(_tea_brewing_option_row(
			"▶ %s x%d" % [String(leaf.get("name", "")), int(leaf.get("quantity", 0))] if bool(leaf.get("selected", false)) else "%s x%d" % [String(leaf.get("name", "")), int(leaf.get("quantity", 0))],
			GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_LEAF, Vector2i.ZERO, -1, {"tea_id": String(leaf.get("id", ""))})
		))
	if leaves.size() > 4:
		rows.append(_label("찻잎 %d-%d / %d" % [leaf_page + 1, mini(leaves.size(), leaf_page + 4), leaves.size()], 10))
	rows.append(_label("다구", 11))
	var vessels := _array_value(model.get("vessels", []))
	var vessel_page := _tea_brewing_page_start(vessels, "selection_key", String(model.get("selected_vessel_key", "")), 4)
	for vessel in vessels.slice(vessel_page, vessel_page + 4):
		var source_label := "장착" if String(vessel.get("source", "")) == "equipped" else "보유"
		rows.append(_tea_brewing_option_row(
			"▶ %s · %s" % [String(vessel.get("name", "")), source_label] if bool(vessel.get("selected", false)) else "%s · %s" % [String(vessel.get("name", "")), source_label],
			GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_VESSEL, Vector2i.ZERO, -1, {"vessel_key": String(vessel.get("selection_key", ""))})
		))
	if vessels.size() > 4:
		rows.append(_label("다구 %d-%d / %d" % [vessel_page + 1, mini(vessels.size(), vessel_page + 4), vessels.size()], 10))
	rows.append(_label("휴대칸", 11))
	for slot in _array_value(model.get("quickslots", [])):
		rows.append(_tea_brewing_option_row(
			"▶ %s" % String(slot.get("label", "")) if bool(slot.get("selected", false)) else String(slot.get("label", "")),
			GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_SLOT, Vector2i.ZERO, int(slot.get("slot_index", -1)), {"slot_index": int(slot.get("slot_index", -1))})
		))
	var preview: Dictionary = model.get("preview", {})
	rows.append(_label(_tea_brewing_preview_label(preview), 11))
	var brew_button := _tea_brewing_command_button("우리기", GameCommand.new(GameCommand.Type.BREW_TEA))
	brew_button.disabled = not bool(model.get("can_brew", false))
	rows.append(brew_button)
	return rows

func _tea_brewing_toolbar() -> HBoxContainer:
	var toolbar := HBoxContainer.new()
	_ignore_mouse(toolbar)
	toolbar.add_theme_constant_override("separation", 4)
	toolbar.add_child(_tea_brewing_command_button("찻잎‹", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": "leaf"})))
	toolbar.add_child(_tea_brewing_command_button("찻잎›", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "leaf"})))
	toolbar.add_child(_tea_brewing_command_button("다구‹", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": "vessel"})))
	toolbar.add_child(_tea_brewing_command_button("다구›", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "vessel"})))
	toolbar.add_child(_tea_brewing_command_button("칸›", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "slot"})))
	return toolbar

func _tea_brewing_option_row(text: String, command: GameCommand) -> HBoxContainer:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 4)
	var label := _label(text, 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_tea_brewing_command_button("선택", command))
	return row

func _tea_brewing_command_button(text: String, command: GameCommand) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 28)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): mobile_command_issued.emit(command))
	return button

func _tea_brewing_page_start(rows: Array, key: String, selected: String, page_size: int) -> int:
	if rows.size() <= page_size:
		return 0
	var selected_position := -1
	for index in range(rows.size()):
		if String(rows[index].get(key, "")) == selected:
			selected_position = index
			break
	if selected_position < 0:
		return 0
	return clampi(selected_position - 1, 0, rows.size() - page_size)

func _tea_brewing_preview_label(preview: Dictionary) -> String:
	if not bool(preview.get("ok", false)):
		return "미리보기 불가: %s" % String(preview.get("reason", "unknown"))
	var prepared: Dictionary = preview.get("prepared_tea", {})
	var slot_status := "빈 칸" if not bool(preview.get("target_slot_occupied", false)) else "차 있음"
	return "미리보기 %s + %s · 기운 +%d · %d회 · %.1fs · %s" % [
		String(prepared.get("tea_name", prepared.get("tea_id", ""))),
		String(prepared.get("vessel_name", prepared.get("vessel_id", ""))),
		int(prepared.get("ki_recovery", 0)),
		int(prepared.get("remaining_uses", 0)),
		float(prepared.get("drink_seconds", 0.0)),
		slot_status
	]

func _meta_codex_rows() -> Array:
	var rows: Array = []
	if meta_codex_command_runtime == null or not meta_codex_command_runtime.has_method("read_model"):
		rows.append(_label("도감 read model 없음", 11))
		return rows
	var model: Dictionary = meta_codex_command_runtime.read_model()
	rows.append(_label("탭 %s · 필터 %s · 발견 %d · 엔딩 %d" % [
		String(model.get("selected_tab", "")),
		String(model.get("filter_mode", "")),
		int(_dictionary_value(model.get("counts", {})).get("discovered_records", 0)),
		int(_dictionary_value(model.get("counts", {})).get("endings", 0))
	], 11))
	var tabs := HBoxContainer.new()
	_ignore_mouse(tabs)
	tabs.add_theme_constant_override("separation", 4)
	for tab in _array_value(model.get("available_tabs", [])):
		tabs.add_child(_meta_codex_command_button(_meta_tab_label(String(tab)), GameCommand.new(GameCommand.Type.META_CODEX_SET_TAB, Vector2i.ZERO, -1, {"tab": String(tab)})))
	rows.append(tabs)
	var filters := HBoxContainer.new()
	_ignore_mouse(filters)
	filters.add_theme_constant_override("separation", 4)
	filters.add_child(_meta_codex_command_button("전체", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "all"})))
	filters.add_child(_meta_codex_command_button("발견", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "discovered"})))
	filters.add_child(_meta_codex_command_button("미발견", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "masked"})))
	filters.add_child(_meta_codex_command_button("‹", GameCommand.new(GameCommand.Type.META_CODEX_NAVIGATE, Vector2i.LEFT)))
	filters.add_child(_meta_codex_command_button("›", GameCommand.new(GameCommand.Type.META_CODEX_NAVIGATE, Vector2i.RIGHT)))
	rows.append(filters)
	var model_rows := _array_value(model.get("rows", []))
	var detail := _dictionary_value(model.get("detail", {}))
	var page_start := _meta_codex_page_start(model_rows, String(detail.get("id", "")), 5)
	for index in range(page_start, mini(model_rows.size(), page_start + 5)):
		var row: Dictionary = model_rows[index]
		rows.append(_meta_codex_option_row(
			"▶ %s · %s" % [String(row.get("name", "")), String(row.get("summary", ""))] if bool(row.get("selected", false)) else "%s · %s" % [String(row.get("name", "")), String(row.get("summary", ""))],
			GameCommand.new(GameCommand.Type.META_CODEX_SELECT_DETAIL, Vector2i.ZERO, -1, {"id": String(row.get("id", ""))})
		))
	if model_rows.size() > 5:
		rows.append(_label("항목 %d-%d / %d" % [page_start + 1, mini(model_rows.size(), page_start + 5), model_rows.size()], 10))
	rows.append(_label("상세: %s" % _meta_detail_text(detail), 10))
	return rows

func _meta_codex_option_row(text: String, command: GameCommand) -> HBoxContainer:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 4)
	var label := _label(text, 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_meta_codex_command_button("보기", command))
	return row

func _meta_codex_command_button(text: String, command: GameCommand) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 28)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): mobile_command_issued.emit(command))
	return button

func _meta_codex_page_start(rows: Array, selected: String, page_size: int) -> int:
	if rows.size() <= page_size:
		return 0
	for index in range(rows.size()):
		if String(rows[index].get("id", "")) == selected:
			return clampi(index - 2, 0, rows.size() - page_size)
	return 0

func _meta_detail_text(detail: Dictionary) -> String:
	if detail.is_empty():
		return "표시할 항목 없음"
	if bool(detail.get("masked", false)):
		return "미발견 항목 — 스포일러를 가립니다"
	var related := _dictionary_value(detail.get("related", {}))
	var characters := _array_value(related.get("characters", []))
	var memories := _array_value(related.get("memories", []))
	var parts := [String(detail.get("name", detail.get("id", "")))]
	if not characters.is_empty():
		parts.append("인물 %s" % ", ".join(_related_names(characters)))
	if not memories.is_empty():
		parts.append("기억 %s" % ", ".join(_related_names(memories)))
	return " · ".join(parts)

func _related_names(rows: Array) -> Array:
	var names := []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			names.append(String(row.get("name", row.get("id", ""))))
		else:
			names.append(String(row))
	return names

func _meta_tab_label(tab: String) -> String:
	match tab:
		"quests":
			return "퀘스트"
		"teas":
			return "차"
		"tea_ware":
			return "다구"
		"yokai":
			return "요괴"
		"memories":
			return "기억"
		_:
			return tab

func _crafting_rows() -> Array:
	var rows: Array = []
	if crafting_service == null or not crafting_service.has_method("read_model"):
		return rows
	var model: Dictionary = crafting_service.read_model(inventory, crafting_context, {
		"category": _crafting_filter,
		"selected_recipe_id": _selected_recipe_id
	})
	if not bool(model.get("ok", false)):
		rows.append(_label("제작 read model 없음", 11))
		return rows
	_selected_recipe_id = String(model.get("selected_recipe_id", ""))
	var counts: Dictionary = model.get("counts", {})
	rows.append(_label("제작법 %d/%d · 가능 %d · 필터 %s" % [
		int(counts.get("visible", 0)),
		int(counts.get("total", 0)),
		int(counts.get("craftable", 0)),
		_crafting_filter_label(_crafting_filter)
	], 11))
	var filters := HBoxContainer.new()
	_ignore_mouse(filters)
	filters.add_theme_constant_override("separation", 4)
	for category in model.get("categories", []):
		var category_id := String(category)
		filters.add_child(_crafting_filter_button(_crafting_filter_label(category_id), category_id))
	rows.append(filters)
	var model_rows: Array = model.get("rows", [])
	var page_start := _crafting_page_start(model_rows, _selected_recipe_id, 5)
	for index in range(page_start, mini(model_rows.size(), page_start + 5)):
		rows.append(_crafting_row(model_rows[index]))
	if model_rows.size() > 5:
		rows.append(_label("항목 %d-%d / %d" % [page_start + 1, mini(model_rows.size(), page_start + 5), model_rows.size()], 10))
	rows.append(_crafting_detail_row(model.get("detail", {})))
	return rows

func _crafting_row(row_model: Dictionary) -> Control:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 4)
	var prefix := "▶ " if bool(row_model.get("selected", false)) else ""
	var label := _label("%s%s · %s" % [
		prefix,
		String(row_model.get("name", row_model.get("recipe_id", ""))),
		String(row_model.get("reason_label", ""))
	], 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var select_button := Button.new()
	select_button.text = "상세"
	select_button.custom_minimum_size = Vector2(52, 28)
	select_button.focus_mode = Control.FOCUS_ALL
	select_button.mouse_filter = Control.MOUSE_FILTER_STOP
	var recipe_id := String(row_model.get("recipe_id", ""))
	select_button.pressed.connect(func():
		_selected_recipe_id = recipe_id
		_refresh_open_menu()
	)
	row.add_child(select_button)
	var button := Button.new()
	button.text = "제작"
	button.disabled = not bool(row_model.get("craftable", false))
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func():
		mobile_command_issued.emit(GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, 0, {"recipe_id": recipe_id}))
	)
	row.add_child(button)
	return row

func _crafting_filter_button(text: String, category: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(54, 28)
	button.disabled = category == _crafting_filter
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func():
		_crafting_filter = category
		_selected_recipe_id = ""
		_refresh_open_menu()
	)
	return button

func _crafting_detail_row(detail: Dictionary) -> Label:
	if detail.is_empty():
		return _label("상세: 표시할 제작법 없음", 10)
	var result: Dictionary = detail.get("result", {})
	var parts := [
		"상세 %s → %s x%d" % [
			String(detail.get("recipe_id", "")),
			String(result.get("name", result.get("item_id", ""))),
			int(result.get("quantity", 1))
		],
		String(detail.get("reason_label", ""))
	]
	var materials := []
	for material in detail.get("materials", []):
		materials.append("%s %d/%d" % [
			String(material.get("name", material.get("item_id", ""))),
			int(material.get("available", 0)),
			int(material.get("required", 0))
		])
	if not materials.is_empty():
		parts.append("재료 %s" % ", ".join(materials))
	var facilities := []
	for facility in detail.get("facilities", []):
		facilities.append("%s%s" % [
			String(facility.get("name", facility.get("item_id", ""))),
			"" if bool(facility.get("available", false)) else "(필요)"
		])
	if facilities.is_empty():
		parts.append("손제작")
	else:
		parts.append("시설 %s" % ", ".join(facilities))
	var unlock_biome_id := String(detail.get("unlock_biome_id", ""))
	if not unlock_biome_id.is_empty():
		parts.append("해금 %s" % unlock_biome_id)
	return _label(" · ".join(parts), 10)

func _crafting_page_start(rows: Array, selected: String, page_size: int) -> int:
	if rows.size() <= page_size:
		return 0
	for index in range(rows.size()):
		if String(rows[index].get("recipe_id", "")) == selected:
			return clampi(index - 2, 0, rows.size() - page_size)
	return 0

func _crafting_filter_label(category: String) -> String:
	return "전체" if category == "all" else category

func _facility_rows() -> Array:
	var rows: Array = []
	for node in world.get("facility_nodes", []):
		var position: Dictionary = node.get("position", {})
		rows.append(_label("%s (%d,%d)" % [
			String(node.get("facility_term", node.get("id", ""))),
			int(position.get("x", 0)),
			int(position.get("y", 0))
		], 11))
	if crafting_service != null and crafting_service.has_method("read_model"):
		var model: Dictionary = crafting_service.read_model(inventory, crafting_context)
		var facilities := {}
		for recipe in model.get("rows", []):
			for facility in recipe.get("facilities", []):
				var item_id := String(facility.get("item_id", ""))
				if item_id.is_empty():
					continue
				var current: Dictionary = facilities.get(item_id, {
					"name": String(facility.get("name", item_id)),
					"available": false
				})
				current.available = bool(current.available) or bool(facility.get("available", false))
				facilities[item_id] = current
		var facility_ids := facilities.keys()
		facility_ids.sort()
		for item_id in facility_ids:
			var facility: Dictionary = facilities[item_id]
			rows.append(_label("%s · %s" % [
				String(facility.get("name", item_id)),
				"사용 가능" if bool(facility.get("available", false)) else "필요"
			], 11))
	return rows

func _map_rows() -> Array:
	var rows: Array = []
	var model := _map_read_model({"minimap_width": 21, "minimap_height": 13})
	if not bool(model.get("ok", false)):
		rows.append(_label("지도 read model 없음", 11))
		return rows
	var bounds: Dictionary = model.bounds
	rows.append(_label("지도 %dx%d · 발견 %d · 안개 %d" % [int(bounds.width), int(bounds.height), int(model.discovered_count), int(model.fog_count)], 11))
	rows.append(_label("플레이어 (%d,%d)" % [int(model.player.position.x), int(model.player.position.y)], 11))
	for line in _minimap_text_lines(model.minimap):
		rows.append(_label(line, 9))
	var markers: Array = model.markers
	for index in range(mini(markers.size(), 8)):
		var marker: Dictionary = markers[index]
		var position: Dictionary = marker.position
		rows.append(_label("%s %s (%d,%d)%s" % [
			_marker_label(String(marker.marker_type)),
			String(marker.id),
			int(position.x),
			int(position.y),
			"" if bool(marker.get("discovered", true)) else " · 미발견"
		], 10))
	if markers.size() > 8:
		rows.append(_label("… 표식 %d개 더 있음" % (markers.size() - 8), 10))
	return rows

func _minimap_read_model() -> Dictionary:
	var model := _map_read_model({"minimap_width": 11, "minimap_height": 7})
	if not bool(model.get("ok", false)):
		return model
	return {
		"ok": true,
		"discovered_count": int(model.discovered_count),
		"marker_count": _array_value(model.get("markers", [])).size(),
		"minimap": model.minimap
	}

func _map_read_model(options := {}) -> Dictionary:
	if map_read_model_builder == null or not map_read_model_builder.has_method("build"):
		return {"ok": false, "reason": "missing_map_read_model_builder"}
	return map_read_model_builder.build(world_data if world_data != null else world, run_state, _player_cell(), options)

func _player_cell() -> Vector2i:
	var position := Vector2.ZERO
	if player != null and player.has_method("get"):
		position = player.get("global_position")
	var tile_size := 32
	if world_data != null and world_data.has_method("get"):
		tile_size = max(1, int(world_data.get("tile_size")))
	return Vector2i(int(floor(position.x / float(tile_size))), int(floor(position.y / float(tile_size))))

func _marker_label(marker_type: String) -> String:
	match marker_type:
		"player":
			return "플레이어"
		"dungeon":
			return "던전"
		"teleport":
			return "텔레포트"
		_:
			return "표식"

func _minimap_text(minimap: Dictionary) -> String:
	var lines := _minimap_text_lines(minimap)
	return "\n".join(lines)

func _minimap_text_lines(minimap: Dictionary) -> Array:
	if minimap.is_empty() or typeof(minimap.get("cells", [])) != TYPE_ARRAY:
		return []
	var origin: Dictionary = minimap.get("origin", {})
	var size: Dictionary = minimap.get("size", {})
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0 or height <= 0:
		return []
	var glyphs := {}
	for cell in minimap.cells:
		var position: Dictionary = cell.get("position", {})
		glyphs["%d,%d" % [int(position.x), int(position.y)]] = "?" if bool(cell.get("fog", true)) else "."
	for marker in _array_value(minimap.get("markers", [])):
		var position: Dictionary = marker.get("position", {})
		glyphs["%d,%d" % [int(position.x), int(position.y)]] = _marker_glyph(String(marker.get("marker_type", "")))
	var lines := []
	for y in range(int(origin.get("y", 0)), int(origin.get("y", 0)) + height):
		var line := ""
		for x in range(int(origin.get("x", 0)), int(origin.get("x", 0)) + width):
			line += String(glyphs.get("%d,%d" % [x, y], "?"))
		lines.append(line)
	return lines

func _marker_glyph(marker_type: String) -> String:
	match marker_type:
		"player":
			return "@"
		"dungeon":
			return "D"
		"teleport":
			return "T"
		_:
			return "L"

func _inventory_definition(item_id: String) -> Dictionary:
	if inventory != null and inventory.has_method("definition_for"):
		return inventory.definition_for(item_id)
	if catalog != null and catalog.has_method("find_by_id"):
		return catalog.find_by_id("items", item_id)
	return {"id": item_id, "name": item_id}

func _apply_safe_area_layout() -> void:
	var margin := _safe_margin()
	_place_panel(_panels.status, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y))
	_place_panel(_panels.map, Control.PRESET_TOP_RIGHT, Vector2(-margin.z, margin.y))
	_place_panel(_panels.quickslot, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y + 90.0))
	_place_panel(_panels.menu, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y + 140.0))
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

func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

func _load_texture(reference: String) -> Texture2D:
	var path := reference
	if _ensure_asset_catalog():
		path = asset_catalog.path_for_reference(reference)
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _ensure_asset_catalog() -> bool:
	if _asset_catalog_ready:
		return true
	var result: Dictionary = asset_catalog.load_manifest()
	if result.ok:
		_asset_catalog_ready = true
		return true
	push_warning("HUD asset manifest failed: %s" % result.get("error", "unknown error"))
	return false
