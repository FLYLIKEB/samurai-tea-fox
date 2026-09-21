extends CanvasLayer
class_name GameHud

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const GameHudReadModelProvider = preload("res://src/ui/game_hud_read_model_provider.gd")
const NarrativeDialoguePresenter = preload("res://src/ui/narrative_dialogue_presenter.gd")
const DetailPopup = preload("res://src/ui/detail_popup.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")
const UiPopupLayout = preload("res://src/ui/ui_popup_layout.gd")
const HudMenuViewHelpers = preload("res://src/ui/hud/hud_menu_view_helpers.gd")
const InventoryMenuBuilder = preload("res://src/ui/hud/inventory_menu_builder.gd")
const CraftingMenuBuilder = preload("res://src/ui/hud/crafting_menu_builder.gd")
const TeaBrewingMenuBuilder = preload("res://src/ui/hud/tea_brewing_menu_builder.gd")
const MetaCodexMenuBuilder = preload("res://src/ui/hud/meta_codex_menu_builder.gd")
const StatusToastPresenter = preload("res://src/ui/hud/status_toast_presenter.gd")
const StatusPanelPresenter = preload("res://src/ui/hud/status_panel_presenter.gd")
const MapPanelPresenter = preload("res://src/ui/hud/map_panel_presenter.gd")
const MobileControlsPresenter = preload("res://src/ui/hud/mobile_controls_presenter.gd")
const SettingsPresenter = preload("res://src/ui/hud/settings_presenter.gd")

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
const ICON_CRAFTING_SHORTCUT := "res://assets/sprites/objects/crafting/workbench_32x32.png"
const ICON_MAP_SHORTCUT := "res://assets/ui/icons/atlas/menu_map.png"
const ICON_MOON := "asset_assets_ui_icons_atlas_moon_png"
const ICON_MATERIAL := "asset_assets_ui_icons_atlas_crate_png"
const ICON_TOOL := "asset_assets_ui_icons_atlas_low_table_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"
const ICON_CHECK := "asset_assets_ui_icons_atlas_quest_check_1_png"
const ICON_WOOD := "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png"
const ICON_STONE := "asset_assets_sprites_objects_crafting_mortar_pestle_stone_32x32_png"
const ICON_WORKBENCH := "asset_assets_sprites_objects_crafting_workbench_32x32_png"
const ICON_TEA_TABLE := "res://assets/sprites/objects/crafting/tea_table_2x2_64x64.png"
const BUTTON_DPAD := "asset_assets_ui_controls_dpad_png"
const PORTRAIT_PLAYER := "portrait_chr_8_muchau"

const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"
const HUD_EDGE_GAP := 4.0
const STATUS_PANEL_SIZE := Vector2(184, 104)
const PORTRAIT_BOX_SIZE := Vector2(40, 40)
const RESOURCE_ICON_COUNT := 5
const RESOURCE_ICON_SIZE := Vector2(12, 12)
const EQUIPMENT_ICON_SIZE := Vector2(15, 15)
const EQUIPMENT_SLOT_SIZE := Vector2(28, 24)
const EQUIPMENT_SLOT_KEYS := ["weapon", "armor", "tea_ware"]
const EQUIPMENT_SLOT_LABELS := {
	"weapon": "무기",
	"armor": "방어",
	"tea_ware": "다구"
}
const EQUIPMENT_SLOT_SHORT_LABELS := {
	"weapon": "무",
	"armor": "방",
	"tea_ware": "다"
}
const RESOURCE_DETAIL_PANEL_SIZE := Vector2(172, 62)
const ENEMY_PANEL_SIZE := Vector2(136, 46)
const MAP_PANEL_SIZE := Vector2(140, 126)
const MAP_PANEL_TIME_HEIGHT := 126.0
const QUICKSLOT_PANEL_SIZE := Vector2(264, 70)
const QUICKSLOT_CONTENT_MARGIN := Vector4(18, 20, 18, 24)
const DPAD_BOARD_SIZE := Vector2(96, 96)
const ACTION_BUTTON_SIZE := Vector2(48, 48)
const SECONDARY_ACTION_ICON_BUTTON_SIZE := Vector2(20, 20)
const ACTION_PANEL_SIZE := Vector2(132, 126)
const ACTION_MENU_PANEL_SIZE := Vector2(280, 180)
const BOTTOM_NAV_PANEL_SIZE := Vector2(340, 84)
const SETTINGS_BUTTON_SIZE := Vector2(60, 38)
const SIDE_SHORTCUT_FRAME_SIZE := Vector2(68, 92)
const ACTION_PANEL_COLUMNS := 2
const MENU_PANEL_SIZE := Vector2(500, 280)
const MENU_CONTENT_SIZE := Vector2(452, 228)
const MENU_PANEL_PADDING := Vector2(48, 98)
const FULL_MAP_CELL_SIZE := Vector2(6, 6)
const COMPACT_MAP_CELL_SIZE := Vector2(4, 4)
const TIME_DIAL_SIZE := Vector2(28, 28)
const STATUS_TOAST_DURATION := 0.9
const STATUS_TOAST_MAX_VISIBLE_QUEUE := 4
const STATUS_TOAST_ICON_SIZE := Vector2(18, 18)
const STATUS_TOAST_PANEL_SIZE := Vector2(300, 32)
const TOAST_ITEM_ACQUIRED := "item_acquired"
const TOAST_CRAFT_COMPLETED := "craft_completed"
const TOAST_TEA_BREWED := "tea_brewed"
const TOAST_ENEMY_DEFEATED := "enemy_defeated"
const TOAST_DUNGEON_ENTERED := "dungeon_entered"
const TOAST_DUNGEON_EXITED := "dungeon_exited"
const TOAST_DUNGEON_FLOOR_CHANGED := "dungeon_floor_changed"
const TOAST_BIOME_TRANSITION := "biome_transition"
const TOAST_REGION_TRANSITION := "region_transition"
const TOAST_MAP_TRANSITION := "map_transition"

