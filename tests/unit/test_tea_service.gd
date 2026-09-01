extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const TeaService = preload("res://src/tea/tea_service.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-tea"

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
	_assert_generated_catalog_configures_tea_service(asserts)
	_assert_brewing_creates_prepared_tea_from_inventory(asserts)
	_assert_drink_action_consumes_only_on_completion(asserts)
	_assert_progressive_and_conditional_effects_share_completion_contract(asserts)
	_assert_vessel_modifiers_are_data_driven(asserts)
	_assert_snapshot_round_trips_prepared_tea(asserts)
	_assert_invalid_data_and_combos_are_rejected_atomically(asserts)

func _assert_generated_catalog_configures_tea_service(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for tea service")
	var service_result: Dictionary = TeaService.from_catalog(catalog)
	asserts.true_value(service_result.ok, "tea service initializes from generated catalog")
	if not service_result.ok:
		return
	var service: TeaService = service_result.tea_service
	asserts.equal(service.quickslot_count, 2, "tea quickslot count comes from balance data")
	asserts.equal(service.drink_base_seconds, 1.2, "tea base drink time comes from balance data")
	asserts.true_value(service.tea_definitions.has("father_spring_pan_fired_tea"), "tea definitions come from generated tea data")
	asserts.true_value(service.vessel_definitions.has("humble_clay_bowl"), "vessel definitions come from item data")

func _assert_brewing_creates_prepared_tea_from_inventory(asserts) -> void:
	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	asserts.true_value(inventory.add_item("green_tea", 2).ok, "tea leaves can be stocked")
	asserts.true_value(inventory.add_item("plain_bowl", 1).ok, "vessel can be carried")

	var brewed: Dictionary = service.brew("green_tea", "plain_bowl", inventory)
	asserts.true_value(brewed.ok, "valid tea and vessel brew portable tea")
	asserts.equal(brewed.slot, 0, "brewing fills first empty quickslot")
	asserts.equal(inventory.get_total_quantity("green_tea"), 1, "brewing consumes exactly one tea leaf")
	asserts.equal(inventory.get_total_quantity("plain_bowl"), 1, "brewing does not consume vessel")
	asserts.equal(brewed.prepared_tea.ki_recovery, 18, "prepared tea reads ki recovery from tea data")
	asserts.equal(brewed.prepared_tea.remaining_uses, 1, "prepared tea defaults to one carried use")

func _assert_drink_action_consumes_only_on_completion(asserts) -> void:
	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	var resources := PlayerResources.new(20, 50, 10, 3)
	resources.apply_damage(7)
	resources.spend_ki(30)
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds")
	asserts.true_value(inventory.add_item("plain_bowl", 1).ok, "vessel add succeeds")
	asserts.true_value(service.brew("green_tea", "plain_bowl", inventory, 0).ok, "brew succeeds")

	var start: Dictionary = service.start_drinking(0)
	asserts.true_value(start.ok, "drinking can start from prepared slot")
	asserts.equal(service.get_prepared_tea(0).remaining_uses, 1, "start does not consume prepared tea")
	asserts.equal(resources.ki, 20, "start does not recover ki")
	asserts.equal(resources.hp, 13, "start does not heal HP")

	var interrupt: Dictionary = service.interrupt_drinking(start.action, "hit")
	asserts.true_value(interrupt.ok, "hit can interrupt tea drinking")
	asserts.false_value(interrupt.consumed, "interrupt does not consume prepared tea")
	asserts.true_value(service.has_prepared_tea(0), "interrupted prepared tea remains available")
	asserts.equal(resources.ki, 20, "interrupt does not recover ki")

	var restarted: Dictionary = service.start_drinking(0)
	var partial: Dictionary = service.tick_drinking(restarted.action, 0.3, resources)
	asserts.true_value(partial.ok, "drink action can advance before completion")
	asserts.false_value(partial.completed, "partial drinking is not complete")
	asserts.true_value(service.has_prepared_tea(0), "partial drinking does not consume prepared tea")
	asserts.equal(resources.ki, 20, "partial drinking does not apply effect")

	var complete: Dictionary = service.tick_drinking(partial.action, 0.9, resources)
	asserts.true_value(complete.ok, "drink action completes after configured time")
	asserts.true_value(complete.consumed, "completion consumes prepared tea")
	asserts.false_value(service.has_prepared_tea(0), "completed single-use tea leaves quickslot empty")
	asserts.equal(complete.effect.ki_recovered, 18, "completion applies ki recovery")
	asserts.equal(resources.ki, 38, "tea recovers ki on completion")
	asserts.equal(resources.hp, 13, "tea never recovers HP")

func _assert_progressive_and_conditional_effects_share_completion_contract(asserts) -> void:
	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	var resources := PlayerResources.new(20, 100, 10, 3)
	asserts.true_value(resources.spend_ki(80), "ki can be lowered")
	asserts.true_value(inventory.add_item("slow_tea", 1).ok, "progressive tea add succeeds")
	asserts.true_value(inventory.add_item("focus_tea", 2).ok, "conditional tea add succeeds")
	asserts.true_value(inventory.add_item("plain_bowl", 1).ok, "vessel add succeeds")

	asserts.true_value(service.brew("slow_tea", "plain_bowl", inventory, 0).ok, "progressive tea brews")
	var progressive_start: Dictionary = service.start_drinking(0)
	var progressive_complete: Dictionary = service.complete_drinking(progressive_start.action, resources)
	asserts.true_value(progressive_complete.ok, "progressive tea completes with shared action contract")
	asserts.equal(progressive_complete.effect.mode, TeaService.RECOVERY_PROGRESSIVE, "progressive mode is preserved in effect")
	asserts.equal(progressive_complete.effect.ki_recovered, 12, "progressive tea recovers configured ki on completion")

	asserts.true_value(service.brew("focus_tea", "plain_bowl", inventory, 0).ok, "conditional tea brews")
	var conditional_fail_start: Dictionary = service.start_drinking(0, {"low_ki": false})
	var conditional_fail: Dictionary = service.complete_drinking(conditional_fail_start.action, resources)
	asserts.true_value(conditional_fail.ok, "conditional tea completion succeeds when condition fails")
	asserts.false_value(conditional_fail.effect.condition_passed, "failed condition is reported")
	asserts.equal(conditional_fail.effect.ki_recovered, 0, "failed condition does not recover ki")
	asserts.false_value(service.has_prepared_tea(0), "completed conditional drink is still consumed")

	asserts.true_value(service.brew("focus_tea", "plain_bowl", inventory, 0).ok, "second conditional tea brews")
	var conditional_pass_start: Dictionary = service.start_drinking(0, {"conditions": {"low_ki": true}})
	var conditional_pass: Dictionary = service.complete_drinking(conditional_pass_start.action, resources)
	asserts.true_value(conditional_pass.effect.condition_passed, "nested condition context is accepted")
	asserts.equal(conditional_pass.effect.ki_recovered, 20, "passed condition recovers configured ki")

func _assert_vessel_modifiers_are_data_driven(asserts) -> void:
	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "modified vessel add succeeds")

	var brewed: Dictionary = service.brew("green_tea", "travel_bottle", inventory, 1)
	asserts.true_value(brewed.ok, "modified vessel brews")
	asserts.equal(brewed.prepared_tea.ki_recovery, 25, "vessel recovery multiplier and bonus apply from data")
	asserts.equal(brewed.prepared_tea.remaining_uses, 3, "vessel carry bonus applies from data")
	asserts.equal(brewed.prepared_tea.drink_seconds, 0.7, "vessel drink time modifiers apply from data")
	asserts.equal(brewed.prepared_tea.sustain_modifier, 0.35, "tea and vessel sustain modifiers add from data")
	asserts.false_value(brewed.prepared_tea.core_tea_ware, "non-core vessel stays non-core in prepared tea")

	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds for modifier query")
	var modifier_query := service.get_vessel_modifier_query("travel_bottle")
	var brewed_from_query: Dictionary = service.brew_with_modifier_query("green_tea", modifier_query, inventory, 0)
	asserts.true_value(brewed_from_query.ok, "tea service can brew from modifier query")
	asserts.equal(brewed_from_query.prepared_tea.ki_recovery, 25, "modifier query preserves recovery behavior")

func _assert_snapshot_round_trips_prepared_tea(asserts) -> void:
	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "vessel add succeeds")
	asserts.true_value(service.brew("green_tea", "travel_bottle", inventory, 0).ok, "brew succeeds")
	var snapshot: Dictionary = service.to_snapshot()

	var loaded: TeaService = _fixture_service()
	var load_result: Dictionary = loaded.load_snapshot(snapshot)
	asserts.true_value(load_result.ok, "tea snapshot reload succeeds")
	asserts.equal(loaded.to_snapshot(), snapshot, "tea snapshot round-trip preserves prepared slots")

