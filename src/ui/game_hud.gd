extends CanvasLayer
class_name GameHud

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
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
const ICON_MATERIAL := "asset_assets_ui_icons_atlas_crate_png"
const ICON_TOOL := "asset_assets_ui_icons_atlas_low_table_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"
const ICON_CHECK := "asset_assets_ui_icons_atlas_quest_check_1_png"
const ICON_WOOD := "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png"
const ICON_STONE := "asset_assets_sprites_objects_crafting_mortar_pestle_stone_32x32_png"
const ICON_WORKBENCH := "asset_assets_sprites_objects_crafting_workbench_32x32_png"
const BUTTON_DPAD := "asset_assets_ui_controls_dpad_png"
const FIRST_RUN_PROLOGUE_EVENT_ID := "first_run_prologue"
const PROLOGUE_BACKGROUND := "prologue_first_run_father_muchau_teahouse"
const PORTRAIT_FATHER := "res://assets/sprites/portraits/major/chr_1_kitsune_father_96x96.png"
const PORTRAIT_MUCHAU := "res://assets/sprites/portraits/major/chr_8_muchau_96x96.png"
const PORTRAIT_SEN_RIKYU := "res://assets/sprites/portraits/major/chr_5_sen_rikyu_96x96.png"
const PORTRAIT_BY_CHARACTER := {
	"CHR-1": PORTRAIT_FATHER,
	"CHR-2": "res://assets/sprites/portraits/major/chr_2_wasteland_daimyo_96x96.png",
	"CHR-3": "res://assets/sprites/portraits/major/chr_3_furuta_oribe_96x96.png",
	"CHR-4": "res://assets/sprites/portraits/major/chr_4_snow_monk_96x96.png",
	"CHR-5": PORTRAIT_SEN_RIKYU,
	"CHR-6": "res://assets/sprites/portraits/major/chr_6_yokai_tea_master_96x96.png",
	"CHR-7": "res://assets/sprites/portraits/major/chr_7_mountain_potter_96x96.png",
	"CHR-8": PORTRAIT_MUCHAU,
	"CHR-9": "res://assets/sprites/portraits/major/chr_9_wandering_tea_merchant_96x96.png",
}
const PORTRAIT_PLAYER := PORTRAIT_MUCHAU

const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"
const STATUS_PANEL_SIZE := Vector2(190, 76)
const PORTRAIT_BOX_SIZE := Vector2(48, 48)
const RESOURCE_ICON_COUNT := 5
const RESOURCE_ICON_SIZE := Vector2(16, 16)
const RESOURCE_DETAIL_PANEL_SIZE := Vector2(190, 68)
const ENEMY_PANEL_SIZE := Vector2(150, 50)
const MAP_PANEL_SIZE := Vector2(132, 58)
const MAP_PANEL_TIME_HEIGHT := 84.0
const QUICKSLOT_PANEL_SIZE := Vector2(218, 32)
const DPAD_BOARD_SIZE := Vector2(84, 84)
const ACTION_BUTTON_SIZE := Vector2(68, 30)
const ACTION_MENU_BUTTON_SIZE := Vector2(26, 22)
const SECONDARY_ACTION_ICON_BUTTON_SIZE := Vector2(22, 22)
const ACTION_PANEL_SIZE := Vector2(154, 96)
const ACTION_MENU_PANEL_SIZE := Vector2(142, 132)
const ACTION_PANEL_COLUMNS := 2
const MENU_PANEL_SIZE := Vector2(560, 280)
const MENU_CONTENT_SIZE := Vector2(544, 228)
const MENU_VIEWPORT_RATIO := Vector2(0.88, 0.78)
const MENU_PANEL_PADDING := Vector2(16, 52)
const NARRATIVE_PANEL_SIZE := Vector2(560, 118)
const NARRATIVE_PORTRAIT_SIZE := Vector2(96, 96)
const NARRATIVE_PORTRAIT_FRAME_SIZE := Vector2(104, 104)
const NARRATIVE_PORTRAIT_INSET := 4.0
const NARRATIVE_PANEL_BOTTOM_OFFSET := 12.0
const TIME_DIAL_SIZE := Vector2(28, 28)
const STATUS_TOAST_DURATION := 0.9

class TimeDial:
	extends Control

	var phase := "day"
	var progress_percent := 0

	func set_time(value_phase: String, value_progress_percent: int) -> void:
		phase = value_phase
		progress_percent = clampi(value_progress_percent, 0, 100)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		var track_color := Color(0.29, 0.25, 0.22, 0.92)
		var progress_color := _phase_color()
		draw_circle(center, radius, Color(0.055, 0.049, 0.038, 0.96))
		draw_arc(center, radius, 0.0, TAU, 16, track_color, 2.0, false)
		var filled_segments := int(ceil(float(progress_percent) / 100.0 * 12.0))
		for segment in range(filled_segments):
			var start_angle := -PI * 0.5 + TAU * float(segment) / 12.0
			var end_angle := start_angle + TAU / 12.0 - 0.07
			draw_arc(center, radius, start_angle, end_angle, 2, progress_color, 2.0, false)
		_draw_phase_mark(center, progress_color)

	func _draw_phase_mark(center: Vector2, color: Color) -> void:
		if phase == "night":
			draw_circle(center - Vector2(1.0, 0.0), 4.0, color)
			draw_circle(center + Vector2(1.0, -1.0), 4.0, Color(0.055, 0.049, 0.038, 1.0))
			return
		draw_circle(center, 3.0, color)
		for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(center + direction * 5.0, center + direction * 7.0, color, 1.0, false)

	func _phase_color() -> Color:
		match phase:
			"night":
				return Color(0.37, 0.53, 0.69, 1.0)
			"dusk":
				return Color(0.83, 0.50, 0.18, 1.0)
			_:
				return Color(0.84, 0.65, 0.36, 1.0)

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
var world_origin := Vector2.ZERO
var combat_target
var run_state
var tea_service
var asset_catalog := AssetCatalog.new()
var _asset_catalog_ready := false
var _toast_queue: Array[String] = []
var _toast_label: Label
var _toast_panel: PanelContainer
var _toast_remaining := 0.0
var _crafting_filter := "all"
var _selected_recipe_id := ""
var tea_brewing_command_runtime
var meta_codex_command_runtime
var crafting_service
var crafting_context: Dictionary = {}
var biome_progression_state
var cheat_mode := false
var biome_map_previews: Dictionary = {}
var _selected_map_biome_id := ""
var time_state
var _labels: Dictionary = {}
var _panels: Dictionary = {}
var _mobile_adapter := MobileCommandAdapter.new()
var _built := false
var _theme: Theme
var _time_refresh_elapsed := 0.0
var _action_menu_open := false
var _action_grid: GridContainer
var _secondary_action_bar: HBoxContainer
var _action_menu_grid: GridContainer
var _interaction_button: Button
var _menu_content: VBoxContainer
var _minimap_grid: GridContainer
var _action_scroll: ScrollContainer
var _action_menu_scroll: ScrollContainer
var _narrative_options: HBoxContainer
var _narrative_background: TextureRect
var _narrative_left_portrait_frame: PanelContainer
var _narrative_right_portrait_frame: PanelContainer
var _narrative_left_portrait: TextureRect
var _narrative_right_portrait: TextureRect
var _open_menu_id := ""
var _time_dial: TimeDial
var _resource_detail_label: Label
var _resource_detail_id := ""
var _facility_placement_panel: PanelContainer
var _facility_placement_install_button: Button
var _facility_placement_status: Label

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
		world_origin = runtime_context.get("world_origin", Vector2.ZERO)
		combat_target = runtime_context.get("combat_target", null)
		run_state = runtime_context.get("run_state", null)
		tea_service = runtime_context.get("tea_service", null)
		tea_brewing_command_runtime = runtime_context.get("tea_brewing_command_runtime", null)
		meta_codex_command_runtime = runtime_context.get("meta_codex_command_runtime", null)
		crafting_service = runtime_context.get("crafting_service", null)
		crafting_context = runtime_context.get("crafting_context", {}).duplicate(true)
		biome_progression_state = runtime_context.get("biome_progression_state", null)
		cheat_mode = bool(runtime_context.get("cheat_mode", false))
		biome_map_previews = runtime_context.get("biome_map_previews", {}).duplicate(true)
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
		"combat_target": _combat_target_read_model(),
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

func show_facility_placement_controls() -> void:
	_build()
	if _facility_placement_panel == null:
		return
	_facility_placement_panel.visible = true
	update_facility_placement_controls(false, "설치할 칸을 선택하세요")
	_apply_safe_area_layout()

func update_facility_placement_controls(can_install: bool, status: String) -> void:
	if _facility_placement_install_button != null:
		_facility_placement_install_button.disabled = not can_install
	if _facility_placement_status != null:
		_facility_placement_status.text = status

func hide_facility_placement_controls() -> void:
	if _facility_placement_panel != null:
		_facility_placement_panel.visible = false
	_apply_safe_area_layout()

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
	_selected_map_biome_id = String(world.get("biome_id", ""))
	_show_menu("지도", _map_rows())
	return true

func show_ruin_travel_menu() -> bool:
	_open_menu_id = "ruin_travel"
	_show_menu("유적 연결지", _ruin_travel_rows())
	return true

func show_teleport_travel_menu() -> bool:
	_open_menu_id = "teleport_travel"
	_show_menu("텔레포트 연결지", _teleport_travel_rows())
	return true

func hide_menu() -> bool:
	_open_menu_id = ""
	var panel := _panels.get("menu") as Control
	if panel != null:
		panel.visible = false
	return true

