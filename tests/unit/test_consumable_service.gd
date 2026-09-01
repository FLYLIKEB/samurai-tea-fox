extends RefCounted

const ConsumableService = preload("res://src/consumable/consumable_service.gd")
const ConsumableDefinition = preload("res://src/consumable/consumable_definition.gd")
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

class InvalidResources:
	extends RefCounted

func run(asserts) -> void:
	_assert_generated_catalog_configures_consumables(asserts)
	_assert_use_action_consumes_and_heals_only_on_completion(asserts)
	_assert_heal_requires_valid_resources_before_consuming(asserts)
	_assert_completed_original_action_cannot_be_reused(asserts)
	_assert_hit_interrupt_preserves_hp_and_quantity(asserts)
	_assert_interrupted_original_action_cannot_be_reused(asserts)
	_assert_hp_heal_clamps_and_stack_decrements(asserts)
	_assert_insufficient_quantity_and_crafting_integration(asserts)
	_assert_snapshot_round_trips_active_action(asserts)
	_assert_snapshot_roundtrip_preserves_action_idempotency(asserts)
	_assert_malformed_snapshot_active_actions_are_rejected(asserts)
	_assert_owner_only_snapshot_cannot_authorize_completion(asserts)
	_assert_fabricated_snapshot_action_cannot_authorize_completion(asserts)
	_assert_failed_snapshot_load_preserves_service_state(asserts)
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
	asserts.true_value(service.consumable_definitions["bandage"] is ConsumableDefinition, "runtime stores validated consumable definitions separately from action state")
	asserts.equal(service.definition_for("bandage").effect_type, ConsumableService.EFFECT_HEAL_HP, "bandage effect is normalized from data")
	asserts.equal(service.definition_for("bandage").effect_value, 25, "bandage heal amount comes from item data")
	asserts.equal(service.definition_for("bandage").use_seconds, 1.0, "bandage use time comes from item data")
	var exported_definition := service.definition_for("bandage")
	exported_definition.effect_value = 999
	asserts.equal(service.definition_for("bandage").effect_value, 25, "definition lookup cannot mutate immutable runtime definition data")

	var fallback_result: Dictionary = ConsumableService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": [{"id": "field_dressing", "name": "응급 붕대", "status": "테스트", "type": "소모품", "max_stack": 5, "effect_type": "HP 회복", "effect_value": 10}]
	}))
	asserts.true_value(fallback_result.ok, "consumable without item use_seconds configures")
	if fallback_result.ok:
		asserts.equal(fallback_result.consumable_service.definition_for("field_dressing").use_seconds, 1.0, "missing item use time falls back to balance value")

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

func _assert_heal_requires_valid_resources_before_consuming(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 2).ok, "bandages can be stocked for invalid target regression")
	resources.apply_damage(40)

	var start: Dictionary = service.start_use("bandage", inventory)
	asserts.true_value(start.ok, "consumable use can start before invalid target regression")
	var null_target: Dictionary = service.complete_use(start.action, inventory, null)
	asserts.false_value(null_target.ok, "heal consumable completion rejects null resources")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "null resource failure does not consume inventory")
	asserts.equal(resources.hp, 60, "null resource failure does not change HP")

	var invalid_target: Dictionary = service.complete_use(start.action, inventory, InvalidResources.new())
	asserts.false_value(invalid_target.ok, "heal consumable completion rejects resources without heal_hp")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "invalid resource failure does not consume inventory")
	asserts.equal(resources.hp, 60, "invalid resource failure does not change HP")

func _assert_completed_original_action_cannot_be_reused(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 2).ok, "bandages can be stocked for completion idempotency")
	resources.apply_damage(60)

	var start: Dictionary = service.start_use("bandage", inventory)
	var complete: Dictionary = service.complete_use(start.action, inventory, resources)
	asserts.true_value(complete.ok, "first original action completion succeeds")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "first completion consumes exactly one item")
	asserts.equal(resources.hp, 65, "first completion applies HP healing once")

	var replay: Dictionary = service.complete_use(start.action, inventory, resources)
	asserts.false_value(replay.ok, "same original action cannot complete twice")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "replayed original completion does not consume another item")
	asserts.equal(resources.hp, 65, "replayed original completion does not heal again")

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

