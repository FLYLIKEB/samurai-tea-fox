extends RefCounted
class_name MetaState

var run_count := 0
var best_reached_biome_order := 0
var discovered_records := []
var unlocked_meta_flags := []
var dialogue_memory_flags := []

static func from_dictionary(data: Dictionary):
	var state: MetaState = load("res://src/save/meta_state.gd").new()
	state.run_count = int(data.get("run_count", 0))
	state.best_reached_biome_order = int(data.get("best_reached_biome_order", 0))
	state.discovered_records = _array_value(data.get("discovered_records", []))
	state.unlocked_meta_flags = _array_value(data.get("unlocked_meta_flags", []))
	state.dialogue_memory_flags = _array_value(data.get("dialogue_memory_flags", []))
	return state

func to_dictionary() -> Dictionary:
	return {
		"run_count": run_count,
		"best_reached_biome_order": best_reached_biome_order,
		"discovered_records": discovered_records.duplicate(true),
		"unlocked_meta_flags": unlocked_meta_flags.duplicate(true),
		"dialogue_memory_flags": dialogue_memory_flags.duplicate(true)
	}

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)