func show_narrative_dialogue(read_model: Dictionary) -> bool:
	_build()
	var overlay := _panels.get("narrative_overlay") as Control
	var panel := _panels.get("narrative") as Control
	if panel == null:
		return false
	var event_id := String(read_model.get("event_id", ""))
	var node_id := String(read_model.get("node_id", ""))
	var speaker_id := String(read_model.get("speaker_id", ""))
	_set_gameplay_hud_visible(false)
	if overlay != null:
		overlay.visible = true
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if _narrative_background != null:
		_narrative_background.visible = event_id == FIRST_RUN_PROLOGUE_EVENT_ID
		_narrative_background.texture = _load_texture(PROLOGUE_BACKGROUND)
	_configure_narrative_portraits(event_id, speaker_id)
	_set_label("narrative_speaker", _speaker_label(String(read_model.get("speaker_id", ""))))
	_set_label("narrative_text", String(read_model.get("text", "")))
	_clear_narrative_options()
	for option in _array_value(read_model.get("options", [])):
		if typeof(option) != TYPE_DICTIONARY:
			continue
		var option_id := String(option.get("id", ""))
		var button := Button.new()
		button.text = "넘어가기"
		button.tooltip_text = String(option.get("display_text", "넘어가기"))
		button.custom_minimum_size = Vector2(112, 28)
		button.add_theme_font_size_override("font_size", 12)
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(func(): mobile_command_issued.emit(GameCommand.new(
			GameCommand.Type.NARRATIVE_SELECT_OPTION,
			Vector2i.ZERO,
			-1,
			{
				"event_id": event_id,
				"node_id": node_id,
				"option_id": option_id
			}
		)))
		_narrative_options.add_child(button)
	panel.visible = true
	_apply_safe_area_layout()
	return true

func hide_narrative_dialogue() -> bool:
	var overlay := _panels.get("narrative_overlay") as Control
	if overlay != null:
		overlay.visible = false
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := _panels.get("narrative") as Control
	if panel != null:
		panel.visible = false
	_set_gameplay_hud_visible(true)
	_update()
	return true

func narrative_dialogue_visible() -> bool:
	var overlay := _panels.get("narrative_overlay") as Control
	if overlay != null:
		return overlay.visible
	var panel := _panels.get("narrative") as Control
	return panel != null and panel.visible

func active_menu_id() -> String:
	return _open_menu_id

func show_command_feedback(message: String) -> void:
	var feedback := _labels.get("menu_feedback") as Label
	if feedback != null:
		feedback.text = message
	if not _open_menu_id.is_empty():
		_refresh_open_menu()

func show_status_toast(message: String) -> void:
	if message.is_empty():
		return
	if _toast_queue.size() >= 4 and _toast_queue.back() == message:
		return
	_toast_queue.append(message)
	if _toast_label != null and _toast_remaining <= 0.0:
		_advance_status_toast()

func _process(delta: float) -> void:
	if _toast_label != null and _toast_remaining > 0.0:
		_toast_remaining -= maxf(delta, 0.0)
		if _toast_remaining <= 0.0:
			_advance_status_toast()
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
	_toast_panel = _panel(Vector2(250, 30))
	_toast_panel.name = "StatusToastPanel"
	_toast_panel.z_index = 100
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	root.add_child(_toast_panel)
	_toast_label = _label("", 12)
	_toast_label.name = "StatusToastLabel"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	_toast_panel.add_child(_toast_label)

	var status_panel := _panel(STATUS_PANEL_SIZE)
	status_panel.name = "StatusPanel"
	root.add_child(status_panel)
	_panels.status = status_panel
	var status_body := HBoxContainer.new()
	status_body.name = "StatusBody"
	_ignore_mouse(status_body)
	status_body.add_theme_constant_override("separation", 8)
	status_panel.add_child(status_body)
	var portrait_box := _portrait_box(PORTRAIT_PLAYER)
	portrait_box.name = "PlayerPortrait"
	status_body.add_child(portrait_box)
	var status_rows := VBoxContainer.new()
	status_rows.name = "StatusRows"
	_ignore_mouse(status_rows)
	status_rows.add_theme_constant_override("separation", 2)
	status_body.add_child(status_rows)
	_labels.hp = _add_resource_icon_row(status_rows, "hp", ICON_HP, "체력", Color(0.86, 0.28, 0.16, 1.0))
	_labels.ki = _add_resource_icon_row(status_rows, "ki", ICON_KI, "차기", Color(0.82, 0.53, 0.19, 1.0))
	_labels.kokoro = _add_resource_icon_row(status_rows, "kokoro", ICON_KOKORO, "정신", Color(0.48, 0.40, 0.56, 1.0))
	_build_resource_detail_panel(root)

	var map_panel := _panel(MAP_PANEL_SIZE)
	map_panel.name = "MapPanel"
	root.add_child(map_panel)
	_panels.map = map_panel
	var map_rows := VBoxContainer.new()
	map_rows.name = "MapRows"
	_ignore_mouse(map_rows)
	map_rows.add_theme_constant_override("separation", 3)
	map_panel.add_child(map_rows)
	_labels.map_title = _add_icon_row(map_rows, ICON_MAP, "초록 평원")
	_build_time_dial_row(map_rows)
	_labels.map_stats = _label("타일 0 · 사물 0", 11)
	map_rows.add_child(_labels.map_stats)
	_minimap_grid = GridContainer.new()
	_minimap_grid.name = "MinimapGrid"
	_minimap_grid.columns = 11
	_minimap_grid.add_theme_constant_override("h_separation", 1)
	_minimap_grid.add_theme_constant_override("v_separation", 1)
	_ignore_mouse(_minimap_grid)
	map_rows.add_child(_minimap_grid)

	var enemy_panel := _panel(ENEMY_PANEL_SIZE)
	enemy_panel.name = "EnemyPanel"
	enemy_panel.visible = false
	root.add_child(enemy_panel)
	_panels.enemy = enemy_panel
	var enemy_rows := VBoxContainer.new()
	enemy_rows.name = "EnemyRows"
	_ignore_mouse(enemy_rows)
	enemy_rows.add_theme_constant_override("separation", 3)
	enemy_panel.add_child(enemy_rows)
	_labels.enemy_name = _add_icon_row(enemy_rows, ICON_ATTACK, "적 없음")
	_labels.enemy_hp = _label("HP 0/0", 11)
	enemy_rows.add_child(_labels.enemy_hp)
	_labels.enemy_attack = _label("공격 0", 10)
	enemy_rows.add_child(_labels.enemy_attack)

	var quickslot_panel := _panel(QUICKSLOT_PANEL_SIZE)
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

	var dpad_panel := _unstyled_panel(DPAD_BOARD_SIZE)
	dpad_panel.name = "DPadPanel"
	root.add_child(dpad_panel)
	_panels.dpad = dpad_panel
	_build_dpad(dpad_panel)

	var action_panel := _unstyled_panel(ACTION_PANEL_SIZE)
	action_panel.name = "ActionPanel"
	root.add_child(action_panel)
	_panels.action = action_panel
	_build_actions(action_panel)

	var action_menu_panel := _panel(ACTION_MENU_PANEL_SIZE)
	action_menu_panel.name = "ActionMenuPanel"
	action_menu_panel.visible = false
	root.add_child(action_menu_panel)
	_panels.action_menu = action_menu_panel
	_build_action_menu(action_menu_panel)

	var menu_panel := _menu_panel(MENU_PANEL_SIZE)
	menu_panel.name = "MenuPanel"
	menu_panel.visible = false
	root.add_child(menu_panel)
	_panels.menu = menu_panel
	_build_menu_panel(menu_panel)
	_facility_placement_panel = _panel(Vector2(250, 44))
	_facility_placement_panel.name = "FacilityPlacementPanel"
	_facility_placement_panel.visible = false
	root.add_child(_facility_placement_panel)
	var placement_row := HBoxContainer.new()
	_ignore_mouse(placement_row)
	placement_row.add_theme_constant_override("separation", 4)
	_facility_placement_panel.add_child(placement_row)
	_facility_placement_status = _label("설치할 칸을 선택하세요", 10)
	_facility_placement_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_row.add_child(_facility_placement_status)
	placement_row.add_child(_placement_command_button("회전", GameCommand.Type.FACILITY_ROTATE))
	_facility_placement_install_button = _placement_command_button("설치", GameCommand.Type.FACILITY_CONFIRM)
	_facility_placement_install_button.disabled = true
	placement_row.add_child(_facility_placement_install_button)
	placement_row.add_child(_placement_command_button("취소", GameCommand.Type.FACILITY_CANCEL))

	var narrative_overlay := Control.new()
	narrative_overlay.name = "NarrativeOverlay"
	narrative_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	narrative_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narrative_overlay.visible = false
	root.add_child(narrative_overlay)
	_panels.narrative_overlay = narrative_overlay

	_narrative_background = TextureRect.new()
	_narrative_background.name = "NarrativeBackground"
	_narrative_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_narrative_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_narrative_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_narrative_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narrative_overlay.add_child(_narrative_background)

	_narrative_left_portrait_frame = _narrative_portrait_frame("LeftPortraitFrame")
	narrative_overlay.add_child(_narrative_left_portrait_frame)
	_narrative_left_portrait = _portrait_rect("LeftPortrait")
	narrative_overlay.add_child(_narrative_left_portrait)
	_narrative_right_portrait_frame = _narrative_portrait_frame("RightPortraitFrame")
	narrative_overlay.add_child(_narrative_right_portrait_frame)
	_narrative_right_portrait = _portrait_rect("RightPortrait")
	narrative_overlay.add_child(_narrative_right_portrait)

	var narrative_panel := _dialogue_panel(NARRATIVE_PANEL_SIZE)
	narrative_panel.name = "NarrativePanel"
	narrative_panel.visible = false
	narrative_overlay.add_child(narrative_panel)
	_panels.narrative = narrative_panel
	_build_narrative_panel(narrative_panel)

	_apply_safe_area_layout()

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _block_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP

func _clear_container_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _update() -> void:
	if not _built:
		return
	var model := runtime_read_model()
	_set_label("hp", "체력")
	_set_label("ki", "차기")
	_set_label("kokoro", "정신")
	_update_resource_icons("hp_icons", model.hp, model.hp_max)
	_update_resource_icons("ki_icons", model.ki, model.ki_max)
	_update_resource_icons("kokoro_icons", model.kokoro, model.kokoro_max)
	_update_resource_detail(model)
	_set_label("map_title", model.biome_label)
	_set_label("time_phase", String(model.time_phase_label))
	_set_label("time_progress", "%d%%" % int(model.time_progress_percent))
	if _time_dial != null:
		_time_dial.set_time(String(model.time_phase), int(model.time_progress_percent))
	var combat_model: Dictionary = model.get("combat_target", {})
	var enemy_panel := _panels.get("enemy") as Control
	if enemy_panel != null:
		enemy_panel.visible = bool(combat_model.get("visible", false))
	_set_label("enemy_name", String(combat_model.get("name", "적 없음")))
	_set_label("enemy_hp", "HP %d/%d" % [int(combat_model.get("hp", 0)), int(combat_model.get("hp_max", 0))])
	_set_label("enemy_attack", "무기 공격 %d" % int(combat_model.get("attack", 0)))
	var time_label := _labels.get("time_phase") as Label
	if time_label != null:
		time_label.get_parent().get_parent().visible = time_state != null
	var map_panel := _panels.get("map") as Control
	var map_height := MAP_PANEL_TIME_HEIGHT if time_state != null else MAP_PANEL_SIZE.y
	if map_panel != null and not is_equal_approx(map_panel.custom_minimum_size.y, map_height):
		map_panel.custom_minimum_size.y = map_height
		_apply_safe_area_layout()
	var minimap: Dictionary = model.get("minimap", {})
	_set_label("map_stats", "발견 %d · 표식 %d" % [int(minimap.get("discovered_count", 0)), int(minimap.get("marker_count", 0))] if bool(minimap.get("ok", false)) else "타일 %d · 사물 %d" % [model.terrain_count, model.object_count])
	_render_minimap_grid(_minimap_grid, minimap.get("minimap", {}) if bool(minimap.get("ok", false)) else {}, Vector2(6, 6))
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
	_connect_runtime_signal(combat_target, &"damaged", Callable(self, "_on_combat_target_damaged"))
	_connect_runtime_signal(combat_target, &"defeated", Callable(self, "_on_combat_target_defeated"))
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
	_disconnect_runtime_signal(combat_target, &"damaged", Callable(self, "_on_combat_target_damaged"))
	_disconnect_runtime_signal(combat_target, &"defeated", Callable(self, "_on_combat_target_defeated"))
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

func _on_combat_target_damaged(_event: Dictionary, _applied_damage: int) -> void:
	_update()

func _on_combat_target_defeated() -> void:
	_update()

func _on_phase_changed(_previous, _current) -> void:
	_time_refresh_elapsed = 0.0
	_update()

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
	var spacer := Control.new()
	_ignore_mouse(spacer)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_row.add_child(spacer)
	_secondary_action_bar = HBoxContainer.new()
	_secondary_action_bar.name = "SecondaryActionBar"
	_ignore_mouse(_secondary_action_bar)
	_secondary_action_bar.add_theme_constant_override("separation", 3)
	menu_row.add_child(_secondary_action_bar)
	var menu_button := Button.new()
	menu_button.name = "ActionMenuButton"
	menu_button.text = "☰"
	menu_button.tooltip_text = "보조 행동"
	menu_button.custom_minimum_size = ACTION_MENU_BUTTON_SIZE
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_button.add_theme_font_size_override("font_size", 12)
	menu_button.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.08, 0.06, 0.80), true))
	menu_button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.12, 0.08, 0.92), true))
	menu_button.pressed.connect(func(): _toggle_action_menu())
	menu_row.add_child(menu_button)
	_action_grid = GridContainer.new()
	_action_grid.name = "ActionGrid"
	_ignore_mouse(_action_grid)
	_action_grid.columns = ACTION_PANEL_COLUMNS
	_action_grid.add_theme_constant_override("h_separation", 4)
	_action_grid.add_theme_constant_override("v_separation", 4)
	action_rows.add_child(_action_grid)
	_rebuild_action_buttons()

func _build_action_menu(parent: PanelContainer) -> void:
	_block_mouse(parent)
	_action_menu_scroll = ScrollContainer.new()
	_action_menu_scroll.name = "ActionMenuScroll"
	_action_menu_scroll.custom_minimum_size = Vector2(ACTION_MENU_PANEL_SIZE.x - 12.0, ACTION_MENU_PANEL_SIZE.y - 12.0)
	_action_menu_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_action_menu_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_action_menu_scroll.get_h_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
	_action_menu_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_action_menu_scroll)
	_action_menu_grid = GridContainer.new()
	_action_menu_grid.name = "ActionMenuGrid"
	_ignore_mouse(_action_menu_grid)
	_action_menu_grid.columns = 2
	_action_menu_grid.add_theme_constant_override("h_separation", 4)
	_action_menu_grid.add_theme_constant_override("v_separation", 4)
	_action_menu_scroll.add_child(_action_menu_grid)
	_rebuild_action_buttons()

func _rebuild_action_buttons() -> void:
	if _action_grid == null:
		return
	if _secondary_action_bar != null:
		_clear_container_children(_secondary_action_bar)
		if _tea_quickslot_count() > 0:
			_add_icon_action(_secondary_action_bar, "QuickTeaButton", ICON_TEA, "차 사용", "drink_tea", Vector2i.ZERO, 0)
		_add_icon_action(_secondary_action_bar, "QuickConsumableButton", ICON_CONSUMABLE, "소모품 사용", "use_consumable", Vector2i.ZERO, 0)
		if _balance_integer(BALANCE_ABILITY_SLOTS_ID) > 0:
			_add_icon_action(_secondary_action_bar, "QuickAbilityButton", ICON_ABILITY, "요술 사용", "cast_ability", Vector2i.ZERO, 0)
	_clear_container_children(_action_grid)
	_add_text_action(_action_grid, "AttackButton", ICON_ATTACK, "공격", "attack", Vector2i.ZERO, 0)
	_interaction_button = _add_interaction_action(_action_grid)
	_add_text_action(_action_grid, "InventoryButton", ICON_BAG, "가방", "open_inventory", Vector2i.ZERO, 0)
	_add_text_action(_action_grid, "CraftingButton", ICON_CONSUMABLE, "제작", "open_crafting", Vector2i.ZERO, 0)
	if _action_menu_grid != null:
		_clear_container_children(_action_menu_grid)
		for slot in range(_tea_quickslot_count()):
			_add_text_action(_action_menu_grid, "TeaButton%d" % (slot + 1), ICON_TEA, "차%d" % (slot + 1), "drink_tea", Vector2i.ZERO, slot)
		_add_text_action(_action_menu_grid, "ConsumableButton", ICON_CONSUMABLE, "소모", "use_consumable", Vector2i.ZERO, 0)
		for slot in range(_balance_integer(BALANCE_ABILITY_SLOTS_ID)):
			_add_text_action(_action_menu_grid, "AbilityButton%d" % (slot + 1), ICON_ABILITY, "요술%d" % (slot + 1), "cast_ability", Vector2i.ZERO, slot)
		_add_text_action(_action_menu_grid, "TeaBrewingButton", ICON_TEA, "우리기", "open_tea_brewing", Vector2i.ZERO, 0)
		_add_text_action(_action_menu_grid, "MetaCodexButton", ICON_BAG, "도감", "open_meta_codex", Vector2i.ZERO, 0)
		_add_text_action(_action_menu_grid, "MapButton", ICON_MAP, "지도", "open_map", Vector2i.ZERO, 0)
		_add_text_action(_action_menu_grid, "FacilitiesButton", ICON_MAP, "시설", "open_facilities", Vector2i.ZERO, 0)
		_add_text_action(_action_menu_grid, "SleepButton", ICON_TEA, "수면", "sleep", Vector2i.ZERO, 0)
	var action_panel := _panels.get("action") as Control
	if action_panel != null:
		action_panel.custom_minimum_size = ACTION_PANEL_SIZE
		action_panel.size = ACTION_PANEL_SIZE
	var action_menu_panel := _panels.get("action_menu") as Control
	if action_menu_panel != null:
		action_menu_panel.custom_minimum_size = ACTION_MENU_PANEL_SIZE
		action_menu_panel.size = ACTION_MENU_PANEL_SIZE
		action_menu_panel.visible = _action_menu_open

func _toggle_action_menu() -> void:
	_action_menu_open = not _action_menu_open
	var action_menu_panel := _panels.get("action_menu") as Control
	if action_menu_panel != null:
		action_menu_panel.visible = _action_menu_open

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
		movement_button_changed.emit(direction)
	)
	button.button_up.connect(func():
		feedback.visible = false
		movement_button_changed.emit(Vector2i.ZERO)
	)
	button.focus_exited.connect(func():
		feedback.visible = false
		movement_button_changed.emit(Vector2i.ZERO)
	)

func _add_text_action(parent: Container, name: String, icon_path: String, text: String, button_id: String, direction: Vector2i, slot: int) -> void:
	var button := Button.new()
	button.name = name
	button.custom_minimum_size = ACTION_BUTTON_SIZE
	button.text = text
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 16)
	button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.08, 0.06, 0.82), true))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.12, 0.08, 0.92), true))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.77, 0.54, 0.25, 0.96), true))
	button.pressed.connect(func(): press_mobile_button(button_id, direction, slot))
	parent.add_child(button)

func _add_interaction_action(parent: Container) -> Button:
	var button := Button.new()
	button.name = "InteractionButton"
	button.custom_minimum_size = Vector2(48, 48)
	button.text = "상호\n작용"
	button.tooltip_text = "가까운 유적·텔레포트와 상호작용"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _circle_button_style(Color(0.10, 0.22, 0.16, 0.92)))
	button.add_theme_stylebox_override("hover", _circle_button_style(Color(0.16, 0.38, 0.25, 0.96)))
	button.add_theme_stylebox_override("pressed", _circle_button_style(Color(0.35, 0.68, 0.42, 0.98)))
	button.pressed.connect(func(): press_mobile_button("interact", Vector2i.ZERO, 0))
	parent.add_child(button)
	return button

func _circle_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.72, 0.84, 0.62, 0.9)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	return style

func _add_icon_action(parent: Container, name: String, icon_path: String, tooltip: String, button_id: String, direction: Vector2i, slot: int) -> void:
	var button := Button.new()
	button.name = name
	button.custom_minimum_size = SECONDARY_ACTION_ICON_BUTTON_SIZE
	button.text = ""
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 15)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.08, 0.06, 0.80), true))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.12, 0.08, 0.92), true))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.77, 0.54, 0.25, 0.96), true))
	button.pressed.connect(func(): press_mobile_button(button_id, direction, slot))
	parent.add_child(button)

