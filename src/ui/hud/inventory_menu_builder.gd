extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")

const ICON_BAG := "asset_assets_ui_icons_atlas_bag_png"
const ICON_CONSUMABLE := "asset_assets_ui_icons_atlas_gourd_png"
const ICON_ATTACK := "asset_assets_ui_icons_atlas_attack_sword_png"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_MATERIAL := "asset_assets_ui_icons_atlas_crate_png"
const ICON_TOOL := "asset_assets_ui_icons_atlas_low_table_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"

static func rows(model: Dictionary, prepared_teas: Array, state: Dictionary, deps: Dictionary) -> Array:
	var view = deps.view
	var result: Array = []
	if not model.is_empty():
		var compact := bool(state.get("compact", false))
		var summary := HBoxContainer.new()
		summary.name = "InventorySummary"
		summary.add_theme_constant_override("separation", 8)
		summary.add_child(view.icon_text_row(ICON_BAG, "%d / %d칸" % [int(model.capacity.used), int(model.capacity.total)], 11))
		summary.add_child(view.icon_text_row(_kind_icon_reference(String(model.filter_kind)), _filter_label(String(model.filter_kind)), 11))
		result.append(summary)
		var toolbar := GridContainer.new()
		toolbar.name = "InventoryToolbar"
		toolbar.columns = 3 if compact else 7
		view.ignore_mouse(toolbar)
		toolbar.add_theme_constant_override("h_separation", 4)
		toolbar.add_theme_constant_override("v_separation", 4)
		var toolbar_button_size := Vector2(50, 30) if compact else Vector2(54, 30)
		toolbar.add_child(_command_button(view, deps, "이전", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.LEFT), ICON_SCROLL, toolbar_button_size, "이전"))
		toolbar.add_child(_command_button(view, deps, "다음", GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.RIGHT), ICON_SCROLL, toolbar_button_size, "다음"))
		toolbar.add_child(_command_button(view, deps, "정렬", GameCommand.new(GameCommand.Type.INVENTORY_SORT), ICON_BAG, toolbar_button_size, "정렬"))
		for kind in model.available_filters:
			var kind_id := String(kind)
			toolbar.add_child(_command_button(view, deps, _filter_label(kind_id), GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, {"kind": kind_id}), _kind_icon_reference(kind_id), toolbar_button_size, _filter_label(kind_id)))
		result.append(toolbar)
		var visible_rows := _display_rows(model.slots, int(model.get("selected_slot_index", -1)))
		var page_start := _page_start(visible_rows, "slot_index", int(model.get("selected_slot_index", -1)), 8, -1)
		var page_end := mini(visible_rows.size(), page_start + 8)
		var shelf := VBoxContainer.new()
		shelf.name = "InventoryShelf"
		shelf.add_theme_constant_override("separation", 8)
		var slot_strip := GridContainer.new()
		slot_strip.name = "InventorySlotStrip"
		slot_strip.columns = 3 if compact else 4
		view.ignore_mouse(slot_strip)
		slot_strip.add_theme_constant_override("h_separation", 5)
		slot_strip.add_theme_constant_override("v_separation", 5)
		for row_index in range(page_start, page_end):
			slot_strip.add_child(_slot_card(visible_rows[row_index], state, deps))
		shelf.add_child(slot_strip)
		var preview := _detail_card(_selected_row(visible_rows, int(model.get("selected_slot_index", -1))), state, deps)
		preview.name = "InventoryPreview"
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shelf.add_child(preview)
		result.append(shelf)
		if visible_rows.size() > 8:
			result.append(view.label("%d-%d / %d" % [page_start + 1, page_end, visible_rows.size()], 11))
		_append_prepared_tea_rows(result, prepared_teas, state, deps)
		return result
	result.append(view.label("인벤토리 read model 없음", 11))
	_append_prepared_tea_rows(result, prepared_teas, state, deps)
	return result

static func _append_prepared_tea_rows(rows: Array, prepared_teas: Array, state: Dictionary, deps: Dictionary) -> void:
	if prepared_teas.is_empty():
		return
	var view = deps.view
	rows.append(view.section_label("우린 차"))
	var tea_strip := GridContainer.new()
	tea_strip.name = "PreparedTeaStrip"
	tea_strip.columns = 3 if bool(state.get("compact", false)) else 4
	tea_strip.add_theme_constant_override("h_separation", 5)
	tea_strip.add_theme_constant_override("v_separation", 5)
	for prepared in prepared_teas:
		var card: PanelContainer = view.card_frame(view.label("%s\n%d회" % [String(prepared.get("tea_name", prepared.get("tea_id", "차"))), int(prepared.get("remaining_uses", 1))], 9))
		card.custom_minimum_size = Vector2(66, 60)
		tea_strip.add_child(card)
	rows.append(tea_strip)

