extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

const ICON_CHECK := "asset_assets_ui_icons_atlas_quest_check_1_png"
const ICON_CONSUMABLE := "asset_assets_ui_icons_atlas_gourd_png"
const ICON_MATERIAL := "asset_assets_ui_icons_atlas_crate_png"
const ICON_TOOL := "asset_assets_ui_icons_atlas_low_table_png"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_WORKBENCH := "asset_assets_sprites_objects_crafting_workbench_32x32_png"

static func rows(model: Dictionary, state: Dictionary, deps: Dictionary) -> Array:
	var view = deps.view
	var result: Array = []
	if model.is_empty():
		return result
	if not bool(model.get("ok", false)):
		result.append(view.label("제작 read model 없음", 11))
		return result
	var filter := String(state.get("filter", "all"))
	var counts: Dictionary = model.get("counts", {})
	result.append(view.section_label("제작법 %d/%d · 가능 %d · 필터 %s" % [
		int(counts.get("visible", 0)),
		int(counts.get("total", 0)),
		int(counts.get("craftable", 0)),
		_filter_label(filter)
	]))
	var compact := bool(state.get("compact", false))
	var filters := GridContainer.new()
	filters.name = "CraftingFilterBar"
	filters.columns = 3 if compact else 7
	view.ignore_mouse(filters)
	filters.add_theme_constant_override("h_separation", 4)
	filters.add_theme_constant_override("v_separation", 4)
	for category in model.get("categories", []):
		var category_id := String(category)
		filters.add_child(_filter_button(_filter_label(category_id), category_id, filter, deps))
	result.append(filters)
	result.append(view.section_label("제작법 목록"))
	var recipe_strip := GridContainer.new()
	recipe_strip.name = "CraftingRecipeStrip"
	recipe_strip.columns = 3
	view.ignore_mouse(recipe_strip)
	recipe_strip.add_theme_constant_override("h_separation", 5)
	recipe_strip.add_theme_constant_override("v_separation", 5)
	for row_model in model.get("rows", []):
		recipe_strip.add_child(_recipe_row(row_model, deps))
	result.append(recipe_strip)
	return result

static func detail_content(detail: Dictionary, state: Dictionary, deps: Dictionary) -> Control:
	var view = deps.view
	if detail.is_empty():
		return view.detail_card_with_text("상세", "표시할 제작법 없음")
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
	var compact := bool(state.get("compact", false))
	var card: PanelContainer = view.detail_card("제작 상세")
	card.name = "CraftingDetailCard"
	card.custom_minimum_size = Vector2(220, 42) if compact else Vector2(520, 42)
	var rows_box := card.get_node("Rows") as VBoxContainer
	var flow := HBoxContainer.new()
	flow.name = "CraftingFlow"
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("separation", 6)
	for material in detail.get("materials", []):
		var material_card: PanelContainer = view.card_frame(view.icon_text_row(deps.inventory_item_icon_reference.call(material), "%s\n%d/%d" % [String(material.get("name", material.get("item_id", ""))), int(material.get("available", 0)), int(material.get("required", 0))], 9), false, true)
		material_card.custom_minimum_size = Vector2(96, 56)
		flow.add_child(material_card)
	flow.add_child(view.label("→", 18))
	var result_card: PanelContainer = view.card_frame(view.icon_text_row(deps.crafting_result_icon_reference.call(detail), "%s ×%d" % [
		String(result.get("name", result.get("item_id", ""))),
		int(result.get("quantity", 1))
	], 11), true, true)
	result_card.custom_minimum_size = Vector2(126, 56)
	flow.add_child(result_card)
	rows_box.add_child(flow)
	rows_box.add_child(view.label("상태 %s" % String(detail.get("reason_label", "")), 10))
	var description := String(result.get("description", "")).strip_edges()
	if not description.is_empty():
		rows_box.add_child(view.section_label("설명"))
		rows_box.add_child(view.wrapped_label(description, 10))
	var facts := GridContainer.new()
	facts.name = "CraftingFacts"
	facts.columns = 1 if compact else 3
	view.ignore_mouse(facts)
	facts.add_theme_constant_override("h_separation", 5)
	facts.add_theme_constant_override("v_separation", 5)
	facts.add_child(_fact_card("필요 재료", "없음" if materials.is_empty() else "\n".join(materials), deps))
	facts.add_child(_fact_card("제작 방식", "손제작" if facilities.is_empty() else "\n".join(facilities), deps))
	var unlock_biome_name := String(detail.get("unlock_biome_name", "")).strip_edges()
	if not unlock_biome_name.is_empty():
		facts.add_child(_fact_card("해금 조건", unlock_biome_name, deps))
	rows_box.add_child(facts)
	var craft_button: Button = view.button()
	craft_button.name = "CraftSelectedRecipeButton"
	craft_button.custom_minimum_size = Vector2(160, 42)
	craft_button.disabled = not bool(detail.get("craftable", false))
	craft_button.focus_mode = Control.FOCUS_ALL
	craft_button.mouse_filter = Control.MOUSE_FILTER_STOP
	craft_button.tooltip_text = String(detail.get("reason_label", "제작"))
	var craft_button_content: HBoxContainer = view.icon_text_row(ICON_WORKBENCH, "제작", 12)
	craft_button_content.alignment = BoxContainer.ALIGNMENT_CENTER
	craft_button_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(craft_button_content.get_child(1) as Label).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiContentBounds.add_safe_content(craft_button, craft_button_content, Vector4(8, 6, 8, 6))
	var recipe_id := String(detail.get("recipe_id", ""))
	craft_button.pressed.connect(func():
		deps.emit_command.call(GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, 0, {"recipe_id": recipe_id}))
	)
	rows_box.add_child(craft_button)
	return card

