extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const HudMenuViewHelpers = preload("res://src/ui/hud/hud_menu_view_helpers.gd")
const InventoryMenuBuilder = preload("res://src/ui/hud/inventory_menu_builder.gd")
const CraftingMenuBuilder = preload("res://src/ui/hud/crafting_menu_builder.gd")
const TeaBrewingMenuBuilder = preload("res://src/ui/hud/tea_brewing_menu_builder.gd")
const MetaCodexMenuBuilder = preload("res://src/ui/hud/meta_codex_menu_builder.gd")

const FORBIDDEN_DEP_KEYS := [
	"hud",
	"game_hud",
	"self",
	"provider",
	"read_model_provider",
	"inventory",
	"inventory_command_runtime",
	"crafting_service",
	"tea_service",
	"tea_brewing_command_runtime",
	"meta_codex_command_runtime"
]

var emitted_commands: Array = []
var shown_popups: Array = []
var refresh_count := 0
var selected_recipe_ids: Array = []
var filters: Array = []

func run(asserts) -> void:
	_assert_inventory_builder_rows_and_popup(asserts)
	_assert_tea_brewing_builder_commands(asserts)
	_assert_meta_codex_builder_detail_text(asserts)
	_assert_crafting_builder_callbacks_and_detail(asserts)

func _assert_inventory_builder_rows_and_popup(asserts) -> void:
	_reset_spies()
	var deps := _inventory_deps()
	_assert_no_forbidden_deps(asserts, deps, "inventory builder deps stay presentation-only")
	var rows: Array = InventoryMenuBuilder.rows(_inventory_model(), [{"tea_name": "엽차", "remaining_uses": 2}], {"compact": false}, deps)
	var root := _root_with_rows(rows)
	asserts.true_value(root.get_node_or_null("InventorySummary") != null, "inventory builder renders capacity summary")
	asserts.true_value(_tree_has_text(root, "5 / 24칸"), "inventory builder reads capacity from model")
	asserts.true_value(root.get_node_or_null("InventoryShelf/InventorySlotStrip/InventorySlotCard3") != null, "inventory builder preserves grouped selected slot index")
	asserts.true_value(root.get_node_or_null("PreparedTeaStrip") != null, "inventory builder renders prepared tea strip from input")
	var empty_card := root.get_node_or_null("InventoryShelf/InventorySlotStrip/InventorySlotCard1") as Button
	asserts.true_value(empty_card != null and empty_card.disabled, "inventory builder disables empty slot cards")
	var selected_card := root.get_node_or_null("InventoryShelf/InventorySlotStrip/InventorySlotCard3") as Button
	if selected_card != null:
		selected_card.pressed.emit()
	asserts.equal(emitted_commands.size(), 1, "inventory slot card emits select command")
	asserts.equal(emitted_commands[0].type, GameCommand.Type.INVENTORY_SELECT_SLOT, "inventory slot card emits inventory select command")
	asserts.equal(shown_popups.size(), 1, "inventory slot card requests detail popup")
	asserts.true_value(_tree_has_text(shown_popups[0].content, "두꺼운 나무"), "inventory detail popup content keeps item description")
	asserts.true_value(_tree_has_text(shown_popups[0].content, "사용"), "inventory detail popup content keeps use action")
	asserts.true_value(_tree_has_text(shown_popups[0].content, "장착"), "inventory detail popup content keeps equip action")
	root.free()

func _assert_tea_brewing_builder_commands(asserts) -> void:
	_reset_spies()
	var deps := _base_deps()
	deps["item_icon_reference"] = Callable(self, "_item_icon_reference")
	_assert_no_forbidden_deps(asserts, deps, "tea builder deps stay presentation-only")
	var rows: Array = TeaBrewingMenuBuilder.rows(_tea_model(false), {"compact": true}, deps)
	var root := _root_with_rows(rows)
	asserts.true_value(root.get_node_or_null("TeaBrewingStage") is VBoxContainer, "compact tea builder uses vertical stage")
	asserts.true_value(_tree_has_text(root, "찻상이 있는 곳에서 우릴 수 있습니다"), "tea builder preserves missing location reason text")
	var brew := root.get_node_or_null("TeaBrewingFinish/BrewTeaButton") as Button
	asserts.true_value(brew != null and brew.disabled, "tea builder disables brew button when model cannot brew")
	var next := _find_button_by_name(root, "LeafNextButton")
	if next != null:
		next.pressed.emit()
	asserts.equal(emitted_commands.size(), 1, "tea builder navigation emits command")
	asserts.equal(emitted_commands[0].type, GameCommand.Type.TEA_BREW_NAVIGATE, "tea builder emits tea navigation command")
	asserts.equal(String(emitted_commands[0].payload.get("target", "")), "leaf", "tea navigation targets leaf selector")
	root.free()