func _assert_invalid_data_and_combos_are_rejected_atomically(asserts) -> void:
	var invalid_catalog: Dictionary = TeaService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": [{"id": "plain_bowl", "name": "그릇", "status": "테스트", "type": "다구"}],
		"teas": [{"id": "bad_tea", "name": "나쁜 차", "status": "테스트", "ki_recovery": 1.5}]
	}))
	asserts.false_value(invalid_catalog.ok, "fractional tea recovery is rejected")

	var service: TeaService = _fixture_service()
	var inventory: InventoryModel = _fixture_inventory()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds")
	asserts.true_value(inventory.add_item("plain_bowl", 1).ok, "vessel add succeeds")
	var before_inventory: Dictionary = inventory.to_snapshot()
	var before_tea: Dictionary = service.to_snapshot()

	asserts.false_value(service.brew("missing_tea", "plain_bowl", inventory).ok, "unknown tea is rejected")
	asserts.equal(inventory.to_snapshot(), before_inventory, "unknown tea does not mutate inventory")
	asserts.equal(service.to_snapshot(), before_tea, "unknown tea does not mutate quickslots")

	asserts.false_value(service.brew("green_tea", "missing_vessel", inventory).ok, "unknown vessel is rejected")
	asserts.equal(inventory.to_snapshot(), before_inventory, "unknown vessel does not mutate inventory")

	asserts.true_value(inventory.add_item("two_leaf_tea", 1).ok, "limited serving tea add succeeds")
	var missing_serving_inventory: Dictionary = inventory.to_snapshot()
	asserts.false_value(service.brew("two_leaf_tea", "plain_bowl", inventory).ok, "serving size rejects insufficient leaves")
	asserts.equal(inventory.to_snapshot(), missing_serving_inventory, "insufficient serving size is atomic")

	asserts.true_value(inventory.add_item("location_tea", 1).ok, "location tea add succeeds")
	var missing_location_inventory: Dictionary = inventory.to_snapshot()
	asserts.false_value(service.brew("location_tea", "plain_bowl", inventory).ok, "tea can require a brewing location")
	asserts.equal(inventory.to_snapshot(), missing_location_inventory, "missing brewing location does not consume leaves")
	asserts.true_value(service.brew("location_tea", "plain_bowl", inventory, 1, {"has_brewing_location": true}).ok, "valid brewing location allows tea")

	asserts.true_value(service.brew("green_tea", "plain_bowl", inventory, 0).ok, "first brew fills slot")
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea add succeeds for occupied slot check")
	var occupied_inventory: Dictionary = inventory.to_snapshot()
	asserts.false_value(service.brew("green_tea", "plain_bowl", inventory, 0).ok, "occupied slot is rejected")
	asserts.equal(inventory.to_snapshot(), occupied_inventory, "occupied slot rejection does not consume tea leaf")