func _assert_interrupted_original_action_cannot_be_reused(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage add succeeds for interrupt idempotency")
	resources.apply_damage(30)

	var start: Dictionary = service.start_use("bandage", inventory)
	var interrupt: Dictionary = service.interrupt_use(start.action, "hit")
	asserts.true_value(interrupt.ok, "first interrupt succeeds")
	var replay: Dictionary = service.complete_use(start.action, inventory, resources)
	asserts.false_value(replay.ok, "interrupted original action cannot be reused for completion")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "interrupted original replay preserves quantity")
	asserts.equal(resources.hp, 70, "interrupted original replay preserves HP")

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
	asserts.equal(loaded.to_snapshot().active_action_owners, snapshot.active_action_owners, "active action ownership round-trip preserves authority")

	var run_state := RunState.new()
	run_state.inventory = inventory.to_snapshot()
	run_state.consumables = snapshot
	var encoded := SaveCodec.encode_run(run_state.to_dictionary())
	var decoded: Dictionary = SaveCodec.decode_run(encoded)
	asserts.true_value(decoded.ok, "run save with consumable snapshot decodes")
	asserts.equal(decoded.state.consumables.active_action.elapsed_seconds, 0.5, "run save preserves consumable progress")
	asserts.true_value(decoded.state.consumables.active_action_owners.has(start.action.action_id), "run save preserves consumable active action ownership")

func _assert_snapshot_roundtrip_preserves_action_idempotency(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 2).ok, "bandages can be stocked for snapshot idempotency")
	resources.apply_damage(60)
	var start: Dictionary = service.start_use("bandage", inventory)
	var snapshot: Dictionary = service.to_snapshot(start.action)

	var loaded := _fixture_service()
	asserts.true_value(loaded.load_snapshot(snapshot).ok, "active action ownership loads")
	var complete: Dictionary = loaded.complete_use(start.action, inventory, resources)
	asserts.true_value(complete.ok, "loaded active action can complete once")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "loaded completion consumes exactly one item")
	asserts.equal(resources.hp, 65, "loaded completion heals once")

	var replay: Dictionary = loaded.complete_use(start.action, inventory, resources)
	asserts.false_value(replay.ok, "loaded service rejects completed original action reuse")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "loaded replay preserves quantity")
	asserts.equal(resources.hp, 65, "loaded replay preserves HP")

func _assert_malformed_snapshot_active_actions_are_rejected(asserts) -> void:
	var service := _fixture_service()
	var valid_action := {
		"action_id": "snapshot_action",
		"item_id": "bandage",
		"elapsed_seconds": 0.5,
		"use_seconds": 1.0,
		"context": {},
		"completed": false,
		"interrupted": false
	}
	var cases := [
		{"label": "non-string action id", "action": _with(valid_action, "action_id", 7)},
		{"label": "empty action id", "action": _with(valid_action, "action_id", "")},
		{"label": "non-string item id", "action": _with(valid_action, "item_id", 1)},
		{"label": "unknown item id", "action": _with(valid_action, "item_id", "missing_bandage")},
		{"label": "non-finite use seconds", "action": _with(valid_action, "use_seconds", INF)},
		{"label": "non-finite elapsed seconds", "action": _with(valid_action, "elapsed_seconds", INF)},
		{"label": "negative elapsed", "action": _with(valid_action, "elapsed_seconds", -0.1)},
		{"label": "elapsed beyond use seconds", "action": _with(valid_action, "elapsed_seconds", 1.1)},
		{"label": "timing mismatch", "action": _with(valid_action, "use_seconds", 2.0)},
		{"label": "completed action", "action": _with(valid_action, "completed", true)},
		{"label": "interrupted action", "action": _with(valid_action, "interrupted", true)}
	]
	for malformed in cases:
		var snapshot := service.to_snapshot(malformed.action)
		var loaded := _fixture_service()
		asserts.false_value(loaded.load_snapshot(snapshot).ok, "consumable snapshot rejects %s" % malformed.label)