signal mobile_command_issued(command)

signal movement_button_changed(direction: Vector2i)

signal status_toast_presented(kind: String, event_key: String)
signal return_to_start_requested

var asset_catalog := AssetCatalog.new()
var _asset_catalog_ready := false
var _content_image_map_ready := false
var _crafting_filter := "all"
var _selected_recipe_id := ""
var read_model_provider := GameHudReadModelProvider.new()
var _labels: Dictionary = {}
var _panels: Dictionary = {}
var _mobile_adapter := MobileCommandAdapter.new()
var _built := false
var _theme: Theme
var _time_refresh_elapsed := 0.0
var _menu_content: VBoxContainer
var _action_scroll: ScrollContainer
var _narrative_presenter: NarrativeDialoguePresenter
var _detail_popup: Control
var _open_menu_id := ""
var _facility_placement_panel: PanelContainer
var _facility_placement_install_button: Button
var _facility_placement_status: Label
var _toast_presenter := StatusToastPresenter.new()
var _status_presenter := StatusPanelPresenter.new()
var _map_presenter := MapPanelPresenter.new()
var _mobile_presenter := MobileControlsPresenter.new()
var _settings_presenter := SettingsPresenter.new()

func _ready() -> void:
	_build()
	_bind_runtime_signals()
	_update()

func configure(player_node, generated_world: Dictionary, generated_render_result: Dictionary, runtime_context := {}) -> void:
	_unbind_runtime_signals()
	var injected_provider = runtime_context.get("read_model_provider", null) if typeof(runtime_context) == TYPE_DICTIONARY else null
	if injected_provider != null:
		read_model_provider = injected_provider
	else:
		read_model_provider = GameHudReadModelProvider.new()
		read_model_provider.configure(player_node, generated_world, generated_render_result, runtime_context)
	_build()
	_mobile_presenter.rebuild_actions()
	_apply_safe_area_layout()
	_bind_runtime_signals()
	_update()

func runtime_read_model() -> Dictionary:
	if read_model_provider == null:
		return {}
	return read_model_provider.read_model()

func equipment_hud_snapshot() -> Dictionary:
	return _status_presenter.equipment_hud_snapshot()

func press_mobile_button(button_id: String, direction := Vector2i.ZERO, slot := 0) -> bool:
	if button_id == "repair_teleport":
		return false
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
	_map_presenter.reset_selection(_current_biome_id())
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
	_dismiss_detail_popup()
	_open_menu_id = ""
	var panel := _panels.get("menu") as Control
	if panel != null:
		panel.visible = false
	return true

func show_narrative_dialogue(read_model: Dictionary) -> bool:
	_build()
	if _narrative_presenter == null:
		return false
	var shown := _narrative_presenter.show_read_model(read_model)
	if not shown:
		return false
	_set_gameplay_hud_visible(false)
	_apply_safe_area_layout()
	return true

func hide_narrative_dialogue() -> bool:
	if _narrative_presenter != null:
		_narrative_presenter.hide_dialogue()
	_set_gameplay_hud_visible(true)
	_update()
	return true

func narrative_dialogue_visible() -> bool:
	return _narrative_presenter != null and _narrative_presenter.dialogue_visible()

func active_menu_id() -> String:
	return _open_menu_id

func show_command_feedback(message: String) -> void:
	var feedback := _labels.get("menu_feedback") as Label
	if feedback != null:
		feedback.text = message
	if not _open_menu_id.is_empty():
		_refresh_open_menu()

func show_status_toast(message: String, kind := "info") -> void:
	_toast_presenter.enqueue({"message": message, "kind": kind, "event_key": "message:%s" % message})

func show_status_event(event: Dictionary) -> bool:
	var model := _status_toast_model(event)
	if model.is_empty():
		return false
	model["kind"] = String(event.get("kind", "success"))
	return _toast_presenter.enqueue(model)

func status_toast_debug_snapshot() -> Dictionary:
	return _toast_presenter.debug_snapshot()