func _assert_meta_codex_builder_detail_text(asserts) -> void:
	_reset_spies()
	var deps := _base_deps()
	_assert_no_forbidden_deps(asserts, deps, "meta builder deps stay presentation-only")
	var rows: Array = MetaCodexMenuBuilder.rows(_meta_model(), {"compact": false}, deps)
	var root := _root_with_rows(rows)
	asserts.true_value(_tree_has_text(root, "차 · 발견 1 · 엔딩 0"), "meta builder renders tab/count summary")
	asserts.true_value(_tree_has_text(root, "미발견 항목 — 스포일러를 가립니다"), "meta builder preserves masked spoiler text")
	var tab_button := _find_button(root, "차")
	if tab_button != null:
		tab_button.pressed.emit()
	asserts.equal(emitted_commands[0].type, GameCommand.Type.META_CODEX_SET_TAB, "meta tab button emits command")
	root.free()

func _assert_crafting_builder_callbacks_and_detail(asserts) -> void:
	_reset_spies()
	var deps := _crafting_deps()
	_assert_no_forbidden_deps(asserts, deps, "crafting builder deps stay presentation-only")
	var state := {"compact": false, "filter": "all", "selected_recipe_id": "different"}
	var rows: Array = CraftingMenuBuilder.rows(_crafting_model(), state, deps)
	var root := _root_with_rows(rows)
	asserts.true_value(_tree_has_text(root, "제작법 2/2 · 가능 1 · 필터 전체"), "crafting builder renders counts and filter label")
	var filter_button := _find_button(root.get_node_or_null("CraftingFilterBar"), "도구")
	if filter_button != null:
		filter_button.pressed.emit()
	asserts.equal(filters, ["도구"], "crafting filter button asks GameHud to set filter")
	asserts.equal(selected_recipe_ids, [""], "crafting filter button asks GameHud to reset selected recipe")
	asserts.equal(refresh_count, 1, "crafting filter button asks GameHud to refresh open menu")
	var recipe_card := root.get_node_or_null("CraftingRecipeStrip/CraftingRecipeCard") as Button
	if recipe_card != null:
		recipe_card.pressed.emit()
	asserts.true_value(selected_recipe_ids.has("wooden_workbench"), "crafting recipe card asks GameHud to set selected recipe")
	asserts.true_value(shown_popups.has("wooden_workbench"), "crafting recipe card asks GameHud to show detail popup")
	var detail := CraftingMenuBuilder.detail_content(_crafting_model().detail, state, deps)
	asserts.true_value(_tree_has_text(detail, "필요 재료"), "crafting detail keeps material fact card")
	asserts.true_value(_tree_has_text(detail, "일반 지역"), "crafting detail keeps unlock biome")
	var craft := detail.get_node_or_null("Rows/CraftSelectedRecipeButton") as Button
	if craft != null:
		craft.pressed.emit()
	asserts.equal(emitted_commands.back().type, GameCommand.Type.CRAFT_RECIPE, "crafting detail craft button emits craft command")
	detail.free()
	root.free()

func _base_deps() -> Dictionary:
	return {
		"view": _view(),
		"emit_command": Callable(self, "_record_command")
	}

func _inventory_deps() -> Dictionary:
	var deps := _base_deps()
	deps["show_detail_popup"] = Callable(self, "_record_popup")
	deps["inventory_item_icon_reference"] = Callable(self, "_inventory_item_icon_reference")
	deps["inventory_item_icon"] = Callable(self, "_inventory_item_icon")
	return deps

func _crafting_deps() -> Dictionary:
	var deps := _base_deps()
	deps["refresh_open_menu"] = Callable(self, "_record_refresh")
	deps["show_detail_popup"] = Callable(self, "_record_crafting_popup")
	deps["set_filter"] = Callable(self, "_record_filter")
	deps["set_selected_recipe_id"] = Callable(self, "_record_selected_recipe_id")
	deps["inventory_item_icon_reference"] = Callable(self, "_inventory_item_icon_reference")
	deps["crafting_result_icon_reference"] = Callable(self, "_crafting_result_icon_reference")
	return deps

func _view() -> HudMenuViewHelpers:
	var view := HudMenuViewHelpers.new()
	view.texture_resolver = Callable(self, "_null_texture")
	return view

