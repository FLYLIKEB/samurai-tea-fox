extends RefCounted
class_name ConsumableService

const ITEM_SOURCE := "items"
const BALANCE_USE_SECONDS_ID := "consumable_use_base_seconds"
const SNAPSHOT_SCHEMA_VERSION := 1
const CONSUMABLE_KIND := "소모품"
const EFFECT_HEAL_HP := "heal_hp"
const VALID_EFFECT_TYPES := {
	EFFECT_HEAL_HP: true
}

signal operation_failed(error: Dictionary)
signal use_started(action: Dictionary)
signal use_completed(result: Dictionary)
signal use_interrupted(action: Dictionary)

var data_version := ""
var use_base_seconds := 0.0
var consumable_definitions: Dictionary = {}
var next_action_id := 1

static func from_catalog(catalog) -> Dictionary:
	var seconds_result := _required_positive_number_balance(catalog, BALANCE_USE_SECONDS_ID)
	if not seconds_result.ok:
		return seconds_result
	var definitions_result := _definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result
	var service: ConsumableService = load("res://src/consumable/consumable_service.gd").new()
	var configure_result := service.configure(
		seconds_result.value,
		definitions_result.consumables,
		_catalog_data_version(catalog)
	)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "consumable_service": service}

func configure(new_use_base_seconds: float, new_consumable_definitions: Dictionary, new_data_version := "") -> Dictionary:
	if new_use_base_seconds <= 0.0 or not is_finite(new_use_base_seconds):
		return _fail("invalid_use_seconds", "Consumable use base seconds must be positive.")
	if new_consumable_definitions.is_empty():
		return _fail("missing_consumable_definitions", "Consumable definitions must not be empty.")
	use_base_seconds = new_use_base_seconds
	consumable_definitions = _duplicate_dictionary(new_consumable_definitions)
	data_version = new_data_version
	next_action_id = 1
	return {"ok": true}

func has_definition(item_id: String) -> bool:
	return consumable_definitions.has(item_id)

func definition_for(item_id: String) -> Dictionary:
	return _duplicate_dictionary(consumable_definitions.get(item_id, {}))

func start_use(item_id: String, inventory, context := {}) -> Dictionary:
	if not consumable_definitions.has(item_id):
		return _fail_and_emit(_fail("unknown_consumable", "Unknown consumable definition: %s" % item_id))
	if inventory == null or not inventory.has_method("get_total_quantity") or inventory.get_total_quantity(item_id) < 1:
		return _fail_and_emit(_fail("missing_consumable", "Consumable item is not available: %s" % item_id))
	var definition: Dictionary = consumable_definitions[item_id]
	var action := {
		"action_id": _next_action_id(),
		"item_id": item_id,
		"elapsed_seconds": 0.0,
		"use_seconds": float(definition.use_seconds),
		"context": _duplicate_dictionary(context),
		"completed": false,
		"interrupted": false
	}
	use_started.emit(_duplicate_dictionary(action))
	return {"ok": true, "action": action}

func tick_use(action: Dictionary, delta_seconds: float, inventory, resources = null) -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		return _fail_and_emit(_fail("invalid_delta", "Consumable use delta must be non-negative."))
	var updated_action := _duplicate_dictionary(action)
	updated_action.elapsed_seconds = min(
		float(updated_action.use_seconds),
		float(updated_action.elapsed_seconds) + delta_seconds
	)
	if float(updated_action.elapsed_seconds) < float(updated_action.use_seconds):
		return {"ok": true, "completed": false, "action": updated_action}
	return complete_use(updated_action, inventory, resources)

func complete_use(action: Dictionary, inventory, resources = null) -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("remove_item"):
		return _fail_and_emit(_fail("invalid_inventory", "Consumable use requires an inventory model."))

	var item_id := String(action.item_id)
	if inventory.get_total_quantity(item_id) < 1:
		return _fail_and_emit(_fail("missing_consumable", "Consumable item is not available: %s" % item_id))
	var definition: Dictionary = consumable_definitions[item_id]
	var resource_result := _validate_effect_target(definition, resources)
	if not resource_result.ok:
		return _fail_and_emit(resource_result)
	var remove_result: Dictionary = inventory.remove_item(item_id, 1)
	if not remove_result.ok:
		return _fail_and_emit(remove_result)
	var effect_result := _apply_effect(definition, action.get("context", {}), resources)
	if not effect_result.ok:
		return _fail_and_emit(effect_result)

	var completed_action := _duplicate_dictionary(action)
	completed_action.completed = true
	completed_action.elapsed_seconds = float(completed_action.use_seconds)
	var result := {
		"ok": true,
		"action": completed_action,
		"item_id": item_id,
		"consumed": true,
		"remaining_quantity": int(inventory.get_total_quantity(item_id)),
		"effect": effect_result.effect
	}
	use_completed.emit(_duplicate_dictionary(result))
	return result

func interrupt_use(action: Dictionary, reason := "hit") -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	var interrupted_action := _duplicate_dictionary(action)
	interrupted_action.interrupted = true
	interrupted_action.interrupt_reason = reason
	use_interrupted.emit(_duplicate_dictionary(interrupted_action))
	return {"ok": true, "action": interrupted_action, "consumed": false}

func to_snapshot(active_action := {}) -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"next_action_id": next_action_id,
		"active_action": _duplicate_dictionary(active_action)
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported consumable snapshot schema version.")
	var action_result := _normalize_snapshot_action(snapshot.get("active_action", {}))
	if not action_result.ok:
		return action_result
	data_version = String(snapshot.get("data_version", data_version))
	next_action_id = max(1, int(snapshot.get("next_action_id", next_action_id)))
	return {"ok": true, "active_action": action_result.action}