func _status_toast_model(event: Dictionary) -> Dictionary:
	if event.is_empty() or not bool(event.get("ok", true)):
		return {}
	var event_type := String(event.get("type", event.get("event_type", "")))
	match event_type:
		TOAST_ITEM_ACQUIRED:
			return _content_toast_model(event, "items", String(event.get("item_id", "")), "을(를) 얻었다!", "item")
		TOAST_CRAFT_COMPLETED:
			return _content_toast_model(event, "items", String(event.get("result_item_id", event.get("item_id", ""))), "을(를) 제작했다!", "craft")
		TOAST_TEA_BREWED:
			return _content_toast_model(event, "teas", String(event.get("tea_id", "")), "을(를) 우렸다!", "tea-brew")
		TOAST_ENEMY_DEFEATED:
			return _content_toast_model(event, "monsters", String(event.get("monster_id", event.get("enemy_id", ""))), "을(를) 쓰러뜨렸다!", "enemy")
		TOAST_DUNGEON_ENTERED:
			return _place_toast_model(event, "dungeons", String(event.get("dungeon_id", "")), "던전에 들어갔다!", "dungeon-enter")
		TOAST_DUNGEON_EXITED:
			return _place_toast_model(event, "dungeons", String(event.get("dungeon_id", "")), "던전에서 나왔다!", "dungeon-exit")
		TOAST_DUNGEON_FLOOR_CHANGED:
			return _floor_toast_model(event)
		TOAST_BIOME_TRANSITION, TOAST_REGION_TRANSITION:
			return _place_toast_model(event, "biomes", String(event.get("biome_id", event.get("region_id", ""))), "지역으로 이동했다!", "biome")
		TOAST_MAP_TRANSITION:
			return _place_toast_model(event, "biomes", String(event.get("biome_id", "")), "맵을 이동했다!", "map")
		_:
			return {}

func _content_toast_model(event: Dictionary, dataset: String, stable_id: String, suffix: String, key_prefix: String) -> Dictionary:
	if stable_id.is_empty():
		return {}
	var definition := _catalog_definition(dataset, stable_id)
	var name := String(event.get("name", definition.get("name", stable_id)))
	var quantity := int(event.get("quantity", 0))
	var quantity_label := " x%d" % quantity if quantity > 1 and key_prefix == "item" else ""
	return {
		"message": "%s%s%s" % [name, quantity_label, suffix],
		"icon_reference": _content_icon_reference(dataset, stable_id, definition),
		"event_key": "%s:%s:%s" % [key_prefix, stable_id, String(event.get("event_id", ""))]
	}

func _place_toast_model(event: Dictionary, dataset: String, stable_id: String, fallback_message: String, key_prefix: String) -> Dictionary:
	var definition := _catalog_definition(dataset, stable_id)
	var name := String(event.get("name", definition.get("name", "")))
	var message := fallback_message
	if not name.is_empty() and key_prefix in ["biome", "map"]:
		message = "%s %s" % [name, fallback_message]
	return {
		"message": message,
		"icon_reference": _content_icon_reference(dataset, stable_id, definition),
		"event_key": "%s:%s:%s" % [key_prefix, stable_id, String(event.get("event_id", ""))]
	}

func _floor_toast_model(event: Dictionary) -> Dictionary:
	var floor_number := int(event.get("floor", event.get("floor_index", 0)))
	var message := "던전 층을 이동했다!" if floor_number <= 0 else "던전 %d층으로 이동했다!" % floor_number
	return {
		"message": message,
		"icon_reference": ICON_MAP,
		"event_key": "dungeon-floor:%d:%s" % [floor_number, String(event.get("event_id", ""))]
	}

func _catalog_definition(dataset: String, stable_id: String) -> Dictionary:
	return read_model_provider.catalog_definition(dataset, stable_id) if read_model_provider != null else {}

func _content_icon_reference(dataset: String, stable_id: String, definition: Dictionary) -> String:
	var icon_reference := String(definition.get("icon_asset_id", ""))
	if not icon_reference.is_empty():
		return icon_reference
	if _ensure_content_image_map() and not stable_id.is_empty():
		return asset_catalog.content_asset_id(dataset, stable_id)
	return ""

func _ensure_content_image_map() -> bool:
	if _content_image_map_ready:
		return true
	if not _ensure_asset_catalog():
		return false
	var result: Dictionary = asset_catalog.load_content_image_map()
	if result.ok:
		_content_image_map_ready = true
		return true
	push_warning("HUD content image map failed: %s" % result.get("error", "unknown error"))
	return false

