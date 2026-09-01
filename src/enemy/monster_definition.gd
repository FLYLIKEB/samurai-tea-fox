extends RefCounted
class_name MonsterDefinition

const REQUIRED_NUMERIC_FIELDS := ["hp", "stagger_resistance", "movement_speed", "attack", "attack_period_seconds"]

var id: String
var name: String
var status: String
var kind: String
var hp: int
var stagger_resistance: float
var movement_speed: float
var attack: int
var attack_period_seconds: float
var data_snapshot: Dictionary

func _init(values: Dictionary) -> void:
	id = String(values.id)
	name = String(values.get("name", ""))
	status = String(values.get("status", ""))
	kind = String(values.get("kind", ""))
	hp = int(values.hp)
	stagger_resistance = float(values.stagger_resistance)
	movement_speed = float(values.movement_speed)
	attack = int(values.attack)
	attack_period_seconds = float(values.attack_period_seconds)
	data_snapshot = values.duplicate(true)

static func from_catalog(catalog, monster_id: String) -> Dictionary:
	var row: Dictionary = catalog.find_by_id("monsters", monster_id)
	if row.is_empty():
		return {"ok": false, "error": "Missing monster definition: %s" % monster_id}
	return from_dictionary(row)

static func from_dictionary(row: Dictionary) -> Dictionary:
	var validation := validate_row(row)
	if not validation.ok:
		return validation
	return {"ok": true, "definition": load("res://src/enemy/monster_definition.gd").new(row)}

static func validate_row(row: Dictionary) -> Dictionary:
	var monster_id := String(row.get("id", ""))
	if monster_id == "":
		return {"ok": false, "error": "Monster definition is missing id."}
	for field in REQUIRED_NUMERIC_FIELDS:
		if not row.has(field):
			return {"ok": false, "error": "Monster definition is missing required runtime field: %s.%s" % [monster_id, field]}
		var value = row[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {"ok": false, "error": "Monster runtime field must be finite number: %s.%s" % [monster_id, field]}
	if float(row.hp) <= 0.0 or float(row.hp) != floor(float(row.hp)):
		return {"ok": false, "error": "Monster HP must be a positive integer: %s" % monster_id}
	if float(row.attack) < 0.0 or float(row.attack) != floor(float(row.attack)):
		return {"ok": false, "error": "Monster attack must be a non-negative integer: %s" % monster_id}
	if float(row.stagger_resistance) < 0.0:
		return {"ok": false, "error": "Monster stagger resistance must be non-negative: %s" % monster_id}
	if float(row.movement_speed) <= 0.0:
		return {"ok": false, "error": "Monster movement speed must be positive: %s" % monster_id}
	if float(row.attack_period_seconds) <= 0.0:
		return {"ok": false, "error": "Monster attack period must be positive: %s" % monster_id}
	return {"ok": true}

func to_runtime_snapshot() -> Dictionary:
	return data_snapshot.duplicate(true)
