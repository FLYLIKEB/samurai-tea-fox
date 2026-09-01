extends RefCounted
class_name RunState

var data_version := ""
var seed := 0
var current_biome_id := ""
var inventory := {}
var equipment := {}
var currency := 0
var tails := 1
var abilities := []
var repaired_teleports := []
var crafting_unlocks := []
var narrative_flags := []
var narrative_event_counts := {}

func to_dictionary() -> Dictionary:
	return {
		"data_version": data_version,
		"seed": seed,
		"current_biome_id": current_biome_id,
		"inventory": inventory,
		"equipment": equipment,
		"currency": currency,
		"tails": tails,
		"abilities": abilities,
		"repaired_teleports": repaired_teleports,
		"crafting_unlocks": crafting_unlocks,
		"narrative_flags": narrative_flags,
		"narrative_event_counts": narrative_event_counts
	}