func _process(delta: float) -> void:
	_toast_presenter.tick(delta)
	var model := runtime_read_model()
	if not bool(model.get("time_visible", false)):
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
	_panels.merge(_toast_presenter.build(root, {
		"texture_resolver": Callable(self, "_load_texture"),
		"presented": Callable(self, "_emit_status_toast_presented")
	}), true)
	_panels.merge(_status_presenter.build(root, {
		"texture_resolver": Callable(self, "_load_texture"),
		"item_icon_reference": Callable(self, "_item_icon_reference"),
		"request_layout": Callable(self, "_apply_safe_area_layout"),
		"runtime_read_model": Callable(self, "runtime_read_model")
	}), true)
	_labels.merge(_status_presenter.labels, true)
	_panels.merge(_map_presenter.build(root, {
		"texture_resolver": Callable(self, "_load_texture"),
		"press_mobile_button": Callable(self, "press_mobile_button"),
		"show_detail_popup": Callable(self, "_show_detail_popup"),
		"request_map_refresh": Callable(self, "_refresh_map_menu"),
		"emit_command": Callable(self, "_emit_mobile_command")
	}), true)
	_labels.merge(_map_presenter.labels, true)

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

	var quickslot_panel := _unstyled_panel(QUICKSLOT_PANEL_SIZE)
	quickslot_panel.name = "QuickSlotPanel"
	quickslot_panel.clip_contents = true
	root.add_child(quickslot_panel)
	_panels.quickslot = quickslot_panel
	var quickslot_frame := TextureRect.new()
	quickslot_frame.name = "QuickSlotFrame"
	quickslot_frame.texture = _load_texture(PixelUiTheme.HUD_RESOURCES_TEXTURE)
	quickslot_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quickslot_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_ignore_mouse(quickslot_frame)
	quickslot_panel.add_child(quickslot_frame)
	var quickslot_content := MarginContainer.new()
	quickslot_content.name = "QuickSlotContent"
	quickslot_content.add_theme_constant_override("margin_left", int(QUICKSLOT_CONTENT_MARGIN.x))
	quickslot_content.add_theme_constant_override("margin_top", int(QUICKSLOT_CONTENT_MARGIN.y))
	quickslot_content.add_theme_constant_override("margin_right", int(QUICKSLOT_CONTENT_MARGIN.z))
	quickslot_content.add_theme_constant_override("margin_bottom", int(QUICKSLOT_CONTENT_MARGIN.w))
	_ignore_mouse(quickslot_content)
	quickslot_panel.add_child(quickslot_content)
	var quick_rows := HBoxContainer.new()
	quick_rows.name = "QuickSlotRows"
	_ignore_mouse(quick_rows)
	quick_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	quick_rows.add_theme_constant_override("separation", 6)
	quickslot_content.add_child(quick_rows)
	_labels.inventory = _add_icon_row(quick_rows, ICON_BAG, "가방")
	_labels.tea_slots = _add_icon_row(quick_rows, ICON_KI, "차")
	_labels.consumable = _add_icon_row(quick_rows, ICON_CONSUMABLE, "소모")
	_labels.abilities = _add_icon_row(quick_rows, ICON_ABILITY, "요술")
	for label_id in ["inventory", "tea_slots", "consumable", "abilities"]:
		var label := _labels[label_id] as Label
		label.add_theme_font_size_override("font_size", 10)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for row in quick_rows.get_children():
		(row as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_panels.merge(_mobile_presenter.build(root, {
		"texture_resolver": Callable(self, "_load_texture"),
		"press_mobile_button": Callable(self, "press_mobile_button"),
		"movement_changed": Callable(self, "_emit_movement_button_changed"),
		"tea_quickslot_count": Callable(self, "_tea_quickslot_count"),
		"balance_integer": Callable(self, "_balance_integer")
	}), true)
	_panels.merge(_settings_presenter.build(root, {
		"request_layout": Callable(self, "_apply_safe_area_layout"),
		"return_to_start": Callable(self, "_emit_return_to_start_requested")
	}), true)
	_restore_touch_control_child_order(root)

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

	_narrative_presenter = NarrativeDialoguePresenter.new()
	_narrative_presenter.configure(Callable(self, "_load_texture"), Callable(self, "_speaker_label"))
	_narrative_presenter.command_issued.connect(func(command): mobile_command_issued.emit(command))
	_narrative_presenter.build()
	root.add_child(_narrative_presenter)
	_panels.narrative_overlay = _narrative_presenter
	_panels.narrative = _narrative_presenter.narrative_panel

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
	_status_presenter.update(model)
	if _map_presenter.update(model):
		_apply_safe_area_layout()
	var combat_model: Dictionary = model.get("combat_target", {})
	var enemy_panel := _panels.get("enemy") as Control
	if enemy_panel != null:
		enemy_panel.visible = bool(combat_model.get("visible", false))
	_set_label("enemy_name", String(combat_model.get("name", "적 없음")))
	_set_label("enemy_hp", "HP %d/%d" % [int(combat_model.get("hp", 0)), int(combat_model.get("hp_max", 0))])
	_set_label("enemy_attack", "무기 공격 %d" % int(combat_model.get("attack", 0)))
	_set_label("inventory", "%d / %d" % [model.inventory_used_slots, model.inventory_slot_count])
	_set_label("tea_slots", "%d / %d" % [model.tea_ready_slots, model.tea_quickslot_count])
	_set_label("consumable", "준비" if model.consumable_ready else "없음")
	_set_label("abilities", "요술 %d" % model.ability_slot_count)

func _bind_runtime_signals() -> void:
	if read_model_provider != null and read_model_provider.has_signal("changed"):
		var callback := Callable(self, "_on_provider_changed")
		if not read_model_provider.is_connected("changed", callback):
			read_model_provider.connect("changed", callback)

func _unbind_runtime_signals() -> void:
	if read_model_provider != null and read_model_provider.has_signal("changed"):
		var callback := Callable(self, "_on_provider_changed")
		if read_model_provider.is_connected("changed", callback):
			read_model_provider.disconnect("changed", callback)

func _on_provider_changed(_read_model: Dictionary) -> void:
	_update()
	_refresh_open_menu()

func _restore_touch_control_child_order(root: Control) -> void:
	for node_name in ["DPadPanel", "ActionPanel", "ActionMenuPanel", "SideShortcutFrame", "SettingsButton", "FacilitiesShortcutButton", "BottomNavPanel"]:
		var node := root.get_node_or_null(NodePath(node_name))
		if node != null:
			root.move_child(node, root.get_child_count() - 1)

func _build_menu_panel(parent: PanelContainer) -> void:
	_block_mouse(parent)
	var rows := VBoxContainer.new()
	rows.name = "MenuRows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 4)
	parent.add_child(rows)
	var header := HBoxContainer.new()
	header.name = "MenuTitleBar"
	_ignore_mouse(header)
	header.add_theme_constant_override("separation", 8)
	rows.add_child(header)
	_labels.menu_title = _label("메뉴", 12)
	_labels.menu_title.name = "MenuTitleLabel"
	_labels.menu_title.clip_text = true
	_labels.menu_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_labels.menu_title.custom_minimum_size = Vector2(72, 0)
	header.add_child(_labels.menu_title)
	var spacer := Control.new()
	_ignore_mouse(spacer)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := UiContentBounds.fit_close_button(_button())
	close.name = "CloseMenuButton"
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
func _placement_command_button(text: String, command_type: int) -> Button:
	var button := _command_button_base(text, Vector2(48, 26), Control.FOCUS_NONE)
	button.pressed.connect(func(): mobile_command_issued.emit(GameCommand.new(command_type)))
	return button

func _set_gameplay_hud_visible(visible: bool) -> void:
	for panel_id in ["status", "map", "enemy", "quickslot", "dpad", "action", "side_shortcuts", "settings", "facilities_shortcut", "bottom_nav", "action_menu", "menu"]:
		var panel := _panels.get(panel_id) as Control
		if panel != null:
			panel.visible = visible and (
				(panel_id != "menu" or not _open_menu_id.is_empty())
				and (panel_id != "action_menu" or _settings_presenter.is_open())
			)
	if not visible:
		_open_menu_id = ""
		_settings_presenter.set_open(false)

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
	panel.move_to_front()
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
	return InventoryMenuBuilder.rows(_inventory_read_model(), _prepared_tea_rows(), _menu_state(), _inventory_menu_deps())

func _tea_brewing_rows() -> Array:
	return TeaBrewingMenuBuilder.rows(_tea_brewing_read_model(), _menu_state(), _tea_brewing_menu_deps())

func _meta_codex_rows() -> Array:
	return MetaCodexMenuBuilder.rows(_meta_codex_read_model(), _menu_state(), _meta_codex_menu_deps())

func _crafting_rows() -> Array:
	var model := _crafting_read_model(_crafting_filter, _selected_recipe_id)
	if not model.is_empty() and bool(model.get("ok", false)):
		_selected_recipe_id = String(model.get("selected_recipe_id", ""))
	return CraftingMenuBuilder.rows(model, _menu_state(), _crafting_menu_deps())

func _show_crafting_detail_popup(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	_refresh_open_menu()
	var model := _crafting_read_model(_crafting_filter, recipe_id)
	_show_detail_popup("제작 상세", CraftingMenuBuilder.detail_content(model.get("detail", {}), _menu_state(), _crafting_menu_deps()))

func _menu_state() -> Dictionary:
	return {
		"compact": _inventory_uses_compact_layout(),
		"filter": _crafting_filter,
		"selected_recipe_id": _selected_recipe_id
	}

func _menu_view() -> HudMenuViewHelpers:
	var view := HudMenuViewHelpers.new()
	view.texture_resolver = Callable(self, "_load_texture")
	return view

func _inventory_menu_deps() -> Dictionary:
	return {
		"view": _menu_view(),
		"emit_command": Callable(self, "_emit_mobile_command"),
		"show_detail_popup": Callable(self, "_show_detail_popup"),
		"inventory_item_icon_reference": Callable(self, "_inventory_item_icon_reference")
	}

func _tea_brewing_menu_deps() -> Dictionary:
	return {
		"view": _menu_view(),
		"emit_command": Callable(self, "_emit_mobile_command"),
		"item_icon_reference": Callable(self, "_item_icon_reference")
	}

func _meta_codex_menu_deps() -> Dictionary:
	return {
		"view": _menu_view(),
		"emit_command": Callable(self, "_emit_mobile_command")
	}

func _crafting_menu_deps() -> Dictionary:
	return {
		"view": _menu_view(),
		"emit_command": Callable(self, "_emit_mobile_command"),
		"refresh_open_menu": Callable(self, "_refresh_open_menu"),
		"show_detail_popup": Callable(self, "_show_crafting_detail_popup"),
		"set_filter": Callable(self, "_set_crafting_filter"),
		"set_selected_recipe_id": Callable(self, "_set_selected_recipe_id"),
		"inventory_item_icon_reference": Callable(self, "_inventory_item_icon_reference"),
		"crafting_result_icon_reference": Callable(self, "_crafting_result_icon_reference")
	}

func _prepared_tea_rows() -> Array:
	return read_model_provider.prepared_tea_rows() if read_model_provider != null else []

func _emit_mobile_command(command) -> void:
	mobile_command_issued.emit(command)

func _emit_movement_button_changed(direction: Vector2i) -> void:
	movement_button_changed.emit(direction)

func _emit_return_to_start_requested() -> void:
	return_to_start_requested.emit()

func _emit_status_toast_presented(kind: String, event_key: String) -> void:
	status_toast_presented.emit(kind, event_key)

func _refresh_map_menu() -> void:
	if _open_menu_id == "map":
		_show_menu("지도", _map_rows())

func _set_crafting_filter(value: String) -> void:
	_crafting_filter = value

func _set_selected_recipe_id(value: String) -> void:
	_selected_recipe_id = value

func _inventory_uses_compact_layout() -> bool:
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(640, 360)
	return viewport_size.x <= 480.0

func _page_start(rows: Array, key: String, selected, page_size: int, default_value = "") -> int:
	if rows.size() <= page_size:
		return 0
	for index in range(rows.size()):
		if str(rows[index].get(key, default_value)) == str(selected):
			return clampi(index - 2, 0, rows.size() - page_size)
	return 0

func _filter_label(value: String) -> String:
	return "전체" if value == "all" else value

func _command_button_base(text: String, min_size: Vector2, focus_mode: int, icon_reference := "", tooltip := "") -> Button:
	var button := _button()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = focus_mode
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = tooltip
	if not icon_reference.is_empty():
		button.icon = _load_texture(icon_reference)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
	return button

func _show_detail_popup(title: String, content: Control) -> void:
	_dismiss_detail_popup()
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(640, 360)
	var popup_size := UiPopupLayout.fitted_size(Vector2(420, 240), viewport_size - Vector2(48, 48))
	_detail_popup = DetailPopup.new()
	_detail_popup.setup(title, content, popup_size, PixelUiTheme.parchment_panel_style(), PixelUiTheme.create_parchment())
	_detail_popup.dismissed.connect(func(): _detail_popup = null)
	get_node("Root").add_child(_detail_popup)
	_detail_popup.move_to_front()

func _dismiss_detail_popup() -> void:
	if is_instance_valid(_detail_popup):
		if _detail_popup.get_parent() != null:
			_detail_popup.get_parent().remove_child(_detail_popup)
		_detail_popup.queue_free()
	_detail_popup = null

func _facility_rows() -> Array:
	var rows: Array = []
	rows.append(_section_label("시설"))
	var facility_strip := HBoxContainer.new()
	facility_strip.name = "FacilityCardStrip"
	_ignore_mouse(facility_strip)
	facility_strip.add_theme_constant_override("separation", 5)
	for node in _facility_nodes():
		var position: Dictionary = node.get("position", {})
		facility_strip.add_child(_detail_card_with_text("지도 시설", "%s (%d,%d)" % [
			String(node.get("facility_term", node.get("id", ""))),
			int(position.get("x", 0)),
			int(position.get("y", 0))
		]))
	if facility_strip.get_child_count() > 0:
		rows.append(facility_strip)
	var model := _crafting_read_model("all", "")
	if not model.is_empty():
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
	return _map_presenter.map_rows(_map_context())

func _ruin_travel_rows() -> Array:
	return _map_presenter.ruin_travel_rows(_map_context())

func _teleport_travel_rows() -> Array:
	return _map_presenter.teleport_travel_rows(_map_context())

func _map_context() -> Dictionary:
	var current_id := _current_biome_id()
	var selected_id := _map_presenter.selected_biome_id(current_id)
	var definitions := _ordered_biome_definitions()
	var accessible_ids := []
	for definition in definitions:
		var biome_id := String(definition.get("id", ""))
		if _is_biome_map_accessible(biome_id):
			accessible_ids.append(biome_id)
	return {
		"current_biome_id": current_id,
		"selected_biome_id": selected_id,
		"map_model": _map_read_model({"minimap_width": 48, "minimap_height": 28, "reveal_all": true}, selected_id),
		"minimap_model": _minimap_read_model(),
		"biome_definitions": definitions,
		"accessible_ids": accessible_ids,
		"projection": _biome_progression_projection(),
		"dungeon_cleared_current": _dungeon_cleared_for_current_biome(),
		"compact": _inventory_uses_compact_layout(),
		"repaired_ruin_biome_ids": _repaired_ruin_biome_ids()
	}

func _minimap_read_model() -> Dictionary:
	return read_model_provider.minimap_read_model() if read_model_provider != null else {}

func _map_read_model(options := {}, selected_biome_id := "") -> Dictionary:
	return read_model_provider.map_read_model(options, selected_biome_id) if read_model_provider != null else {}

func _player_cell() -> Vector2i:
	return read_model_provider._player_cell() if read_model_provider != null else Vector2i.ZERO

func _inventory_definition(item_id: String) -> Dictionary:
	return read_model_provider.inventory_definition(item_id) if read_model_provider != null else {"id": item_id, "name": item_id}

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
	var content_reference := _content_icon_reference("items", item_id, {})
	if not content_reference.is_empty():
		return content_reference
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
	var wide_landscape := viewport_size.x >= 600.0 and viewport_size.x > viewport_size.y and not narrative_dialogue_visible()
	var top_limit := viewport_size.x - margin.z
	if _narrative_presenter != null:
		_narrative_presenter.apply_layout(viewport_size, margin)
	_place_panel(_panels.status, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y))
	_place_panel(_panels.map, Control.PRESET_TOP_RIGHT, Vector2(-margin.z, margin.y))
	var status_rect := _panel_rect(_panels.status)
	var map_rect := _panel_rect(_panels.map)
	var quickslot_rect := _top_center_rect(_panels.quickslot, viewport_size, margin.y)
	if (
		quickslot_rect.position.x < margin.x
		or quickslot_rect.end.x > top_limit
		or quickslot_rect.intersects(status_rect)
		or quickslot_rect.intersects(map_rect)
	):
		var top_gap_left := status_rect.end.x + HUD_EDGE_GAP
		var top_gap_right := map_rect.position.x - HUD_EDGE_GAP
		if quickslot_rect.size.x <= top_gap_right - top_gap_left:
			quickslot_rect.position.x = clampf(quickslot_rect.position.x, top_gap_left, top_gap_right - quickslot_rect.size.x)
		else:
			quickslot_rect.position.x = margin.x
			quickslot_rect.position.y = maxf(status_rect.end.y, map_rect.end.y) + HUD_EDGE_GAP
	var dpad_size := _control_layout_size(_panels.dpad as Control) if _panels.dpad is Control else DPAD_BOARD_SIZE
	var dpad_reserved_rect := Rect2(
		Vector2(margin.x, viewport_size.y - margin.w - dpad_size.y - HUD_EDGE_GAP),
		Vector2(dpad_size.x + HUD_EDGE_GAP, dpad_size.y + HUD_EDGE_GAP)
	)
	if quickslot_rect.intersects(dpad_reserved_rect):
		var shifted_x := margin.x + dpad_size.x + HUD_EDGE_GAP
		if shifted_x + quickslot_rect.size.x <= top_limit:
			quickslot_rect.position.x = shifted_x
	_place_panel(_panels.quickslot, Control.PRESET_TOP_LEFT, quickslot_rect.position)
	var top_stack_bottom := maxf(maxf(status_rect.end.y, map_rect.end.y), quickslot_rect.end.y)
	var resource_detail := _panels.get("resource_detail") as Control
	_place_panel(resource_detail, Control.PRESET_TOP_LEFT, Vector2(margin.x, margin.y + STATUS_PANEL_SIZE.y + 4.0))
	var enemy_top := margin.y + STATUS_PANEL_SIZE.y + 8.0
	if resource_detail != null and resource_detail.visible:
		enemy_top += RESOURCE_DETAIL_PANEL_SIZE.y + 4.0
	if quickslot_rect.position.x < margin.x + ENEMY_PANEL_SIZE.x + HUD_EDGE_GAP:
		var enemy_size := _control_layout_size(_panels.enemy as Control) if _panels.enemy is Control else ENEMY_PANEL_SIZE
		if enemy_top + enemy_size.y > quickslot_rect.position.y - HUD_EDGE_GAP:
			enemy_top = maxf(enemy_top, quickslot_rect.end.y + HUD_EDGE_GAP)
	_place_panel(_panels.enemy, Control.PRESET_TOP_LEFT, Vector2(margin.x, enemy_top))
	_place_panel(_panels.get("toast"), Control.PRESET_CENTER_TOP, Vector2(0.0, top_stack_bottom + HUD_EDGE_GAP))
	_resize_menu_panel(viewport_size, margin)
	_place_panel(_panels.menu, Control.PRESET_CENTER, Vector2.ZERO)
	_place_panel(_panels.dpad, Control.PRESET_BOTTOM_LEFT, Vector2(margin.x, -margin.w))
	_place_panel(_panels.action, Control.PRESET_BOTTOM_RIGHT, Vector2(-margin.z, -margin.w))
	var side_shortcut_top := map_rect.end.y + HUD_EDGE_GAP
	_place_panel(_panels.side_shortcuts, Control.PRESET_TOP_RIGHT, Vector2(-margin.z, side_shortcut_top))
	_place_panel(_panels.settings, Control.PRESET_TOP_RIGHT, Vector2(-margin.z - 4.0, side_shortcut_top + 4.0))
	_place_panel(_panels.facilities_shortcut, Control.PRESET_TOP_RIGHT, Vector2(-margin.z - 4.0, side_shortcut_top + 47.0))
	_place_panel(_panels.bottom_nav, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -margin.w))
	_panels.bottom_nav.visible = wide_landscape
	var action_rect := _panel_rect(_panels.action)
	_resolve_enemy_bottom_overlap(top_stack_bottom)
	_resize_action_menu_panel(viewport_size, margin, top_stack_bottom)
	_place_action_menu_panel(viewport_size, margin, top_stack_bottom)
	_place_panel(_facility_placement_panel, Control.PRESET_CENTER_BOTTOM, Vector2(0.0, -margin.w - 8.0))