func _assert_owner_only_snapshot_cannot_authorize_completion(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage can be stocked for owner-only snapshot regression")
	resources.apply_damage(60)
	var start: Dictionary = service.start_use("bandage", inventory)
	var owner_only_snapshot: Dictionary = service.to_snapshot(start.action)
	owner_only_snapshot.active_action = {}

	var loaded := _fixture_service()
	var before_loaded: Dictionary = loaded.to_snapshot()
	var load_result: Dictionary = loaded.load_snapshot(owner_only_snapshot)
	asserts.false_value(load_result.ok, "owner-only consumable snapshot is rejected")
	asserts.equal(loaded.to_snapshot(), before_loaded, "owner-only snapshot load leaves service state unchanged")

	var fabricated_completion: Dictionary = loaded.complete_use(start.action, inventory, resources)
	asserts.false_value(fabricated_completion.ok, "owner-only snapshot cannot fabricate completion authority")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "fabricated completion preserves inventory")
	asserts.equal(resources.hp, 40, "fabricated completion preserves HP")

func _assert_fabricated_snapshot_action_cannot_authorize_completion(asserts) -> void:
	var fabricated_action := {
		"action_id": "consumable_action_000009",
		"item_id": "bandage",
		"elapsed_seconds": 0.5,
		"use_seconds": 1.0,
		"context": {},
		"completed": false,
		"interrupted": false
	}
	var fabricated_snapshot := {
		"schema_version": ConsumableService.SNAPSHOT_SCHEMA_VERSION,
		"data_version": "fixture-consumables",
		"next_action_id": 2,
		"active_action": fabricated_action,
		"active_action_owners": {
			"consumable_action_000009": {
				"item_id": "bandage",
				"use_seconds": 1.0
			}
		}
	}
	var loaded := _fixture_service()
	var before_loaded: Dictionary = loaded.to_snapshot()
	var load_result: Dictionary = loaded.load_snapshot(fabricated_snapshot)
	asserts.false_value(load_result.ok, "fabricated consumable action sequence is rejected")
	asserts.equal(loaded.to_snapshot(), before_loaded, "fabricated snapshot load leaves service state unchanged")

	var inventory := _fixture_inventory()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage can be stocked for fabricated snapshot regression")
	resources.apply_damage(60)
	var fabricated_completion: Dictionary = loaded.complete_use(fabricated_action, inventory, resources)
	asserts.false_value(fabricated_completion.ok, "fabricated snapshot cannot grant completion authority")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "fabricated active action completion preserves inventory")
	asserts.equal(resources.hp, 40, "fabricated active action completion preserves HP")

func _assert_failed_snapshot_load_preserves_service_state(asserts) -> void:
	var service := _fixture_service()
	var inventory := _fixture_inventory()
	asserts.true_value(inventory.add_item("bandage", 1).ok, "bandage can be stocked before failed load atomicity regression")
	var start: Dictionary = service.start_use("bandage", inventory)
	var partial: Dictionary = service.tick_use(start.action, 0.25, inventory)
	var before: Dictionary = service.to_snapshot(partial.action)
	var malformed: Dictionary = before.duplicate(true)
	malformed.data_version = "tampered-data-version"
	malformed.next_action_id = 99
	malformed.active_action_owners = {
		String(partial.action.action_id): {
			"item_id": "bandage",
			"use_seconds": 1.0
		},
		"extra_action": {
			"item_id": "bandage",
			"use_seconds": 1.0
		}
	}

	var load_result: Dictionary = service.load_snapshot(malformed)
	asserts.false_value(load_result.ok, "malformed owner consistency rejects snapshot load")
	asserts.equal(service.to_snapshot(partial.action), before, "failed consumable snapshot load is atomic")

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

func _with(source: Dictionary, key: String, value) -> Dictionary:
	var copy := source.duplicate(true)
	copy[key] = value
	return copy
