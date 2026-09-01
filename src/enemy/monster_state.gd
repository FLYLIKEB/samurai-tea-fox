extends RefCounted
class_name MonsterState

signal damaged(event: Dictionary, applied_damage: int)
signal staggered(event: Dictionary, applied_stagger: float)
signal defeated(event: Dictionary)
signal drop_requested(event: Dictionary)

var combat_id: String
var definition_id: String
var definition_snapshot: Dictionary
var hp_max: int
var hp: int
var stagger_resistance: float
var movement_speed: float
var attack: int
var attack_period_seconds: float
var received_damage_events: Array = []
var received_stagger_events: Array = []
var death_events: Array = []

var _defeated_emitted := false

func _init(definition, initial_combat_id: String) -> void:
	combat_id = initial_combat_id
	definition_id = definition.id
	definition_snapshot = definition.to_runtime_snapshot()
	hp_max = definition.hp
	hp = hp_max
	stagger_resistance = definition.stagger_resistance
	movement_speed = definition.movement_speed
	attack = definition.attack
	attack_period_seconds = definition.attack_period_seconds

func get_combat_id() -> String:
	return combat_id

func apply_damage_event(event: Dictionary) -> int:
	var amount := maxi(int(event.get("damage", 0)), 0)
	var applied := mini(amount, hp)
	var recorded := event.duplicate(true)
	recorded["applied_damage"] = applied
	received_damage_events.append(recorded)
	hp -= applied
	if applied > 0:
		damaged.emit(recorded, applied)
	_apply_stagger_from_damage(recorded)
	if hp <= 0:
		_emit_defeat(recorded)
	return applied

func apply_stagger_event(event: Dictionary) -> float:
	var incoming := maxf(float(event.get("stagger", event.get("stagger_amount", 0.0))), 0.0)
	var applied := maxf(incoming - stagger_resistance, 0.0)
	var recorded := event.duplicate(true)
	recorded["applied_stagger"] = applied
	received_stagger_events.append(recorded)
	if applied > 0.0:
		staggered.emit(recorded, applied)
	return applied

func is_defeated() -> bool:
	return hp <= 0

func to_dictionary() -> Dictionary:
	return {
		"combat_id": combat_id,
		"definition_id": definition_id,
		"hp": hp,
		"hp_max": hp_max,
		"stagger_resistance": stagger_resistance,
		"movement_speed": movement_speed,
		"attack": attack,
		"attack_period_seconds": attack_period_seconds
	}

func _apply_stagger_from_damage(event: Dictionary) -> void:
	if event.has("stagger") or event.has("stagger_amount"):
		apply_stagger_event(event)

func _emit_defeat(source_event: Dictionary) -> void:
	if _defeated_emitted:
		return
	_defeated_emitted = true
	var event := {
		"type": "monster_defeated",
		"combat_id": combat_id,
		"definition_id": definition_id,
		"source_id": String(source_event.get("source_id", "")),
		"source_event": source_event.duplicate(true)
	}
	death_events.append(event.duplicate(true))
	defeated.emit(event)
	var drop_event := {
		"type": "monster_drop_requested",
		"combat_id": combat_id,
		"definition_id": definition_id,
		"source_id": event.source_id
	}
	drop_requested.emit(drop_event)
