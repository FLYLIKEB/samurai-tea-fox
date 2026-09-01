extends RefCounted
class_name NarrativeConditionResolver

const RUN_FLAG := "run_flag"
const RUN_NOT_FLAG := "run_not_flag"
const CURRENT_BIOME := "current_biome"
const HAS_ITEM := "has_item"
const META_FLAG := "meta_flag"
const META_NOT_FLAG := "meta_not_flag"
const META_RUN_COUNT_AT_LEAST := "meta_run_count_at_least"

const META_CONDITION_TYPES := [META_FLAG, META_NOT_FLAG, META_RUN_COUNT_AT_LEAST]

func resolve(condition: Dictionary, run_query: Dictionary, meta_query := {}) -> Dictionary:
	if condition.is_empty():
		return {"ok": true, "passed": true}
	var condition_type := String(condition.get("type", ""))
	if condition_type.is_empty() or condition_type == "always":
		return {"ok": true, "passed": true}
	match condition_type:
		RUN_FLAG:
			return {"ok": true, "passed": _has_string(run_query.get("flags", []), String(condition.get("id", "")))}
		RUN_NOT_FLAG:
			return {"ok": true, "passed": not _has_string(run_query.get("flags", []), String(condition.get("id", "")))}
		CURRENT_BIOME:
			return {"ok": true, "passed": String(run_query.get("current_biome_id", "")) == String(condition.get("id", ""))}
		HAS_ITEM:
			return {"ok": true, "passed": _inventory_has_item(run_query.get("inventory", {}), String(condition.get("id", "")))}
		META_FLAG:
			return {"ok": true, "passed": _has_string(meta_query.get("dialogue_memory_flags", []), String(condition.get("id", ""))) or _has_string(meta_query.get("unlocked_meta_flags", []), String(condition.get("id", "")))}
		META_NOT_FLAG:
			return {"ok": true, "passed": not (_has_string(meta_query.get("dialogue_memory_flags", []), String(condition.get("id", ""))) or _has_string(meta_query.get("unlocked_meta_flags", []), String(condition.get("id", ""))))}
		META_RUN_COUNT_AT_LEAST:
			return {"ok": true, "passed": int(meta_query.get("run_count", 0)) >= int(condition.get("value", 0))}
	return {"ok": false, "passed": false, "reason": "unknown_condition_type", "error": "Unknown narrative condition type '%s'." % condition_type}

func requires_meta(condition: Dictionary) -> bool:
	return META_CONDITION_TYPES.has(String(condition.get("type", "")))

func _has_string(values, id: String) -> bool:
	if id.is_empty() or typeof(values) != TYPE_ARRAY:
		return false
	return values.has(id)

func _inventory_has_item(inventory, item_id: String) -> bool:
	if item_id.is_empty():
		return false
	if typeof(inventory) == TYPE_DICTIONARY:
		if inventory.has(item_id):
			return int(inventory.get(item_id, 0)) > 0
		var slots = inventory.get("slots", [])
		if typeof(slots) == TYPE_ARRAY:
			for slot in slots:
				if typeof(slot) == TYPE_DICTIONARY and String(slot.get("item_id", "")) == item_id and int(slot.get("quantity", 0)) > 0:
					return true
	if typeof(inventory) == TYPE_ARRAY:
		for entry in inventory:
			if typeof(entry) == TYPE_STRING and entry == item_id:
				return true
			if typeof(entry) == TYPE_DICTIONARY and String(entry.get("item_id", "")) == item_id and int(entry.get("quantity", 0)) > 0:
				return true
	return false
