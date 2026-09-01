extends RefCounted
class_name ConsumableDefinition

const KIND := "소모품"
const EFFECT_HEAL_HP := "heal_hp"
const VALID_EFFECT_TYPES := {
	EFFECT_HEAL_HP: true
}

var id: String
var name: String
var status: String
var kind: String
var effect_type: String
var effect_value: int
var use_seconds: float
var max_stack: int

func _init(values := {}) -> void:
	id = String(values.get("id", ""))
	name = String(values.get("name", id))
	status = String(values.get("status", ""))
	kind = String(values.get("kind", KIND))
	effect_type = String(values.get("effect_type", ""))
	effect_value = int(values.get("effect_value", 0))
	use_seconds = float(values.get("use_seconds", 0.0))
	max_stack = int(values.get("max_stack", 1))

static func from_dictionary(row: Dictionary, default_use_seconds: float) -> Dictionary:
	var id := String(row.get("id", ""))
	if id.is_empty():
		return _fail("missing_consumable_id", "Consumable definition is missing a stable id.")
	if default_use_seconds <= 0.0 or not is_finite(default_use_seconds):
		return _fail("invalid_use_seconds", "Consumable use base seconds must be positive.")

	var effect_type := normalized_effect_type(row)
	if not VALID_EFFECT_TYPES.has(effect_type):
		return _fail("invalid_effect_type", "Unknown consumable effect type: %s" % effect_type)

	var effect_value_result := _required_non_negative_integer(row, "effect_value")
	if not effect_value_result.ok:
		return effect_value_result
	var use_seconds_result := _optional_positive_number(row, "use_seconds", default_use_seconds)
	if not use_seconds_result.ok:
		return use_seconds_result
	var max_stack_result := _optional_positive_integer(row, "max_stack", 1)
	if not max_stack_result.ok:
		return max_stack_result

	return {"ok": true, "definition": load("res://src/consumable/consumable_definition.gd").new({
		"id": id,
		"name": String(row.get("name", id)),
		"status": String(row.get("status", "")),
		"kind": KIND,
		"effect_type": effect_type,
		"effect_value": effect_value_result.value,
		"use_seconds": use_seconds_result.value,
		"max_stack": max_stack_result.value
	})}

static func normalized_effect_type(row: Dictionary) -> String:
	var raw := String(row.get("effect_type", row.get("effect", ""))).strip_edges()
	match raw:
		"HP 회복", "체력 회복", EFFECT_HEAL_HP:
			return EFFECT_HEAL_HP
		_:
			return raw

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"status": status,
		"kind": kind,
		"effect_type": effect_type,
		"effect_value": effect_value,
		"use_seconds": use_seconds,
		"max_stack": max_stack
	}

static func _required_non_negative_integer(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Consumable definition is missing required field: %s.%s" % [row.get("id", ""), field])
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	if float(value) != floor(float(value)) or int(value) < 0:
		return _fail("invalid_definition", "Definition field must be a non-negative integer: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": int(value)}

static func _optional_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	if float(value) != floor(float(value)):
		return _fail("invalid_definition", "Definition field must be an integer: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": int(value)}

static func _optional_positive_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	var value_result := _optional_integer(row, field, fallback)
	if not value_result.ok:
		return value_result
	if int(value_result.value) <= 0:
		return _fail("invalid_definition", "Definition field must be a positive integer: %s.%s" % [row.get("id", ""), field])
	return value_result

static func _optional_number(row: Dictionary, field: String, fallback: float) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": float(value)}

static func _optional_positive_number(row: Dictionary, field: String, fallback: float) -> Dictionary:
	var value_result := _optional_number(row, field, fallback)
	if not value_result.ok:
		return value_result
	if float(value_result.value) <= 0.0:
		return _fail("invalid_definition", "Definition field must be positive: %s.%s" % [row.get("id", ""), field])
	return value_result

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