func _build_menu_panel(parent: PanelContainer) -> void:
	_block_mouse(parent)
	var rows := VBoxContainer.new()
	rows.name = "MenuRows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 4)
	parent.add_child(rows)
	var header := HBoxContainer.new()
	_ignore_mouse(header)
	header.add_theme_constant_override("separation", 8)
	rows.add_child(header)
	_labels.menu_title = _label("메뉴", 12)
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
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.custom_minimum_size = MENU_CONTENT_SIZE
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.get_h_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
	rows.add_child(scroll)
	_menu_content = VBoxContainer.new()
	_menu_content.name = "MenuContent"
	_ignore_mouse(_menu_content)
	_menu_content.add_theme_constant_override("separation", 3)
	scroll.add_child(_menu_content)
	_labels.menu_feedback = _label("", 11)
	rows.add_child(_labels.menu_feedback)
func _advance_status_toast() -> void:
	if _toast_label == null or _toast_queue.is_empty():
		if _toast_label != null:
			_toast_label.visible = false
		if _toast_panel != null:
			_toast_panel.visible = false
		_toast_remaining = 0.0
		return
	_toast_label.text = _toast_queue.pop_front()
	_toast_label.visible = true
	_toast_panel.visible = true
	_toast_remaining = STATUS_TOAST_DURATION

func _placement_command_button(text: String, command_type: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(48, 26)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): mobile_command_issued.emit(GameCommand.new(command_type)))
	return button

func _build_narrative_panel(parent: PanelContainer) -> void:
	var rows := VBoxContainer.new()
	rows.name = "NarrativeRows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 4)
	parent.add_child(rows)
	var speaker_plate := PanelContainer.new()
	speaker_plate.name = "SpeakerPlate"
	speaker_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	speaker_plate.add_theme_stylebox_override("panel", PixelUiTheme.button_style(Color(0.12, 0.08, 0.05, 0.94)))
	_ignore_mouse(speaker_plate)
	rows.add_child(speaker_plate)
	_labels.narrative_speaker = _label("", 13)
	_labels.narrative_speaker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58, 1.0))
	speaker_plate.add_child(_labels.narrative_speaker)
	_labels.narrative_text = _label("", 12)
	_labels.narrative_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_labels.narrative_text.custom_minimum_size = Vector2(528, 38)
	rows.add_child(_labels.narrative_text)
	_narrative_options = HBoxContainer.new()
	_narrative_options.name = "NarrativeOptions"
	_ignore_mouse(_narrative_options)
	_narrative_options.add_theme_constant_override("separation", 6)
	rows.add_child(_narrative_options)

func _portrait_rect(name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = name
	rect.custom_minimum_size = NARRATIVE_PORTRAIT_SIZE
	rect.size = NARRATIVE_PORTRAIT_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _narrative_portrait_frame(name: String) -> PanelContainer:
	var frame := _menu_panel(NARRATIVE_PORTRAIT_FRAME_SIZE)
	frame.name = name
	return frame

func _set_gameplay_hud_visible(visible: bool) -> void:
	for panel_id in ["status", "map", "enemy", "quickslot", "dpad", "action", "action_menu", "menu"]:
		var panel := _panels.get(panel_id) as Control
		if panel != null:
			panel.visible = visible and (
				(panel_id != "menu" or not _open_menu_id.is_empty())
				and (panel_id != "action_menu" or _action_menu_open)
			)
	if not visible:
		_open_menu_id = ""
		_action_menu_open = false

func _clear_narrative_options() -> void:
	for child in _narrative_options.get_children():
		if child is Control:
			var control := child as Control
			control.visible = false
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if child is BaseButton:
			(child as BaseButton).disabled = true
		child.queue_free()

func _configure_narrative_portraits(event_id: String, speaker_id: String) -> void:
	if _narrative_left_portrait == null or _narrative_right_portrait == null:
		return
	if event_id != FIRST_RUN_PROLOGUE_EVENT_ID:
		_set_portrait(_narrative_left_portrait, _portrait_asset_id_for_speaker(speaker_id), true)
		_set_portrait(_narrative_right_portrait, "", false)
		return
	var left_asset := PORTRAIT_FATHER
	var right_asset := PORTRAIT_MUCHAU
	if speaker_id == "CHR-5":
		right_asset = PORTRAIT_SEN_RIKYU
	_set_portrait(_narrative_left_portrait, left_asset, true)
	_set_portrait(_narrative_right_portrait, right_asset, true)
	_narrative_left_portrait.modulate = Color(1, 1, 1, 1) if speaker_id == "CHR-1" else Color(0.70, 0.70, 0.70, 0.72)
	_narrative_right_portrait.modulate = Color(1, 1, 1, 1) if speaker_id != "CHR-1" else Color(0.70, 0.70, 0.70, 0.72)

func _set_portrait(rect: TextureRect, asset_id: String, visible: bool) -> void:
	rect.visible = visible and not asset_id.is_empty()
	rect.texture = _load_texture(asset_id) if rect.visible else null
	var frame := rect.get_parent().get_node_or_null("%sFrame" % rect.name) as Control
	if frame != null:
		frame.visible = rect.visible

func _portrait_asset_id_for_speaker(speaker_id: String) -> String:
	return String(PORTRAIT_BY_CHARACTER.get(speaker_id, ""))

func _show_menu(title: String, rows: Array) -> void:
	_build()
	var panel := _panels.get("menu") as Control
	if panel == null or _menu_content == null:
		return
	_set_label("menu_title", title)
	_clear_container_children(_menu_content)
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
		"ruin_travel":
			_show_menu("유적 연결지", _ruin_travel_rows())
		"teleport_travel":
			_show_menu("텔레포트 연결지", _teleport_travel_rows())

func _inventory_rows() -> Array:
	var rows: Array = []
	if inventory_command_runtime != null and inventory_command_runtime.has_method("read_model"):
		var model: Dictionary = inventory_command_runtime.read_model()
		rows.append(_section_label("차 & 도구 (인벤토리) · %d/%d · %s" % [int(model.capacity.used), int(model.capacity.total), String(model.filter_kind)]))
		var toolbar := HBoxContainer.new()
		toolbar.name = "InventoryToolbar"
		_ignore_mouse(toolbar)
		toolbar.add_theme_constant_override("separation", 4)
		toolbar.add_child(_inventory_command_button("이전", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.LEFT), ICON_SCROLL, Vector2(54, 30), "이전"))
		toolbar.add_child(_inventory_command_button("다음", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.RIGHT), ICON_SCROLL, Vector2(54, 30), "다음"))
		toolbar.add_child(_inventory_command_button("정렬", GameCommand.new(GameCommand.Type.INVENTORY_SORT), ICON_BAG, Vector2(54, 30), "정렬"))
		for kind in model.available_filters:
			var kind_id := String(kind)
			toolbar.add_child(_inventory_command_button(_inventory_filter_label(kind_id), GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, {"kind": kind_id}), _inventory_kind_icon_reference(kind_id), Vector2(54, 30), _inventory_filter_label(kind_id)))
		rows.append(toolbar)
		var visible_rows: Array = _inventory_display_rows(model.slots, int(model.get("selected_slot_index", -1)))
		var page_start := _inventory_page_start(visible_rows, int(model.get("selected_slot_index", -1)), 8)
		var page_end := mini(visible_rows.size(), page_start + 8)
		var slot_strip := GridContainer.new()
		slot_strip.name = "InventorySlotStrip"
		slot_strip.columns = 4
		_ignore_mouse(slot_strip)
		slot_strip.add_theme_constant_override("h_separation", 5)
		slot_strip.add_theme_constant_override("v_separation", 5)
		for row_index in range(page_start, page_end):
			var row: Dictionary = visible_rows[row_index]
			slot_strip.add_child(_inventory_slot_card(row))
		rows.append(slot_strip)
		if visible_rows.size() > 8:
			rows.append(_label("%d-%d / %d" % [page_start + 1, page_end, visible_rows.size()], 11))
		var selected := _selected_inventory_row(visible_rows, int(model.get("selected_slot_index", -1)))
		rows.append(_inventory_detail_card(selected))
		return rows
	rows.append(_label("인벤토리 read model 없음", 11))
	return rows

func _inventory_slot_card(row: Dictionary) -> Button:
	var button := _inventory_command_button(
		"빈칸" if bool(row.get("empty", false)) else "%s\n* %d" % [String(row.get("name", row.get("item_id", ""))), int(row.get("quantity", 0))],
		GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, int(row.slot_index), {"slot_index": int(row.slot_index)})
	)
	button.name = "InventorySlotCard%d" % int(row.get("slot_index", -1))
	button.custom_minimum_size = Vector2(66, 60)
	button.icon = _load_texture(_inventory_item_icon_reference(row))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", _menu_card_style(false))
	button.add_theme_stylebox_override("hover", _menu_card_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.12, 0.08, 0.96)))
	if bool(row.get("selected", false)):
		button.add_theme_stylebox_override("normal", _menu_card_style(true))
	button.disabled = bool(row.get("empty", false))
	button.tooltip_text = String(row.get("name", row.get("item_id", "")))
	return button

func _inventory_display_rows(slot_rows: Array, selected_slot_index: int) -> Array:
	var display_rows := []
	var group_indexes := {}
	for row in slot_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if bool(row.get("empty", false)) or bool(row.get("can_equip", false)):
			display_rows.append(row)
			continue
		var item_id := String(row.get("item_id", ""))
		if item_id.is_empty():
			display_rows.append(row)
			continue
		if not group_indexes.has(item_id):
			var group: Dictionary = row.duplicate(true)
			group["slot_indexes"] = [int(row.get("slot_index", -1))]
			group["quantity"] = int(row.get("quantity", 0))
			group["stack_label"] = "%d total" % int(group.quantity)
			group["selected"] = int(row.get("slot_index", -1)) == selected_slot_index
			group_indexes[item_id] = display_rows.size()
			display_rows.append(group)
			continue
		var group_index := int(group_indexes[item_id])
		var existing: Dictionary = display_rows[group_index]
		existing["quantity"] = int(existing.get("quantity", 0)) + int(row.get("quantity", 0))
		existing["stack_label"] = "%d total" % int(existing.quantity)
		existing["slot_indexes"].append(int(row.get("slot_index", -1)))
		if int(row.get("slot_index", -1)) == selected_slot_index:
			existing["slot_index"] = selected_slot_index
			existing["selected"] = true
		display_rows[group_index] = existing
	return display_rows

func _selected_inventory_row(rows: Array, selected_slot_index: int) -> Dictionary:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("slot_index", -1)) == selected_slot_index:
			return row
		if row.has("slot_indexes") and row.slot_indexes.has(selected_slot_index):
			return row
	return rows[0] if not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY else {}

