extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	_assert_read_model_filter_sort_and_capacity(asserts)
	_assert_common_commands_select_use_and_equip(asserts)
	_assert_can_use_matches_actual_item_capability(asserts)
	_assert_main_routes_inventory_commands_and_saves_equipment(asserts)
	_assert_hud_inventory_menu_uses_command_read_model(asserts)
	_assert_project_input_map_exposes_inventory_keyboard_actions(asserts)

func _assert_read_model_filter_sort_and_capacity(asserts) -> void:
	var fixture := _fixture_runtime()
	var runtime: InventoryCommandRuntime = fixture[0]
	var model: Dictionary = runtime.read_model()
	asserts.equal(model.capacity.total, 24, "read model exposes total slot capacity")
	asserts.equal(model.capacity.used, 6, "read model exposes used slots")
	asserts.true_value(model.available_filters.has("소모품"), "read model exposes kind filters")
	asserts.true_value(model.available_filters.has("무기"), "read model exposes equipment filters")
	asserts.true_value(model.slots[0].has("stack_label"), "read model exposes stack labels")
	asserts.true_value(model.slots[0].commands.has("select"), "read model exposes stable selection command descriptors")

	var filtered: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, {"kind": "소모품"}))
	asserts.true_value(filtered.ok, "kind filter command succeeds")
	asserts.equal(filtered.read_model.slots.size(), 1, "kind filter limits the read model")
	asserts.equal(filtered.read_model.slots[0].item_id, "bandage", "filter keeps matching consumable")

	asserts.true_value(runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, {"kind": "all"})).ok, "all filter restores every slot")
	asserts.true_value(runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SORT)).ok, "sort command succeeds")
	asserts.equal(runtime.read_model().capacity.used, 6, "sort preserves occupied slot count")

func _assert_common_commands_select_use_and_equip(asserts) -> void:
	var fixture := _fixture_runtime()
	var runtime: InventoryCommandRuntime = fixture[0]
	var consumable: ConsumableService = fixture[3]
	var desktop := DesktopCommandAdapter.new()
	var mobile := MobileCommandAdapter.new()
	asserts.equal(desktop.command_for_action("inventory_sort").type, mobile.command_for_button("inventory_sort").type, "desktop and mobile share inventory sort command")
	asserts.equal(desktop.command_for_action("inventory_select", Vector2i.ZERO, 2).type, mobile.command_for_button("inventory_select", Vector2i.ZERO, 2).type, "desktop and mobile share inventory select command")
	asserts.equal(mobile.command_for_button("equip_inventory_slot", Vector2i.ZERO, 1).type, GameCommand.Type.EQUIP_INVENTORY_SLOT, "mobile equip emits shared inventory command")
	asserts.equal(desktop.command_for_action("use_inventory_slot", Vector2i.ZERO, 0).type, GameCommand.Type.USE_INVENTORY_SLOT, "desktop use emits shared inventory command")

	asserts.true_value(runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, 2, {"slot_index": 2})).ok, "select slot command succeeds")
	asserts.equal(runtime.read_model().selected_slot_index, 2, "selection is reflected in read model")
	asserts.true_value(runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.RIGHT)).ok, "keyboard/mobile navigation command succeeds")
	asserts.equal(runtime.read_model().selected_slot_index, 3, "navigation advances selected slot")

	var use_result: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, 0, {"slot_index": 0}))
	asserts.true_value(use_result.ok, "use command exposes consumable use intent through inventory command runtime")
	asserts.equal(use_result.use_intent.item_id, "bandage", "use command targets selected consumable item")
	asserts.equal(consumable.to_snapshot().active_action, {}, "inventory runtime leaves consumable lifecycle ownership to Main")

	var equip_result: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, 1, {"slot_index": 1}))
	asserts.true_value(equip_result.ok, "equip command equips an inventory slot")
	asserts.equal(equip_result.slot, EquipmentModel.SLOT_WEAPON, "weapon lands in the weapon equipment slot")
	asserts.equal(fixture[2].get_equipped_slot(EquipmentModel.SLOT_WEAPON).item_id, "short_travel_sword", "equipment model owns equipped weapon after command")

func _assert_can_use_matches_actual_item_capability(asserts) -> void:
	var fixture := _fixture_runtime()
	var runtime: InventoryCommandRuntime = fixture[0]
	var inventory: InventoryModel = fixture[1]
	var equipment: EquipmentModel = fixture[2]
	var consumable: ConsumableService = fixture[3]
	var leaf_row := _row_for_item(runtime, "father_spring_pan_fired_tea")
	var consumable_row := _row_for_item(runtime, "bandage")
	var equipment_row := _row_for_item(runtime, "short_travel_sword")

	asserts.false_value(leaf_row.is_empty(), "fixture contains a tea leaf row")
	asserts.false_value(bool(leaf_row.get("can_use", false)), "tea leaves are not direct-use inventory actions")
	asserts.false_value(_commands(leaf_row).has("use"), "tea leaf row omits direct use command")
	asserts.true_value(bool(consumable_row.get("can_use", false)), "valid consumable keeps direct-use capability")
	asserts.true_value(_commands(consumable_row).has("use"), "valid consumable exposes use command")
	asserts.true_value(bool(equipment_row.get("can_use", false)), "equipment keeps inventory use-as-equip capability")
	asserts.true_value(_commands(equipment_row).has("use"), "equipment exposes use command for equip flow")

	var before_inventory: Dictionary = inventory.to_snapshot()
	var before_equipment: Dictionary = equipment.to_snapshot()
	var before_consumable: Dictionary = consumable.to_snapshot()
	var leaf_result: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, int(leaf_row.slot_index), {"slot_index": int(leaf_row.slot_index)}))
	asserts.false_value(leaf_result.ok, "direct tea leaf use command is rejected")
	asserts.equal(leaf_result.reason, "not_usable", "direct tea leaf use fails before unsupported consumable flow")
	asserts.equal(inventory.to_snapshot(), before_inventory, "direct tea leaf use does not mutate inventory")
	asserts.equal(equipment.to_snapshot(), before_equipment, "direct tea leaf use does not mutate equipment")
	asserts.equal(consumable.to_snapshot(), before_consumable, "direct tea leaf use does not start a consumable action")

	var bandage_result: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, int(consumable_row.slot_index), {"slot_index": int(consumable_row.slot_index)}))
	asserts.true_value(bandage_result.ok, "valid consumable direct use still emits intent")
	asserts.equal(bandage_result.use_intent.item_id, "bandage", "valid consumable use targets bandage")
	asserts.equal(consumable.to_snapshot().active_action, before_consumable.active_action, "direct use intent does not start consumable service inside inventory runtime")