func _panel_rect(panel) -> Rect2:
	if not panel is Control:
		return Rect2()
	var control := panel as Control
	return Rect2(control.position, control.size)

func _top_center_rect(panel, viewport_size: Vector2, top: float) -> Rect2:
	if not panel is Control:
		return Rect2(Vector2(viewport_size.x * 0.5, top), Vector2.ZERO)
	var control := panel as Control
	var panel_size := _control_layout_size(control)
	return Rect2(Vector2((viewport_size.x - panel_size.x) * 0.5, top), panel_size)

func _control_layout_size(control: Control) -> Vector2:
	var combined := control.get_combined_minimum_size()
	return Vector2(
		maxf(control.custom_minimum_size.x, combined.x),
		maxf(control.custom_minimum_size.y, combined.y)
	)

func _resize_action_menu_panel(viewport_size: Vector2, margin: Vector4, top_stack_bottom: float) -> void:
	var action_menu_panel := _panels.get("action_menu") as Control
	if action_menu_panel == null:
		return
	var panel_size := UiPopupLayout.fitted_size(ACTION_MENU_PANEL_SIZE, Vector2(
		viewport_size.x - margin.x - margin.z,
		viewport_size.y - margin.y - margin.w
	))
	action_menu_panel.custom_minimum_size = panel_size
	action_menu_panel.size = panel_size

