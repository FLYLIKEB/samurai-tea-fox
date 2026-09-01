extends RefCounted

const ConsumableService = preload("res://src/consumable/consumable_service.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-consumables"

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_generated_catalog_configures_consumables(asserts)
	_assert_use_action_consumes_and_heals_only_on_completion(asserts)
	_assert_hit_interrupt_preserves_hp_and_quantity(asserts)
	_assert_hp_heal_clamps_and_stack_decrements(asserts)
	_assert_insufficient_quantity_and_crafting_integration(asserts)
	_assert_snapshot_round_trips_active_action(asserts)
	_assert_invalid_data_is_rejected(asserts)

func _assert_generated_catalog_configures_consumables(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for consumable service")
	var service_result: Dictionary = ConsumableService.from_catalog(catalog)
	asserts.true_value(service_result.ok, "consumable service initializes from generated catalog")
	if not service_result.ok:
		return
	var service: ConsumableService = service_result.consumable_service
	asserts.true_value(service.has_definition("bandage"), "bandage definition comes from generated item data")
	asserts.equal(service.definition_for("bandage").effect_type, ConsumableService.EFFECT_HEAL_HP, "bandage effect is normalized from data")
	asserts.equal(service.definition_for("bandage").effect_value, 25, "bandage heal amount comes from item data")
	asserts.equal(service.definition_for("bandage").use_seconds, 1.0, "bandage use time comes from item data")

func _assert_use_action_consumes_and_heals_only_on_completion(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 2).ok, "bandages can be stocked")
	resources.apply_damage(60)

	var start: Dictionary = service.start_use("bandage", inventory)
	asserts.true_value(start.ok, "consumable use can start")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "start does not consume an item")
	asserts.equal(resources.hp, 40, "start does not heal HP")

	var partial: Dictionary = service.tick_use(start.action, 0.4, inventory, resources)
	asserts.true_value(partial.ok, "consumable use can progress")
	asserts.false_value(partial.completed, "partial use is not complete")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "progress does not consume an item")
	asserts.equal(resources.hp, 40, "progress does not heal HP")

	var complete: Dictionary = service.tick_use(partial.action, 0.6, inventory, resources)
	asserts.true_value(complete.ok, "consumable completes at configured use time")
	asserts.true_value(complete.consumed, "completion consumes one item")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "completion decrements stacked quantity")
	asserts.equal(complete.effect.hp_healed, 25, "completion reports applied healing")
	asserts.equal(resources.hp, 65, "completion applies HP healing")

func _assert_hit_interrupt_preserves_hp_and_quantity(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage add succeeds")
	resources.apply_damage(30)

	var start: Dictionary = service.start_use("bandage", inventory)
	var interrupt: Dictionary = service.interrupt_use(start.action, "hit")
	asserts.true_value(interrupt.ok, "hit can interrupt consumable use")
	asserts.false_value(interrupt.consumed, "interrupt does not consume the item")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "interrupt preserves quantity")
	asserts.equal(resources.hp, 70, "interrupt does not heal HP")
	asserts.false_value(service.complete_use(interrupt.action, inventory, resources).ok, "interrupted action cannot complete later")

func _assert_hp_heal_clamps_and_stack_decrements(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 3).ok, "stacked bandages can be stocked")
	resources.apply_damage(10)
	var start: Dictionary = service.start_use("bandage", inventory)
	var complete: Dictionary = service.complete_use(start.action, inventory, resources)
	asserts.true_value(complete.ok, "direct completion is valid")
	asserts.equal(complete.effect.hp_healed, 10, "HP healing clamps at maximum")
	asserts.equal(resources.hp, 100, "HP cannot exceed maximum")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "one item is consumed from the stack")

func _assert_insufficient_quantity_and_crafting_integration(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	asserts.false_value(service.start_use("bandage", inventory).ok, "missing bandage cannot start use")

	var crafting_script = load("res://src/crafting/crafting_service.gd")
	var craft_result: Dictionary = crafting_script.from_catalog(FakeCatalog.new({
		"items": _item_rows(),
		"teas": [],
		"recipes": [
			{"id": "bandage", "name": "붕대 제작", "status": "테스트", "facility": "손제작", "materials": [{"item_id": "cloth", "quantity": 2}], "result_item_id": "bandage", "result_quantity": 1}
		]
	}))
	asserts.true_value(craft_result.ok, "cloth-to-bandage recipe configures")
	if not craft_result.ok:
		return
	var insufficient: Dictionary = craft_result.crafting_service.can_craft("bandage", inventory)
	asserts.false_value(insufficient.ok, "bandage crafting reports insufficient cloth")
	asserts.true_value(inventory.add_item("cloth", 2).ok, "cloth can be stocked")
	asserts.true_value(craft_result.crafting_service.craft("bandage", inventory).ok, "cloth crafts into bandage")
	asserts.equal(inventory.get_total_quantity("cloth"), 0, "bandage crafting consumes cloth")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "bandage crafting adds inventory item")

func _assert_snapshot_round_trips_active_action(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage add succeeds before snapshot")
	var start: Dictionary = service.start_use("bandage", inventory)
	var partial: Dictionary = service.tick_use(start.action, 0.5, inventory)
	var snapshot: Dictionary = service.to_snapshot(partial.action)

	var loaded := _fixture_service()
	var load_result: Dictionary = loaded.load_snapshot(snapshot)
	asserts.true_value(load_result.ok, "consumable snapshot reload succeeds")
	asserts.equal(load_result.active_action, snapshot.active_action, "active action round-trip preserves progress")

	var run_state := RunState.new()
	run_state.inventory = inventory.to_snapshot()
	run_state.consumables = snapshot
	var encoded := SaveCodec.encode_run(run_state.to_dictionary())
	var decoded: Dictionary = SaveCodec.decode_run(encoded)
	asserts.true_value(decoded.ok, "run save with consumable snapshot decodes")
	asserts.equal(decoded.state.consumables.active_action.elapsed_seconds, 0.5, "run save preserves consumable progress")

func _assert_invalid_data_is_rejected(asserts) -> void:
	var missing_balance: Dictionary = ConsumableService.from_catalog(FakeCatalog.new({
		"balance": [],
		"items": _item_rows()
	}))
	asserts.false_value(missing_balance.ok, "missing use seconds balance is rejected")

	var bad_effect: Dictionary = ConsumableService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": [{"id": "bad", "name": "bad", "status": "테스트", "type": "소모품", "effect_type": "poison", "effect_value": 1}]
	}))
	asserts.false_value(bad_effect.ok, "unknown consumable effect is rejected")

	var fractional_heal: Dictionary = ConsumableService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": [{"id": "bad", "name": "bad", "status": "테스트", "type": "소모품", "effect_type": "HP 회복", "effect_value": 1.5}]
	}))
	asserts.false_value(fractional_heal.ok, "fractional heal values are rejected")

func _fixture_service() -> ConsumableService:
	var result: Dictionary = ConsumableService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": _item_rows()
	}))
	return result.consumable_service

func _fixture_inventory() -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 4}],
		"items": _item_rows(),
		"teas": []
	}))
	return result.inventory

func _balance_rows() -> Array:
	return [
		{"id": "consumable_use_base_seconds", "name": "소모품 기본 사용 시간", "status": "테스트", "value": 1.0}
	]

func _item_rows() -> Array:
	return [
		{"id": "cloth", "name": "천", "status": "테스트", "type": "재료", "max_stack": 20},
		{"id": "bandage", "name": "붕대", "status": "테스트", "type": "소모품", "max_stack": 5, "effect_type": "HP 회복", "effect_value": 25, "use_seconds": 1.0}
	]
