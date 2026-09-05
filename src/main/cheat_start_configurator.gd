extends RefCounted
## 치트 시작의 인벤토리·진행 상태만 구성한다. 저장과 장면 연결은 호출자가 수행한다.

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const INVENTORY_SLOT_COUNT := 1000
const RESOURCE_QUANTITY := 99
const RESOURCE_ITEM_TYPE := "재료"
const BANDAGE_QUANTITY := 200

var catalog
var inventory
var equipment
var run_state

func _init(next_catalog, next_inventory, next_equipment, next_run_state) -> void:
	catalog = next_catalog
	inventory = next_inventory
	equipment = next_equipment
	run_state = next_run_state

func apply(snapshot_runtime: Callable) -> Dictionary:
	if inventory == null or catalog == null or not catalog.has_method("get_definitions"):
		return {"ok": false, "reason": "cheat_inventory_unavailable", "error": "Cheat mode requires inventory and item definitions."}
	normalize_cheat_progression_state()

	var inventory_before: Dictionary = inventory.to_snapshot()
	var capacity_result: Dictionary = inventory.expand_capacity(INVENTORY_SLOT_COUNT)
	if not capacity_result.ok:
		return capacity_result
	var resource_item_ids: Array = []
	for definition in catalog.get_definitions("items"):
		if String(definition.get("type", "")) != RESOURCE_ITEM_TYPE:
			continue
		var item_id := String(definition.get("id", ""))
		if item_id.is_empty():
			continue
		var quantity_to_add: int = RESOURCE_QUANTITY - int(inventory.get_total_quantity(item_id))
		if quantity_to_add > 0:
			var add_result: Dictionary = inventory.add_item(item_id, quantity_to_add)
			if not add_result.ok:
				inventory.load_snapshot(inventory_before)
				return add_result
		resource_item_ids.append(item_id)
	var bandage_quantity: int = BANDAGE_QUANTITY - int(inventory.get_total_quantity("bandage"))

	for definition in catalog.get_definitions("biomes"):
		var biome_id := String(definition.get("id", ""))
		if biome_id.is_empty() or not definition.has("progression_order"):
			continue
		if not run_state.completed_dungeon_ids.has(biome_id):
			run_state.completed_dungeon_ids.append(biome_id)
		run_state.teleport_states[biome_id] = BiomeProgressionState.TELEPORT_REPAIRED
		if not run_state.repaired_teleports.has(biome_id):
			run_state.repaired_teleports.append(biome_id)
		if not run_state.crafting_unlocks.has(biome_id):
			run_state.crafting_unlocks.append(biome_id)
	# Cheat mode is a fully-completed run snapshot, not merely an inventory boost.
	run_state.completed_runtime_dungeon_ids.clear()
	run_state.dungeon_runtime_state.clear()
	if bandage_quantity > 0:
		var bandage_result: Dictionary = inventory.add_item("bandage", bandage_quantity)
		if not bandage_result.ok:
			inventory.load_snapshot(inventory_before)
			return bandage_result
	var weapon_id := strongest_weapon_id_for_cheat_start()
	if not weapon_id.is_empty() and equipment != null:
		if inventory_slot_for_item(weapon_id) < 0:
			var weapon_result: Dictionary = inventory.add_item(weapon_id, 1)
			if not weapon_result.ok:
				inventory.load_snapshot(inventory_before)
				return weapon_result
		var weapon_slot := inventory_slot_for_item(weapon_id)
		if weapon_slot >= 0:
			var equip_result: Dictionary = equipment.equip_from_inventory(inventory, weapon_slot)
			if not equip_result.ok:
				inventory.load_snapshot(inventory_before)
				return equip_result
	resource_item_ids.sort()
	snapshot_runtime.call()
	# Cheat-start setup mutates the freshly-created run after its initial save.
	# Advance the lifecycle epoch so subsequent turn saves are newer than the
	# invalidation marker created while starting the run.
	run_state.lifecycle_epoch += 1
	return {
		"ok": true,
		"applied": true,
		"slot_count": inventory.slot_count,
		"resource_quantity": RESOURCE_QUANTITY,
		"bandage_quantity": BANDAGE_QUANTITY,
		"all_biomes_cleared": true,
		"weapon_id": weapon_id,
		"resource_item_ids": resource_item_ids
}

func normalize_cheat_progression_state() -> void:
	if run_state == null or catalog == null:
		return
	for definition in catalog.get_definitions("biomes"):
		var biome_id := String(definition.get("id", ""))
		if biome_id.is_empty() or not definition.has("progression_order"):
			continue
		if not run_state.completed_dungeon_ids.has(biome_id):
			run_state.completed_dungeon_ids.append(biome_id)
		run_state.teleport_states[biome_id] = BiomeProgressionState.TELEPORT_REPAIRED
		if not run_state.repaired_teleports.has(biome_id):
			run_state.repaired_teleports.append(biome_id)
		if not run_state.crafting_unlocks.has(biome_id):
			run_state.crafting_unlocks.append(biome_id)
	run_state.completed_runtime_dungeon_ids.clear()
	run_state.dungeon_runtime_state.clear()

func strongest_weapon_id_for_cheat_start() -> String:
	var best_id := ""
	var best_damage := -1
	for definition in catalog.get_definitions("items"):
		if String(definition.get("type", "")) != "무기":
			continue
		var damage := int(definition.get("base_damage", definition.get("effect_value", 0)))
		if damage > best_damage:
			best_damage = damage
			best_id = String(definition.get("id", ""))
	return best_id

func inventory_slot_for_item(item_id: String) -> int:
	for index in range(inventory.slot_count):
		if String(inventory.get_slot(index).get("item_id", "")) == item_id:
			return index
	return -1
