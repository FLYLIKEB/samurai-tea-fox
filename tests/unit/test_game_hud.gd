extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

class FakeResources:
	signal hp_changed(previous: int, current: int, maximum: int)
	signal ki_changed(previous: int, current: int, maximum: int)
	signal kokoro_changed(previous: int, current: int, maximum: int)

	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

	func heal_hp(_amount: int) -> int:
		return 0

	func set_hp(value: int) -> void:
		var previous := hp
		hp = value
		hp_changed.emit(previous, hp, hp_max)

class FakePlayer:
	var resources := FakeResources.new()

class FakeInventory:
	signal changed(snapshot: Dictionary)

	var slot_count := 14
	var slots := [
		{"item_id": "wood", "quantity": 3},
		{},
		{"item_id": "bandage", "quantity": 1}
	]

	func definition_for(item_id: String) -> Dictionary:
		return {"id": item_id, "type": "소모품"} if item_id == "bandage" else {"id": item_id, "type": "재료"}

	func get_total_quantity(item_id: String) -> int:
		var total := 0
		for slot in slots:
			if typeof(slot) == TYPE_DICTIONARY and String(slot.get("item_id", "")) == item_id:
				total += int(slot.get("quantity", 0))
		return total

class FakeInventoryCommandRuntime:
	signal read_model_changed(read_model: Dictionary)

	func read_model() -> Dictionary:
		return {
			"schema_version": 1,
			"data_version": "hud-fixture",
			"read_only": true,
			"filter_kind": "all",
			"sort_mode": "kind_name",
			"selected_slot_index": 0,
			"capacity": {"used": 2, "total": 14, "empty": 12, "full": false},
			"available_filters": ["all", "재료", "소모품"],
			"equipment": {},
			"slots": [
				{"slot_index": 0, "empty": false, "selected": true, "item_id": "wood", "name": "wood", "kind": "재료", "quantity": 3, "max_stack": 20, "stack_label": "3/20", "can_use": false, "can_equip": false, "label": "01 wood x3 (3/20)", "commands": {}},
				{"slot_index": 1, "empty": true, "selected": false, "item_id": "", "name": "", "kind": "", "quantity": 0, "max_stack": 0, "stack_label": "0/0", "can_use": false, "can_equip": false, "label": "02 빈 슬롯", "commands": {}},
				{"slot_index": 2, "empty": false, "selected": false, "item_id": "bandage", "name": "bandage", "kind": "소모품", "quantity": 1, "max_stack": 5, "stack_label": "1/5", "can_use": true, "can_equip": false, "label": "03 bandage x1 (1/5)", "commands": {}}
			]
		}

class FakeTeaService:
	signal changed(snapshot: Dictionary)

	var quickslot_count := 3
	var quick_slots := [
		{"tea_id": "green_tea", "remaining_uses": 1},
		{},
		{}
	]

class FakeCraftingService:
	var recipe_definitions := {
		"wooden_workbench": {
			"id": "wooden_workbench",
			"name": "목재 작업대 제작",
			"materials": [{"item_id": "wood", "quantity": 2}],
			"facility_item_ids": [],
			"result_item_id": "wooden_workbench",
			"result_quantity": 1
		}
	}

	func recipe_for(recipe_id: String) -> Dictionary:
		return recipe_definitions.get(recipe_id, {}).duplicate(true)

	func can_craft(recipe_id: String, inventory, _context := {}) -> Dictionary:
		if recipe_id == "wooden_workbench" and inventory.get_total_quantity("wood") >= 2:
			return {"ok": true, "craftable": true}
		return {"ok": false, "craftable": false, "reason": "missing_materials"}

class FakeTimeConfig:
	func phase_duration_seconds(_phase: StringName) -> float:
		return 120.0

class FakeTimeState:
	signal phase_changed(previous: StringName, current: StringName)

	var phase: StringName = &"night"
	var phase_elapsed_seconds := 30.0
	var config := FakeTimeConfig.new()

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		match key:
			"balance":
				return [{"id": "ability_equip_slots", "value": 2}]
			"recipes":
				return [
					{"id": "bandage", "status": "테스트"},
					{"id": "iron_kettle", "status": "초안"}
				]
			_:
				return []

	func find_by_id(key: String, id: String) -> Dictionary:
		for definition in get_definitions(key):
			if String(definition.get("id", "")) == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_read_model_uses_runtime_and_balance_sources(asserts)
	_assert_runtime_signals_refresh_labels(asserts)
	_assert_reconfigure_clears_missing_time_context(asserts)
	_assert_dpad_emits_press_and_release_movement(asserts)
	_assert_mobile_controls_emit_shared_commands(asserts)
	_assert_dodge_control_does_not_use_baked_dash_asset(asserts)
	_assert_fast_menus_show_runtime_read_models(asserts)

