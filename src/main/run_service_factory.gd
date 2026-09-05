extends RefCounted
## 카탈로그 검증과 기본 런 서비스 생성. Main은 조립된 서비스를 장면에 연결한다.

const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")
const CraftingService = preload("res://src/crafting/crafting_service.gd")
const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const RepairInteractionService = preload("res://src/world/interactions/repair_interaction_service.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")
const CoreTeaWareCollection = preload("res://src/dungeon/core_tea_ware_collection.gd")
const FinalRoomStateBuilder = preload("res://src/meta/final_room_state_builder.gd")

static func create(loaded_catalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(loaded_catalog)
	if not inventory_result.ok:
		return inventory_result
	var equipment_result: Dictionary = EquipmentModel.from_catalog(loaded_catalog)
	if not equipment_result.ok:
		return equipment_result
	var tea_result: Dictionary = TeaService.from_catalog(loaded_catalog)
	if not tea_result.ok:
		return tea_result
	var time_config_result: Dictionary = TimeConfig.from_catalog(loaded_catalog)
	if not time_config_result.ok and catalog_declares_time_balance(loaded_catalog):
		return time_config_result
	var crafting_result: Dictionary = CraftingService.from_catalog(loaded_catalog)
	if not crafting_result.ok:
		return crafting_result
	var facility_placement_result: Dictionary = FacilityPlacementService.from_catalog(loaded_catalog)
	if not facility_placement_result.ok:
		return facility_placement_result
	var repair_interaction_result: Dictionary = RepairInteractionService.from_catalog(loaded_catalog)
	if not repair_interaction_result.ok:
		return repair_interaction_result
	var consumable_result: Dictionary = ConsumableService.from_catalog(loaded_catalog)
	if not consumable_result.ok and String(consumable_result.get("reason", "")) not in ["missing_balance", "missing_consumable_definitions"]:
		return consumable_result
	var core_tea_ware_result: Dictionary = CoreTeaWareCollection.from_catalog(loaded_catalog)
	if not core_tea_ware_result.ok:
		return core_tea_ware_result
	var final_room_result: Dictionary = FinalRoomStateBuilder.from_catalog(loaded_catalog)
	if not final_room_result.ok:
		return final_room_result
	return {
		"ok": true,
		"inventory": inventory_result.inventory,
		"equipment": equipment_result.equipment,
		"tea_service": tea_result.tea_service,
		"time_state": TimeState.new(time_config_result.config) if time_config_result.ok else null,
		"crafting_service": crafting_result.crafting_service,
		"facility_placement_service": facility_placement_result.facility_placement_service,
		"repair_interaction_service": repair_interaction_result.repair_interaction_service,
		"consumable_service": consumable_result.consumable_service if consumable_result.ok else null,
		"core_tea_ware_collection": core_tea_ware_result.collection,
		"final_room_state_builder": final_room_result.builder,
	}

static func catalog_declares_time_balance(loaded_catalog) -> bool:
	if loaded_catalog == null or not loaded_catalog.has_method("find_by_id"):
		return false
	for id in [
		TimeConfig.DAY_DURATION_ID,
		TimeConfig.DUSK_DURATION_ID,
		TimeConfig.NIGHT_DURATION_ID,
		TimeConfig.LATE_NIGHT_DURATION_ID,
		TimeConfig.DUSK_KOKORO_DECAY_ID,
		TimeConfig.NIGHT_KOKORO_DECAY_ID,
		TimeConfig.LATE_NIGHT_KOKORO_DECAY_ID,
		TimeConfig.LOW_KOKORO_ABILITY_COST_INCREASE_ID,
		TimeConfig.SLEEP_HEAL_RATIO_ID
	]:
		if not loaded_catalog.find_by_id("balance", id).is_empty():
			return true
	return false