func _fixture_service() -> TeaService:
	var result: Dictionary = TeaService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	return result.tea_service

func _fixture_inventory() -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 8}],
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	return result.inventory

func _balance_rows() -> Array:
	return [
		{"id": "tea_quickslot_count", "name": "차 퀵슬롯 수", "status": "테스트", "value": 2},
		{"id": "tea_drink_base_seconds", "name": "차 마시기 기본 시간", "status": "테스트", "value": 1.2}
	]

func _item_rows() -> Array:
	return [
		{"id": "plain_bowl", "name": "소박한 사발", "status": "테스트", "type": "다구"},
		{
			"id": "travel_bottle",
			"name": "보온 차병",
			"status": "테스트",
			"type": "다구",
			"effect_type": "차 운용",
			"effect_value": 2,
			"tea_recovery_multiplier": 1.25,
			"carry_use_bonus": 2,
			"drink_seconds_multiplier": 0.5,
			"drink_seconds_bonus": 0.1,
			"sustain_modifier": 0.25,
			"core_tea_ware": false
		},
		{"id": "stone", "name": "돌", "status": "테스트", "type": "재료", "max_stack": 10}
	]

func _tea_rows() -> Array:
	return [
		{"id": "green_tea", "name": "녹차", "status": "테스트", "ki_recovery": 18, "sustain_modifier": 0.1, "max_stack": 4},
		{"id": "slow_tea", "name": "느린 차", "status": "테스트", "ki_recovery": 12, "recovery_mode": "progressive", "drink_seconds": 1.5, "max_stack": 4},
		{"id": "focus_tea", "name": "집중 차", "status": "테스트", "ki_recovery": 20, "recovery_mode": "conditional", "condition_key": "low_ki", "max_stack": 4},
		{"id": "two_leaf_tea", "name": "두 잎 차", "status": "테스트", "ki_recovery": 10, "serving_size": 2, "max_stack": 4},
		{"id": "location_tea", "name": "자리 차", "status": "테스트", "ki_recovery": 10, "requires_brewing_location": true, "max_stack": 4}
	]
