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

static func from_dictionary(data: Dictionary):
	var state: RunState = load("res://src/save/run_state.gd").new()
	state.data_version = String(data.get("data_version", ""))
	state.seed = int(data.get("seed", 0))
	state.current_biome_id = String(data.get("current_biome_id", ""))
	state.inventory = _dictionary_value(data.get("inventory", {}))
	state.equipment = _dictionary_value(data.get("equipment", {}))
	state.currency = int(data.get("currency", 0))
	state.tails = int(data.get("tails", 1))
	state.abilities = _array_value(data.get("abilities", []))
	state.completed_dungeon_ids = _array_value(data.get("completed_dungeon_ids", []))
	state.teleport_states = _dictionary_value(data.get("teleport_states", {}))
	state.repaired_teleports = _array_value(data.get("repaired_teleports", []))
	state.crafting_unlocks = _array_value(data.get("crafting_unlocks", []))
	state.narrative_flags = _array_value(data.get("narrative_flags", []))
	state.narrative_event_counts = _dictionary_value(data.get("narrative_event_counts", {}))
	state.consumables = _dictionary_value(data.get("consumables", {}))
	return state

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

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)
