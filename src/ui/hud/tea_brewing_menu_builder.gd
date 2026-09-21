extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")

const ICON_KOKORO := "ui_tea_leaf_icon"
const ICON_TEA := "asset_assets_ui_icons_atlas_tea_action_cup_png"
const ICON_TEA_WARE := "asset_assets_ui_icons_atlas_bowl_png"
const ICON_TEA_TABLE := "res://assets/sprites/objects/crafting/tea_table_2x2_64x64.png"

static func rows(model: Dictionary, state: Dictionary, deps: Dictionary) -> Array:
	var view = deps.view
	var result: Array = []
	if model.is_empty():
		result.append(view.label("차 우리기 read model 없음", 11))
		return result
	var leaves := _array_value(model.get("leaves", []))
	var vessels := _array_value(model.get("vessels", []))
	var slots := _array_value(model.get("quickslots", []))
	var preview: Dictionary = model.get("preview", {})
	var leaf := _selected_row(leaves, "id", String(model.get("selected_leaf_id", "")))
	var vessel := _selected_row(vessels, "selection_key", String(model.get("selected_vessel_key", "")))
	var slot := _selected_row(slots, "slot_index", int(model.get("selected_slot_index", -1)))

	var location: HBoxContainer = view.icon_text_row(ICON_TEA_TABLE, "찻상 준비됨" if bool(model.get("has_brewing_location", false)) else "이 차를 우리려면 찻상이 필요합니다", 10)
	location.name = "TeaBrewingLocation"
	result.append(location)

	var compact := bool(state.get("compact", false))
	var stage: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	stage.name = "TeaBrewingStage"
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 8)
	view.ignore_mouse(stage)
	stage.add_child(_selector_card("찻잎", ICON_KOKORO, _leaf_label(leaf), "leaf", not leaves.is_empty(), deps))
	stage.add_child(_stage_mark("+", view))
	stage.add_child(_selector_card("다구", _vessel_icon(vessel, deps), _vessel_label(vessel), "vessel", not vessels.is_empty(), deps))
	stage.add_child(_stage_mark("↓" if compact else "→", view))
	stage.add_child(_selector_card("찻잔", ICON_TEA, _slot_label(slot), "slot", not slots.is_empty(), deps))
	result.append(stage)

	var finish := HBoxContainer.new()
	finish.name = "TeaBrewingFinish"
	finish.add_theme_constant_override("separation", 8)
	view.ignore_mouse(finish)
	var preview_label: Label = view.wrapped_label(_preview_label(preview), 10)
	preview_label.name = "TeaBrewingPreview"
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	finish.add_child(preview_label)
	var brew_button: Button = view.command_button("차 우리기", GameCommand.new(GameCommand.Type.BREW_TEA), deps.emit_command, Vector2(42, 22), Control.FOCUS_ALL)
	brew_button.name = "BrewTeaButton"
	brew_button.icon = view.load_texture(ICON_TEA)
	brew_button.expand_icon = true
	brew_button.add_theme_constant_override("icon_max_width", 24)
	brew_button.custom_minimum_size = Vector2(132, 38)
	brew_button.add_theme_stylebox_override("normal", view.button_style(Color(0.16, 0.27, 0.14, 0.96)))
	brew_button.add_theme_stylebox_override("hover", view.button_style(Color(0.24, 0.40, 0.18, 0.98)))
	brew_button.add_theme_stylebox_override("pressed", view.button_style(Color(0.38, 0.52, 0.20, 1.0)))
	brew_button.disabled = not bool(model.get("can_brew", false))
	finish.add_child(brew_button)
	result.append(finish)
	return result

static func _selector_card(title: String, icon_reference: String, text: String, target: String, enabled: bool, deps: Dictionary) -> PanelContainer:
	var view = deps.view
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(132, 112)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	view.ignore_mouse(content)
	var title_label: Label = view.label(title, 10)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_label)
	var icon: TextureRect = view.item_icon_rect(icon_reference, Vector2(48, 48))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(icon)
	var name_label: Label = view.wrapped_label(text, 9)
	name_label.custom_minimum_size = Vector2(124, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 4)
	view.ignore_mouse(controls)
	var previous: Button = view.command_button("‹", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": target}), deps.emit_command, Vector2(42, 22), Control.FOCUS_ALL)
	previous.name = "%sPreviousButton" % target.capitalize()
	previous.disabled = not enabled
	controls.add_child(previous)
	var next: Button = view.command_button("›", GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": target}), deps.emit_command, Vector2(42, 22), Control.FOCUS_ALL)
	next.name = "%sNextButton" % target.capitalize()
	next.disabled = not enabled
	controls.add_child(next)
	content.add_child(controls)
	var card: PanelContainer = view.card_frame(content, enabled)
	card.name = "%sCard" % title
	return card

static func _stage_mark(text: String, view) -> Label:
	var result: Label = view.label(text, 18)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_color_override("font_color", Color(0.84, 0.65, 0.36, 1.0))
	return result

static func _selected_row(rows: Array, key: String, selected) -> Dictionary:
	for row in rows:
		if row.get(key) == selected:
			return row
	return rows[0] if not rows.is_empty() else {}

static func _vessel_icon(vessel: Dictionary, deps: Dictionary) -> String:
	return deps.item_icon_reference.call(String(vessel.get("id", "")), "다구", vessel) if not vessel.is_empty() else ICON_TEA_WARE

static func _leaf_label(leaf: Dictionary) -> String:
	return "%s  ×%d" % [String(leaf.get("name", "")), int(leaf.get("quantity", 0))] if not leaf.is_empty() else "찻잎을 고르세요"

static func _vessel_label(vessel: Dictionary) -> String:
	return String(vessel.get("name", "")) if not vessel.is_empty() else "다구를 고르세요"

static func _slot_label(slot: Dictionary) -> String:
	return String(slot.get("label", "")) if not slot.is_empty() else "빈 찻잔이 없습니다"

static func _preview_label(preview: Dictionary) -> String:
	if not bool(preview.get("ok", false)):
		match String(preview.get("reason", "")):
			"missing_tea_leaf":
				return "찻잎을 골라 주세요"
			"unknown_vessel", "missing_vessel":
				return "다구를 골라 주세요"
			"missing_brewing_location":
				return "찻상이 있는 곳에서 우릴 수 있습니다"
			"quickslot_occupied":
				return "다른 찻잔을 골라 주세요"
			_:
				return "찻잎과 다구를 골라 주세요"
	var prepared: Dictionary = preview.get("prepared_tea", {})
	var slot_status := "빈 칸" if not bool(preview.get("target_slot_occupied", false)) else "차 있음"
	return "%s\n기운 +%d  ·  %d잔  ·  %.1f초  ·  %s" % [
		String(prepared.get("tea_name", prepared.get("tea_id", ""))),
		int(prepared.get("ki_recovery", 0)),
		int(prepared.get("remaining_uses", 0)),
		float(prepared.get("drink_seconds", 0.0)),
		slot_status
	]

static func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []
