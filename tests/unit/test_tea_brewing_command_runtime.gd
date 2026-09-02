extends RefCounted

const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const Main = preload("res://src/main/main.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const TeaBrewingCommandRuntime = preload("res://src/tea/tea_brewing_command_runtime.gd")
const TeaService = preload("res://src/tea/tea_service.gd")

func run(asserts) -> void:
	_assert_read_model_previews_valid_combo(asserts)
	_assert_brew_command_consumes_leaf_and_places_quickslot(asserts)
	_assert_invalid_selection_is_rejected_without_mutation(asserts)
	_assert_location_requirement_blocks_ui_command(asserts)
	_assert_command_adapters_and_hud_route_brewing(asserts)
	_assert_main_and_save_round_trip_portable_tea(asserts)

func _assert_read_model_previews_valid_combo(asserts) -> void:
	var fixture := _fixture()
	var runtime: TeaBrewingCommandRuntime = fixture.runtime
	asserts.true_value(runtime.select_leaf("green_tea").ok, "green tea can be selected for preview")
	var model: Dictionary = runtime.read_model()
	asserts.true_value(model.read_only, "brewing model is read-only")
	asserts.equal(model.leaves.size(), 2, "read model lists owned tea leaves")
	asserts.equal(model.vessels.size(), 1, "read model lists carried tea ware")
	asserts.equal(model.quickslots.size(), 2, "read model lists portable tea slots")
	asserts.true_value(model.can_brew, "valid default combo can brew")
	asserts.equal(model.preview.prepared_tea.ki_recovery, 18, "preview delegates effect calculation to tea service")
	asserts.equal(model.preview.prepared_tea.remaining_uses, 1, "preview exposes portable carry count")

func _assert_brew_command_consumes_leaf_and_places_quickslot(asserts) -> void:
	var fixture := _fixture()
	var runtime: TeaBrewingCommandRuntime = fixture.runtime
	asserts.true_value(runtime.select_leaf("green_tea").ok, "tea leaf selection succeeds")
	asserts.true_value(runtime.select_vessel("inventory:plain_bowl:2").ok, "tea ware selection succeeds")
	asserts.true_value(runtime.select_slot(1).ok, "quickslot selection succeeds")
	var before_inventory: Dictionary = fixture.inventory.to_snapshot()
	var result: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.BREW_TEA))
	asserts.true_value(result.ok, "brew command succeeds")
	asserts.equal(fixture.inventory.get_total_quantity("green_tea"), int(before_inventory.slots[0].quantity) - 1, "brew command consumes tea leaf in domain service")
	asserts.true_value(fixture.tea_service.has_prepared_tea(1), "brew command places portable tea in selected quickslot")
	asserts.equal(fixture.tea_service.get_prepared_tea(1).tea_id, "green_tea", "prepared tea preserves selected leaf")

func _assert_invalid_selection_is_rejected_without_mutation(asserts) -> void:
	var fixture := _fixture()
	var runtime: TeaBrewingCommandRuntime = fixture.runtime
	var before_inventory: Dictionary = fixture.inventory.to_snapshot()
	var before_tea: Dictionary = fixture.tea_service.to_snapshot()
	var invalid: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_LEAF, Vector2i.ZERO, -1, {"tea_id": "missing"}))
	asserts.false_value(invalid.ok, "missing leaf is rejected")
	asserts.equal(fixture.inventory.to_snapshot(), before_inventory, "invalid selection does not mutate inventory")
	asserts.equal(fixture.tea_service.to_snapshot(), before_tea, "invalid selection does not mutate tea slots")

func _assert_location_requirement_blocks_ui_command(asserts) -> void:
	var fixture := _fixture(false)
	var runtime: TeaBrewingCommandRuntime = fixture.runtime
	asserts.true_value(runtime.select_leaf("location_tea").ok, "location tea can be selected")
	var model: Dictionary = runtime.read_model()
	asserts.false_value(model.can_brew, "location-required tea cannot brew without location")
	asserts.equal(model.preview.reason, "missing_brewing_location", "read model exposes location requirement reason")
	var before_inventory: Dictionary = fixture.inventory.to_snapshot()
	var brewed: Dictionary = runtime.handle_command(GameCommand.new(GameCommand.Type.BREW_TEA))
	asserts.false_value(brewed.ok, "brew command rejects missing location")
	asserts.equal(fixture.inventory.to_snapshot(), before_inventory, "missing location does not consume leaves")

