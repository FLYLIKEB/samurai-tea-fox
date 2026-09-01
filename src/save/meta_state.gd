extends RefCounted
class_name MetaState

var run_count := 0
var best_reached_biome_order := 0
var discovered_records := []
var unlocked_meta_flags := []
var dialogue_memory_flags := []

func to_dictionary() -> Dictionary:
	return {
		"run_count": run_count,
		"best_reached_biome_order": best_reached_biome_order,
		"discovered_records": discovered_records,
		"unlocked_meta_flags": unlocked_meta_flags,
		"dialogue_memory_flags": dialogue_memory_flags
	}

