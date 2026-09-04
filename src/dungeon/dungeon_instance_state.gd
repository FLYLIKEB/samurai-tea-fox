extends RefCounted
class_name DungeonInstanceState

const STATE_OUTSIDE := "outside"
const STATE_ENTERING := "entering"
const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"
const STATE_RETURNING := "returning"
const STATE_RETURNED := "returned"

const BOSS_FLOW_NONE := "none"
const BOSS_FLOW_PRE_DIALOGUE_PENDING := "pre_dialogue_pending"
const BOSS_FLOW_PRE_DIALOGUE_ACTIVE := "pre_dialogue_active"
const BOSS_FLOW_COMBAT_ACTIVE := "boss_combat_active"
const BOSS_FLOW_RESOLVED := "boss_resolved"

var instance_id := ""
var dungeon_id := ""
var biome_id := ""
var lifecycle_state := STATE_OUTSIDE
var world_data := {}
var player_cell := {}
var enemy_states := {}
var acquisitions := {}
var return_context := {}
var completion_payload := {}
var clear_event := {}
var clear_event_emitted := false
var reward_hook_invoked := false
var reward_claimed := false
var boss_flow_state := BOSS_FLOW_NONE
var boss_id := ""
var boss_encounter_id := ""
var pre_boss_dialogue_event_id := ""
var pre_boss_dialogue_completed := false
var boss_resolution_event := {}

static func from_dictionary(data: Dictionary):
	var state: DungeonInstanceState = load("res://src/dungeon/dungeon_instance_state.gd").new()
	state.instance_id = String(data.get("instance_id", ""))
	state.dungeon_id = String(data.get("dungeon_id", ""))
	state.biome_id = String(data.get("biome_id", ""))
	state.lifecycle_state = String(data.get("lifecycle_state", STATE_OUTSIDE))
	state.world_data = _dictionary_value(data.get("world_data", {}))
	state.player_cell = _dictionary_value(data.get("player_cell", {}))
	state.enemy_states = _dictionary_value(data.get("enemy_states", {}))
	state.acquisitions = _dictionary_value(data.get("acquisitions", {}))
	state.return_context = _dictionary_value(data.get("return_context", {}))
	state.completion_payload = _dictionary_value(data.get("completion_payload", {}))
	state.clear_event = _dictionary_value(data.get("clear_event", {}))
	state.clear_event_emitted = bool(data.get("clear_event_emitted", false))
	state.reward_hook_invoked = bool(data.get("reward_hook_invoked", false))
	state.reward_claimed = bool(data.get("reward_claimed", false))
	state.boss_flow_state = String(data.get("boss_flow_state", BOSS_FLOW_NONE))
	state.boss_id = String(data.get("boss_id", ""))
	state.boss_encounter_id = String(data.get("boss_encounter_id", ""))
	state.pre_boss_dialogue_event_id = String(data.get("pre_boss_dialogue_event_id", ""))
	state.pre_boss_dialogue_completed = bool(data.get("pre_boss_dialogue_completed", false))
	state.boss_resolution_event = _dictionary_value(data.get("boss_resolution_event", {}))
	return state

func to_dictionary() -> Dictionary:
	return {
		"schema_version": 1,
		"instance_id": instance_id,
		"dungeon_id": dungeon_id,
		"biome_id": biome_id,
		"lifecycle_state": lifecycle_state,
		"world_data": world_data.duplicate(true),
		"player_cell": player_cell.duplicate(true),
		"enemy_states": enemy_states.duplicate(true),
		"acquisitions": acquisitions.duplicate(true),
		"return_context": return_context.duplicate(true),
		"completion_payload": completion_payload.duplicate(true),
		"clear_event": clear_event.duplicate(true),
		"clear_event_emitted": clear_event_emitted,
		"reward_hook_invoked": reward_hook_invoked,
		"reward_claimed": reward_claimed,
		"boss_flow_state": boss_flow_state,
		"boss_id": boss_id,
		"boss_encounter_id": boss_encounter_id,
		"pre_boss_dialogue_event_id": pre_boss_dialogue_event_id,
		"pre_boss_dialogue_completed": pre_boss_dialogue_completed,
		"boss_resolution_event": boss_resolution_event.duplicate(true)
	}

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