func _assert_read_model_uses_runtime_and_balance_sources(asserts) -> void:
	var hud := _configured_hud()
	var read_model: Dictionary = hud.runtime_read_model()
	asserts.equal(read_model.hp, 82, "HUD reads HP from player resources")
	asserts.equal(read_model.ki, 36, "HUD reads ki from player resources")
	asserts.equal(read_model.kokoro, 7, "HUD reads kokoro from player resources")
	asserts.equal(read_model.inventory_slot_count, 14, "HUD inventory slots come from runtime inventory built from balance")
	asserts.equal(read_model.inventory_used_slots, 2, "HUD observes occupied inventory slots without mutating them")
	asserts.equal(read_model.tea_quickslot_count, 3, "HUD tea quick slots come from runtime tea service")
	asserts.true_value(read_model.consumable_ready, "HUD derives the consumable quickslot from item definition data")
	asserts.equal(read_model.ability_slot_count, 2, "HUD ability slots come from balance definitions")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionGrid/TeaButton3") != null, "HUD creates tea controls from the runtime quickslot count")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionGrid/AbilityButton2") != null, "HUD creates ability controls from the balance slot count")
	asserts.equal(read_model.time_phase, "night", "HUD reads current time phase")
	asserts.equal(read_model.time_progress_percent, 25, "HUD calculates time progress from the time read model")
	hud.free()

func _assert_runtime_signals_refresh_labels(asserts) -> void:
	var hud := _configured_hud()
	var resources = hud.player.resources
	resources.set_hp(61)
	var hp_label := hud.get("_labels").get("hp") as Label
	asserts.equal(hp_label.text, "HP 61 / 100", "resource signals refresh HUD labels without frame polling")
	hud.time_state.phase = &"dusk"
	hud.time_state.phase_changed.emit(&"night", &"dusk")
	var time_label := hud.get("_labels").get("time") as Label
	asserts.true_value(time_label.text.begins_with("해질녘"), "time phase events refresh the HUD")
	hud.free()

func _assert_reconfigure_clears_missing_time_context(asserts) -> void:
	var hud := _configured_hud()
	var time_label := hud.get("_labels").get("time") as Label
	asserts.true_value(time_label.get_parent().visible, "HUD shows time while a runtime time state is supplied")
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {})
	asserts.equal(hud.time_state, null, "HUD clears a stale time observer when the new runtime context omits it")
	asserts.false_value(time_label.get_parent().visible, "HUD hides the time row after its runtime time state is removed")
	hud.free()

func _assert_dpad_emits_press_and_release_movement(asserts) -> void:
	var hud := _configured_hud()
	var received: Array[Vector2i] = []
	hud.movement_button_changed.connect(func(direction: Vector2i): received.append(direction))
	var left_button := hud.get_node_or_null("Root/DPadPanel/DPadBoard/DPadLeft") as Button
	asserts.true_value(left_button != null, "HUD owns a left dpad button")
	if left_button != null:
		left_button.button_down.emit()
		left_button.button_up.emit()
	asserts.equal(received, [Vector2i.LEFT, Vector2i.ZERO], "dpad press starts movement and release stops it")
	hud.free()

