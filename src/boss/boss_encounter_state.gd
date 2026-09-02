extends RefCounted
class_name BossEncounterState

const STATE_IDLE := "idle"
const STATE_ACTIVE := "active"
const STATE_RESOLVED := "resolved"
const STATE_ABORTED := "aborted"

var encounter_id := ""
var boss_id := ""
var dungeon_id := ""
var lifecycle_state := STATE_IDLE
var current_hp := 0
var max_hp := 0
var phase_index := 0
var pattern_cursor := 0
var pattern_cooldown_remaining := 0.0
var resolution_event := {}

static func from_dictionary(data: Dictionary):
	var state: BossEncounterState = load("res://src/boss/boss_encounter_state.gd").new()
	state.encounter_id = String(data.get("encounter_id", ""))
	state.boss_id = String(data.get("boss_id", ""))
	state.dungeon_id = String(data.get("dungeon_id", ""))
	state.lifecycle_state = String(data.get("lifecycle_state", STATE_IDLE))
	state.current_hp = int(data.get("current_hp", 0))
	state.max_hp = int(data.get("max_hp", 0))
	state.phase_index = int(data.get("phase_index", 0))
	state.pattern_cursor = int(data.get("pattern_cursor", 0))
	state.pattern_cooldown_remaining = float(data.get("pattern_cooldown_remaining", 0.0))
	state.resolution_event = _dictionary_value(data.get("resolution_event", {}))
	return state

func to_dictionary() -> Dictionary:
	return {
		"schema_version": 1,
		"encounter_id": encounter_id,
		"boss_id": boss_id,
		"dungeon_id": dungeon_id,
		"lifecycle_state": lifecycle_state,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"phase_index": phase_index,
		"pattern_cursor": pattern_cursor,
		"pattern_cooldown_remaining": pattern_cooldown_remaining,
		"resolution_event": resolution_event.duplicate(true)
	}

static func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
