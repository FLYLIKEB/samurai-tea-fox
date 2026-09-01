extends RefCounted

const CombatConfig = preload("res://src/combat/combat_config.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const TeaService = preload("res://src/tea/tea_service.gd")

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
	asserts.false_value(equipment.item_definitions.has("clay"), "materials are not equippable")

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

func _assert_snapshot_round_trips_equipped_instances(asserts) -> void:
	var inventory := _fixture_inventory()
	var equipment := _fixture_equipment()
	asserts.true_value(inventory.add_item("short_travel_sword", 1, {"mark": "kept"}).ok, "weapon add succeeds")
	asserts.true_value(inventory.add_item("linen_armor", 1).ok, "armor add succeeds")
	asserts.true_value(inventory.add_item("oribe_bowl", 1).ok, "tea ware add succeeds")
	asserts.true_value(equipment.equip_from_inventory(inventory, 0).ok, "weapon equips")
	asserts.true_value(equipment.equip_from_inventory(inventory, 1).ok, "armor equips")
	asserts.true_value(equipment.equip_from_inventory(inventory, 2).ok, "tea ware equips")

	var snapshot := equipment.to_snapshot()
	asserts.equal(snapshot.schema_version, EquipmentModel.SNAPSHOT_SCHEMA_VERSION, "equipment snapshot is versioned")
	var loaded := _fixture_equipment()
	var load_result: Dictionary = loaded.load_snapshot(snapshot)
	asserts.true_value(load_result.ok, "equipment snapshot reload succeeds")
	asserts.equal(loaded.to_snapshot(), snapshot, "equipment snapshot preserves slots and instances")
	asserts.equal(loaded.get_equipped_slot(EquipmentModel.SLOT_WEAPON).metadata.mark, "kept", "equipment snapshot preserves metadata")

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
		{"id": "plain_bowl", "name": "소박한 사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 0, "core_tea_ware": false},
		{"id": "travel_bottle", "name": "보온 차병", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 2, "core_tea_ware": false, "tea_recovery_multiplier": 1.25, "tea_recovery_bonus": 2, "carry_use_bonus": 2, "drink_seconds_multiplier": 0.5, "drink_seconds_bonus": 0.1, "sustain_modifier": 0.25},
		{"id": "oribe_bowl", "name": "오리베 찻사발", "status": "테스트", "type": "다구", "equipment_slot": "다구", "max_stack": 1, "effect_type": "차 운용", "effect_value": 10, "core_tea_ware": "__YES__", "core_tea_ware_order": 1, "tea_recovery_bonus": 10}
	]

func _tea_rows() -> Array:
	return [
		{"id": "green_tea", "name": "녹차", "status": "테스트", "ki_recovery": 18, "sustain_modifier": 0.1, "max_stack": 4}
	]
