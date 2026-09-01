extends RefCounted
class_name CombatantState

var combat_id: String
var definition_id: String
var hp_max: int
var hp: int
var attack: int
var received_damage_events: Array = []

func _init(initial_combat_id: String, initial_hp_max: int, initial_attack: int, initial_definition_id := "") -> void:
	combat_id = initial_combat_id
	definition_id = initial_definition_id
	hp_max = maxi(initial_hp_max, 1)
	hp = hp_max
	attack = maxi(initial_attack, 0)

static func from_catalog(catalog, monster_id := "road_bandit", instance_id := "") -> Dictionary:
	var definition: Dictionary = catalog.find_by_id("monsters", monster_id)
	if definition.is_empty():
		return {"ok": false, "error": "Missing monster definition: %s" % monster_id}
	for field in ["hp", "attack"]:
		var value = definition.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {"ok": false, "error": "Monster field must be a non-negative number: %s.%s" % [monster_id, field]}
		if float(value) != floor(float(value)):
			return {"ok": false, "error": "Monster field must be an integer: %s.%s" % [monster_id, field]}
	if int(definition.hp) <= 0:
		return {"ok": false, "error": "Monster HP must be positive: %s" % monster_id}
	var combat_id := instance_id
	if combat_id == "":
		combat_id = monster_id
	var hp_value := int(definition.hp)
	var attack_value := int(definition.attack)
	return {
		"ok": true,
		"combatant": load("res://src/combat/combatant_state.gd").new(combat_id, hp_value, attack_value, monster_id)
	}

func get_combat_id() -> String:
	return combat_id

func apply_damage_event(event: Dictionary) -> int:
	var amount := maxi(int(event.get("damage", 0)), 0)
	var applied := mini(amount, hp)
	hp -= applied
	received_damage_events.append(event.duplicate(true))
	return applied

func is_defeated() -> bool:
	return hp <= 0

func to_dictionary() -> Dictionary:
	return {
		"combat_id": combat_id,
		"definition_id": definition_id,
		"hp": hp,
		"hp_max": hp_max,
		"attack": attack
	}
