extends RefCounted
class_name RuinLootService

const WorldData = preload("res://src/world/data/world_data.gd")

const CATEGORY_WEAPON := "weapon"
const CATEGORY_ARMOR := "armor"
const CATEGORY_TEA := "tea"
const CATEGORIES := [CATEGORY_WEAPON, CATEGORY_ARMOR, CATEGORY_TEA]

func loot(target_id: String, world_seed: int, biome_id: String, catalog, inventory, run_state) -> Dictionary:
	if not target_id.begins_with("%s_" % WorldData.LANDMARK_ABANDONED_HOUSE):
		return _fail("invalid_abandoned_house_target")
	if catalog == null or inventory == null or run_state == null:
		return _fail("missing_runtime")
	var interaction_key := state_key(biome_id, target_id)
	if not run_state.world_interactions.get(interaction_key, {}).is_empty():
		return _fail("already_looted")
	var category := _category_for(target_id)
	var candidates := _candidates_for(category, biome_id, catalog, inventory)
	if candidates.is_empty():
		return _fail("missing_reward_candidates")
	var item: Dictionary = candidates[_roll(world_seed, target_id) % candidates.size()]
	var item_id := String(item.get("id", ""))
	var add_result: Dictionary = inventory.add_item(item_id, 1)
	if not add_result.ok:
		return add_result
	run_state.world_interactions[interaction_key] = {
		"target_id": target_id,
		"biome_id": biome_id,
		"state": "looted",
		"item_id": item_id,
		"quantity": 1
	}
	return {"ok": true, "target_id": target_id, "item_id": item_id, "item_name": String(item.get("name", item_id)), "quantity": 1, "category": category}

static func state_key(biome_id: String, target_id: String) -> String:
	return "%s:%s" % [biome_id, target_id]

func _category_for(target_id: String) -> String:
	var suffix := target_id.trim_prefix("%s_" % WorldData.LANDMARK_ABANDONED_HOUSE)
	return String(CATEGORIES[posmod(int(suffix), CATEGORIES.size())]) if suffix.is_valid_int() else CATEGORY_TEA

func _candidates_for(category: String, biome_id: String, catalog, inventory) -> Array:
	var candidates := []
	var definitions: Array = catalog.get_definitions("teas") if category == CATEGORY_TEA else catalog.get_definitions("items")
	for definition in definitions:
		if String(definition.get("status", "")) != "확정":
			continue
		if category == CATEGORY_WEAPON and String(definition.get("type", "")) != "무기":
			continue
		if category == CATEGORY_ARMOR and String(definition.get("type", "")) != "방어구":
			continue
		if not inventory.has_definition(String(definition.get("id", ""))):
			continue
		var biome_ids = definition.get("biome_ids", [])
		if biome_ids is Array and not biome_ids.is_empty() and biome_id not in biome_ids:
			continue
		candidates.append(definition)
	if candidates.is_empty() and category != CATEGORY_TEA:
		for definition in catalog.get_definitions("items"):
			if String(definition.get("status", "")) == "확정" and inventory.has_definition(String(definition.get("id", ""))) and ((category == CATEGORY_WEAPON and String(definition.get("type", "")) == "무기") or (category == CATEGORY_ARMOR and String(definition.get("type", "")) == "방어구")):
				candidates.append(definition)
	return candidates

func _roll(world_seed: int, target_id: String) -> int:
	var value := posmod(world_seed, 2147483647)
	for byte in target_id.to_utf8_buffer():
		value = posmod(value * 1103515245 + int(byte) + 12345, 2147483647)
	return value

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
