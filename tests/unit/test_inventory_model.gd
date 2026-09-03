extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-inventory"

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
	_assert_generated_catalog_configures_inventory(asserts)
	_assert_stack_merge_split_and_overflow_are_data_driven(asserts)
	_assert_instance_items_occupy_individual_slots(asserts)
	_assert_sorting_preserves_items_and_moves_empty_slots_to_end(asserts)
	_assert_versioned_snapshot_round_trips(asserts)
	_assert_max_owned_rejects_manipulated_snapshot_and_insert(asserts)
	_assert_change_and_failure_events_are_observable(asserts)
	_assert_capacity_expansion_preserves_contents(asserts)
	_assert_invalid_catalog_values_are_rejected(asserts)

func _assert_generated_catalog_configures_inventory(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads")
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	asserts.true_value(inventory_result.ok, "inventory initializes from generated catalog")
	if not inventory_result.ok:
		return
	var inventory: InventoryModel = inventory_result.inventory
	asserts.equal(inventory.slot_count, 24, "inventory slot count comes from balance data")
	asserts.true_value(inventory.has_definition("short_travel_sword"), "item definitions come from item data")
	asserts.true_value(inventory.has_definition("bandage"), "generated consumable item is inventory-addressable")
	asserts.equal(inventory.definition_for("bandage").max_stack, 5, "consumable stack size comes from generated item data")
	asserts.true_value(inventory.has_definition("father_spring_pan_fired_tea"), "tea definitions are inventory items")
	asserts.equal(inventory.definition_for("short_travel_sword").requires_instance, true, "weapon policy is individual")

func _assert_stack_merge_split_and_overflow_are_data_driven(asserts) -> void:
	var inventory := _fixture_inventory(3)
	var add_result: Dictionary = inventory.add_item("clay", 17)
	asserts.true_value(add_result.ok, "stackable material can be added")
	asserts.equal(inventory.get_slot(0).quantity, 10, "first stack fills to data max_stack")
	asserts.equal(inventory.get_slot(1).quantity, 7, "remaining material uses next slot")

	var overflow_snapshot := inventory.to_snapshot()
	var overflow: Dictionary = inventory.add_item("clay", 14)
	asserts.false_value(overflow.ok, "overflowing add is rejected")
	asserts.equal(inventory.to_snapshot(), overflow_snapshot, "overflowing add is atomic")

	var split: Dictionary = inventory.split_slot(0, 4, 2)
	asserts.true_value(split.ok, "stack can be split into an empty slot")
	asserts.equal(inventory.get_slot(0).quantity, 6, "split subtracts from source")
	asserts.equal(inventory.get_slot(2).quantity, 4, "split writes target stack")

	var remove: Dictionary = inventory.remove_item("clay", 8)
	asserts.true_value(remove.ok, "stacked material can be removed across slots")
	asserts.equal(inventory.get_total_quantity("clay"), 9, "removal updates total quantity")

func _assert_instance_items_occupy_individual_slots(asserts) -> void:
	var inventory := _fixture_inventory(4)
	var result: Dictionary = inventory.add_item("short_travel_sword", 2, {"durability": 9})
	asserts.true_value(result.ok, "individual equipment can be added")
	asserts.equal(result.instance_ids.size(), 2, "equipment creates one instance per quantity")
	asserts.true_value(result.instance_ids[0] != result.instance_ids[1], "equipment instances have unique ids")
	asserts.equal(inventory.get_slot(0).quantity, 1, "equipment quantity is always one per slot")
	asserts.equal(inventory.get_slot(1).metadata.durability, 9, "instance metadata is copied into the slot")

	var split: Dictionary = inventory.split_slot(0, 1, 2)
	asserts.false_value(split.ok, "instance items cannot be split")

func _assert_sorting_preserves_items_and_moves_empty_slots_to_end(asserts) -> void:
	var inventory := _fixture_inventory(5)
	asserts.true_value(inventory.add_item("short_travel_sword", 1).ok, "weapon add succeeds")
	asserts.true_value(inventory.add_item("clay", 3).ok, "material add succeeds")
	asserts.true_value(inventory.add_item("father_spring_pan_fired_tea", 2).ok, "tea leaf add succeeds")
	asserts.true_value(inventory.move_slot(0, 4).ok, "slot move creates a gap")
	var extracted: Dictionary = inventory.extract_slot(4)
	asserts.true_value(extracted.ok, "slot can be extracted for domain transfer")
	asserts.equal(extracted.slot.item_id, "short_travel_sword", "extract returns moved item")
	asserts.equal(inventory.get_slot(4), {}, "extract clears source slot")
	asserts.true_value(inventory.insert_slot(extracted.slot, 4).ok, "slot can be inserted after extraction")
	asserts.true_value(inventory.sort_slots().ok, "sort succeeds")
	asserts.equal(inventory.get_total_quantity("short_travel_sword"), 1, "sort preserves equipment")
	asserts.equal(inventory.get_total_quantity("clay"), 3, "sort preserves materials")
	asserts.equal(inventory.get_total_quantity("father_spring_pan_fired_tea"), 2, "sort preserves tea leaves")
	asserts.equal(inventory.get_slot(3), {}, "sort moves empty slots after occupied slots")
	asserts.equal(inventory.get_slot(4), {}, "sort keeps trailing empty slots stable")

func _assert_versioned_snapshot_round_trips(asserts) -> void:
	var inventory := _fixture_inventory(4)
	asserts.true_value(inventory.add_item("clay", 8).ok, "material add succeeds before snapshot")
	asserts.true_value(inventory.add_item("ash_stained_iron_kettle", 1, {"grade_roll": "calm"}).ok, "vessel add succeeds before snapshot")
	var snapshot := inventory.to_snapshot()
	asserts.equal(snapshot.schema_version, InventoryModel.SNAPSHOT_SCHEMA_VERSION, "snapshot is versioned")
	asserts.equal(snapshot.slots.size(), 4, "snapshot preserves slot positions")

	var loaded := _fixture_inventory(4)
	var load_result: Dictionary = loaded.load_snapshot(snapshot)
	asserts.true_value(load_result.ok, "snapshot reload succeeds")
	asserts.equal(loaded.to_snapshot(), snapshot, "snapshot round-trip preserves inventory state")

func _assert_max_owned_rejects_manipulated_snapshot_and_insert(asserts) -> void:
	var inventory := _fixture_inventory(3)
	asserts.true_value(inventory.add_item("item_29", 1).ok, "max-owned fixture accepts one resurrection item")
	var baseline := inventory.to_snapshot()
	var manipulated := baseline.duplicate(true)
	manipulated.slots[1] = {"item_id": "item_29", "quantity": 1, "instance_id": "", "metadata": {}}
	var loaded: Dictionary = inventory.load_snapshot(manipulated)
	asserts.false_value(loaded.ok, "snapshot cannot bypass aggregate max_owned across slots")
	asserts.equal(loaded.reason, "max_owned_exceeded", "snapshot cap failure has a stable reason")
	asserts.equal(inventory.to_snapshot(), baseline, "rejected over-cap snapshot leaves inventory unchanged")

	var inserted: Dictionary = inventory.insert_slot(
		{"item_id": "item_29", "quantity": 1, "instance_id": "", "metadata": {}},
		1
	)
	asserts.false_value(inserted.ok, "slot insertion cannot bypass aggregate max_owned")
	asserts.equal(inserted.reason, "max_owned_exceeded", "insert cap failure has a stable reason")
	asserts.equal(inventory.to_snapshot(), baseline, "rejected over-cap insert leaves inventory unchanged")

func _assert_change_and_failure_events_are_observable(asserts) -> void:
	var inventory := _fixture_inventory(2)
	var changes: Array = []
	var failures: Array = []
	inventory.changed.connect(func(snapshot: Dictionary) -> void:
		changes.append(snapshot)
	)
	inventory.operation_failed.connect(func(error: Dictionary) -> void:
		failures.append(error)
	)
	asserts.true_value(inventory.add_item("clay", 2).ok, "successful add emits a change")
	asserts.false_value(inventory.add_item("missing_item", 1).ok, "failed add emits a failure")
	asserts.equal(changes.size(), 1, "change event emits once for a mutation")
	asserts.equal(changes[0].schema_version, InventoryModel.SNAPSHOT_SCHEMA_VERSION, "change event carries a versioned snapshot")
	asserts.equal(failures.size(), 1, "failure event emits once for a failed command")
	asserts.equal(failures[0].reason, "unknown_item", "failure event carries a stable reason")

func _assert_capacity_expansion_preserves_contents(asserts) -> void:
	var inventory := _fixture_inventory(2)
	asserts.true_value(inventory.add_item("clay", 7).ok, "capacity fixture contains an item before expansion")
	asserts.true_value(inventory.expand_capacity(1000).ok, "inventory capacity can expand for a cheat run")
	asserts.equal(inventory.slot_count, 1000, "expanded inventory exposes the requested slot count")
	asserts.equal(inventory.slots.size(), 1000, "expanded inventory allocates every slot")
	asserts.equal(inventory.get_total_quantity("clay"), 7, "capacity expansion preserves existing items")
	asserts.equal(inventory.to_snapshot().slot_count, 1000, "expanded capacity is included in the run snapshot")
	asserts.false_value(inventory.expand_capacity(999).ok, "capacity expansion API does not silently discard slots")

func _assert_invalid_catalog_values_are_rejected(asserts) -> void:
	var missing_slots: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [],
		"items": [{"id": "clay", "name": "점토", "status": "확정", "type": "재료", "max_stack": 10}],
		"teas": []
	}))
	asserts.false_value(missing_slots.ok, "missing default slot balance is rejected")

	var invalid_stack: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 2}],
		"items": [{"id": "clay", "name": "점토", "status": "확정", "type": "재료", "max_stack": 2.5}],
		"teas": []
	}))
	asserts.false_value(invalid_stack.ok, "fractional max_stack is rejected")

func _fixture_inventory(slot_count: int) -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": slot_count}],
		"items": [
			{"id": "clay", "name": "점토", "status": "확정", "type": "재료", "max_stack": 10},
			{"id": "item_29", "name": "부활 차씨", "status": "확정", "type": "소모품", "effect_type": "부활", "max_stack": 1, "max_owned": 1},
			{"id": "short_travel_sword", "name": "짧은 여행검", "status": "확정", "type": "무기"},
			{"id": "ash_stained_iron_kettle", "name": "재 묻은 철솥", "status": "초안", "type": "다구"}
		],
		"teas": [
			{"id": "father_spring_pan_fired_tea", "name": "아버지의 봄 덖음차", "status": "초안", "max_stack": 6}
		]
	}))
	return result.inventory
