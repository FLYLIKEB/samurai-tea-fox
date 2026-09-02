extends RefCounted
class_name MetaState

var run_count := 0
var best_reached_biome_order := 0
var discovered_records := []
var unlocked_meta_flags := []
var dialogue_memory_flags := []
var meta_unlock_counters := {}
var past_choice_ids := []
var reached_place_ids := []
var death_record_ids := []

static func from_dictionary(data: Dictionary):
	var state: MetaState = load("res://src/save/meta_state.gd").new()
	state.run_count = int(data.get("run_count", 0))
	state.best_reached_biome_order = int(data.get("best_reached_biome_order", 0))
	state.discovered_records = _array_value(data.get("discovered_records", []))
	state.unlocked_meta_flags = _array_value(data.get("unlocked_meta_flags", []))
	state.dialogue_memory_flags = _array_value(data.get("dialogue_memory_flags", []))
	state.meta_unlock_counters = _dictionary_value(data.get("meta_unlock_counters", {}))
	state.past_choice_ids = _array_value(data.get("past_choice_ids", []))
	state.reached_place_ids = _array_value(data.get("reached_place_ids", []))
	state.death_record_ids = _array_value(data.get("death_record_ids", []))
	return state

func to_dictionary() -> Dictionary:
	return {
		"run_count": run_count,
		"best_reached_biome_order": best_reached_biome_order,
		"discovered_records": discovered_records.duplicate(true),
		"unlocked_meta_flags": unlocked_meta_flags.duplicate(true),
		"dialogue_memory_flags": dialogue_memory_flags.duplicate(true),
		"meta_unlock_counters": meta_unlock_counters.duplicate(true),
		"past_choice_ids": past_choice_ids.duplicate(true),
		"reached_place_ids": reached_place_ids.duplicate(true),
		"death_record_ids": death_record_ids.duplicate(true)
	}

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)