func _assert_command_adapters_and_hud_route_brewing(asserts) -> void:
	var desktop := DesktopCommandAdapter.new()
	var mobile := MobileCommandAdapter.new()
	asserts.equal(desktop.command_for_action("open_tea_brewing").type, GameCommand.Type.OPEN_TEA_BREWING, "desktop opens brewing menu")
	asserts.equal(mobile.command_for_button("open_tea_brewing").type, GameCommand.Type.OPEN_TEA_BREWING, "mobile opens brewing menu")
	asserts.equal(desktop.command_for_action("brew_tea").type, GameCommand.Type.BREW_TEA, "desktop emits brew command")
	asserts.equal(mobile.command_for_button("tea_brew_next_leaf").payload.target, "leaf", "mobile leaf navigation is command-backed")
	var project := FileAccess.get_file_as_string("res://project.godot")
	asserts.true_value("open_tea_brewing={" in project, "project input map exposes tea brewing menu")
	asserts.true_value("brew_tea={" in project, "project input map exposes brew action")

	var fixture := _fixture()
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {"tea_service": fixture.tea_service, "tea_brewing_command_runtime": fixture.runtime, "inventory": fixture.inventory, "catalog": FakeCatalog.new(_definitions()), "crafting_context": {"has_brewing_location": true}})
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.press_mobile_button("open_tea_brewing"), "HUD mobile button emits open brewing command")
	asserts.true_value(hud.show_tea_brewing_menu(), "HUD opens brewing menu")
	asserts.equal(hud.active_menu_id(), "tea_brewing", "HUD exposes active brewing menu for gated keyboard commands")
	asserts.true_value(_tree_has_text(hud, "차 우리기"), "HUD renders brewing menu title")
	asserts.true_value(_tree_has_text(hud, "미리보기"), "HUD renders combination preview")
	asserts.equal(received[0].type, GameCommand.Type.OPEN_TEA_BREWING, "HUD emits shared brewing command")
	hud.free()

func _assert_main_and_save_round_trip_portable_tea(asserts) -> void:
	var fixture := _fixture()
	var main := Main.new()
	main.tea_service = fixture.tea_service
	main.tea_brewing_command_runtime = fixture.runtime
	main.inventory = fixture.inventory
	main.run_state = RunState.new()
	asserts.true_value(main.tea_brewing_read_model().ok, "Main exposes brewing read model")
	main.tea_brewing_command_runtime.select_leaf("green_tea")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.BREW_TEA)), "Main routes brew command")
	asserts.true_value(main.run_state.tea.quick_slots[0].has("tea_id"), "Main syncs portable tea state after brewing")
	var decoded: Dictionary = SaveCodec.decode_run(SaveCodec.encode_run(main.run_state))
	asserts.true_value(decoded.ok, "Run save with portable tea decodes")
	asserts.equal(decoded.run_state.tea.quick_slots[0].tea_id, "green_tea", "portable tea quickslot round-trips through run save")
	main.free()

func _fixture(has_brewing_location := true) -> Dictionary:
	var service_result: Dictionary = TeaService.from_catalog(FakeCatalog.new(_definitions()))
	var inventory_result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new(_definitions()))
	var inventory: InventoryModel = inventory_result.inventory
	assert(inventory.add_item("green_tea", 2).ok)
	assert(inventory.add_item("location_tea", 1).ok)
	assert(inventory.add_item("plain_bowl", 1).ok)
	var runtime := TeaBrewingCommandRuntime.new()
	var configured: Dictionary = runtime.configure(service_result.tea_service, inventory, null, func(): return {"has_brewing_location": has_brewing_location}, "fixture-tea")
	assert(configured.ok)
	return {"runtime": runtime, "tea_service": service_result.tea_service, "inventory": inventory, "equipment": null}

func _definitions() -> Dictionary:
	return {
		"balance": [
			{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 8},
			{"id": "tea_quickslot_count", "name": "차 퀵슬롯 수", "status": "테스트", "value": 2},
			{"id": "tea_drink_base_seconds", "name": "차 마시기 기본 시간", "status": "테스트", "value": 1.2},
			{"id": "ability_equip_slots", "name": "요술 슬롯", "status": "테스트", "value": 1}
		],
		"items": [
			{"id": "plain_bowl", "name": "소박한 사발", "status": "테스트", "type": "다구"}
		],
		"teas": [
			{"id": "green_tea", "name": "들녘 덖음차", "status": "테스트", "ki_recovery": 18, "max_stack": 9},
			{"id": "location_tea", "name": "다실 차", "status": "테스트", "ki_recovery": 22, "max_stack": 9, "requires_brewing_location": true}
		]
	}

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and text in node.text:
		return true
	if node is Button and text in node.text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions
	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])
	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

class FakeResources:
	var hp := 10
	var hp_max := 10
	var ki := 4
	var ki_max := 4
	var kokoro := 1
	var kokoro_max := 1

class FakePlayer:
	var resources := FakeResources.new()
	var global_position := Vector2.ZERO