func _assert_main_routes_inventory_commands_and_saves_equipment(asserts) -> void:
	var catalog := _catalog()
	var main := Main.new()
	main.run_state = RunState.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures inventory command runtime")
	asserts.true_value(main.inventory.add_item("short_travel_sword", 1).ok, "fixture adds weapon to main inventory")
	var command := GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, 0, {"slot_index": 0})
	asserts.true_value(main.submit_action_command(command), "main routes equip command through inventory runtime")
	asserts.equal(main.run_state.equipment.slots.weapon.item_id, "short_travel_sword", "main snapshots equipment after inventory command")
	asserts.true_value(main.inventory_read_model().ok, "main exposes inventory read model")
	main.free()

func _assert_hud_inventory_menu_uses_command_read_model(asserts) -> void:
	var fixture := _fixture_runtime()
	asserts.equal(fixture.size(), 4, "fixture exposes runtime inventory equipment consumable")
	var runtime: InventoryCommandRuntime = fixture[0]
	for slot in runtime.read_model().slots:
		if bool(slot.get("can_equip", false)):
			runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, int(slot.slot_index), {"slot_index": int(slot.slot_index)}))
			break
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {"inventory": fixture[1], "inventory_command_runtime": runtime, "catalog": FakeHudCatalog.new()})
	asserts.true_value(hud.show_inventory_menu(), "HUD opens command-backed inventory menu")
	asserts.true_value(_tree_has_text(hud, "차 & 도구 (인벤토리) · 6/24"), "HUD shows capacity from inventory command read model")
	asserts.true_value(_tree_has_text(hud, "이전"), "HUD exposes previous navigation without dragging")
	asserts.true_value(_tree_has_text(hud, "다음"), "HUD exposes next navigation without dragging")
	asserts.true_value(_tree_has_text(hud, "정렬"), "HUD exposes sort command without dragging")
	asserts.true_value(_tree_has_text(hud, "사용"), "HUD exposes use command without dragging")
	asserts.true_value(_tree_has_text(hud, "장착"), "HUD exposes equip command without dragging")
	var leaf_row := _row_for_item(runtime, "father_spring_pan_fired_tea")
	runtime.handle_command(GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, int(leaf_row.slot_index), {"slot_index": int(leaf_row.slot_index)}))
	hud.show_inventory_menu()
	asserts.true_value(_tree_has_text(hud, "서호용정"), "HUD shows selected tea leaf in inventory")
	asserts.false_value(_tree_has_text(hud, "사용"), "HUD does not expose direct use for selected tea leaf")
	hud.free()

func _assert_project_input_map_exposes_inventory_keyboard_actions(asserts) -> void:
	var project := FileAccess.get_file_as_string("res://project.godot")
	for action in ["inventory_previous", "inventory_next", "inventory_sort", "inventory_use_selected", "inventory_equip_selected", "inventory_filter_all", "inventory_filter_consumable", "inventory_filter_equipment"]:
		asserts.true_value("%s={" % action in project, "project input map exposes %s" % action)

func _fixture_runtime() -> Array:
	var catalog := _catalog()
	var inventory: InventoryModel = InventoryModel.from_catalog(catalog).inventory
	var equipment: EquipmentModel = EquipmentModel.from_catalog(catalog).equipment
	var consumable: ConsumableService = ConsumableService.from_catalog(catalog).consumable_service
	inventory.add_item("bandage", 2)
	inventory.add_item("short_travel_sword", 1)
	inventory.add_item("ash_stained_iron_kettle", 1)
	inventory.add_item("father_spring_pan_fired_tea", 3)
	var runtime := InventoryCommandRuntime.new()
	runtime.configure(inventory, equipment, consumable, catalog.data_version)
	return [runtime, inventory, equipment, consumable]

func _catalog() -> DataCatalog:
	var catalog := DataCatalog.new()
	catalog.load_from_directory("res://data/generated")
	return catalog

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and text in node.text:
		return true
	if node is Button and text in node.text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

func _row_for_item(runtime: InventoryCommandRuntime, item_id: String) -> Dictionary:
	for row in runtime.read_model().slots:
		if String(row.get("item_id", "")) == item_id:
			return row
	return {}

func _commands(row: Dictionary) -> Dictionary:
	return row.get("commands", {}) if typeof(row.get("commands", {})) == TYPE_DICTIONARY else {}

class FakeResources:
	var hp := 10
	var hp_max := 10
	var ki := 4
	var ki_max := 4
	var kokoro := 1
	var kokoro_max := 1

class FakePlayer:
	var resources := FakeResources.new()

class FakeHudCatalog:
	func get_definitions(key: String) -> Array:
		return [{"id": "ability_equip_slots", "value": 1}] if key == "balance" else []
	func find_by_id(key: String, id: String) -> Dictionary:
		for row in get_definitions(key):
			if row.id == id:
				return row
		return {}
