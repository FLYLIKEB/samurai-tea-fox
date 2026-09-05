extends RefCounted

const CombatConfig = preload("res://src/combat/combat_config.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const Main = preload("res://src/main/main.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-equipment"

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
	_assert_generated_catalog_configures_equipment(asserts)
	_assert_equip_unequip_and_replace_preserve_instances(asserts)
	_assert_combat_queries_are_definition_driven(asserts)
	_assert_tea_modifier_query_brews_from_equipped_ware(asserts)
	_assert_drink_completed_signal_accounts_without_manual_call(asserts)
	_assert_tea_ware_attachment_accumulates_from_completed_equipped_use(asserts)
	_assert_tea_ware_attachment_handles_swaps_and_run_reset(asserts)
	_assert_tea_ware_completion_accounting_is_idempotent(asserts)
	_assert_tea_ware_attachment_rejects_invalid_stage_data(asserts)
	_assert_core_and_general_tea_ware_are_distinct(asserts)
	_assert_snapshot_round_trips_equipped_instances(asserts)
	_assert_invalid_slots_and_types_are_rejected(asserts)

func _assert_generated_catalog_configures_equipment(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for equipment")
	var equipment_result: Dictionary = EquipmentModel.from_catalog(catalog)
	asserts.true_value(equipment_result.ok, "equipment initializes from generated catalog")
	if not equipment_result.ok:
		return
	var equipment: EquipmentModel = equipment_result.equipment
	asserts.true_value(equipment.item_definitions.has("short_travel_sword"), "weapon definition is equippable")
	asserts.true_value(equipment.item_definitions.has("traveler_quilted_clothes"), "armor definition is equippable")
	asserts.true_value(equipment.item_definitions.has("oribe_green_glazed_bowl"), "core tea ware definition is equippable")
	asserts.true_value(equipment.item_definitions.has("humble_clay_bowl"), "draft tea ware without redundant slot metadata is equippable")
	asserts.false_value(equipment.item_definitions.has("clay"), "materials are not equippable")
	asserts.equal(equipment.item_definitions.oribe_green_glazed_bowl.tea_recovery_bonus, 10, "generated core tea ware modifier is rebuilt from effect value")
	asserts.true_value(equipment.item_definitions.oribe_green_glazed_bowl.core_tea_ware, "generated core tea ware flag is preserved")
	asserts.equal(equipment.item_definitions.oribe_green_glazed_bowl.core_tea_ware_order, 1, "generated core tea ware order is preserved")
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	asserts.true_value(inventory_result.ok, "generated catalog also configures inventory for draft tea ware")
	if inventory_result.ok:
		var inventory: InventoryModel = inventory_result.inventory
		asserts.true_value(inventory.add_item("humble_clay_bowl", 1).ok, "draft tea ware can enter inventory")
		asserts.true_value(equipment.equip_from_inventory(inventory, 0).ok, "draft tea ware equips from generated inventory")

func _assert_equip_unequip_and_replace_preserve_instances(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("short_travel_sword", 1, {"temper": "calm"}).ok, "first weapon add succeeds")
	asserts.true_value(inventory.add_item("stone_sword", 1, {"temper": "rough"}).ok, "second weapon add succeeds")
	var first_slot := inventory.get_slot(0)
	var second_slot := inventory.get_slot(1)

	var equip_first: Dictionary = equipment.equip_from_inventory(inventory, 0)
	asserts.true_value(equip_first.ok, "weapon equips from inventory")
	asserts.equal(equipment.get_equipped_slot(EquipmentModel.SLOT_WEAPON).instance_id, first_slot.instance_id, "equipped weapon keeps instance id")
	asserts.equal(equipment.get_equipped_slot(EquipmentModel.SLOT_WEAPON).metadata.temper, "calm", "equipped weapon keeps metadata")
	asserts.equal(inventory.get_slot(0), {}, "equipping removes item from inventory slot")

	var replace: Dictionary = equipment.equip_from_inventory(inventory, 1)
	asserts.true_value(replace.ok, "weapon can be replaced")
	asserts.equal(equipment.get_equipped_slot(EquipmentModel.SLOT_WEAPON).instance_id, second_slot.instance_id, "replacement equips new instance")
	asserts.equal(inventory.get_slot(1).instance_id, first_slot.instance_id, "replaced instance returns to source inventory slot")

	var unequip: Dictionary = equipment.unequip_to_inventory(EquipmentModel.SLOT_WEAPON, inventory, 0)
	asserts.true_value(unequip.ok, "weapon can be unequipped")
	asserts.equal(inventory.get_slot(0).instance_id, second_slot.instance_id, "unequip preserves current instance id")
	asserts.equal(equipment.get_equipped_slot(EquipmentModel.SLOT_WEAPON), {}, "equipment slot is empty after unequip")

func _assert_combat_queries_are_definition_driven(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("stone_sword", 1).ok, "weapon add succeeds")
	asserts.true_value(inventory.add_item("linen_armor", 1).ok, "armor add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 0).ok, "weapon equip succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "armor equip succeeds")

	var config := _test_config()
	asserts.true_value(config.apply_weapon_query(equipment.get_weapon_combat_query()).ok, "combat config accepts weapon query")
	asserts.true_value(config.apply_armor_query(equipment.get_armor_combat_query()).ok, "combat config accepts armor query")
	asserts.equal(config.weapon_id, "stone_sword", "weapon id comes from equipped definition")
	asserts.equal(config.weapon_base_damage, 18, "weapon damage comes from equipped definition")
	asserts.equal(config.weapon_range_tiles, 1.4, "weapon range comes from equipped definition")
	asserts.equal(config.weapon_attack_speed, 1.2, "weapon speed comes from equipped definition")
	asserts.equal(config.armor_id, "linen_armor", "armor id comes from equipped definition")
	asserts.equal(config.armor_defense, 5, "armor defense comes from equipped definition")

func _assert_tea_modifier_query_brews_from_equipped_ware(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	var tea_service := _fixture_tea_service()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea leaf add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "tea ware equips")

	var brewed: Dictionary = tea_service.brew_with_modifier_query(
		"green_tea",
		equipment.get_tea_modifier_query(),
		inventory,
		0
	)
	asserts.true_value(brewed.ok, "equipped tea ware modifier can brew")
	asserts.equal(brewed.prepared_tea.vessel_id, "travel_bottle", "prepared tea records equipped tea ware")
	asserts.equal(brewed.prepared_tea.ki_recovery, 25, "modifier recovery is data-driven")
	asserts.equal(brewed.prepared_tea.remaining_uses, 3, "modifier carry uses are data-driven")
	asserts.equal(inventory.get_total_quantity("green_tea"), 0, "brewing consumes tea leaf")
	asserts.equal(inventory.get_total_quantity("travel_bottle"), 0, "equipped tea ware is not still in inventory")

func _assert_drink_completed_signal_accounts_without_manual_call(asserts) -> void:
	var runtime := Main.new()
	var configure_result: Dictionary = runtime._configure_run_services(FakeCatalog.new({
		"balance": [
			{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 8},
			{"id": "tea_quickslot_count", "name": "차 퀵슬롯 수", "status": "테스트", "value": 2},
			{"id": "tea_drink_base_seconds", "name": "차 마시기 기본 시간", "status": "테스트", "value": 1.2}
		],
		"items": _item_rows(),
		"teas": _tea_rows(),
		"recipes": [
			{"id": "clay", "name": "점토 묶음", "status": "테스트", "materials": [], "facility": "손제작", "result_item_id": "clay", "result_quantity": 1}
		],
		"events": [
			{"id": "first_run_prologue", "name": "첫 런 프롤로그", "status": "테스트", "replay_policy": "once", "start_node_id": "start", "run_start": {"min_run_count": 0, "max_run_count": 0, "priority": 1}, "nodes": [{"id": "start", "speaker": "father", "text": "테스트 시작", "options": [{"id": "continue", "display_text": "계속", "completes_event": true, "results": []}]}]}
		]
	}))
	asserts.true_value(configure_result.ok, "production runtime services configure: %s" % JSON.stringify(configure_result))
	asserts.true_value(runtime.inventory.add_item("green_tea", 1).ok, "signal test tea leaf add succeeds")
	asserts.true_value(runtime.inventory.add_item("travel_bottle", 1).ok, "signal test tea ware add succeeds")
	asserts.true_value(runtime.equipment.equip_from_inventory(runtime.inventory, 1).ok, "signal test tea ware equips")

	asserts.true_value(runtime.tea_service.brew_with_modifier_query("green_tea", runtime.equipment.get_tea_modifier_query(), runtime.inventory, 0).ok, "signal test tea brews")
	var start: Dictionary = runtime.tea_service.start_drinking(0)
	asserts.true_value(start.ok, "signal test drink starts")
	asserts.true_value(runtime.tea_service.complete_drinking(start.action).ok, "signal test drink completes")
	asserts.equal(runtime.equipment.get_tea_ware_use_count(), 1, "production drink_completed signal increments use count without manual accounting call")
	runtime.free()

func _assert_tea_ware_attachment_accumulates_from_completed_equipped_use(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	var tea_service := _fixture_tea_service()
	var resources := PlayerResources.new(20, 100, 10, 3)
	asserts.true_value(resources.spend_ki(80), "ki can be lowered for tea recovery")
	asserts.true_value(inventory.add_item("green_tea", 2).ok, "tea leaves add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "tea ware equips")

	var initial_query := equipment.get_tea_modifier_query()
	asserts.equal(equipment.get_tea_ware_use_count(), 0, "newly equipped tea ware starts with zero run uses")
	asserts.equal(equipment.get_tea_ware_attachment_description_key(), "attachment.travel.fresh", "zero uses resolves first description key")
	asserts.equal(initial_query.attachment_description_key, "attachment.travel.fresh", "modifier query exposes current description key")
	asserts.equal(initial_query.tea_recovery_bonus, 2, "attachment adds no tea recovery bonus")

	asserts.true_value(tea_service.brew_with_modifier_query("green_tea", initial_query, inventory, 0).ok, "equipped tea ware brews")
	var start: Dictionary = tea_service.start_drinking(0)
	asserts.true_value(start.ok, "drink starts")
	asserts.equal(equipment.get_tea_ware_use_count(), 0, "drink start does not count as vessel use")
	var interrupt: Dictionary = tea_service.interrupt_drinking(start.action, "hit")
	asserts.true_value(interrupt.ok, "drink interrupts")
	asserts.false_value(equipment.record_tea_ware_use_completion(interrupt).ok, "interruption is rejected for accounting")
	asserts.equal(equipment.get_tea_ware_use_count(), 0, "interruption does not count as vessel use")

	var partial_start: Dictionary = tea_service.start_drinking(0)
	var partial: Dictionary = tea_service.tick_drinking(partial_start.action, 0.1, resources)
	asserts.true_value(partial.ok, "partial tick succeeds")
	asserts.false_value(equipment.record_tea_ware_use_completion({"ok": true, "consumed": false, "action": partial.action}).ok, "partial use is rejected for accounting")
	asserts.equal(equipment.get_tea_ware_use_count(), 0, "partial tick does not count as vessel use")

	var first_complete: Dictionary = tea_service.complete_drinking(partial.action, resources)
	asserts.true_value(first_complete.ok, "first use completes")
	var first_accounting: Dictionary = equipment.record_tea_ware_use_completion(first_complete, inventory)
	asserts.true_value(first_accounting.accounted, "matching equipped vessel completion is accounted")
	asserts.equal(first_accounting.use_count, 1, "first completion increments use count")
	asserts.equal(first_accounting.description_key, "attachment.travel.fresh", "count below second threshold stays in first stage")

	var second_complete: Dictionary = _complete_prepared_use(tea_service, resources)
	asserts.true_value(equipment.record_tea_ware_use_completion(second_complete, inventory).accounted, "second completion is accounted")
	asserts.equal(equipment.get_tea_ware_use_count(), 2, "second completion reaches second threshold")
	asserts.equal(equipment.get_tea_ware_attachment_description_key(), "attachment.travel.warmed", "second threshold resolves second description key")

	var third_complete: Dictionary = _complete_prepared_use(tea_service, resources)
	asserts.true_value(equipment.record_tea_ware_use_completion(third_complete, inventory).accounted, "third carried use is accounted")
	asserts.equal(equipment.get_tea_ware_attachment_description_key(), "attachment.travel.warmed", "third use remains second stage")

	asserts.true_value(tea_service.brew_with_modifier_query("green_tea", equipment.get_tea_modifier_query(), inventory, 0).ok, "second brew succeeds after carried uses are gone")
	var fourth_complete: Dictionary = _complete_prepared_use(tea_service, resources)
	asserts.true_value(equipment.record_tea_ware_use_completion(fourth_complete, inventory).accounted, "fourth completion is accounted")
	asserts.equal(equipment.get_tea_ware_use_count(), 4, "fourth completion reaches final tested threshold")
	asserts.equal(equipment.get_tea_ware_attachment_description_key(), "attachment.travel.seasoned", "fourth use resolves third description key")

	var after_query := equipment.get_tea_modifier_query()
	asserts.equal(after_query.tea_recovery_multiplier, initial_query.tea_recovery_multiplier, "attachment does not change tea recovery multiplier")
	asserts.equal(after_query.tea_recovery_bonus, initial_query.tea_recovery_bonus, "attachment does not change tea recovery bonus")
	asserts.equal(after_query.carry_use_bonus, initial_query.carry_use_bonus, "attachment does not change carried uses")
	asserts.equal(after_query.drink_seconds_multiplier, initial_query.drink_seconds_multiplier, "attachment does not change drink speed")
	asserts.equal(after_query.sustain_modifier, initial_query.sustain_modifier, "attachment does not change sustain modifier")

func _assert_tea_ware_attachment_handles_swaps_and_run_reset(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	var tea_service := _fixture_tea_service()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "tea leaf add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "first tea ware add succeeds")
	asserts.true_value(inventory.add_item("oribe_bowl", 1).ok, "second tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "first tea ware equips")
	var travel_instance_id := String(equipment.get_equipped_slot(EquipmentModel.SLOT_TEA_WARE).instance_id)
	asserts.true_value(tea_service.brew_with_modifier_query("green_tea", equipment.get_tea_modifier_query(), inventory, 0).ok, "tea brews with first tea ware")
	var start: Dictionary = tea_service.start_drinking(0)
	asserts.equal(start.action.vessel_instance_id, travel_instance_id, "drink action captures brewing vessel instance")
	asserts.true_value(equipment.equip_from_inventory(inventory, 2).ok, "swap equips second tea ware")

	var complete: Dictionary = tea_service.complete_drinking(start.action)
	var accounting: Dictionary = equipment.record_tea_ware_use_completion(complete, inventory)
	asserts.true_value(accounting.ok, "swapped-away completion is handled without failure")
	asserts.true_value(accounting.accounted, "swapped-away vessel completion accounts to original run-owned instance")
	asserts.equal(accounting.source, "inventory", "swap completion finds original vessel in inventory")
	var original_slot: Dictionary = inventory.get_slot(int(accounting.inventory_slot))
	asserts.equal(original_slot.instance_id, travel_instance_id, "original vessel returned to inventory")
	asserts.equal(original_slot.metadata.tea_ware_use_count, 1, "original inventory vessel gains completion metadata")
	asserts.equal(equipment.get_tea_ware_use_count(), 0, "replacement tea ware did not inherit prior vessel use")

	var reset_inventory := _fixture_inventory()
	var reset_equipment := _fixture_equipment()
	asserts.true_value(reset_inventory.add_item("travel_bottle", 1).ok, "reset run tea ware add succeeds")
	asserts.true_value(reset_equipment.equip_from_inventory(reset_inventory, 0).ok, "reset run tea ware equips")
	asserts.equal(reset_equipment.get_equipped_slot(EquipmentModel.SLOT_TEA_WARE).metadata, {}, "fresh run has no carried attachment metadata")
	asserts.equal(reset_equipment.get_tea_ware_use_count(), 0, "fresh run resets tea ware use count")

func _assert_tea_ware_completion_accounting_is_idempotent(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	var tea_service := _fixture_tea_service()
	asserts.true_value(inventory.add_item("green_tea", 1).ok, "idempotency tea leaf add succeeds")
	asserts.true_value(inventory.add_item("travel_bottle", 1).ok, "idempotency tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "idempotency tea ware equips")
	asserts.true_value(tea_service.brew_with_modifier_query("green_tea", equipment.get_tea_modifier_query(), inventory, 0).ok, "idempotency tea brews")
	var complete: Dictionary = _complete_prepared_use(tea_service, null)
	var first: Dictionary = equipment.record_tea_ware_use_completion(complete, inventory)
	var duplicate: Dictionary = equipment.record_tea_ware_use_completion(complete, inventory)
	asserts.true_value(first.accounted, "first stable completion is accounted")
	asserts.false_value(duplicate.accounted, "duplicate stable completion is a no-op")
	asserts.equal(duplicate.reason, "duplicate_completion", "duplicate completion reports idempotent reason")
	asserts.equal(equipment.get_tea_ware_use_count(), 1, "duplicate completion does not increment use count twice")

	var snapshot := equipment.to_snapshot()
	var loaded := _fixture_equipment()
	asserts.true_value(loaded.load_snapshot(snapshot).ok, "idempotency snapshot reload succeeds")
	var after_load_duplicate: Dictionary = loaded.record_tea_ware_use_completion(complete, inventory)
	asserts.false_value(after_load_duplicate.accounted, "loaded snapshot preserves accounted completion id")
	asserts.equal(loaded.get_tea_ware_use_count(), 1, "loaded duplicate does not increment after snapshot roundtrip")

func _assert_tea_ware_attachment_rejects_invalid_stage_data(asserts) -> void:
	var too_few_stages := _item_rows()
	too_few_stages.append({"id": "bad_bowl", "name": "나쁜 사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 0, "attachment_stage_thresholds": [0, 2], "attachment_description_keys": ["a", "b"]})
	asserts.false_value(EquipmentModel.from_catalog(FakeCatalog.new({"items": too_few_stages})).ok, "tea ware attachment requires at least three stages")

	var missing_stages := _item_rows()
	missing_stages.append({"id": "missing_stage_bowl", "name": "누락 사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 0, "attachment_description_keys": ["a", "b", "c"]})
	asserts.false_value(EquipmentModel.from_catalog(FakeCatalog.new({"items": missing_stages})).ok, "tea ware attachment stage data is required")

	var unordered_stages := _item_rows()
	unordered_stages.append({"id": "bad_cup", "name": "나쁜 잔", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 0, "attachment_stage_thresholds": [0, 3, 3], "attachment_description_keys": ["a", "b", "c"]})
	asserts.false_value(EquipmentModel.from_catalog(FakeCatalog.new({"items": unordered_stages})).ok, "tea ware attachment thresholds must ascend")

func _assert_core_and_general_tea_ware_are_distinct(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("plain_bowl", 1).ok, "general tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 0).ok, "general tea ware equips")
	asserts.false_value(equipment.get_tea_modifier_query().core_tea_ware, "general tea ware is not core")
	asserts.equal(equipment.get_tea_modifier_query().core_tea_ware_order, 0, "general tea ware has no core order")
	asserts.true_value(equipment.unequip_to_inventory(EquipmentModel.SLOT_TEA_WARE, inventory, 0).ok, "general tea ware unequips")

	asserts.true_value(inventory.add_item("oribe_bowl", 1).ok, "core tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "core tea ware equips")
	asserts.true_value(equipment.get_tea_modifier_query().core_tea_ware, "core tea ware flag comes from definition")
	asserts.equal(equipment.get_tea_modifier_query().core_tea_ware_order, 1, "core tea ware order comes from definition")
	asserts.equal(equipment.get_tea_modifier_query().tea_recovery_bonus, 10, "core tea ware modifier is regenerated from effect value")

func _assert_snapshot_round_trips_equipped_instances(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("short_travel_sword", 1, {"mark": "kept"}).ok, "weapon add succeeds")
	asserts.true_value(inventory.add_item("linen_armor", 1).ok, "armor add succeeds")
	asserts.true_value(inventory.add_item("oribe_bowl", 1).ok, "tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 0).ok, "weapon equips")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "armor equips")
	asserts.true_value(equipment.equip_from_inventory(inventory, 2).ok, "tea ware equips")
	equipment.equipped_slots[EquipmentModel.SLOT_TEA_WARE].metadata[EquipmentModel.METADATA_TEA_WARE_USE_COUNT] = 4

	var snapshot := equipment.to_snapshot()
	asserts.equal(snapshot.schema_version, EquipmentModel.SNAPSHOT_SCHEMA_VERSION, "equipment snapshot is versioned")
	var loaded := _fixture_equipment()
	var load_result: Dictionary = loaded.load_snapshot(snapshot)
	asserts.true_value(load_result.ok, "equipment snapshot reload succeeds")
	asserts.equal(loaded.to_snapshot(), snapshot, "equipment snapshot preserves slots and instances")
	asserts.equal(loaded.get_equipped_slot(EquipmentModel.SLOT_WEAPON).metadata.mark, "kept", "equipment snapshot preserves metadata")
	asserts.equal(loaded.get_tea_ware_use_count(), 4, "equipment snapshot preserves per-run tea ware use count")
	asserts.equal(loaded.get_tea_ware_attachment_description_key(), "items.oribe_bowl.attachment.stage_1", "loaded tea ware resolves description key from metadata")

func _assert_invalid_slots_and_types_are_rejected(asserts) -> void:
	var invalid_weapon_type: Dictionary = EquipmentModel.from_catalog(FakeCatalog.new({
		"items": [{"id": "bad_weapon", "name": "나쁜 무기", "status": "테스트", "type": "재료", "equipment_slot": "무기", "base_damage": 1, "range": 1.0, "attack_speed": 1.0, "effect_type": "공격"}]
	}))
	asserts.false_value(invalid_weapon_type.ok, "equipment type mismatch is rejected")

	var invalid_weapon_effect: Dictionary = EquipmentModel.from_catalog(FakeCatalog.new({
		"items": [{"id": "bad_weapon", "name": "나쁜 무기", "status": "테스트", "type": "무기", "equipment_slot": "무기", "base_damage": 1, "range": 1.0, "attack_speed": 1.0, "effect_type": "방어"}]
	}))
	asserts.false_value(invalid_weapon_effect.ok, "wrong weapon effect type is rejected")

	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("clay", 1).ok, "material add succeeds")
	asserts.false_value(equipment.equip_from_inventory(inventory, 0).ok, "non-equipment item cannot be equipped")

	var invalid_snapshot := {
		"schema_version": EquipmentModel.SNAPSHOT_SCHEMA_VERSION,
		"slots": {
			EquipmentModel.SLOT_WEAPON: {"item_id": "linen_armor", "quantity": 1, "instance_id": "inst_bad", "metadata": {}}
		}
	}
	asserts.false_value(equipment.load_snapshot(invalid_snapshot).ok, "snapshot rejects item in wrong slot")

func _fixture_equipment() -> EquipmentModel:
	var result: Dictionary = EquipmentModel.from_catalog(FakeCatalog.new({"items": _item_rows()}))
	return result.equipment

func _fixture_inventory() -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 8}],
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	return result.inventory

func _fixture_tea_service() -> TeaService:
	var result: Dictionary = TeaService.from_catalog(FakeCatalog.new({
		"balance": [
			{"id": "tea_quickslot_count", "name": "차 퀵슬롯 수", "status": "테스트", "value": 2},
			{"id": "tea_drink_base_seconds", "name": "차 마시기 기본 시간", "status": "테스트", "value": 1.2}
		],
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	return result.tea_service

func _complete_prepared_use(tea_service: TeaService, resources) -> Dictionary:
	var start: Dictionary = tea_service.start_drinking(0)
	if not start.ok:
		return start
	return tea_service.complete_drinking(start.action, resources)

func _test_config() -> CombatConfig:
	var result: Dictionary = CombatConfig.from_catalog(FakeCatalog.new({
		"balance": [
			{"id": "basic_attack_combo_hits", "value": 3},
			{"id": "basic_combo_finisher_knockback_tiles", "value": 0.5},
			{"id": "dodge_cooldown_seconds", "value": 0.9},
			{"id": "dodge_distance_tiles", "value": 1.8},
			{"id": "dodge_invulnerability_seconds", "value": 0.18},
			{"id": "ki_attack_multiplier_0", "value": 0.7},
			{"id": "ki_attack_multiplier_100", "value": 1.3},
			{"id": "ki_max", "value": 100},
			{"id": "hit_invulnerability_seconds", "value": 0.2}
		],
		"items": [{"id": "short_travel_sword", "base_damage": 14, "range": 1.15, "attack_speed": 1.0}]
	}))
	return result.config

func _item_rows() -> Array:
	return [
		{"id": "clay", "name": "점토", "status": "확정", "type": "재료", "max_stack": 10},
		{"id": "short_travel_sword", "name": "짧은 여행검", "status": "확정", "type": "무기", "equipment_slot": "무기", "max_stack": 1, "base_damage": 14, "range": 1.15, "attack_speed": 1.0, "effect_type": "공격", "effect_value": 14},
		{"id": "stone_sword", "name": "산철검", "status": "테스트", "type": "무기", "equipment_slot": "무기", "max_stack": 1, "base_damage": 18, "range": 1.4, "attack_speed": 1.2, "effect_type": "공격", "effect_value": 18},
		{"id": "linen_armor", "name": "누비옷", "status": "테스트", "type": "방어구", "equipment_slot": "방어구", "max_stack": 1, "defense": 5, "effect_type": "방어", "effect_value": 5},
		{"id": "plain_bowl", "name": "소박한 사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 0, "core_tea_ware": false, "attachment_stage_thresholds": [0, 3, 7], "attachment_description_keys": ["items.plain_bowl.attachment.stage_0", "items.plain_bowl.attachment.stage_1", "items.plain_bowl.attachment.stage_2"]},
		{"id": "travel_bottle", "name": "보온 차병", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 2, "core_tea_ware": false, "tea_recovery_multiplier": 1.25, "carry_use_bonus": 2, "drink_seconds_multiplier": 0.5, "drink_seconds_bonus": 0.1, "sustain_modifier": 0.25, "attachment_stage_thresholds": [0, 2, 4], "attachment_description_keys": ["attachment.travel.fresh", "attachment.travel.warmed", "attachment.travel.seasoned"]},
		{"id": "oribe_bowl", "name": "오리베 찻사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 10, "core_tea_ware": "__YES__", "core_tea_ware_order": 1, "attachment_stage_thresholds": [0, 3, 7], "attachment_description_keys": ["items.oribe_bowl.attachment.stage_0", "items.oribe_bowl.attachment.stage_1", "items.oribe_bowl.attachment.stage_2"]}
	]

func _tea_rows() -> Array:
	return [
		{"id": "green_tea", "name": "녹차", "status": "테스트", "ki_recovery": 18, "sustain_modifier": 0.1, "max_stack": 4}
	]
