extends RefCounted
class_name MonsterSpawnFactory

const MonsterDefinition = preload("res://src/enemy/monster_definition.gd")
const MonsterState = preload("res://src/enemy/monster_state.gd")

var catalog
var _sequence_by_definition: Dictionary = {}

func _init(initial_catalog) -> void:
	catalog = initial_catalog

func spawn(monster_id: String, spawn_context := {}) -> Dictionary:
	var definition_result: Dictionary = MonsterDefinition.from_catalog(catalog, monster_id)
	if not definition_result.ok:
		return definition_result
	var combat_id := String(spawn_context.get("combat_id", ""))
	if combat_id == "":
		combat_id = _next_combat_id(monster_id)
	var state := MonsterState.new(definition_result.definition, combat_id)
	return {
		"ok": true,
		"monster": state,
		"definition": definition_result.definition
	}

func _next_combat_id(monster_id: String) -> String:
	var next_sequence := int(_sequence_by_definition.get(monster_id, 0)) + 1
	_sequence_by_definition[monster_id] = next_sequence
	return "%s_%d" % [monster_id, next_sequence]