func _place_action_menu_panel(viewport_size: Vector2, margin: Vector4, top_stack_bottom: float) -> void:
	var action_menu_panel := _panels.get("action_menu") as Control
	if action_menu_panel == null:
		return
	_place_panel(action_menu_panel, Control.PRESET_CENTER, Vector2.ZERO)

func _resolve_enemy_bottom_overlap(top_stack_bottom: float) -> void:
	var enemy_panel := _panels.get("enemy") as Control
	if enemy_panel == null or not enemy_panel.visible:
		return
	var enemy_rect := _panel_rect(enemy_panel)
	var bottom_controls: Array[Rect2] = []
	var dpad_rect := _panel_rect(_panels.dpad)
	var action_rect := _panel_rect(_panels.action)
	if dpad_rect.size != Vector2.ZERO:
		bottom_controls.append(dpad_rect)
	if action_rect.size != Vector2.ZERO:
		bottom_controls.append(action_rect)
	for control_rect in bottom_controls:
		if not enemy_rect.intersects(control_rect):
			continue
		var candidate_y := control_rect.position.y - HUD_EDGE_GAP - enemy_rect.size.y
		if candidate_y >= top_stack_bottom + HUD_EDGE_GAP:
			_place_panel(enemy_panel, Control.PRESET_TOP_LEFT, Vector2(enemy_rect.position.x, candidate_y))
		else:
			enemy_panel.visible = false
		return