func _inventory_detail_card(row: Dictionary) -> Control:
	var card := _detail_card("선택한 항목")
	var rows := card.get_node("Rows") as VBoxContainer
	if not row.is_empty() and not bool(row.get("empty", false)):
		rows.add_child(_icon_text_row(_inventory_item_icon_reference(row), String(row.get("name", row.get("item_id", ""))), 11))
		rows.add_child(_label("%s · * %d · %s" % [
			String(row.get("kind", "")),
			int(row.get("quantity", 0)),
			String(row.get("stack_label", ""))
		], 10))
	else:
		rows.add_child(_icon_text_row("", "표시할 항목 없음", 11))
	var actions := HBoxContainer.new()
	_ignore_mouse(actions)
	actions.add_theme_constant_override("separation", 4)
	if not row.is_empty():
		var slot_index := int(row.get("slot_index", -1))
		if bool(row.get("can_use", false)):
			actions.add_child(_inventory_command_button("사용", GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, slot_index, {"slot_index": slot_index}), _inventory_item_icon_reference(row), Vector2(54, 28), "사용"))
		if bool(row.get("can_equip", false)):
			actions.add_child(_inventory_command_button("장착", GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, slot_index, {"slot_index": slot_index}), _inventory_item_icon_reference(row), Vector2(54, 28), "장착"))
	rows.add_child(actions)
	return card

func _inventory_command_button(text: String, command: GameCommand, icon_reference := "", min_size := Vector2(40, 24), tooltip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = tooltip
	if not icon_reference.is_empty():
		button.icon = _load_texture(icon_reference)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.065, 0.05, 0.92)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.10, 0.07, 0.96)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.23, 0.17, 0.09, 0.98)))
	button.pressed.connect(func(): mobile_command_issued.emit(command))
	return button

func _inventory_filter_label(kind: String) -> String:
	return "전체" if kind == "all" else kind

func _inventory_kind_icon_reference(kind: String) -> String:
	match kind:
		"소모품":
			return ICON_CONSUMABLE
		"찻잎":
			return ICON_TEA
		"재료":
			return ICON_MATERIAL
		"다구":
			return ICON_TEA_WARE
		"무기":
			return ICON_ATTACK
		"방어구":
			return ICON_TOOL
		_:
			return ICON_BAG

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
	button.custom_minimum_size = Vector2(40, 24)
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
	button.custom_minimum_size = Vector2(40, 24)
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
	rows.append(_section_label("제작법 %d/%d · 가능 %d · 필터 %s" % [
		int(counts.get("visible", 0)),
		int(counts.get("total", 0)),
		int(counts.get("craftable", 0)),
		_crafting_filter_label(_crafting_filter)
	]))
	var filters := HBoxContainer.new()
	filters.name = "CraftingFilterBar"
	_ignore_mouse(filters)
	filters.add_theme_constant_override("separation", 4)
	for category in model.get("categories", []):
		var category_id := String(category)
		filters.add_child(_crafting_filter_button(_crafting_filter_label(category_id), category_id))
	rows.append(filters)
	var model_rows: Array = model.get("rows", [])
	# Keep the full recipe list visible; the menu is scrollable and hiding
	# craftable entries behind an implicit six-item page made facilities appear
	# to be missing.
	var page_start := _crafting_page_start(model_rows, _selected_recipe_id, model_rows.size())
	var recipe_strip := GridContainer.new()
	recipe_strip.name = "CraftingRecipeStrip"
	recipe_strip.columns = 3
	_ignore_mouse(recipe_strip)
	recipe_strip.add_theme_constant_override("h_separation", 5)
	recipe_strip.add_theme_constant_override("v_separation", 5)
	for index in range(page_start, model_rows.size()):
		recipe_strip.add_child(_crafting_row(model_rows[index]))
	rows.append(recipe_strip)
	rows.append(_crafting_detail_row(model.get("detail", {})))
	return rows

func _crafting_row(row_model: Dictionary) -> Control:
	var card := VBoxContainer.new()
	card.name = "CraftingRecipeCard"
	_ignore_mouse(card)
	card.custom_minimum_size = Vector2(104, 76)
	card.add_theme_constant_override("separation", 3)
	var summary := VBoxContainer.new()
	summary.name = "CraftingRecipeSummary"
	_ignore_mouse(summary)
	summary.add_theme_constant_override("separation", 2)
	var icon_row := HBoxContainer.new()
	_ignore_mouse(icon_row)
	icon_row.add_theme_constant_override("separation", 4)
	icon_row.add_child(_item_icon_rect(_crafting_result_icon_reference(row_model), Vector2(26, 26)))
	icon_row.add_child(_item_icon_rect(_crafting_state_icon_reference(row_model), Vector2(16, 16)))
	summary.add_child(icon_row)
	var result := _dictionary_value(row_model.get("result", {}))
	var label := _label("%s\n%s" % [
		String(result.get("name", row_model.get("name", row_model.get("recipe_id", "")))),
		String(row_model.get("reason_label", ""))
	], 9)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(label)
	card.add_child(summary)
	var actions := HBoxContainer.new()
	_ignore_mouse(actions)
	actions.add_theme_constant_override("separation", 3)
	var select_button := Button.new()
	select_button.text = "보기"
	select_button.icon = _load_texture(ICON_SCROLL)
	select_button.expand_icon = true
	select_button.add_theme_constant_override("icon_max_width", 14)
	select_button.custom_minimum_size = Vector2(44, 24)
	select_button.focus_mode = Control.FOCUS_ALL
	select_button.mouse_filter = Control.MOUSE_FILTER_STOP
	select_button.tooltip_text = "상세"
	select_button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.065, 0.05, 0.92)))
	select_button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.10, 0.07, 0.96)))
	select_button.add_theme_stylebox_override("pressed", _button_style(Color(0.23, 0.17, 0.09, 0.98)))
	var recipe_id := String(row_model.get("recipe_id", ""))
	select_button.pressed.connect(func():
		_selected_recipe_id = recipe_id
		_refresh_open_menu()
	)
	actions.add_child(select_button)
	var button := Button.new()
	button.text = "제작"
	button.icon = _load_texture(ICON_WORKBENCH)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 14)
	button.disabled = not bool(row_model.get("craftable", false))
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = "제작"
	button.custom_minimum_size = Vector2(44, 24)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.065, 0.05, 0.92)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.10, 0.07, 0.96)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.23, 0.17, 0.09, 0.98)))
	button.pressed.connect(func():
		mobile_command_issued.emit(GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, 0, {"recipe_id": recipe_id}))
	)
	actions.add_child(button)
	card.add_child(actions)
	var frame := _card_frame(card, bool(row_model.get("selected", false)))
	frame.add_theme_stylebox_override("panel", _crafting_card_style(row_model))
	return frame

func _crafting_filter_button(text: String, category: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = _load_texture(_crafting_category_icon_reference(category))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 18)
	button.custom_minimum_size = Vector2(58, 30)
	button.disabled = category == _crafting_filter
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = text
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.065, 0.05, 0.92)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.10, 0.07, 0.96)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.23, 0.17, 0.09, 0.98)))
	button.pressed.connect(func():
		_crafting_filter = category
		_selected_recipe_id = ""
		_refresh_open_menu()
	)
	return button

func _crafting_state_icon_reference(row_model: Dictionary) -> String:
	if bool(row_model.get("craftable", false)):
		return ICON_CHECK
	if String(row_model.get("reason", "")) == "missing_materials":
		return ICON_MATERIAL
	return ICON_TOOL

func _crafting_category_icon_reference(category: String) -> String:
	match category:
		"다구":
			return ICON_TEA_WARE
		"도구":
			return ICON_TOOL
		"소모품":
			return ICON_CONSUMABLE
		"찻잎":
			return ICON_TEA
		"재료":
			return ICON_MATERIAL
		_:
			return ICON_WORKBENCH

func _crafting_detail_row(detail: Dictionary) -> Control:
	if detail.is_empty():
		return _detail_card_with_text("상세", "표시할 제작법 없음")
	var result: Dictionary = detail.get("result", {})
	var materials := []
	for material in detail.get("materials", []):
		materials.append("%s %d/%d" % [
			String(material.get("name", material.get("item_id", ""))),
			int(material.get("available", 0)),
			int(material.get("required", 0))
		])
	var facilities := []
	for facility in detail.get("facilities", []):
		facilities.append("%s%s" % [
			String(facility.get("name", facility.get("item_id", ""))),
			"" if bool(facility.get("available", false)) else "(필요)"
		])
	var card := _detail_card("제작 상세")
	var rows := card.get_node("Rows") as VBoxContainer
	rows.add_child(_icon_text_row(_crafting_result_icon_reference(detail), "%s → %s x%d" % [
		String(detail.get("recipe_id", "")),
		String(result.get("name", result.get("item_id", ""))),
		int(result.get("quantity", 1))
	], 11))
	rows.add_child(_label("상태 %s" % String(detail.get("reason_label", "")), 10))
	if not materials.is_empty():
		rows.add_child(_label("재료 %s" % ", ".join(materials), 10))
	rows.add_child(_label("시설 %s" % ("손제작" if facilities.is_empty() else ", ".join(facilities)), 10))
	var unlock_biome_id := String(detail.get("unlock_biome_id", ""))
	if not unlock_biome_id.is_empty():
		rows.add_child(_label("해금 %s" % unlock_biome_id, 10))
	return card

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
	rows.append(_section_label("시설"))
	var facility_strip := HBoxContainer.new()
	facility_strip.name = "FacilityCardStrip"
	_ignore_mouse(facility_strip)
	facility_strip.add_theme_constant_override("separation", 5)
	for node in world.get("facility_nodes", []):
		var position: Dictionary = node.get("position", {})
		facility_strip.add_child(_detail_card_with_text("지도 시설", "%s (%d,%d)" % [
			String(node.get("facility_term", node.get("id", ""))),
			int(position.get("x", 0)),
			int(position.get("y", 0))
		]))
	if facility_strip.get_child_count() > 0:
		rows.append(facility_strip)
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
			rows.append(_detail_card_with_text("제작 연계", "%s · %s" % [
				String(facility.get("name", item_id)),
				"사용 가능" if bool(facility.get("available", false)) else "필요"
			]))
	return rows