func _assert_no_forbidden_deps(asserts, deps: Dictionary, message: String) -> void:
	for key in FORBIDDEN_DEP_KEYS:
		asserts.false_value(deps.has(key), "%s: %s" % [message, key])

func _root_with_rows(rows: Array) -> VBoxContainer:
	var root := VBoxContainer.new()
	for row in rows:
		root.add_child(row)
	return root

func _inventory_model() -> Dictionary:
	return {
		"filter_kind": "all",
		"capacity": {"used": 5, "total": 24},
		"selected_slot_index": 3,
		"available_filters": ["all", "재료"],
		"slots": [
			{"slot_index": 0, "empty": false, "selected": false, "item_id": "wood", "name": "나무", "kind": "재료", "quantity": 2, "stack_label": "2/20", "description": "두꺼운 나무", "can_use": true, "can_equip": true},
			{"slot_index": 1, "empty": true, "selected": false, "item_id": "", "name": "", "kind": "", "quantity": 0},
			{"slot_index": 3, "empty": false, "selected": true, "item_id": "wood", "name": "나무", "kind": "재료", "quantity": 3, "stack_label": "3/20", "description": "두꺼운 나무", "can_use": true, "can_equip": true}
		]
	}

func _tea_model(can_brew: bool) -> Dictionary:
	return {
		"has_brewing_location": false,
		"can_brew": can_brew,
		"selected_leaf_id": "leaf",
		"selected_vessel_key": "vessel:1",
		"selected_slot_index": 0,
		"leaves": [{"id": "leaf", "name": "찻잎", "quantity": 2}],
		"vessels": [{"id": "kettle", "selection_key": "vessel:1", "name": "철솥"}],
		"quickslots": [{"slot_index": 0, "label": "1번 찻잔"}],
		"preview": {"ok": false, "reason": "missing_brewing_location"}
	}

func _meta_model() -> Dictionary:
	return {
		"selected_tab": "teas",
		"available_tabs": ["teas", "memories"],
		"counts": {"discovered_records": 1, "endings": 0},
		"rows": [{"id": "tea_1", "name": "차 기록", "summary": "첫 잔", "selected": true}],
		"detail": {"id": "tea_1", "masked": true}
	}

func _crafting_model() -> Dictionary:
	var row := {
		"recipe_id": "wooden_workbench",
		"name": "목재 작업대 제작",
		"category": "도구",
		"selected": true,
		"craftable": true,
		"reason": "",
		"reason_label": "제작 가능",
		"result": {"item_id": "wooden_workbench", "name": "목재 작업대", "quantity": 1, "description": "기초 제작대"},
		"materials": [{"item_id": "wood", "name": "목재", "available": 2, "required": 2}],
		"facilities": [],
		"unlock_biome_name": "일반 지역"
	}
	return {
		"ok": true,
		"selected_recipe_id": "wooden_workbench",
		"categories": ["all", "도구"],
		"rows": [row, row.merged({"recipe_id": "stone_axe", "selected": false, "craftable": false, "reason": "missing_materials"}, true)],
		"detail": row,
		"counts": {"total": 2, "visible": 2, "craftable": 1}
	}

func _record_command(command) -> void:
	emitted_commands.append(command)

func _record_popup(title: String, content: Control) -> void:
	shown_popups.append({"title": title, "content": content})

func _record_crafting_popup(recipe_id: String) -> void:
	shown_popups.append(recipe_id)

func _record_refresh() -> void:
	refresh_count += 1

func _record_filter(value: String) -> void:
	filters.append(value)

func _record_selected_recipe_id(value: String) -> void:
	selected_recipe_ids.append(value)

func _reset_spies() -> void:
	emitted_commands.clear()
	shown_popups.clear()
	refresh_count = 0
	selected_recipe_ids.clear()
	filters.clear()

func _inventory_item_icon_reference(row: Dictionary) -> String:
	return String(row.get("icon_reference", ""))

func _inventory_item_icon(_row: Dictionary) -> Texture2D:
	return null

func _crafting_result_icon_reference(row: Dictionary) -> String:
	return String(_dictionary_value(row.get("result", {})).get("icon_reference", ""))

func _item_icon_reference(_item_id: String, _kind: String, _definition: Dictionary) -> String:
	return ""

func _null_texture(_reference: String) -> Texture2D:
	return null

func _tree_has_text(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Label and text in node.text:
		return true
	if node is Button and text in node.text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and text in node.text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _find_button_by_name(node: Node, button_name: String) -> Button:
	if node == null:
		return null
	if node is Button and node.name == button_name:
		return node
	for child in node.get_children():
		var found := _find_button_by_name(child, button_name)
		if found != null:
			return found
	return null

func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
