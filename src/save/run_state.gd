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
var completed_dungeon_ids := []
var teleport_states := {}
var repaired_teleports := []
var crafting_unlocks := []
var narrative_flags := []
var narrative_event_counts := {}
var consumables := {}

func reset_biome_progression() -> void:
	current_biome_id = ""
	completed_dungeon_ids.clear()
	teleport_states.clear()
	repaired_teleports.clear()
	crafting_unlocks.clear()

func to_dictionary() -> Dictionary:
	return {
		"data_version": data_version,
		"seed": seed,
		"current_biome_id": current_biome_id,
		"inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"currency": currency,
		"tails": tails,
		"abilities": abilities.duplicate(true),
		"completed_dungeon_ids": completed_dungeon_ids.duplicate(true),
		"teleport_states": teleport_states.duplicate(true),
		"repaired_teleports": repaired_teleports.duplicate(true),
		"crafting_unlocks": crafting_unlocks.duplicate(true),
		"narrative_flags": narrative_flags.duplicate(true),
		"narrative_event_counts": narrative_event_counts.duplicate(true),
		"consumables": consumables.duplicate(true)
	}