func _map_rows() -> Array:
	var rows: Array = []
	var selected_id := _selected_map_biome_id if not _selected_map_biome_id.is_empty() else String(world.get("biome_id", ""))
	var map_source = world_data
	if selected_id != String(world.get("biome_id", "")) and biome_map_previews.has(selected_id):
		map_source = WorldData.from_dictionary(biome_map_previews[selected_id].get("world_data", {}))
	var model := _map_read_model({"minimap_width": 48, "minimap_height": 28, "reveal_all": true}, map_source)
	if not bool(model.get("ok", false)):
		rows.append(_label("지도 read model 없음", 11))
		return rows
	rows.append(_section_label("전체 지도 · 접근 가능한 지역을 선택하세요"))
	rows.append(_biome_map_selector())
	var selected := _biome_definition(selected_id)
	rows.append(_label("현재 보기: %s%s" % [String(selected.get("name", selected_id)), " · 현재 위치" if selected_id == String(world.get("biome_id", "")) else ""], 12))
	if selected_id != String(world.get("biome_id", "")) and not _is_biome_map_accessible(selected_id):
		rows.append(_label("이 지역은 아직 잠겨 있습니다. 해금 후 상세 지도가 표시됩니다.", 10))
		return rows
	var bounds: Dictionary = model.bounds
	rows.append(_label("지도 %dx%d · 발견 %d · 안개 %d" % [int(bounds.width), int(bounds.height), int(model.discovered_count), int(model.fog_count)], 11))
	rows.append(_label("플레이어 (%d,%d)" % [int(model.player.position.x), int(model.player.position.y)], 11))
	var current_biome_id := String(world.get("biome_id", ""))
	if current_biome_id.is_empty() and run_state != null:
		current_biome_id = String(run_state.current_biome_id)
	# Cheat mode represents a fully-completed save regardless of legacy/stale
	# progression fields that may have been loaded before the HUD was configured.
	var dungeon_cleared: bool = cheat_mode or (run_state != null and run_state.completed_dungeon_ids.has(current_biome_id))
	if run_state != null:
		dungeon_cleared = dungeon_cleared or String(run_state.teleport_states.get(current_biome_id, "")) in ["repairable", "repaired"]
		dungeon_cleared = dungeon_cleared or run_state.crafting_unlocks.has(current_biome_id)
	rows.append(_label("현재 던전: %s" % ("클리어" if dungeon_cleared else "미클리어"), 11))
	rows.append(_map_color_grid(model.minimap, Vector2(8, 8)))
	var markers: Array = model.markers
	rows.append(_label("중요 오브젝트", 11))
	for marker in markers:
		rows.append(_map_marker_button(marker))
	return rows

func _map_marker_button(marker: Dictionary) -> Button:
	var position: Dictionary = marker.get("position", {})
	var button := Button.new()
	button.text = "%s · %s  (%d,%d)%s" % [
		_marker_label(String(marker.get("marker_type", ""))),
		String(marker.get("id", "")),
		int(position.get("x", 0)),
		int(position.get("y", 0)),
		"" if bool(marker.get("discovered", true)) else " · 미발견"
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(270, 28)
	button.pressed.connect(func(): _show_map_marker_info(marker))
	return button

func _show_map_marker_info(marker: Dictionary) -> void:
	var position: Dictionary = marker.get("position", {})
	var marker_type := String(marker.get("marker_type", ""))
	var status := "확인됨" if bool(marker.get("discovered", true)) else "미발견"
	var info := "%s\n종류: %s\n좌표: (%d, %d)\n상태: %s" % [
		String(marker.get("id", "중요 오브젝트")),
		_marker_label(marker_type),
		int(position.get("x", 0)),
		int(position.get("y", 0)),
		status
	]
	_show_menu("지도 정보", [_label(info, 12), _map_back_button()])

func _map_back_button() -> Button:
	var button := Button.new()
	button.text = "지도 돌아가기"
	button.custom_minimum_size = Vector2(180, 30)
	button.pressed.connect(func(): _show_menu("지도", _map_rows()))
	return button

func _ruin_travel_rows() -> Array:
	var rows: Array = [_label("수리된 다른 유적을 선택하세요", 11)]
	var current_id := String(world.get("biome_id", ""))
	var repaired_ids: Array = []
	if run_state != null:
		repaired_ids = run_state.completed_dungeon_ids
	for definition in _ordered_biome_definitions():
		var destination_id := String(definition.get("id", ""))
		if destination_id.is_empty() or destination_id == current_id or not repaired_ids.has(destination_id):
			continue
		var button := Button.new()
		button.text = "이동 · %s" % String(definition.get("name", destination_id))
		button.custom_minimum_size = Vector2(220, 34)
		button.pressed.connect(func():
			mobile_command_issued.emit(GameCommand.new(GameCommand.Type.TRAVEL_TO_BIOME, Vector2i.ZERO, -1, {"biome_id": destination_id, "travel_mode": "ruin"}))
		)
		rows.append(button)
	if rows.size() == 1:
		rows.append(_label("이동할 수리 완료 유적이 없습니다", 11))
	rows.append(_label("텔레포트는 별도로 수리·관리됩니다", 10))
	return rows

func _teleport_travel_rows() -> Array:
	var rows: Array = [_label("수리된 텔레포트 · 연결된 일반 지역을 선택하세요", 11)]
	if biome_progression_state == null:
		rows.append(_label("바이옴 연결 정보 없음", 11))
		return rows
	var projection: Dictionary = biome_progression_state.to_projection()
	var order: Array = projection.get("biome_order", [])
	var current_id := String(world.get("biome_id", ""))
	var current_index := order.find(current_id)
	var destinations: Array = []
	for index in [current_index - 1, current_index + 1]:
		if index < 0 or index >= order.size():
			continue
		var destination_id := String(order[index])
		if index > current_index and String(projection.get("next_biome_id", "")) != destination_id:
			continue
		if index > current_index and not bool(projection.get("can_advance_biome", false)):
			continue
		destinations.append(destination_id)
	for destination_id in destinations:
		var definition := _biome_definition(destination_id)
		var button := Button.new()
		button.text = "이동 · %s" % String(definition.get("name", destination_id))
		button.custom_minimum_size = Vector2(220, 34)
		button.pressed.connect(func():
			mobile_command_issued.emit(GameCommand.new(GameCommand.Type.TRAVEL_TO_BIOME, Vector2i.ZERO, -1, {"biome_id": destination_id, "travel_mode": "teleport"}))
		)
		rows.append(button)
	if destinations.is_empty():
		rows.append(_label("현재 연결된 다른 일반 지역이 없습니다", 11))
	return rows

func _biome_map_selector() -> Control:
	var strip := GridContainer.new()
	strip.name = "BiomeMapSelector"
	strip.columns = 2
	strip.add_theme_constant_override("separation", 4)
	for definition in _ordered_biome_definitions():
		var biome_id := String(definition.get("id", ""))
		var button := Button.new()
		button.name = "BiomeMap_%s" % biome_id
		button.text = String(definition.get("name", biome_id))
		button.tooltip_text = "선택하여 지역 지도 보기"
		button.custom_minimum_size = Vector2(86, 30)
		button.disabled = biome_id == String(world.get("biome_id", "")) and _selected_map_biome_id == biome_id
		button.pressed.connect(func():
			_selected_map_biome_id = biome_id
			_show_menu("지도", _map_rows())
		)
		strip.add_child(button)
	if strip.get_child_count() == 0:
		strip.add_child(_label("지역 데이터 없음", 10))
	return strip

func _ordered_biome_definitions() -> Array:
	if catalog == null or not catalog.has_method("get_definitions"):
		return []
	var definitions: Array = catalog.get_definitions("biomes")
	definitions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_order = left.get("progression_order", 999)
		var right_order = right.get("progression_order", 999)
		var left_value: int = 999 if left_order == null else int(left_order)
		var right_value: int = 999 if right_order == null else int(right_order)
		return left_value < right_value
	)
	return definitions

func _biome_definition(biome_id: String) -> Dictionary:
	for definition in _ordered_biome_definitions():
		if String(definition.get("id", "")) == biome_id:
			return definition
	return {}

func _is_biome_map_accessible(biome_id: String) -> bool:
	if cheat_mode:
		return true
	var current_id := String(world.get("biome_id", ""))
	if biome_id == current_id:
		return true
	if run_state != null and run_state.crafting_unlocks.has(biome_id):
		return true
	if biome_progression_state != null and biome_progression_state.has_method("teleport_state_for"):
		return String(biome_progression_state.teleport_state_for(biome_id)) == "repaired"
	return false

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

func _map_read_model(options := {}, source_world_data = null) -> Dictionary:
	if map_read_model_builder == null or not map_read_model_builder.has_method("build"):
		return {"ok": false, "reason": "missing_map_read_model_builder"}
	var selected_source = source_world_data if source_world_data != null else (world_data if world_data != null else world)
	return map_read_model_builder.build(selected_source, run_state, _player_cell(), options)

func _combat_target_read_model() -> Dictionary:
	var combatant = _object_property(combat_target, "combatant")
	if combatant == null:
		return {"visible": false}
	var hp := int(_object_property(combatant, "hp", 0))
	var hp_max := int(_object_property(combatant, "hp_max", 0))
	if hp_max <= 0:
		return {"visible": false}
	var definition_id := String(_object_property(combatant, "definition_id", _object_property(combat_target, "monster_id", "")))
	var definition := {}
	if catalog != null and catalog.has_method("find_by_id") and not definition_id.is_empty():
		definition = catalog.find_by_id("monsters", definition_id)
	return {
		"visible": hp > 0,
		"id": definition_id,
		"name": String(definition.get("name", definition_id if not definition_id.is_empty() else "적")),
		"hp": hp,
		"hp_max": hp_max,
		"attack": int(_object_property(combatant, "attack", 0))
	}

func _player_cell() -> Vector2i:
	var position := Vector2.ZERO
	if player != null and player.has_method("get"):
		position = player.get("global_position")
	var tile_size := 32
	if world_data != null and world_data.has_method("get"):
		tile_size = max(1, int(world_data.get("tile_size")))
	var local_position := position - world_origin
	return Vector2i(int(floor(local_position.x / float(tile_size))), int(floor(local_position.y / float(tile_size))))