static func _slot_card(row: Dictionary, state: Dictionary, deps: Dictionary) -> Button:
	var view = deps.view
	var compact := bool(state.get("compact", false))
	var button := _command_button(
		view,
		deps,
		"빈칸" if bool(row.get("empty", false)) else "%s\n× %d" % [String(row.get("name", row.get("item_id", ""))), int(row.get("quantity", 0))],
		GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, int(row.slot_index), {"slot_index": int(row.slot_index)})
	)
	button.name = "InventorySlotCard%d" % int(row.get("slot_index", -1))
	button.custom_minimum_size = Vector2(64, 62) if compact else Vector2(78, 70)
	button.icon = view.load_texture(deps.inventory_item_icon_reference.call(row))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28 if compact else 34)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", view.menu_card_style(false))
	button.add_theme_stylebox_override("hover", view.menu_card_style(true))
	button.add_theme_stylebox_override("pressed", view.menu_card_style(true))
	if bool(row.get("selected", false)):
		button.add_theme_stylebox_override("normal", view.menu_card_style(true))
	button.disabled = bool(row.get("empty", false))
	button.tooltip_text = String(row.get("name", row.get("item_id", "")))
	button.pressed.connect(func(): deps.show_detail_popup.call("아이템 상세", _detail_card(row, state, deps)))
	return button

static func _display_rows(slot_rows: Array, selected_slot_index: int) -> Array:
	var result := []
	var group_indexes := {}
	for row in slot_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if bool(row.get("empty", false)) or bool(row.get("can_equip", false)):
			result.append(row)
			continue
		var item_id := String(row.get("item_id", ""))
		if item_id.is_empty():
			result.append(row)
			continue
		if not group_indexes.has(item_id):
			var group: Dictionary = row.duplicate(true)
			group["slot_indexes"] = [int(row.get("slot_index", -1))]
			group["quantity"] = int(row.get("quantity", 0))
			group["stack_label"] = "합계 %d개" % int(group.quantity)
			group["selected"] = int(row.get("slot_index", -1)) == selected_slot_index
			group_indexes[item_id] = result.size()
			result.append(group)
			continue
		var group_index := int(group_indexes[item_id])
		var existing: Dictionary = result[group_index]
		existing["quantity"] = int(existing.get("quantity", 0)) + int(row.get("quantity", 0))
		existing["stack_label"] = "합계 %d개" % int(existing.quantity)
		existing["slot_indexes"].append(int(row.get("slot_index", -1)))
		if int(row.get("slot_index", -1)) == selected_slot_index:
			existing["slot_index"] = selected_slot_index
			existing["selected"] = true
		result[group_index] = existing
	return result

static func _selected_row(rows: Array, selected_slot_index: int) -> Dictionary:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("slot_index", -1)) == selected_slot_index:
			return row
		if row.has("slot_indexes") and row.slot_indexes.has(selected_slot_index):
			return row
	return rows[0] if not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY else {}

static func _detail_card(row: Dictionary, state: Dictionary, deps: Dictionary) -> Control:
	var view = deps.view
	var compact := bool(state.get("compact", false))
	var card: PanelContainer = view.detail_card("선택한 항목")
	card.custom_minimum_size = Vector2(220, 42) if compact else Vector2(288, 42)
	var rows := card.get_node("Rows") as VBoxContainer
	if not row.is_empty() and not bool(row.get("empty", false)):
		rows.add_child(view.icon_text_row(deps.inventory_item_icon_reference.call(row), String(row.get("name", row.get("item_id", ""))), 11))
		rows.add_child(view.label("%s · × %d · %s" % [
			String(row.get("kind", "")),
			int(row.get("quantity", 0)),
			String(row.get("stack_label", ""))
		], 10))
		var description := String(row.get("description", "")).strip_edges()
		if not description.is_empty():
			rows.add_child(view.wrapped_label(description, 10))
	else:
		rows.add_child(view.icon_text_row("", "표시할 항목 없음", 11))
	var actions := HBoxContainer.new()
	view.ignore_mouse(actions)
	actions.add_theme_constant_override("separation", 4)
	if not row.is_empty():
		var slot_index := int(row.get("slot_index", -1))
		if bool(row.get("can_use", false)):
			var action_label := "설치" if bool(row.get("can_install", false)) else "사용"
			actions.add_child(_command_button(view, deps, action_label, GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, slot_index, {"slot_index": slot_index}), deps.inventory_item_icon_reference.call(row), Vector2(54, 28), action_label))
		if bool(row.get("can_equip", false)):
			actions.add_child(_command_button(view, deps, "장착", GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, slot_index, {"slot_index": slot_index}), deps.inventory_item_icon_reference.call(row), Vector2(54, 28), "장착"))
	rows.add_child(actions)
	return card

static func _command_button(view, deps: Dictionary, text: String, command: GameCommand, icon_reference := "", min_size := Vector2(40, 24), tooltip := "") -> Button:
	return view.command_button(text, command, deps.emit_command, min_size, Control.FOCUS_ALL, icon_reference, tooltip)

static func _kind_icon_reference(kind: String) -> String:
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

static func _page_start(rows: Array, key: String, selected, page_size: int, default_value = "") -> int:
	if rows.size() <= page_size:
		return 0
	for index in range(rows.size()):
		if str(rows[index].get(key, default_value)) == str(selected):
			return clampi(index - 2, 0, rows.size() - page_size)
	return 0

static func _filter_label(value: String) -> String:
	return "전체" if value == "all" else value