func _place_panel(panel, preset: int, offset: Vector2) -> void:
	if not panel is Control:
		return
	var control := panel as Control
	var panel_size := _control_layout_size(control)
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
	var target := UiPopupLayout.fitted_size(MENU_PANEL_SIZE, available)
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

func _menu_panel(size: Vector2) -> PanelContainer:
	var panel := _styled_panel(size, PixelUiTheme.parchment_panel_style())
	panel.theme = PixelUiTheme.create_parchment()
	return panel

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

func _add_icon_row(parent: Container, icon_path: String, text: String) -> Label:
	var row := HBoxContainer.new()
	_ignore_mouse(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
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
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not text.is_empty():
		row.add_child(value)
	return value

func _label(text: String, font_size := 12) -> Label:
	var label := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button() -> Button:
	return UiContentBounds.fit_button(Button.new())

func _section_label(text: String) -> Label:
	return _wrapped_label(text, 11)

func _wrapped_label(text: String, font_size := 12) -> Label:
	var label := _label(text, font_size)
	UiContentBounds.fit_label(label, true, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _card_frame(content: Control, selected := false, centered := false) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = content.custom_minimum_size + Vector2(6, 6)
	_ignore_mouse(frame)
	frame.add_theme_stylebox_override("panel", _menu_card_style(selected))
	if centered:
		var center := CenterContainer.new()
		center.name = "ContentCenter"
		_ignore_mouse(center)
		frame.add_child(center)
		center.add_child(content)
	else:
		frame.add_child(content)
	return frame

func _detail_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "DetailCard"
	card.custom_minimum_size = Vector2(288, 42)
	_ignore_mouse(card)
	var card_style := _menu_card_style(false)
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
	return read_model_provider.speaker_label(speaker_id) if read_model_provider != null else speaker_id

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

func _menu_card_style(selected := false) -> StyleBoxTexture:
	return PixelUiTheme.parchment_card_style(selected)

func _tea_quickslot_count() -> int:
	return read_model_provider.tea_quickslot_count() if read_model_provider != null else 0

func _balance_integer(id: String) -> int:
	return read_model_provider.balance_integer(id) if read_model_provider != null else 0

func _inventory_read_model() -> Dictionary:
	return read_model_provider.inventory_read_model() if read_model_provider != null else {}

func _tea_brewing_read_model() -> Dictionary:
	return read_model_provider.tea_brewing_read_model() if read_model_provider != null else {}

func _meta_codex_read_model() -> Dictionary:
	return read_model_provider.meta_codex_read_model() if read_model_provider != null else {}

func _crafting_read_model(filter: String, selected_recipe_id: String) -> Dictionary:
	return read_model_provider.crafting_read_model(filter, selected_recipe_id) if read_model_provider != null else {}

func _facility_nodes() -> Array:
	return read_model_provider.facility_nodes() if read_model_provider != null else []

func _current_biome_id() -> String:
	return read_model_provider.current_biome_id() if read_model_provider != null else "common_region"

func _dungeon_cleared_for_current_biome() -> bool:
	return read_model_provider.dungeon_cleared_for_current_biome() if read_model_provider != null else false

func _repaired_ruin_biome_ids() -> Array:
	return read_model_provider.repaired_ruin_biome_ids() if read_model_provider != null else []

func _biome_progression_projection() -> Dictionary:
	return read_model_provider.biome_progression_projection() if read_model_provider != null else {}

func _ordered_biome_definitions() -> Array:
	return read_model_provider.ordered_biome_definitions() if read_model_provider != null else []

func _is_biome_map_accessible(biome_id: String) -> bool:
	return read_model_provider.is_biome_map_accessible(biome_id) if read_model_provider != null else false

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