func _marker_label(marker_type: String) -> String:
	match marker_type:
		"player":
			return "플레이어"
		"dungeon":
			return "던전"
		"ruin":
			return "유적"
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
			return "R"
		"ruin":
			return "U"
		"teleport":
			return "T"
		_:
			return "L"

func _map_color_grid(minimap: Dictionary, cell_size: Vector2) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "MapColorGrid"
	_ignore_mouse(grid)
	var size: Dictionary = minimap.get("size", {})
	grid.columns = maxi(1, int(size.get("width", 1)))
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	_render_minimap_grid(grid, minimap, cell_size)
	return grid

func _render_minimap_grid(grid: GridContainer, minimap: Dictionary, cell_size: Vector2) -> void:
	if grid == null:
		return
	_clear_container_children(grid)
	var size: Dictionary = minimap.get("size", {})
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0 or height <= 0:
		return
	grid.columns = width
	var marker_by_position := {}
	var marker_data_by_position := {}
	for marker in _array_value(minimap.get("markers", [])):
		var marker_position: Dictionary = marker.get("position", {})
		var marker_key := "%d,%d" % [int(marker_position.get("x", 0)), int(marker_position.get("y", 0))]
		marker_by_position[marker_key] = String(marker.get("marker_type", ""))
		marker_data_by_position[marker_key] = marker
	var cell_by_position := {}
	for cell in _array_value(minimap.get("cells", [])):
		var cell_position: Dictionary = cell.get("position", {})
		cell_by_position["%d,%d" % [int(cell_position.get("x", 0)), int(cell_position.get("y", 0))]] = cell
	var origin: Dictionary = minimap.get("origin", {})
	for y in range(int(origin.get("y", 0)), int(origin.get("y", 0)) + height):
		for x in range(int(origin.get("x", 0)), int(origin.get("x", 0)) + width):
			var key := "%d,%d" % [x, y]
			var tile: Control
			if marker_data_by_position.has(key):
				var marker_button := Button.new()
				marker_button.text = _marker_glyph(String(marker_by_position.get(key, "")))
				marker_button.custom_minimum_size = cell_size
				marker_button.tooltip_text = String(marker_data_by_position[key].get("id", "중요 오브젝트"))
				var marker: Dictionary = marker_data_by_position[key]
				marker_button.pressed.connect(func(): _show_map_marker_info(marker))
				tile = marker_button
			else:
				var color_tile := ColorRect.new()
				color_tile.custom_minimum_size = cell_size
				color_tile.color = _minimap_cell_color(cell_by_position.get(key, {}))
				tile = color_tile
				_ignore_mouse(tile)
			grid.add_child(tile)

func _minimap_cell_color(cell: Dictionary) -> Color:
	if cell.is_empty() or bool(cell.get("fog", true)):
		return Color(0.05, 0.05, 0.05, 0.88)
	var terrain_id := String(cell.get("terrain_id", ""))
	if "water" in terrain_id or "river" in terrain_id or "ice" in terrain_id:
		return Color(0.18, 0.43, 0.68, 0.95)
	if "forest" in terrain_id or "tree" in terrain_id or "jungle" in terrain_id or "pine" in terrain_id:
		return Color(0.16, 0.45, 0.22, 0.95)
	if "mountain" in terrain_id or "rock" in terrain_id or "cliff" in terrain_id:
		return Color(0.42, 0.42, 0.36, 0.95)
	if "path" in terrain_id or "road" in terrain_id:
		return Color(0.63, 0.53, 0.33, 0.95)
	if "snow" in terrain_id:
		return Color(0.78, 0.84, 0.88, 0.95)
	return Color(0.43, 0.57, 0.28, 0.95)

func _minimap_marker_color(marker_type: String) -> Color:
	match marker_type:
		"player":
			return Color(1.0, 0.95, 0.48, 1.0)
		"dungeon":
			return Color(0.76, 0.28, 0.22, 1.0)
		"teleport":
			return Color(0.56, 0.38, 0.92, 1.0)
		_:
			return Color(0.95, 0.72, 0.32, 1.0)

func _inventory_definition(item_id: String) -> Dictionary:
	if inventory != null and inventory.has_method("definition_for"):
		return inventory.definition_for(item_id)
	if catalog != null and catalog.has_method("find_by_id"):
		return catalog.find_by_id("items", item_id)
	return {"id": item_id, "name": item_id}

func _inventory_item_icon_reference(row: Dictionary) -> String:
	if row.is_empty() or bool(row.get("empty", false)):
		return ""
	var item_id := String(row.get("item_id", ""))
	var definition := _inventory_definition(item_id)
	return _item_icon_reference(item_id, String(row.get("kind", definition.get("type", ""))), definition)

func _crafting_result_icon_reference(row_model: Dictionary) -> String:
	var result: Dictionary = row_model.get("result", {})
	var item_id := String(result.get("item_id", row_model.get("result_item_id", row_model.get("recipe_id", ""))))
	var definition := _inventory_definition(item_id)
	var kind := String(result.get("kind", result.get("type", definition.get("type", row_model.get("category", "")))))
	return _item_icon_reference(item_id, kind, result.merged(definition, false))

func _item_icon_reference(item_id: String, kind: String, definition: Dictionary) -> String:
	for key in ["icon_asset_id", "icon", "asset_id", "sprite_asset_id", "source_id"]:
		var reference := String(definition.get(key, ""))
		if not reference.is_empty():
			return reference
	match item_id:
		"wood", "old_wood", "rare_wood":
			return ICON_WOOD
		"stone", "hard_stone":
			return ICON_STONE
		"wooden_workbench":
			return ICON_WORKBENCH
	var normalized_kind := kind.strip_edges()
	match normalized_kind:
		"소모품":
			return ICON_CONSUMABLE
		"다구":
			return ICON_TEA_WARE
		"차", "찻잎":
			return ICON_TEA
		"도구", "시설":
			return ICON_TOOL
		"재료":
			return ICON_MATERIAL
	return ICON_BAG

func _apply_safe_area_layout() -> void:
	var margin := _safe_margin()
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(640, 360)
	var narrative_overlay := _panels.get("narrative_overlay") as Control
	if narrative_overlay != null:
		narrative_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		narrative_overlay.offset_left = 0
		narrative_overlay.offset_top = 0
		narrative_overlay.offset_right = 0
		narrative_overlay.offset_bottom = 0
	if _narrative_background != null:
		_narrative_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_narrative_background.offset_left = 0
		_narrative_background.offset_top = 0
		_narrative_background.offset_right = 0
		_narrative_background.offset_bottom = 0
	var portrait_y := maxf(
		margin.y + 44.0,
		viewport_size.y - margin.w - NARRATIVE_PANEL_BOTTOM_OFFSET - NARRATIVE_PANEL_SIZE.y - NARRATIVE_PORTRAIT_FRAME_SIZE.y + 16.0
	)
	var left_frame_position := Vector2(margin.x + 24.0, portrait_y)
	var right_frame_position := Vector2(viewport_size.x - margin.z - NARRATIVE_PORTRAIT_FRAME_SIZE.x - 24.0, portrait_y)
	if _narrative_left_portrait != null:
		_narrative_left_portrait.size = NARRATIVE_PORTRAIT_SIZE
		_narrative_left_portrait.position = left_frame_position + Vector2.ONE * NARRATIVE_PORTRAIT_INSET
	if _narrative_left_portrait_frame != null:
		_narrative_left_portrait_frame.size = NARRATIVE_PORTRAIT_FRAME_SIZE
		_narrative_left_portrait_frame.position = left_frame_position
	if _narrative_right_portrait != null:
		_narrative_right_portrait.size = NARRATIVE_PORTRAIT_SIZE
		_narrative_right_portrait.position = right_frame_position + Vector2.ONE * NARRATIVE_PORTRAIT_INSET
	if _narrative_right_portrait_frame != null:
		_narrative_right_portrait_frame.size = NARRATIVE_PORTRAIT_FRAME_SIZE
		_narrative_right_portrait_frame.position = right_frame_position
	_place_panel(_panels.status, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y))
	var resource_detail := _panels.get("resource_detail") as Control
	_place_panel(resource_detail, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y + STATUS_PANEL_SIZE.y + 4.0))
	_place_panel(_panels.map, Control.PRESET_TOP_RIGHT, Vector2(-margin.z, margin.y))
	var enemy_top := margin.y + STATUS_PANEL_SIZE.y + 8.0
	if resource_detail != null and resource_detail.visible:
		enemy_top += RESOURCE_DETAIL_PANEL_SIZE.y + 4.0
	_place_panel(_panels.enemy, Control.PRESET_TOP_LEFT, Vector2(margin.x, enemy_top))
	_place_panel(_panels.quickslot, Control.PRESET_CENTER_TOP, Vector2(0.0, margin.y))
	_place_panel(_toast_panel, Control.PRESET_CENTER_TOP, Vector2(0.0, margin.y + STATUS_PANEL_SIZE.y + 8.0))
	_resize_menu_panel(viewport_size, margin)
	_place_panel(_panels.menu, Control.PRESET_CENTER, Vector2.ZERO)
	_place_panel(_panels.dpad, Control.PRESET_BOTTOM_LEFT, Vector2(margin.x, -margin.w))
	_place_panel(_panels.action_menu, Control.PRESET_BOTTOM_RIGHT, Vector2(-margin.z, -margin.w - ACTION_PANEL_SIZE.y - 8.0))
	_place_panel(_panels.action, Control.PRESET_BOTTOM_RIGHT, Vector2(-margin.z, -margin.w))
	_place_panel(_panels.narrative, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -margin.w - NARRATIVE_PANEL_BOTTOM_OFFSET))
	_place_panel(_facility_placement_panel, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -margin.w - 8.0))

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
		Control.PRESET_CENTER:
			control.offset_left = -panel_size.x * 0.5 + offset.x
			control.offset_top = -panel_size.y * 0.5 + offset.y
			control.offset_right = panel_size.x * 0.5 + offset.x
			control.offset_bottom = panel_size.y * 0.5 + offset.y