static func _recipe_row(row_model: Dictionary, deps: Dictionary) -> Control:
	var view = deps.view
	var card := VBoxContainer.new()
	card.name = "CraftingRecipeContent"
	view.ignore_mouse(card)
	card.add_theme_constant_override("separation", 3)
	var summary := VBoxContainer.new()
	summary.name = "CraftingRecipeSummary"
	view.ignore_mouse(summary)
	summary.add_theme_constant_override("separation", 2)
	var icon_row := HBoxContainer.new()
	view.ignore_mouse(icon_row)
	icon_row.add_theme_constant_override("separation", 4)
	icon_row.add_child(view.item_icon_rect(deps.crafting_result_icon_reference.call(row_model), Vector2(34, 34)))
	icon_row.add_child(view.item_icon_rect(_state_icon_reference(row_model), Vector2(16, 16)))
	summary.add_child(icon_row)
	var result := _dictionary_value(row_model.get("result", {}))
	var recipe_label: Label = view.label("%s\n%s" % [
		String(result.get("name", row_model.get("name", row_model.get("recipe_id", "")))),
		String(row_model.get("reason_label", ""))
	], 9)
	UiContentBounds.fit_label(recipe_label, false, true)
	recipe_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(recipe_label)
	card.add_child(summary)
	var recipe_id := String(row_model.get("recipe_id", ""))
	var button: Button = view.button()
	button.name = "CraftingRecipeCard"
	button.custom_minimum_size = Vector2(118, 88)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = "%s 상세" % String(result.get("name", row_model.get("name", recipe_id)))
	button.add_theme_stylebox_override("normal", view.crafting_card_style(row_model))
	button.add_theme_stylebox_override("hover", view.menu_card_style(true))
	button.add_theme_stylebox_override("pressed", view.menu_card_style(true))
	button.pressed.connect(func():
		deps.set_selected_recipe_id.call(recipe_id)
		deps.show_detail_popup.call(recipe_id)
	)
	UiContentBounds.add_safe_content(button, card, Vector4(8, 8, 8, 8))
	return button

static func _filter_button(text: String, category: String, active_filter: String, deps: Dictionary) -> Button:
	var view = deps.view
	var button: Button = view.button()
	button.text = text
	button.icon = view.load_texture(_category_icon_reference(category))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 18)
	button.custom_minimum_size = Vector2(58, 30)
	button.disabled = category == active_filter
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = text
	button.pressed.connect(func():
		deps.set_filter.call(category)
		deps.set_selected_recipe_id.call("")
		deps.refresh_open_menu.call()
	)
	return button

static func _fact_card(title: String, text: String, deps: Dictionary) -> PanelContainer:
	var view = deps.view
	var card := PanelContainer.new()
	card.name = "CraftingFactCard"
	card.custom_minimum_size = Vector2(120, 58)
	view.ignore_mouse(card)
	card.add_theme_stylebox_override("panel", view.menu_card_style(false))
	var rows_box := VBoxContainer.new()
	rows_box.name = "CenteredContent"
	view.ignore_mouse(rows_box)
	rows_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rows_box.add_theme_constant_override("separation", 1)
	UiContentBounds.add_safe_content(card, rows_box, Vector4(4, 4, 4, 4))
	var title_label: Label = view.label(title, 9)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows_box.add_child(title_label)
	var text_label: Label = view.label(text, 10)
	UiContentBounds.fit_label(text_label, false, true)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows_box.add_child(text_label)
	return card

static func _state_icon_reference(row_model: Dictionary) -> String:
	if bool(row_model.get("craftable", false)):
		return ICON_CHECK
	if String(row_model.get("reason", "")) == "missing_materials":
		return ICON_MATERIAL
	return ICON_TOOL

static func _category_icon_reference(category: String) -> String:
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

static func _filter_label(value: String) -> String:
	return "전체" if value == "all" else value

static func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
