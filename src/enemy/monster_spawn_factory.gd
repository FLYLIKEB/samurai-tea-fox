extends RefCounted
class_name MonsterSpawnFactory

const MonsterDefinition = preload("res://src/enemy/monster_definition.gd")
const MonsterState = preload("res://src/enemy/monster_state.gd")
const MonsterBehaviorRuntime = preload("res://src/enemy/behavior/monster_behavior_runtime.gd")

var catalog
var _sequence_by_definition: Dictionary = {}

func _init(initial_catalog) -> void:
	catalog = initial_catalog

func spawn(monster_id: String, spawn_context := {}) -> Dictionary:
	var row: Dictionary = catalog.find_by_id("monsters", monster_id)
	if row.is_empty():
		return {"ok": false, "error": "Missing monster definition: %s" % monster_id}
	row = row.duplicate(true)
	var behavior_type_override := String(spawn_context.get("behavior_type_override", ""))
	if not behavior_type_override.is_empty():
		row["behavior_type"] = behavior_type_override
	var definition_result: Dictionary = MonsterDefinition.from_dictionary(row)
	if not definition_result.ok:
		return definition_result
	var combat_id := String(spawn_context.get("combat_id", ""))
	if combat_id == "":
		combat_id = _next_combat_id(monster_id)
	var state := MonsterState.new(definition_result.definition, combat_id)
	var behavior := MonsterBehaviorRuntime.new(definition_result.definition, combat_id)
	state.staggered.connect(behavior.on_staggered)
	return {
		"ok": true,
		"monster": state,
		"behavior": behavior,
		"definition": definition_result.definition
	}

func _next_combat_id(monster_id: String) -> String:
	var next_sequence := int(_sequence_by_definition.get(monster_id, 0)) + 1
	_sequence_by_definition[monster_id] = next_sequence
	return "%s_%d" % [monster_id, next_sequence]