func _resize_menu_panel(viewport_size: Vector2, margin: Vector4) -> void:
	var menu_panel := _panels.get("menu") as Control
	if menu_panel == null:
		return
	var available := Vector2(
		maxf(1.0, viewport_size.x - margin.x - margin.z),
		maxf(1.0, viewport_size.y - margin.y - margin.w)
	)
	var target := Vector2(
		maxf(minf(MENU_PANEL_SIZE.x, available.x), available.x * MENU_VIEWPORT_RATIO.x),
		maxf(minf(MENU_PANEL_SIZE.y, available.y), available.y * MENU_VIEWPORT_RATIO.y)
	)
	menu_panel.custom_minimum_size = target
	menu_panel.size = target
	var scroll := menu_panel.get_node_or_null("MenuRows/MenuScroll") as Control
	if scroll != null:
		scroll.custom_minimum_size = Vector2(
			maxf(120.0, target.x - MENU_PANEL_PADDING.x),
			maxf(80.0, target.y - MENU_PANEL_PADDING.y)
		)

func _safe_margin() -> Vector4:
	var fallback := Vector4(12, 12, 12, 12)
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return fallback
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return fallback
	if safe.position.x < 0 or safe.position.y < 0:
		return fallback
	if safe.position.x >= viewport_size.x or safe.position.y >= viewport_size.y:
		return fallback
	if safe.size.x > viewport_size.x or safe.size.y > viewport_size.y:
		return fallback
	return Vector4(
		maxf(fallback.x, float(safe.position.x)),
		maxf(fallback.y, float(safe.position.y)),
		maxf(fallback.z, maxf(0.0, viewport_size.x - float(safe.position.x + safe.size.x))),
		maxf(fallback.w, maxf(0.0, viewport_size.y - float(safe.position.y + safe.size.y)))
	)

func _panel(size: Vector2) -> PanelContainer:
	return _styled_panel(size, _panel_style())

func _unstyled_panel(size: Vector2) -> PanelContainer:
	return _styled_panel(size, StyleBoxEmpty.new())

func _dialogue_panel(size: Vector2) -> PanelContainer:
	return _menu_panel(size)

func _menu_panel(size: Vector2) -> PanelContainer:
	return _styled_panel(size, _panel_style())

func _styled_panel(size: Vector2, style: StyleBox) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _portrait_box(asset_id: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = PORTRAIT_BOX_SIZE
	box.add_theme_stylebox_override("panel", _button_style(Color(0.12, 0.08, 0.05, 0.86)))
	_ignore_mouse(box)
	var texture := TextureRect.new()
	texture.name = "PortraitTexture"
	texture.custom_minimum_size = PORTRAIT_BOX_SIZE - Vector2(8, 8)
	texture.texture = _load_texture(asset_id)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(texture)
	return box

func _add_resource_icon_row(parent: Container, id: String, icon_path: String, text: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "%sDisplay" % ("Health" if id == "hp" else id.capitalize())
	_block_mouse(row)
	row.add_theme_constant_override("separation", 3)
	row.tooltip_text = "%s 상세 보기" % text
	row.gui_input.connect(func(event): _on_resource_row_gui_input(event, id, row))
	parent.add_child(row)
	var icons := HBoxContainer.new()
	icons.name = "Icons"
	_ignore_mouse(icons)
	icons.add_theme_constant_override("separation", 0)
	row.add_child(icons)
	var texture := _load_texture(icon_path)
	for index in range(RESOURCE_ICON_COUNT):
		var icon := TextureRect.new()
		icon.name = "Icon%d" % (index + 1)
		icon.custom_minimum_size = RESOURCE_ICON_SIZE
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_meta("empty_color", Color(0.20, 0.16, 0.13, 0.72))
		icon.set_meta("filled_color", color)
		_ignore_mouse(icon)
		icons.add_child(icon)
	_labels["%s_icons" % id] = icons
	var value := _label(text, 8)
	row.add_child(value)
	return value

func _build_resource_detail_panel(parent: Control) -> void:
	var panel := _panel(RESOURCE_DETAIL_PANEL_SIZE)
	panel.name = "ResourceDetailPanel"
	panel.visible = false
	_block_mouse(panel)
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			panel.accept_event()
	)
	parent.add_child(panel)
	_panels.resource_detail = panel
	_resource_detail_label = _label("", 10)
	panel.add_child(_resource_detail_label)

func _on_resource_row_gui_input(event: InputEvent, id: String, row: Control) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if not pressed:
		return
	row.accept_event()
	if get_viewport() != null:
		get_viewport().set_input_as_handled()
	var panel := _panels.get("resource_detail") as Control
	if panel == null:
		return
	if panel.visible:
		panel.visible = false
		_resource_detail_id = ""
		_apply_safe_area_layout()
		return
	_resource_detail_id = "all"
	panel.visible = true
	panel.move_to_front()
	_update_resource_detail(runtime_read_model())
	_apply_safe_area_layout()

func _update_resource_detail(model: Dictionary) -> void:
	if _resource_detail_label == null or _resource_detail_id.is_empty():
		return
	_resource_detail_label.text = "자원 상세\n체력 %d / %d\n차기 %d / %d\n정신 %d / %d" % [
		int(model.hp), int(model.hp_max),
		int(model.ki), int(model.ki_max),
		int(model.kokoro), int(model.kokoro_max)
	]

func _update_resource_icons(id: String, current: int, maximum: int) -> void:
	var icons := _labels.get(id) as HBoxContainer
	if icons == null:
		return
	var filled_units := 0.0
	if maximum > 0:
		filled_units = clampf(float(current) / float(maximum), 0.0, 1.0) * RESOURCE_ICON_COUNT
	for index in range(icons.get_child_count()):
		var icon := icons.get_child(index) as TextureRect
		if icon != null:
			var fill_ratio := clampf(filled_units - float(index), 0.0, 1.0)
			icon.set_meta("fill_ratio", fill_ratio)
			icon.modulate = (icon.get_meta("empty_color") as Color).lerp(icon.get_meta("filled_color") as Color, fill_ratio)

func _add_icon_row(parent: Container, icon_path: String, text: String) -> Label:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var icon := TextureRect.new()
	_ignore_mouse(icon)
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(icon_path)
	row.add_child(icon)
	var value := _label(text)
	row.add_child(value)
	return value

func _label(text: String, font_size := 12) -> Label:
	var label := Label.new()
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.93, 0.83, 0.63, 1.0))
	return label

func _build_time_dial_row(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "TimeDialRow"
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	_time_dial = TimeDial.new()
	_time_dial.name = "TimeDial"
	_time_dial.custom_minimum_size = TIME_DIAL_SIZE
	_ignore_mouse(_time_dial)
	row.add_child(_time_dial)
	var labels := VBoxContainer.new()
	labels.name = "TimeLabels"
	_ignore_mouse(labels)
	labels.add_theme_constant_override("separation", -2)
	row.add_child(labels)
	_labels.time_phase = _label("낮", 10)
	labels.add_child(_labels.time_phase)
	_labels.time_progress = _label("0%", 9)
	_labels.time_progress.modulate = Color(0.84, 0.65, 0.36, 1.0)
	labels.add_child(_labels.time_progress)

func _section_label(text: String) -> Label:
	var label := _label(text, 11)
	label.add_theme_color_override("font_color", Color(0.93, 0.83, 0.63, 1.0))
	return label

func _card_frame(content: Control, selected := false) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = content.custom_minimum_size + Vector2(6, 6)
	_ignore_mouse(frame)
	frame.add_theme_stylebox_override("panel", _menu_card_style(selected))
	frame.add_child(content)
	return frame

func _detail_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "DetailCard"
	card.custom_minimum_size = Vector2(288, 42)
	_ignore_mouse(card)
	card.add_theme_stylebox_override("panel", _menu_card_style(false))
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 3)
	card.add_child(rows)
	var title_label := _section_label(title)
	rows.add_child(title_label)
	return card

func _detail_card_with_text(title: String, text: String) -> PanelContainer:
	var card := _detail_card(title)
	var rows := card.get_node("Rows") as VBoxContainer
	rows.add_child(_section_label(text))
	return card

func _icon_text_row(icon_reference: String, text: String, font_size := 11) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "IconTextRow"
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 6)
	row.add_child(_item_icon_rect(icon_reference, Vector2(24, 24)))
	var label := _label(text, font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

func _item_icon_rect(icon_reference: String, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(icon_reference)
	_ignore_mouse(icon)
	return icon

func _set_label(id: String, text: String) -> void:
	var label := _labels.get(id) as Label
	if label != null:
		label.text = text

func _speaker_label(speaker_id: String) -> String:
	if catalog != null and catalog.has_method("find_character_by_id"):
		var character: Dictionary = catalog.find_character_by_id(speaker_id)
		if not character.is_empty():
			return String(character.get("name", speaker_id))
	return speaker_id

func _pixel_theme() -> Theme:
	return PixelUiTheme.create()

func _panel_style() -> StyleBoxFlat:
	return PixelUiTheme.panel_style()

func _button_style(color: Color, rounded := false) -> StyleBoxFlat:
	return PixelUiTheme.button_style(color, rounded)

func _dpad_feedback_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 0.84, 0.50, minf(color.a + 0.28, 1.0))
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _menu_card_style(selected := false) -> StyleBoxFlat:
	var style := _button_style(Color(0.07, 0.06, 0.045, 0.92))
	if selected:
		style.bg_color = Color(0.10, 0.08, 0.055, 0.96)
		style.border_color = Color(0.92, 0.68, 0.32, 1.0)
	return style

func _crafting_card_style(row_model: Dictionary) -> StyleBoxFlat:
	var selected := bool(row_model.get("selected", false))
	var style := _menu_card_style(selected)
	if bool(row_model.get("craftable", false)):
		style.bg_color = Color(0.045, 0.095, 0.055, 0.94)
		style.border_color = Color(0.45, 0.86, 0.36, 1.0)
	elif String(row_model.get("reason", "")) == "missing_materials":
		style.bg_color = Color(0.11, 0.045, 0.04, 0.94)
		style.border_color = Color(0.86, 0.34, 0.25, 1.0)
	if selected:
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
	return style

func _parchment_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.67, 0.55, 0.36, 0.96)
	style.border_color = Color(0.30, 0.12, 0.06, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
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
	if reference.is_empty():
		return null
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
	var texture := ImageTexture.create_from_image(image)
	if texture != null:
		texture.resource_path = path
	return texture

func _ensure_asset_catalog() -> bool:
	if _asset_catalog_ready:
		return true
	var result: Dictionary = asset_catalog.load_manifest()
	if result.ok:
		_asset_catalog_ready = true
		return true
	push_warning("HUD asset manifest failed: %s" % result.get("error", "unknown error"))
	return false