func _assert_mobile_controls_emit_shared_commands(asserts) -> void:
	var hud := _configured_hud()
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.press_mobile_button("move", Vector2i.LEFT), "HUD accepts mobile movement control")
	asserts.true_value(hud.press_mobile_button("attack", Vector2i.RIGHT), "HUD accepts mobile attack control")
	asserts.true_value(hud.press_mobile_button("dodge", Vector2i.LEFT), "HUD accepts mobile dodge control")
	asserts.true_value(hud.press_mobile_button("drink_tea", Vector2i.ZERO, 1), "HUD accepts mobile tea control")
	asserts.true_value(hud.press_mobile_button("use_consumable", Vector2i.ZERO, 0), "HUD accepts mobile consumable control")
	asserts.true_value(hud.press_mobile_button("cast_ability", Vector2i.UP, 0), "HUD accepts mobile ability control")
	asserts.true_value(hud.press_mobile_button("cast_ability", Vector2i.UP, 1), "HUD accepts the second mobile ability slot")
	asserts.true_value(hud.press_mobile_button("open_inventory"), "HUD accepts inventory command control")
	asserts.true_value(hud.press_mobile_button("open_tea_brewing"), "HUD accepts tea brewing command control")
	asserts.true_value(hud.press_mobile_button("open_meta_codex"), "HUD accepts meta codex command control")
	asserts.true_value(hud.press_mobile_button("open_crafting"), "HUD accepts crafting command control")
	asserts.true_value(hud.press_mobile_button("open_facilities"), "HUD accepts facilities command control")
	asserts.true_value(hud.press_mobile_button("open_map"), "HUD accepts map command control")
	asserts.equal(received.size(), 13, "HUD emits exactly one command per valid mobile control")
	asserts.equal(received[0].type, GameCommand.Type.MOVE, "movement control emits shared move command")
	asserts.equal(received[1].type, GameCommand.Type.ATTACK, "attack control emits shared attack command")
	asserts.equal(received[2].type, GameCommand.Type.DODGE, "dodge control emits shared dodge command")
	asserts.equal(received[3].type, GameCommand.Type.DRINK_TEA, "tea control emits shared tea command")
	asserts.equal(received[4].type, GameCommand.Type.USE_CONSUMABLE, "consumable control emits shared consumable command")
	asserts.equal(received[5].type, GameCommand.Type.CAST_ABILITY, "ability control emits shared ability command")
	asserts.equal(received[6].type, GameCommand.Type.CAST_ABILITY, "second ability control emits shared ability command")
	asserts.equal(received[6].slot, 1, "second ability control preserves its stable slot index")
	asserts.equal(received[7].type, GameCommand.Type.OPEN_INVENTORY, "inventory control emits shared inventory command")
	asserts.equal(received[8].type, GameCommand.Type.OPEN_TEA_BREWING, "tea brewing control emits shared brewing menu command")
	asserts.equal(received[9].type, GameCommand.Type.OPEN_META_CODEX, "meta codex control emits shared codex menu command")
	asserts.equal(received[10].type, GameCommand.Type.OPEN_CRAFTING, "crafting control emits shared crafting menu command")
	asserts.equal(received[11].type, GameCommand.Type.OPEN_FACILITIES, "facilities control emits shared facilities menu command")
	asserts.equal(received[12].type, GameCommand.Type.OPEN_MAP, "map control emits shared map menu command")
	var untouched_hud := _configured_hud()
	asserts.equal(untouched_hud.player.resources.hp, 82, "HUD button emission does not mutate player resources")
	untouched_hud.free()
	hud.free()

func _assert_dodge_control_does_not_use_baked_dash_asset(asserts) -> void:
	var hud := _configured_hud()
	var root := hud.get_node_or_null("Root")
	asserts.true_value(root != null, "HUD root is built")
	asserts.false_value(_tree_uses_texture(root, "dash_button.png"), "HUD does not use baked dash text asset")
	asserts.true_value(_tree_has_text(root, "회피"), "HUD renders official dodge term as font text")
	hud.free()

func _assert_fast_menus_show_runtime_read_models(asserts) -> void:
	var hud := _configured_hud()
	asserts.true_value(hud.show_inventory_menu(), "HUD opens the inventory menu")
	asserts.true_value(_tree_has_text(hud, "▶ 01 wood x3 (3/20)"), "inventory menu lists occupied runtime slots")
	asserts.true_value(hud.show_facilities_menu(), "HUD opens the facilities menu")
	asserts.true_value(_tree_has_text(hud, "우물 (4,5)"), "facilities menu lists generated facility nodes")
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.show_crafting_menu(), "HUD opens the crafting menu")
	asserts.true_value(_tree_has_text(hud, "제작"), "crafting menu exposes craft buttons")
	var craft_button := _first_enabled_button(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuContent"))
	if craft_button != null:
		craft_button.pressed.emit()
	asserts.equal(received.size(), 1, "crafting button emits one command")
	if not received.is_empty():
		asserts.equal(received[0].type, GameCommand.Type.CRAFT_RECIPE, "crafting button emits the shared craft command")
		asserts.equal(received[0].payload.get("recipe_id", ""), "wooden_workbench", "crafting command preserves the stable recipe id")
	hud.free()

func _configured_hud() -> GameHud:
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {
		"biome_id": "common_region",
		"facility_nodes": [{"id": "facility_0", "facility_term": "우물", "position": {"x": 4, "y": 5}}]
	}, {"counts": {}}, {
		"catalog": FakeCatalog.new(),
		"inventory": FakeInventory.new(),
		"inventory_command_runtime": FakeInventoryCommandRuntime.new(),
		"tea_service": FakeTeaService.new(),
		"crafting_service": FakeCraftingService.new(),
		"crafting_context": {"unlocked_biome_ids": ["common_region"]},
		"time_state": FakeTimeState.new()
	})
	return hud

func _tree_uses_texture(node: Node, needle: String) -> bool:
	var texture = null
	if node is TextureRect:
		texture = (node as TextureRect).texture
	elif node is TextureButton:
		texture = (node as TextureButton).texture_normal
	if texture != null and String(texture.resource_path).contains(needle):
		return true
	for child in node.get_children():
		if _tree_uses_texture(child, needle):
			return true
	return false

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

func _first_enabled_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button and not (node as Button).disabled:
		return node as Button
	for child in node.get_children():
		var found := _first_enabled_button(child)
		if found != null:
			return found
	return null
