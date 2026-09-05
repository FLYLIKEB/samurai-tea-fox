extends RefCounted
class_name RunState

const TailState = preload("res://src/player/tail_state.gd")

var data_version := ""
var lifecycle_epoch := 0
var seed := 0
var current_biome_id := ""
var player_cell := {}
var player_resources := {}
var overworld_enemy_state := {}
var inventory := {}
var equipment := {}
var currency := 0
var trade_stock := {}
var tails := 1
var tail_state := TailState.default_dictionary()
var abilities := []
var completed_dungeon_ids := []
var completed_runtime_dungeon_ids := []
var dungeon_runtime_state := {}
var teleport_states := {}
var repaired_teleports := []
var map_discovery := {}
var map_discovery_by_biome := {}
var crafting_unlocks := []
var narrative_flags := []
var narrative_event_counts := {}
var discovered_records := []
var memory_tea_cutscene := {}
var tea := {}
var consumables := {}
var time := {}
var choice_history := []
var choice_group_selections := {}
var target_survival := {}
var philosophy_marks := []
var final_room_effects := []
var core_tea_ware_collection := {}
var acquisitions := {}
var biome_acquisitions := {}
var placed_facilities := []
var world_interactions := {}

static func from_dictionary(data: Dictionary):
	var state: RunState = load("res://src/save/run_state.gd").new()
	state.data_version = String(data.get("data_version", ""))
	state.lifecycle_epoch = int(data.get("lifecycle_epoch", 0))
	state.seed = int(data.get("seed", 0))
	state.current_biome_id = String(data.get("current_biome_id", ""))
	state.player_cell = _dictionary_value(data.get("player_cell", {}))
	state.player_resources = _dictionary_value(data.get("player_resources", {}))
	state.overworld_enemy_state = _dictionary_value(data.get("overworld_enemy_state", {}))
	state.inventory = _dictionary_value(data.get("inventory", {}))
	state.equipment = _dictionary_value(data.get("equipment", {}))
	state.currency = int(data.get("currency", 0))
	state.trade_stock = _dictionary_value(data.get("trade_stock", {}))
	var tail_snapshot: Dictionary = _dictionary_value(data.get("tail_state", {}))
	if tail_snapshot.is_empty():
		tail_snapshot = TailState.from_tail_count(int(data.get("tails", 1))).to_dictionary()
	var tail_result: Dictionary = TailState.from_dictionary(tail_snapshot)
	state.tail_state = tail_result.tail_state.to_dictionary() if tail_result.ok else TailState.default_dictionary()
	state.tails = int(state.tail_state.tail_count)
	state.abilities = _array_value(data.get("abilities", []))
	state.completed_dungeon_ids = _array_value(data.get("completed_dungeon_ids", []))
	state.completed_runtime_dungeon_ids = _array_value(data.get("completed_runtime_dungeon_ids", []))
	state.dungeon_runtime_state = _dictionary_value(data.get("dungeon_runtime_state", {}))
	state.teleport_states = _dictionary_value(data.get("teleport_states", {}))
	state.repaired_teleports = _array_value(data.get("repaired_teleports", []))
	state.map_discovery = _dictionary_value(data.get("map_discovery", {}))
	state.map_discovery_by_biome = _dictionary_value(data.get("map_discovery_by_biome", {}))
	state.crafting_unlocks = _array_value(data.get("crafting_unlocks", []))
	state.narrative_flags = _array_value(data.get("narrative_flags", []))
	state.narrative_event_counts = _dictionary_value(data.get("narrative_event_counts", {}))
	state.discovered_records = _array_value(data.get("discovered_records", []))
	state.memory_tea_cutscene = _dictionary_value(data.get("memory_tea_cutscene", {}))
	state.tea = _dictionary_value(data.get("tea", {}))
	state.consumables = _dictionary_value(data.get("consumables", {}))
	state.time = _dictionary_value(data.get("time", {}))
	state.choice_history = _array_value(data.get("choice_history", []))
	state.choice_group_selections = _dictionary_value(data.get("choice_group_selections", {}))
	state.target_survival = _dictionary_value(data.get("target_survival", {}))
	state.philosophy_marks = _array_value(data.get("philosophy_marks", []))
	state.final_room_effects = _array_value(data.get("final_room_effects", []))
	state.core_tea_ware_collection = _dictionary_value(data.get("core_tea_ware_collection", {}))
	state.acquisitions = _dictionary_value(data.get("acquisitions", {}))
	state.biome_acquisitions = _dictionary_value(data.get("biome_acquisitions", {}))
	state.placed_facilities = _array_value(data.get("placed_facilities", []))
	state.world_interactions = _dictionary_value(data.get("world_interactions", {}))
	return state

func reset_biome_progression() -> void:
	current_biome_id = ""
	completed_dungeon_ids.clear()
	completed_runtime_dungeon_ids.clear()
	dungeon_runtime_state.clear()
	teleport_states.clear()
	repaired_teleports.clear()
	map_discovery.clear()
	map_discovery_by_biome.clear()
	crafting_unlocks.clear()
	acquisitions.clear()
	biome_acquisitions.clear()
	placed_facilities.clear()
	world_interactions.clear()

func reset_run_growth() -> void:
	tails = 1
	tail_state = TailState.default_dictionary()
	abilities.clear()
	core_tea_ware_collection.clear()
	tea.clear()

func to_dictionary() -> Dictionary:
	return {
		"data_version": data_version,
		"lifecycle_epoch": lifecycle_epoch,
		"seed": seed,
		"current_biome_id": current_biome_id,
		"player_cell": player_cell.duplicate(true),
		"player_resources": player_resources.duplicate(true),
		"overworld_enemy_state": overworld_enemy_state.duplicate(true),
		"inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"currency": currency,
		"trade_stock": trade_stock.duplicate(true),
		"tails": tails,
		"tail_state": tail_state.duplicate(true),
		"abilities": abilities.duplicate(true),
		"completed_dungeon_ids": completed_dungeon_ids.duplicate(true),
		"completed_runtime_dungeon_ids": completed_runtime_dungeon_ids.duplicate(true),
		"dungeon_runtime_state": dungeon_runtime_state.duplicate(true),
		"teleport_states": teleport_states.duplicate(true),
		"repaired_teleports": repaired_teleports.duplicate(true),
		"map_discovery": map_discovery.duplicate(true),
		"map_discovery_by_biome": map_discovery_by_biome.duplicate(true),
		"crafting_unlocks": crafting_unlocks.duplicate(true),
		"narrative_flags": narrative_flags.duplicate(true),
		"narrative_event_counts": narrative_event_counts.duplicate(true),
		"discovered_records": discovered_records.duplicate(true),
		"memory_tea_cutscene": memory_tea_cutscene.duplicate(true),
		"tea": tea.duplicate(true),
		"consumables": consumables.duplicate(true),
		"time": time.duplicate(true),
		"choice_history": choice_history.duplicate(true),
		"choice_group_selections": choice_group_selections.duplicate(true),
		"target_survival": target_survival.duplicate(true),
		"philosophy_marks": philosophy_marks.duplicate(true),
		"final_room_effects": final_room_effects.duplicate(true),
		"core_tea_ware_collection": core_tea_ware_collection.duplicate(true),
		"acquisitions": acquisitions.duplicate(true),
		"biome_acquisitions": biome_acquisitions.duplicate(true),
		"placed_facilities": placed_facilities.duplicate(true),
		"world_interactions": world_interactions.duplicate(true)
	}

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)
