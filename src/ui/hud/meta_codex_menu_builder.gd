extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")

const ICON_KOKORO := "ui_tea_leaf_icon"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"

static func rows(model: Dictionary, state: Dictionary, deps: Dictionary) -> Array:
	var view = deps.view
	var result: Array = []
	if model.is_empty():
		result.append(view.label("도감 read model 없음", 11))
		return result
	result.append(view.icon_text_row(_tab_icon(String(model.get("selected_tab", ""))), "%s · 발견 %d · 엔딩 %d" % [
		_tab_label(String(model.get("selected_tab", ""))),
		int(_dictionary_value(model.get("counts", {})).get("discovered_records", 0)),
		int(_dictionary_value(model.get("counts", {})).get("endings", 0))
	], 11))
	var tabs := HBoxContainer.new()
	view.ignore_mouse(tabs)
	tabs.add_theme_constant_override("separation", 4)
	for tab in _array_value(model.get("available_tabs", [])):
		tabs.add_child(_command_button(view, deps, _tab_label(String(tab)), GameCommand.new(GameCommand.Type.META_CODEX_SET_TAB, Vector2i.ZERO, -1, {"tab": String(tab)})))
	result.append(tabs)
	var filters := HBoxContainer.new()
	view.ignore_mouse(filters)
	filters.add_theme_constant_override("separation", 4)
	filters.add_child(_command_button(view, deps, "전체", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "all"})))
	filters.add_child(_command_button(view, deps, "발견", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "discovered"})))
	filters.add_child(_command_button(view, deps, "미발견", GameCommand.new(GameCommand.Type.META_CODEX_SET_FILTER, Vector2i.ZERO, -1, {"filter": "masked"})))
	filters.add_child(_command_button(view, deps, "‹", GameCommand.new(GameCommand.Type.META_CODEX_NAVIGATE, Vector2i.LEFT)))
	filters.add_child(_command_button(view, deps, "›", GameCommand.new(GameCommand.Type.META_CODEX_NAVIGATE, Vector2i.RIGHT)))
	result.append(filters)
	var model_rows := _array_value(model.get("rows", []))
	var detail := _dictionary_value(model.get("detail", {}))
	var page_start := _page_start(model_rows, "id", String(detail.get("id", "")), 5)
	var compact := bool(state.get("compact", false))
	var journal: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	journal.name = "CodexJournal"
	journal.add_theme_constant_override("separation", 6)
	var entries := GridContainer.new()
	entries.name = "CodexEntryGrid"
	entries.columns = 1 if compact else 2
	entries.add_theme_constant_override("h_separation", 4)
	entries.add_theme_constant_override("v_separation", 4)
	for index in range(page_start, mini(model_rows.size(), page_start + 5)):
		var row: Dictionary = model_rows[index]
		entries.add_child(_option_card(row, String(model.get("selected_tab", "")), GameCommand.new(GameCommand.Type.META_CODEX_SELECT_DETAIL, Vector2i.ZERO, -1, {"id": String(row.get("id", ""))}), deps))
	journal.add_child(entries)
	var detail_card: PanelContainer = view.detail_card("기록 상세")
	detail_card.name = "CodexDetailCard"
	detail_card.custom_minimum_size = Vector2(166, 90)
	var detail_rows := detail_card.get_node("Rows") as VBoxContainer
	detail_rows.add_child(view.wrapped_label(_detail_text(detail), 10))
	journal.add_child(detail_card)
	result.append(journal)
	if model_rows.size() > 5:
		result.append(view.label("항목 %d-%d / %d" % [page_start + 1, mini(model_rows.size(), page_start + 5), model_rows.size()], 10))
	return result

static func _option_card(row: Dictionary, tab: String, command: GameCommand, deps: Dictionary) -> Button:
	var view = deps.view
	var button := _command_button(view, deps, "%s\n%s" % [String(row.get("name", "")), String(row.get("summary", ""))], command)
	button.custom_minimum_size = Vector2(136, 54)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = view.load_texture(_tab_icon(tab))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_stylebox_override("normal", view.menu_card_style(bool(row.get("selected", false))))
	return button

static func _command_button(view, deps: Dictionary, text: String, command: GameCommand) -> Button:
	return view.command_button(text, command, deps.emit_command, Vector2(40, 24), Control.FOCUS_ALL)

static func _detail_text(detail: Dictionary) -> String:
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

static func _related_names(rows: Array) -> Array:
	var names := []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			names.append(String(row.get("name", row.get("id", ""))))
		else:
			names.append(String(row))
	return names

static func _tab_label(tab: String) -> String:
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

static func _tab_icon(tab: String) -> String:
	match tab:
		"teas":
			return ICON_TEA
		"tea_ware":
			return ICON_TEA_WARE
		"yokai":
			return ICON_KOKORO
		"memories":
			return ICON_SCROLL
		_:
			return ICON_SCROLL

static func _page_start(rows: Array, key: String, selected, page_size: int, default_value = "") -> int:
	if rows.size() <= page_size:
		return 0
	for index in range(rows.size()):
		if str(rows[index].get(key, default_value)) == str(selected):
			return clampi(index - 2, 0, rows.size() - page_size)
	return 0

static func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

static func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