static func _definitions_from_catalog(catalog) -> Dictionary:
	var consumables: Dictionary = {}
	for row in _catalog_definitions(catalog, ITEM_SOURCE):
		if String(row.get("type", "")) != CONSUMABLE_KIND:
			continue
		var definition_result := _definition_from_row(row)
		if not definition_result.ok:
			return definition_result
		consumables[definition_result.definition.id] = definition_result.definition
	if consumables.is_empty():
		return _fail("missing_consumable_definitions", "No consumable item definitions were found.")
	return {"ok": true, "consumables": consumables}

static func _definition_from_row(row: Dictionary) -> Dictionary:
	var effect_type := _normalized_effect_type(row)
	if not VALID_EFFECT_TYPES.has(effect_type):
		return _fail("invalid_effect_type", "Unknown consumable effect type: %s" % effect_type)
	var effect_value_result := _required_non_negative_integer(row, "effect_value")
	if not effect_value_result.ok:
		return effect_value_result
	var use_seconds_result := _optional_positive_number(row, "use_seconds", 0.0)
	if not use_seconds_result.ok:
		return use_seconds_result
	var max_stack_result := _optional_positive_integer(row, "max_stack", 1)
	if not max_stack_result.ok:
		return max_stack_result
	return {"ok": true, "definition": {
		"id": String(row.id),
		"name": String(row.get("name", row.id)),
		"status": String(row.get("status", "")),
		"kind": CONSUMABLE_KIND,
		"effect_type": effect_type,
		"effect_value": effect_value_result.value,
		"use_seconds": use_seconds_result.value,
		"max_stack": max_stack_result.value
	}}

func _apply_effect(definition: Dictionary, _context, resources) -> Dictionary:
	var effect := {
		"type": String(definition.effect_type),
		"hp_healed": 0,
		"hp_heal_requested": 0
	}
	if String(definition.effect_type) != EFFECT_HEAL_HP:
		return _fail("invalid_effect_type", "Unknown consumable effect type: %s" % definition.effect_type)
	var requested := int(definition.effect_value)
	effect.hp_heal_requested = requested
	var healed := requested
	if resources != null:
		healed = int(resources.heal_hp(requested))
	effect.hp_healed = healed
	return {"ok": true, "effect": effect}

func _validate_effect_target(definition: Dictionary, resources) -> Dictionary:
	if String(definition.effect_type) == EFFECT_HEAL_HP and resources != null and not resources.has_method("heal_hp"):
		return _fail("invalid_resources", "HP healing consumable requires a resource model with heal_hp.")
	return {"ok": true}

static func _normalized_effect_type(row: Dictionary) -> String:
	var raw := String(row.get("effect_type", row.get("effect", ""))).strip_edges()
	match raw:
		"HP 회복", "체력 회복", "heal_hp":
			return EFFECT_HEAL_HP
		_:
			return raw

func _validate_action(action: Dictionary) -> Dictionary:
	if action.get("completed", false):
		return _fail("completed_consumable_action", "Consumable action is already completed.")
	if action.get("interrupted", false):
		return _fail("interrupted_consumable_action", "Consumable action is interrupted.")
	var item_id := String(action.get("item_id", ""))
	if item_id.is_empty() or not consumable_definitions.has(item_id):
		return _fail("unknown_consumable", "Unknown consumable definition: %s" % item_id)
	if not action.has("action_id") or String(action.action_id).is_empty():
		return _fail("invalid_consumable_action", "Consumable action is missing identity.")
	return {"ok": true}

func _normalize_snapshot_action(raw_action) -> Dictionary:
	if raw_action == null or (typeof(raw_action) == TYPE_DICTIONARY and raw_action.is_empty()):
		return {"ok": true, "action": {}}
	if typeof(raw_action) != TYPE_DICTIONARY:
		return _fail("invalid_consumable_action", "Consumable snapshot action must be a dictionary.")
	var action: Dictionary = _duplicate_dictionary(raw_action)
	var action_result := _validate_action(action)
	if not action_result.ok:
		return action_result
	return {"ok": true, "action": action}

func _next_action_id() -> String:
	var value := "consumable_action_%06d" % next_action_id
	next_action_id += 1
	return value

static func _required_positive_number_balance(catalog, id: String) -> Dictionary:
	if not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Catalog cannot look up balance values.")
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return _fail("missing_balance", "Missing required consumable balance value: %s" % id)
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
		return _fail("invalid_balance", "Consumable balance value must be a positive number: %s" % id)
	return {"ok": true, "value": float(value)}

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
	if float(value_result.value) < 0.0:
		return _fail("invalid_definition", "Definition field must be non-negative: %s.%s" % [row.get("id", ""), field])
	if row.has(field) and row[field] != null and float(value_result.value) <= 0.0:
		return _fail("invalid_definition", "Definition field must be positive: %s.%s" % [row.get("id", ""), field])
	return value_result

static func _catalog_definitions(catalog, dataset: String) -> Array:
	if catalog.has_method("get_definitions"):
		return catalog.get_definitions(dataset)
	var raw_definitions = catalog.get("definitions") if catalog.has_method("get") else {}
	if typeof(raw_definitions) == TYPE_DICTIONARY:
		return raw_definitions.get(dataset, [])
	return []

static func _catalog_data_version(catalog) -> String:
	var value = catalog.get("data_version") if catalog.has_method("get") else ""
	return "" if value == null else String(value)

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
