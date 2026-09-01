extends RefCounted
class_name AbilityDefinition

var id: String
var name: String
var type: String
var tail_requirement: int
var ki_cost: int
var cooldown_seconds: float
var base_damage: int
var range_tiles: float
var duration_seconds: float
var status_effect: String

func _init(values := {}) -> void:
	id = String(values.get("id", ""))
	name = String(values.get("name", ""))
	type = String(values.get("type", ""))
	tail_requirement = int(values.get("tail_requirement", 0))
	ki_cost = int(values.get("ki_cost", 0))
	cooldown_seconds = float(values.get("cooldown_seconds", 0.0))
	base_damage = int(values.get("base_damage", 0))
	range_tiles = float(values.get("range", values.get("range_tiles", 0.0)))
	duration_seconds = float(values.get("duration_seconds", 0.0))
	status_effect = String(values.get("status_effect", ""))

static func from_dictionary(values: Dictionary) -> Dictionary:
	for field in ["id", "name", "type", "tail_requirement", "ki_cost", "cooldown_seconds", "base_damage", "range"]:
		if not values.has(field):
			return {"ok": false, "error": "Ability definition '%s' is missing field '%s'" % [values.get("id", ""), field]}

	for field in ["tail_requirement", "ki_cost", "base_damage"]:
		if typeof(values[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[field])) or float(values[field]) != floor(float(values[field])):
			return {"ok": false, "error": "Ability field must be an integer: %s.%s" % [values.get("id", ""), field]}

	for field in ["cooldown_seconds", "range"]:
		if typeof(values[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[field])):
			return {"ok": false, "error": "Ability field must be numeric: %s.%s" % [values.get("id", ""), field]}

	if int(values.tail_requirement) < 0:
		return {"ok": false, "error": "Ability tail requirement must be non-negative: %s" % values.id}
	if int(values.ki_cost) < 0:
		return {"ok": false, "error": "Ability ki cost must be non-negative: %s" % values.id}
	if float(values.cooldown_seconds) < 0.0:
		return {"ok": false, "error": "Ability cooldown must be non-negative: %s" % values.id}
	if int(values.base_damage) < 0:
		return {"ok": false, "error": "Ability damage must be non-negative: %s" % values.id}
	if float(values.range) < 0.0:
		return {"ok": false, "error": "Ability range must be non-negative: %s" % values.id}

	return {"ok": true, "definition": load("res://src/ability/ability_definition.gd").new(values)}

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": type,
		"tail_requirement": tail_requirement,
		"ki_cost": ki_cost,
		"cooldown_seconds": cooldown_seconds,
		"base_damage": base_damage,
		"range_tiles": range_tiles,
		"duration_seconds": duration_seconds,
		"status_effect": status_effect
	}
