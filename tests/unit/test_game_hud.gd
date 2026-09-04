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
		if item_id == "bandage":
			return {"id": item_id, "type": "소모품", "icon_asset_id": "asset_assets_ui_icons_atlas_gourd_png"}
		if item_id == "wooden_workbench":
			return {"id": item_id, "type": "도구", "icon_asset_id": "asset_assets_sprites_objects_crafting_workbench_32x32_png"}
		return {"id": item_id, "type": "재료", "icon_asset_id": "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png"}

	func get_total_quantity(item_id: String) -> int:
		var total := 0
		for slot in slots:
			if typeof(slot) == TYPE_DICTIONARY and String(slot.get("item_id", "")) == item_id:
				total += int(slot.get("quantity", 0))
		return total

class FakeInventoryCommandRuntime:
	signal read_model_changed(read_model: Dictionary)

	var equipment := {
		"weapon": {
			"slot": "weapon",
			"item_id": "mountain_iron_dagger",
			"instance_id": "weapon-1",
			"definition": {"id": "mountain_iron_dagger", "name": "산철 단검", "type": "무기"}
		},
		"armor": {
			"slot": "armor",
			"item_id": "traveler_quilted_clothes",
			"instance_id": "armor-1",
			"definition": {"id": "traveler_quilted_clothes", "name": "나그네 누비옷", "type": "방어구"}
		},
		"tea_ware": {
			"slot": "tea_ware",
			"item_id": "humble_clay_bowl",
			"instance_id": "tea-ware-1",
			"definition": {"id": "humble_clay_bowl", "name": "소박한 흙찻잔", "type": "다구"}
		}
	}

	func set_equipment_slot(slot_key: String, payload: Dictionary) -> void:
		equipment[slot_key] = payload.duplicate(true)
		read_model_changed.emit(read_model())

	func read_model() -> Dictionary:
		return {
			"schema_version": 1,
			"data_version": "hud-fixture",
			"read_only": true,
			"filter_kind": "all",
			"sort_mode": "kind_name",
			"selected_slot_index": 0,
			"capacity": {"used": 3, "total": 14, "empty": 11, "full": false},
			"available_filters": ["all", "재료", "소모품"],
			"equipment": equipment.duplicate(true),
			"slots": [
				{"slot_index": 0, "empty": false, "selected": true, "item_id": "wood", "name": "wood", "kind": "재료", "quantity": 3, "max_stack": 20, "stack_label": "3/20", "can_use": false, "can_equip": false, "label": "01 wood x3 (3/20)", "commands": {}},
				{"slot_index": 1, "empty": true, "selected": false, "item_id": "", "name": "", "kind": "", "quantity": 0, "max_stack": 0, "stack_label": "0/0", "can_use": false, "can_equip": false, "label": "02 빈 슬롯", "commands": {}},
				{"slot_index": 2, "empty": false, "selected": false, "item_id": "bandage", "name": "bandage", "kind": "소모품", "quantity": 1, "max_stack": 5, "stack_label": "1/5", "can_use": true, "can_equip": false, "label": "03 bandage x1 (1/5)", "commands": {}},
				{"slot_index": 3, "empty": false, "selected": false, "item_id": "wood", "name": "wood", "kind": "재료", "quantity": 7, "max_stack": 20, "stack_label": "7/20", "can_use": false, "can_equip": false, "label": "04 wood x7 (7/20)", "commands": {}}
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

class FakeCombatant:
	var definition_id := "road_bandit"
	var hp := 70
	var hp_max := 70
	var attack := 9

class FakeCombatTarget:
	signal damaged(event: Dictionary, applied_damage: int)
	signal defeated()

	var monster_id := "road_bandit"
	var combatant := FakeCombatant.new()

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

	func read_model(inventory, context := {}, options := {}) -> Dictionary:
		var availability := can_craft("wooden_workbench", inventory, context)
		var row := {
			"recipe_id": "wooden_workbench",
			"name": "목재 작업대 제작",
			"category": "도구",
			"selected": true,
			"craftable": bool(availability.craftable),
			"reason": String(availability.get("reason", "")),
			"reason_label": "제작 가능" if bool(availability.craftable) else "재료 부족",
			"result": {"item_id": "wooden_workbench", "name": "목재 작업대", "quantity": 1, "icon_asset_id": "asset_assets_sprites_objects_crafting_workbench_32x32_png"},
			"materials": [{"item_id": "wood", "name": "목재", "available": inventory.get_total_quantity("wood"), "required": 2}],
			"facilities": [],
			"unlock_biome_id": "common_region"
		}
		var missing_row := {
			"recipe_id": "stone_axe",
			"name": "돌도끼 제작",
			"category": "도구",
			"selected": false,
			"craftable": false,
			"reason": "missing_materials",
			"reason_label": "재료 부족",
			"result": {"item_id": "stone_axe", "name": "돌도끼", "quantity": 1},
			"materials": [{"item_id": "stone", "name": "돌", "available": 0, "required": 1}],
			"facilities": [],
			"unlock_biome_id": "common_region"
		}
		return {
			"ok": true,
			"selected_filter": String(options.get("category", "all")),
			"selected_recipe_id": "wooden_workbench",
			"categories": ["all", "도구"],
			"rows": [row, missing_row],
			"detail": row,
			"counts": {"total": 2, "visible": 2, "craftable": 1 if bool(availability.craftable) else 0}
		}

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
			"items":
				return [
					{"id": "wood", "name": "나무", "type": "재료"},
					{"id": "wooden_workbench", "name": "목재 작업대", "type": "도구", "icon_asset_id": "asset_assets_sprites_objects_crafting_workbench_32x32_png"},
					{"id": "mountain_iron_dagger", "name": "산철 단검", "type": "무기"},
					{"id": "traveler_quilted_clothes", "name": "나그네 누비옷", "type": "방어구"},
					{"id": "humble_clay_bowl", "name": "소박한 흙찻잔", "type": "다구"},
					{"id": "missing_icon_item", "name": "그림 없는 잎", "type": "재료"}
				]
			"monsters":
				return [{"id": "road_bandit", "name": "노상 도적", "hp": 70, "attack": 9}]
			"biomes":
				return [{"id": "common_region", "name": "일반 지역"}]
			"dungeons":
				return [{"id": "common_region_core_dungeon", "name": "일반 유적"}]
			_:
				return []

	func find_by_id(key: String, id: String) -> Dictionary:
		for definition in get_definitions(key):
			if String(definition.get("id", "")) == id:
				return definition
		return {}

	func find_character_by_id(character_id: String) -> Dictionary:
		if character_id == "CHR-1":
			return {"character_id": "CHR-1", "name": "아버지 — 차를 사랑하는 구미호", "meta_memory": true}
		if character_id == "CHR-5":
			return {"character_id": "CHR-5", "name": "센리큐 — 이름 없는 노다인", "meta_memory": true}
		if character_id == "CHR-8":
			return {"character_id": "CHR-8", "name": "무차우", "meta_memory": false}
		return {}

func run(asserts) -> void:
	_assert_read_model_uses_runtime_and_balance_sources(asserts)
	_assert_inventory_item_icons_use_content_image_map(asserts)
	_assert_crafting_result_icons_use_content_image_map(asserts)
	_assert_equipment_strip_reads_runtime_equipment(asserts)
	_assert_status_resources_use_visual_meters(asserts)
	_assert_resource_details_open_without_emitting_movement(asserts)
	_assert_time_uses_circular_dial(asserts)
	_assert_runtime_signals_refresh_labels(asserts)
	_assert_reconfigure_clears_missing_time_context(asserts)
	_assert_dpad_emits_press_and_release_movement(asserts)
	_assert_mobile_controls_emit_shared_commands(asserts)
	_assert_dodge_control_does_not_use_baked_dash_asset(asserts)
	_assert_fast_menus_show_runtime_read_models(asserts)
	_assert_safe_area_layout_uses_viewport_top(asserts)
	_assert_status_toasts_use_event_models_icons_and_queue_limits(asserts)
	_assert_narrative_dialogue_emits_option_commands(asserts)
	_assert_major_character_portraits_follow_speaker_ids(asserts)

func _assert_inventory_item_icons_use_content_image_map(asserts) -> void:
	var hud := _configured_hud()
	asserts.equal(
		hud._inventory_item_icon_reference({"item_id": "wood", "kind": "재료"}),
		"item_wood_icon",
		"inventory item icons resolve the dedicated content image before generic fallbacks"
	)
	hud.free()

func _assert_crafting_result_icons_use_content_image_map(asserts) -> void:
	var hud := _configured_hud()
	asserts.equal(
		hud._crafting_result_icon_reference({"recipe_id": "stone_axe", "category": "도구", "result": {"item_id": "wooden_workbench", "name": "목재 작업대"}}),
		"item_wooden_workbench_object_64",
		"crafting result icons resolve the dedicated content image before fixture icons"
	)
	hud.free()

func _assert_equipment_strip_reads_runtime_equipment(asserts) -> void:
	var hud := _configured_hud()
	var strip := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/EquipmentStrip") as HBoxContainer
	asserts.true_value(strip != null, "HUD keeps the equipment strip inside the player status panel")
	if strip != null:
		asserts.equal(strip.get_child_count(), 3, "equipment strip always shows weapon, armor, and tea ware slots")
	var read_model: Dictionary = hud.runtime_read_model()
	asserts.equal(read_model.equipment.weapon.item_id, "mountain_iron_dagger", "HUD runtime model reads equipped weapon from inventory runtime")
	var snapshot: Dictionary = hud.equipment_hud_snapshot()
	asserts.equal(snapshot.weapon.item_id, "mountain_iron_dagger", "equipment HUD exposes the equipped weapon item id")
	asserts.equal(snapshot.armor.item_id, "traveler_quilted_clothes", "equipment HUD exposes the equipped armor item id")
	asserts.equal(snapshot.tea_ware.item_id, "humble_clay_bowl", "equipment HUD exposes the equipped tea ware item id")
	asserts.equal(snapshot.weapon.icon_reference, "item_mountain_iron_dagger_icon", "weapon icon uses the dedicated content image map entry")
	asserts.equal(snapshot.armor.icon_reference, "item_traveler_quilted_clothes_icon", "armor icon uses the dedicated content image map entry")
	asserts.equal(snapshot.tea_ware.icon_reference, "item_humble_clay_bowl_icon", "tea ware icon uses the dedicated content image map entry")
	asserts.equal(snapshot.weapon.display_text, "무 산철", "weapon slot keeps a visible slot cue and short item name")
	asserts.equal(snapshot.armor.display_text, "방 나그네", "armor slot keeps a visible slot cue and short item name")
	asserts.equal(snapshot.tea_ware.display_text, "다 소박한", "tea ware slot keeps a visible slot cue and short item name")
	asserts.true_value(bool(snapshot.weapon.icon_has_texture), "equipped weapon slot loads a runtime texture")
	asserts.true_value(String(snapshot.tea_ware.tooltip).contains("소박한 흙찻잔"), "equipment tooltip keeps the full item name")
	var runtime := hud.inventory_command_runtime as FakeInventoryCommandRuntime
	runtime.set_equipment_slot("weapon", {})
	snapshot = hud.equipment_hud_snapshot()
	asserts.equal(snapshot.weapon.item_id, "", "unequip read_model_changed immediately clears the weapon item id")
	asserts.equal(snapshot.weapon.display_text, "무 -", "empty equipment slot renders a visible empty state")
	asserts.false_value(bool(snapshot.weapon.icon_has_texture), "empty equipment slot hides the icon texture")
	hud.free()

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
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionGrid/AttackButton") != null, "HUD shows attack as a primary mobile action")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionGrid/DodgeButton") != null, "HUD shows dodge as a primary mobile action")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionGrid/InventoryButton") != null, "HUD shows inventory as a primary mobile action")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionGrid/CraftingButton") != null, "HUD shows crafting as a primary mobile action")
	var quick_tea := hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/SecondaryActionBar/QuickTeaButton") as Button
	var quick_consumable := hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/SecondaryActionBar/QuickConsumableButton") as Button
	var quick_ability := hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/SecondaryActionBar/QuickAbilityButton") as Button
	asserts.true_value(quick_tea != null, "HUD shows tea as an icon-only secondary quick action")
	asserts.true_value(quick_consumable != null, "HUD shows consumable as an icon-only secondary quick action")
	asserts.true_value(quick_ability != null, "HUD shows ability as an icon-only secondary quick action")
	if quick_tea != null:
		asserts.equal(quick_tea.text, "", "tea secondary quick action does not render explanatory text")
	if quick_consumable != null:
		asserts.equal(quick_consumable.text, "", "consumable secondary quick action does not render explanatory text")
	if quick_ability != null:
		asserts.equal(quick_ability.text, "", "ability secondary quick action does not render explanatory text")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/ActionMenuButton") != null, "HUD opens secondary actions from a hamburger-style button")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/TeaButton3") != null, "HUD creates tea controls from the runtime quickslot count in the secondary action drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/AbilityButton2") != null, "HUD creates ability controls from the balance slot count in the secondary action drawer")
	asserts.false_value((hud.get_node_or_null("Root/ActionMenuPanel") as Control).visible, "HUD keeps secondary actions hidden until the hamburger button is pressed")
	var hamburger := hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/ActionMenuButton") as Button
	if hamburger != null:
		hamburger.pressed.emit()
	asserts.true_value((hud.get_node_or_null("Root/ActionMenuPanel") as Control).visible, "HUD shows the secondary action drawer after pressing the hamburger button")
	asserts.equal((hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll") as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "secondary action scroll consumes touch input instead of moving the player")
	asserts.equal(read_model.time_phase, "night", "HUD reads current time phase")
	asserts.equal(read_model.time_progress_percent, 25, "HUD calculates time progress from the time read model")
	asserts.true_value(hud.get_node_or_null("Root/StatusPanel/StatusBody/PlayerPortrait") != null, "HUD renders the mockup-style player portrait block")
	asserts.equal(read_model.combat_target.name, "노상 도적", "HUD reads combat target names from definition data")
	asserts.true_value(hud.get_node_or_null("Root/EnemyPanel") != null, "HUD renders the mockup-style enemy status panel")
	hud.free()

func _assert_resource_details_open_without_emitting_movement(asserts) -> void:
	var hud := _configured_hud()
	var received_commands: Array = []
	hud.mobile_command_issued.connect(func(command): received_commands.append(command))
	var health_row := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/HealthDisplay") as Control
	var ki_row := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/KiDisplay") as Control
	var detail_panel := hud.get_node_or_null("Root/ResourceDetailPanel") as Control
	var enemy_panel := hud.get_node_or_null("Root/EnemyPanel") as Control
	asserts.true_value(health_row != null and health_row.mouse_filter == Control.MOUSE_FILTER_STOP, "resource row consumes pointer input")
	asserts.true_value(detail_panel != null and not detail_panel.visible, "resource detail starts hidden")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	health_row.gui_input.emit(click)
	asserts.true_value(detail_panel.visible, "clicking a resource opens its detail panel")
	asserts.true_value(_tree_has_text(detail_panel, "자원 상세\n체력 82 / 100\n차기 36 / 60\n정신 7 / 10"), "resource detail shows all exact values together")
	asserts.true_value(detail_panel.position.y + detail_panel.size.y <= enemy_panel.position.y, "open resource detail does not overlap enemy information")
	asserts.equal(received_commands.size(), 0, "resource detail click emits no gameplay command")
	ki_row.gui_input.emit(click)
	asserts.false_value(detail_panel.visible, "clicking the active resource closes its detail panel")
	hud.free()

func _assert_status_resources_use_visual_meters(asserts) -> void:
	var hud := _configured_hud()
	var hearts := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/HealthDisplay/Icons") as HBoxContainer
	asserts.true_value(hearts != null, "HUD renders HP as a heart row")
	if hearts != null:
		asserts.equal(hearts.get_child_count(), 5, "HP uses five heart slots")
		asserts.equal((hearts.get_child(0) as Control).custom_minimum_size, Vector2(14, 14), "resource icons use the compact HUD size")
		asserts.equal((hearts.get_child(0) as TextureRect).expand_mode, TextureRect.EXPAND_IGNORE_SIZE, "resource icons ignore their source texture size")
		asserts.equal((hearts.get_child(0) as TextureRect).get_meta("fill_ratio"), 1.0, "full HP heart is filled")
		asserts.true_value(is_equal_approx(float((hearts.get_child(4) as TextureRect).get_meta("fill_ratio")), 0.1), "partial HP remains visible in the final heart")
	var ki_icons := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/KiDisplay/Icons") as HBoxContainer
	var kokoro_icons := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/KokoroDisplay/Icons") as HBoxContainer
	asserts.true_value(ki_icons != null and ki_icons.get_child_count() == 5, "ki uses five tea cup icons")
	asserts.true_value(kokoro_icons != null and kokoro_icons.get_child_count() == 5, "kokoro uses five tea leaf icons")
	if ki_icons != null:
		asserts.equal((ki_icons.get_child(2) as TextureRect).get_meta("fill_ratio"), 1.0, "ki icon row observes the runtime ratio")
	if kokoro_icons != null:
		asserts.equal((kokoro_icons.get_child(3) as TextureRect).get_meta("fill_ratio"), 0.5, "kokoro icon row observes the runtime ratio")
	hud.free()

func _assert_time_uses_circular_dial(asserts) -> void:
	var hud := _configured_hud()
	var dial := hud.get_node_or_null("Root/MapPanel/MapRows/TimeDialRow/TimeDial") as Control
	asserts.true_value(dial != null, "HUD renders time as a circular dial")
	if dial != null:
		asserts.equal(dial.custom_minimum_size, Vector2(28, 28), "time dial remains compact beside the minimap")
		asserts.equal(dial.get("phase"), "night", "time dial observes the runtime phase")
		asserts.equal(dial.get("progress_percent"), 25, "time dial observes phase progress")
	asserts.true_value(_tree_has_text(hud.get_node("Root/MapPanel/MapRows/TimeDialRow"), "밤"), "time dial keeps a text phase cue")
	asserts.true_value(_tree_has_text(hud.get_node("Root/MapPanel/MapRows/TimeDialRow"), "25%"), "time dial keeps a numeric progress cue")
	hud.free()

func _assert_runtime_signals_refresh_labels(asserts) -> void:
	var hud := _configured_hud()
	var resources = hud.player.resources
	resources.set_hp(61)
	var hp_label := hud.get("_labels").get("hp") as Label
	asserts.equal(hp_label.text, "체력", "resource signals keep the permanent HUD label compact")
	var fourth_heart := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/HealthDisplay/Icons/Icon4") as TextureRect
	asserts.true_value(is_equal_approx(float(fourth_heart.get_meta("fill_ratio")), 0.05), "resource signals refresh partial heart fill")
	hud.time_state.phase = &"dusk"
	hud.time_state.phase_changed.emit(&"night", &"dusk")
	var time_label := hud.get("_labels").get("time_phase") as Label
	asserts.true_value(time_label.text.begins_with("해질녘"), "time phase events refresh the HUD")
	hud.free()


func _assert_reconfigure_clears_missing_time_context(asserts) -> void:
	var hud := _configured_hud()
	var time_label := hud.get("_labels").get("time_phase") as Label
	asserts.true_value(time_label.get_parent().get_parent().visible, "HUD shows time while a runtime time state is supplied")
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {})
	asserts.equal(hud.time_state, null, "HUD clears a stale time observer when the new runtime context omits it")
	asserts.false_value(time_label.get_parent().get_parent().visible, "HUD hides the time row after its runtime time state is removed")
	hud.free()

func _assert_dpad_emits_press_and_release_movement(asserts) -> void:
	var hud := _configured_hud()
	var received: Array[Vector2i] = []
	hud.movement_button_changed.connect(func(direction: Vector2i): received.append(direction))
	var dpad_panel := hud.get_node_or_null("Root/DPadPanel") as Control
	asserts.true_value(dpad_panel != null, "HUD keeps the dpad command surface")
	if dpad_panel != null:
		asserts.true_value(dpad_panel.visible, "HUD displays the compact directional pad")
		asserts.false_value(_panel_uses_dark_background(dpad_panel), "dpad omits the outer dark panel background")
		asserts.equal(dpad_panel.custom_minimum_size, Vector2(72, 72), "dpad provides a compact mobile touch surface")
	var left_button := hud.get_node_or_null("Root/DPadPanel/DPadBoard/DPadLeft") as Button
	asserts.true_value(left_button != null, "HUD owns a left dpad button")
	if left_button != null:
		var press_feedback := left_button.get_node_or_null("PressFeedback") as Control
		asserts.true_value(press_feedback != null and not press_feedback.visible, "dpad direction owns hidden press feedback")
		left_button.button_down.emit()
		asserts.true_value(press_feedback.visible, "dpad direction shows feedback while pressed")
		left_button.button_up.emit()
		asserts.false_value(press_feedback.visible, "dpad direction clears feedback on release")
	asserts.equal(received, [Vector2i.LEFT, Vector2i.ZERO], "dpad press starts movement and release stops it")
	hud.free()

func _assert_mobile_controls_emit_shared_commands(asserts) -> void:
	var hud := _configured_hud()
	var action_panel := hud.get_node_or_null("Root/ActionPanel") as Control
	asserts.true_value(action_panel != null, "HUD keeps the action command surface")
	if action_panel != null:
		asserts.false_value(_panel_uses_dark_background(action_panel), "action controls omit the outer dark panel background")
		asserts.equal(action_panel.custom_minimum_size, Vector2(132, 84), "action controls provide compact mobile touch targets")
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
	asserts.true_value(hud.press_mobile_button("sleep"), "HUD accepts sleep command control")
	asserts.true_value(hud.press_mobile_button("complete_dungeon"), "HUD accepts dungeon command control")
	asserts.false_value(hud.press_mobile_button("repair_teleport"), "HUD removes the fixed teleport repair control")
	asserts.equal(received.size(), 15, "HUD emits exactly one command per valid mobile control")
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
	asserts.equal(received[13].type, GameCommand.Type.SLEEP, "sleep control emits shared sleep command")
	asserts.equal(received[14].type, GameCommand.Type.COMPLETE_DUNGEON, "dungeon control emits shared dungeon command")
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
	var menu_panel := hud.get_node_or_null("Root/MenuPanel") as Control
	asserts.true_value(menu_panel != null, "HUD owns the shared fast menu panel")
	if menu_panel != null:
		asserts.equal(int(round(menu_panel.custom_minimum_size.x)), 560, "fast menu expands to a near-full logical viewport width")
		asserts.equal(int(round(menu_panel.custom_minimum_size.y)), 280, "fast menu expands to a near-full logical viewport height")
		asserts.equal(int(round(menu_panel.anchor_left * 100.0)), 50, "fast menu anchors from the horizontal center")
		asserts.equal(int(round(menu_panel.anchor_top * 100.0)), 50, "fast menu anchors from the vertical center")
		asserts.true_value(_panel_uses_dark_background(menu_panel), "fast menu uses the shared dark HUD panel background")
	asserts.equal((hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll") as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "menu scroll consumes touch input instead of moving the player")
	asserts.true_value(_tree_has_text(hud, "차 & 도구 (인벤토리) · 3/14 · all"), "inventory menu renders the mockup-style inventory header")
	var inventory_toolbar := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/InventoryToolbar")
	asserts.true_value(_tree_has_icon_button_with_text(inventory_toolbar, "정렬"), "inventory toolbar uses icon-backed touch commands")
	var inventory_grid := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/InventorySlotStrip") as GridContainer
	asserts.true_value(inventory_grid != null and inventory_grid.columns == 4, "inventory menu renders a mobile-friendly four-column grid")
	var inventory_card := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/InventorySlotStrip/InventorySlotCard0") as Button
	asserts.true_value(inventory_card != null, "inventory menu renders slot cards")
	asserts.true_value(_button_has_icon(inventory_card), "inventory slot cards render item images")
	if inventory_card != null:
		asserts.equal(inventory_card.custom_minimum_size, Vector2(66, 60), "inventory slot cards keep a stable mobile touch size")
	asserts.true_value(_tree_has_text(hud, "wood\n* 10"), "inventory menu groups duplicate item slots into one total")
	asserts.false_value(_tree_has_text(hud, "wood\n* 7"), "inventory menu does not render duplicate item stacks as separate cards")
	asserts.true_value(_panel_uses_dark_background(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/DetailCard") as Control), "inventory detail card uses the shared dark inner background")
	asserts.true_value(hud.show_facilities_menu(), "HUD opens the facilities menu")
	asserts.true_value(_tree_has_text(hud, "우물 (4,5)"), "facilities menu lists generated facility nodes")
	asserts.true_value(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/FacilityCardStrip") != null, "facilities menu renders facility cards")
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.show_crafting_menu(), "HUD opens the crafting menu")
	asserts.true_value(_tree_has_text(hud, "제작법 2/2 · 가능 1 · 필터 전체"), "crafting menu shows recipe counts and active filter")
	var crafting_filter_bar := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/CraftingFilterBar")
	asserts.true_value(_tree_has_icon_button_with_text(crafting_filter_bar, "전체"), "crafting filters use icon-backed touch commands")
	var crafting_grid := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/CraftingRecipeStrip") as GridContainer
	asserts.true_value(crafting_grid != null and crafting_grid.columns == 3, "crafting menu renders a mobile-friendly three-column grid")
	asserts.true_value(_tree_has_text(hud, "wooden_workbench → 목재 작업대 x1"), "crafting menu shows selected recipe result")
	asserts.true_value(_tree_has_text(hud, "상태 제작 가능"), "crafting menu shows selected recipe status on its own row")
	asserts.true_value(_tree_has_text(hud, "재료 목재 3/2"), "crafting menu shows selected recipe materials on their own row")
	asserts.true_value(_tree_has_text(hud, "시설 손제작"), "crafting menu shows selected recipe facility on its own row")
	asserts.true_value(_tree_has_text(hud, "해금 common_region"), "crafting menu shows selected recipe unlock on its own row")
	asserts.true_value(_tree_has_textured_item_icon(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/CraftingRecipeStrip")), "crafting recipe cards render result item images")
	asserts.true_value(_tree_has_textured_item_icon(crafting_grid), "crafting recipe cards include state/result icons")
	asserts.true_value(_panel_uses_dark_background(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/DetailCard") as Control), "crafting detail card uses the shared dark inner background")
	asserts.true_value(_crafting_recipe_cards_have_distinct_state_styles(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/CraftingRecipeStrip")), "crafting cards visibly separate craftable and missing-material states")
	var craft_button := _first_enabled_button_with_text(hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent"), "제작")
	if craft_button != null:
		craft_button.pressed.emit()
	asserts.equal(received.size(), 1, "crafting button emits one command")
	if not received.is_empty():
		asserts.equal(received[0].type, GameCommand.Type.CRAFT_RECIPE, "crafting button emits the shared craft command")
		asserts.equal(received[0].payload.get("recipe_id", ""), "wooden_workbench", "crafting command preserves the stable recipe id")
	hud.free()

func _assert_safe_area_layout_uses_viewport_top(asserts) -> void:
	var hud := _configured_hud()
	var status_panel := hud.get_node_or_null("Root/StatusPanel") as Control
	var quickslot_panel := hud.get_node_or_null("Root/QuickSlotPanel") as Control
	asserts.true_value(status_panel != null, "HUD status panel exists for safe-area layout")
	asserts.true_value(quickslot_panel != null, "HUD quickslot panel exists for safe-area layout")
	if status_panel != null:
		asserts.equal(int(round(status_panel.position.y)), 12, "status panel anchors to the viewport top margin")
	if quickslot_panel != null:
		asserts.equal(int(round(quickslot_panel.position.y)), 12, "quickslot panel anchors to the viewport top margin")
	hud.free()

func _assert_status_toasts_use_event_models_icons_and_queue_limits(asserts) -> void:
	var hud := _configured_hud()
	asserts.false_value(hud.show_status_event({"type": "item_acquired", "ok": false, "item_id": "wood"}), "failed acquisition events do not enqueue a status toast")
	asserts.true_value(hud.show_status_event({"type": "item_acquired", "ok": true, "item_id": "wood", "quantity": 2, "event_id": "pickup-1"}), "successful item acquisition enqueues one toast")
	asserts.false_value(hud.show_status_event({"type": "item_acquired", "ok": true, "item_id": "wood", "quantity": 2, "event_id": "pickup-1"}), "duplicate item events do not enqueue twice")
	var snapshot: Dictionary = hud.status_toast_debug_snapshot()
	asserts.equal(snapshot.label_text, "나무 x2을(를) 얻었다!", "item toast resolves Korean names from stable item id")
	asserts.true_value(bool(snapshot.icon_visible), "item toast shows an icon when the content image map has one")
	asserts.true_value(bool(snapshot.icon_has_texture), "item toast icon loads a runtime texture")
	var label := hud.get_node_or_null("Root/StatusToastPanel/StatusToastRow/StatusToastLabel") as Label
	asserts.true_value(label != null and label.clip_text, "toast label clips long Korean messages instead of overflowing")
	asserts.equal(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "toast label uses ellipsis overflow for narrow viewports")
	asserts.true_value(hud.show_status_event({"type": "craft_completed", "ok": true, "result_item_id": "wooden_workbench", "event_id": "craft-1"}), "successful crafting completion enqueues a toast")
	asserts.true_value(hud.show_status_event({"type": "enemy_defeated", "ok": true, "monster_id": "road_bandit", "event_id": "enemy-1"}), "enemy defeat enqueues a toast")
	asserts.true_value(hud.show_status_event({"type": "dungeon_entered", "ok": true, "dungeon_id": "common_region_core_dungeon", "event_id": "dungeon-enter"}), "dungeon entry enqueues a toast")
	hud._process(1.0)
	asserts.equal(hud.status_toast_debug_snapshot().label_text, "목재 작업대을(를) 제작했다!", "toast queue preserves crafting after acquisition")
	hud._process(1.0)
	asserts.equal(hud.status_toast_debug_snapshot().label_text, "노상 도적을(를) 쓰러뜨렸다!", "toast queue preserves enemy defeat order")
	hud._process(1.0)
	asserts.equal(hud.status_toast_debug_snapshot().label_text, "던전에 들어갔다!", "toast queue preserves dungeon event order")
	asserts.true_value(hud.show_status_event({"type": "item_acquired", "ok": true, "item_id": "missing_icon_item", "event_id": "missing-icon"}), "missing image definitions still enqueue text-only toasts")
	hud._process(1.0)
	snapshot = hud.status_toast_debug_snapshot()
	asserts.equal(snapshot.label_text, "그림 없는 잎을(를) 얻었다!", "missing image fallback keeps readable text")
	asserts.false_value(bool(snapshot.icon_visible), "missing image fallback hides the icon instead of showing a broken texture")
	for index in range(6):
		asserts.true_value(hud.show_status_event({"type": "map_transition", "ok": true, "biome_id": "common_region", "event_id": "map-%d" % index}), "map transition enqueues while respecting queue cap")
	snapshot = hud.status_toast_debug_snapshot()
	asserts.equal((snapshot.queue as Array).size(), 3, "toast queue caps pending items behind the active toast")
	var toast_panel := hud.get_node_or_null("Root/StatusToastPanel") as Control
	asserts.true_value(toast_panel != null and toast_panel.position.y > (hud.get_node("Root/StatusPanel") as Control).position.y, "toast remains below the safe-area top HUD stack")
	hud.free()

func _assert_narrative_dialogue_emits_option_commands(asserts) -> void:
	var hud := _configured_hud()
	var received: Array = []
	hud.mobile_command_issued.connect(func(command):
		received.append(command)
		hud.show_narrative_dialogue({
			"event_id": "first_run_prologue",
			"node_id": "muchau_question",
			"speaker_id": "CHR-8",
			"text": "바다를 건너야 하나요?",
			"options": [{"id": "cross_sea", "display_text": "찻잔을 챙긴다"}]
		})
	)
	asserts.true_value(hud.show_narrative_dialogue({
		"event_id": "first_run_prologue",
		"node_id": "father_farewell",
		"speaker_id": "CHR-1",
		"text": "물이 끓기 전에 서두르지 마라.",
		"options": [{"id": "accept_farewell", "display_text": "고개를 끄덕인다"}]
	}), "HUD shows narrative dialogue read models")
	asserts.true_value(hud.narrative_dialogue_visible(), "HUD reports the narrative panel as visible")
	asserts.true_value(_tree_has_text(hud, "아버지 — 차를 사랑하는 구미호"), "HUD resolves narrative speaker names from character data")
	asserts.true_value(_tree_has_text(hud, "물이 끓기 전에 서두르지 마라."), "HUD renders narrative dialogue text")
	asserts.true_value(_texture_rect_has_texture(hud.get_node_or_null("Root/NarrativeOverlay/NarrativeBackground")), "prologue dialogue renders its scene background")
	asserts.true_value(_tree_uses_texture(hud.get_node_or_null("Root/NarrativeOverlay/LeftPortrait"), "chr_1_kitsune_father_96x96.png"), "prologue dialogue renders the father portrait")
	asserts.true_value(_tree_uses_texture(hud.get_node_or_null("Root/NarrativeOverlay/RightPortrait"), "chr_8_muchau_96x96.png"), "prologue dialogue renders Muchau as the conversation partner")
	asserts.false_value((hud.get_node_or_null("Root/StatusPanel") as Control).visible, "prologue hides the normal status HUD")
	asserts.false_value((hud.get_node_or_null("Root/MapPanel") as Control).visible, "prologue hides the normal map HUD")
	asserts.false_value((hud.get_node_or_null("Root/QuickSlotPanel") as Control).visible, "prologue hides the normal quickslot HUD")
	asserts.false_value((hud.get_node_or_null("Root/ActionPanel") as Control).visible, "prologue hides the normal action HUD")
	asserts.false_value((hud.get_node_or_null("Root/EnemyPanel") as Control).visible, "prologue hides the normal enemy HUD")
	asserts.false_value(_tree_has_text(hud.get_node_or_null("Root/NarrativeOverlay/NarrativePanel/NarrativeRows/NarrativeOptions"), "고개를 끄덕인다"), "prologue does not show choice prose as button text")
	var button := _first_enabled_button_with_text(hud.get_node_or_null("Root/NarrativeOverlay/NarrativePanel/NarrativeRows/NarrativeOptions"), "넘어가기")
	if button != null:
		button.pressed.emit()
	asserts.equal(received.size(), 1, "narrative option emits one command")
	if not received.is_empty():
		asserts.equal(received[0].type, GameCommand.Type.NARRATIVE_SELECT_OPTION, "narrative option emits the shared narrative select command")
		asserts.equal(received[0].payload.get("event_id", ""), "first_run_prologue", "narrative command carries the event id")
		asserts.equal(received[0].payload.get("node_id", ""), "father_farewell", "narrative command carries the node id")
		asserts.equal(received[0].payload.get("option_id", ""), "accept_farewell", "narrative command carries the option id")
	asserts.true_value(hud.hide_narrative_dialogue(), "HUD hides narrative dialogue on request")
	asserts.false_value(hud.narrative_dialogue_visible(), "HUD reports hidden narrative panel")
	asserts.true_value((hud.get_node_or_null("Root/StatusPanel") as Control).visible, "normal status HUD is restored after prologue")
	asserts.false_value((hud.get_node_or_null("Root/MenuPanel") as Control).visible, "prologue restore does not reopen a hidden fast menu")
	hud.free()

func _assert_major_character_portraits_follow_speaker_ids(asserts) -> void:
	var expected := {
		"CHR-2": "chr_2_wasteland_daimyo_96x96.png",
		"CHR-3": "chr_3_furuta_oribe_96x96.png",
		"CHR-4": "chr_4_snow_monk_96x96.png",
		"CHR-5": "chr_5_sen_rikyu_96x96.png",
		"CHR-6": "chr_6_yokai_tea_master_96x96.png",
		"CHR-7": "chr_7_mountain_potter_96x96.png",
		"CHR-8": "chr_8_muchau_96x96.png",
		"CHR-9": "chr_9_wandering_tea_merchant_96x96.png",
	}
	for speaker_id in expected.keys():
		var hud := _configured_hud()
		asserts.true_value(hud.show_narrative_dialogue({
			"event_id": "repeat_dialogue_check",
			"node_id": "speaker_portrait",
			"speaker_id": speaker_id,
			"text": "초상화 연결 확인",
			"options": [{"id": "continue", "display_text": "계속"}]
		}), "%s narrative dialogue opens" % speaker_id)
		asserts.true_value(_tree_uses_texture(hud.get_node_or_null("Root/NarrativeOverlay/LeftPortrait"), String(expected[speaker_id])), "%s uses the mapped portrait" % speaker_id)
		asserts.false_value((hud.get_node_or_null("Root/NarrativeOverlay/RightPortrait") as Control).visible, "%s non-prologue dialogue keeps the partner portrait hidden" % speaker_id)
		hud.free()
	var fallback_hud := _configured_hud()
	asserts.true_value(fallback_hud.show_narrative_dialogue({
		"event_id": "repeat_dialogue_check",
		"node_id": "unknown_speaker",
		"speaker_id": "CHR-UNKNOWN",
		"text": "알 수 없는 화자",
		"options": []
	}), "unknown speaker dialogue still opens")
	asserts.false_value((fallback_hud.get_node_or_null("Root/NarrativeOverlay/LeftPortrait") as Control).visible, "unknown speaker hides the missing portrait instead of showing a broken texture")
	fallback_hud.free()

func _configured_hud() -> GameHud:
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {
		"biome_id": "common_region",
		"facility_nodes": [{"id": "facility_0", "facility_term": "우물", "position": {"x": 4, "y": 5}}]
	}, {"counts": {}}, {
		"catalog": FakeCatalog.new(),
		"inventory": FakeInventory.new(),
		"inventory_command_runtime": FakeInventoryCommandRuntime.new(),
		"combat_target": FakeCombatTarget.new(),
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

func _texture_rect_has_texture(node: Node) -> bool:
	return node is TextureRect and (node as TextureRect).texture != null

func _panel_uses_dark_background(panel: Control) -> bool:
	if panel == null:
		return false
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return false
	return style.bg_color.r < 0.12 and style.bg_color.g < 0.12 and style.bg_color.b < 0.12 and style.bg_color.a >= 0.80

func _button_has_icon(node: Node) -> bool:
	return node is Button and (node as Button).icon != null

func _tree_has_icon_button_with_text(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Button and (node as Button).icon != null and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _tree_has_icon_button_with_text(child, text):
			return true
	return false

func _tree_has_textured_item_icon(node: Node) -> bool:
	if node == null:
		return false
	if node is TextureRect and node.name == "ItemIcon" and (node as TextureRect).texture != null:
		return true
	for child in node.get_children():
		if _tree_has_textured_item_icon(child):
			return true
	return false

func _crafting_recipe_cards_have_distinct_state_styles(node: Node) -> bool:
	if node == null:
		return false
	var border_colors := {}
	for child in node.get_children():
		var panel := child as PanelContainer
		if panel == null:
			continue
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		border_colors["%.3f,%.3f,%.3f" % [style.border_color.r, style.border_color.g, style.border_color.b]] = true
	return border_colors.size() >= 2

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

func _first_enabled_button_with_text(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and not (node as Button).disabled and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _first_enabled_button_with_text(child, text)
		if found != null:
			return found
	return null
