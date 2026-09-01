extends RefCounted
class_name ConsumableService

const ConsumableDefinition = preload("res://src/consumable/consumable_definition.gd")

const ITEM_SOURCE := "items"
const BALANCE_USE_SECONDS_ID := "consumable_use_base_seconds"
const SNAPSHOT_SCHEMA_VERSION := 1
const CONSUMABLE_KIND := ConsumableDefinition.KIND
const EFFECT_HEAL_HP := ConsumableDefinition.EFFECT_HEAL_HP

signal operation_failed(error: Dictionary)
signal use_started(action: Dictionary)
signal use_completed(result: Dictionary)
signal use_interrupted(action: Dictionary)

var data_version := ""
var use_base_seconds := 0.0
var consumable_definitions: Dictionary = {}
var next_action_id := 1
var _active_action: Dictionary = {}

static func from_catalog(catalog) -> Dictionary:
	var seconds_result := _required_positive_number_balance(catalog, BALANCE_USE_SECONDS_ID)
	if not seconds_result.ok:
		return seconds_result
	var definitions_result := _definitions_from_catalog(catalog, seconds_result.value)
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
	for item_id in new_consumable_definitions:
		var definition = new_consumable_definitions[item_id]
		if not definition is ConsumableDefinition or String(item_id) != definition.id:
			return _fail("invalid_consumable_definition", "Consumable definitions must be keyed by their stable IDs.")
	use_base_seconds = new_use_base_seconds
	consumable_definitions = new_consumable_definitions.duplicate()
	data_version = new_data_version
	next_action_id = 1
	_active_action.clear()
	return {"ok": true}

func has_definition(item_id: String) -> bool:
	return consumable_definitions.has(item_id)

func definition_for(item_id: String) -> Dictionary:
	if not consumable_definitions.has(item_id):
		return {}
	var definition: ConsumableDefinition = consumable_definitions[item_id]
	return definition.to_dictionary()

func start_use(item_id: String, inventory, context := {}) -> Dictionary:
	if not _active_action.is_empty():
		return _fail_and_emit(_fail("active_consumable_action", "A consumable use action is already active."))
	if typeof(context) != TYPE_DICTIONARY:
		return _fail_and_emit(_fail("invalid_consumable_action", "Consumable action context must be a dictionary."))
	if not consumable_definitions.has(item_id):
		return _fail_and_emit(_fail("unknown_consumable", "Unknown consumable definition: %s" % item_id))
	if inventory == null or not inventory.has_method("get_total_quantity") or inventory.get_total_quantity(item_id) < 1:
		return _fail_and_emit(_fail("missing_consumable", "Consumable item is not available: %s" % item_id))
	var definition: ConsumableDefinition = consumable_definitions[item_id]
	var action := {
		"action_id": _next_action_id(),
		"item_id": item_id,
		"elapsed_seconds": 0.0,
		"use_seconds": float(definition.use_seconds),
		"context": _duplicate_dictionary(context),
		"completed": false,
		"interrupted": false
	}
	_active_action = _duplicate_dictionary(action)
	var action_copy := _duplicate_dictionary(_active_action)
	use_started.emit(_duplicate_dictionary(action_copy))
	return {"ok": true, "action": action_copy}

func tick_use(delta_seconds: float, inventory, resources = null) -> Dictionary:
	var action_result := _validate_active_action()
	if not action_result.ok:
		return _fail_and_emit(action_result)
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		return _fail_and_emit(_fail("invalid_delta", "Consumable use delta must be non-negative."))
	_active_action.elapsed_seconds = min(
		float(_active_action.use_seconds),
		float(_active_action.elapsed_seconds) + delta_seconds
	)
	if float(_active_action.elapsed_seconds) < float(_active_action.use_seconds):
		return {"ok": true, "completed": false, "action": _duplicate_dictionary(_active_action)}
	return complete_use(inventory, resources)

func complete_use(inventory, resources = null) -> Dictionary:
	var action_result := _validate_active_action()
	if not action_result.ok:
		return _fail_and_emit(action_result)
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("remove_item"):
		return _fail_and_emit(_fail("invalid_inventory", "Consumable use requires an inventory model."))

	var action := _duplicate_dictionary(_active_action)
	var item_id := String(action.item_id)
	if inventory.get_total_quantity(item_id) < 1:
		return _fail_and_emit(_fail("missing_consumable", "Consumable item is not available: %s" % item_id))
	var definition: ConsumableDefinition = consumable_definitions[item_id]
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
	_active_action.clear()
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

func interrupt_use(reason := "hit") -> Dictionary:
	var action_result := _validate_active_action()
	if not action_result.ok:
		return _fail_and_emit(action_result)
	var interrupted_action := _duplicate_dictionary(_active_action)
	interrupted_action.interrupted = true
	interrupted_action.interrupt_reason = reason
	_active_action.clear()
	use_interrupted.emit(_duplicate_dictionary(interrupted_action))
	return {"ok": true, "action": interrupted_action, "consumed": false}

func to_snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"next_action_id": next_action_id,
		"active_action": _duplicate_dictionary(_active_action)
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported consumable snapshot schema version.")
	var loaded_data_version_result := _normalize_snapshot_data_version(snapshot.get("data_version", data_version))
	if not loaded_data_version_result.ok:
		return loaded_data_version_result
	var loaded_next_action_id_result := _normalize_snapshot_next_action_id(snapshot.get("next_action_id", next_action_id))
	if not loaded_next_action_id_result.ok:
		return loaded_next_action_id_result
	var action_result := _normalize_snapshot_action(snapshot.get("active_action", {}))
	if not action_result.ok:
		return action_result
	var sequence_result := _validate_snapshot_action_sequence(action_result.action, loaded_next_action_id_result.next_action_id)
	if not sequence_result.ok:
		return sequence_result
	var legacy_owners_result := _validate_no_legacy_snapshot_authority(snapshot.get("active_action_owners", {}))
	if not legacy_owners_result.ok:
		return legacy_owners_result
	data_version = loaded_data_version_result.data_version
	next_action_id = loaded_next_action_id_result.next_action_id
	_active_action = _duplicate_dictionary(action_result.action)
	return {"ok": true, "active_action": _duplicate_dictionary(_active_action)}

static func _definitions_from_catalog(catalog, default_use_seconds: float) -> Dictionary:
	var consumables: Dictionary = {}
	for row in _catalog_definitions(catalog, ITEM_SOURCE):
		if String(row.get("type", "")) != CONSUMABLE_KIND:
			continue
		var definition_result := ConsumableDefinition.from_dictionary(row, default_use_seconds)
		if not definition_result.ok:
			return definition_result
		var definition: ConsumableDefinition = definition_result.definition
		consumables[definition.id] = definition
	if consumables.is_empty():
		return _fail("missing_consumable_definitions", "No consumable item definitions were found.")
	return {"ok": true, "consumables": consumables}

func _apply_effect(definition: ConsumableDefinition, _context, resources) -> Dictionary:
	var effect := {
		"type": String(definition.effect_type),
		"hp_healed": 0,
		"hp_heal_requested": 0
	}
	var requested := int(definition.effect_value)
	effect.hp_heal_requested = requested
	effect.hp_healed = int(resources.heal_hp(requested))
	return {"ok": true, "effect": effect}

func _validate_effect_target(definition: ConsumableDefinition, resources) -> Dictionary:
	if String(definition.effect_type) != EFFECT_HEAL_HP:
		return _fail("invalid_effect_type", "Unknown consumable effect type: %s" % definition.effect_type)
	if resources == null or not resources.has_method("heal_hp"):
		return _fail("invalid_resources", "HP healing consumable requires a resource model with heal_hp.")
	return {"ok": true}

func _validate_active_action() -> Dictionary:
	if _active_action.is_empty():
		return _fail("inactive_consumable_action", "No consumable use action is active.")
	var shape_result := _validate_action_shape(_active_action)
	if not shape_result.ok:
		return shape_result
	return {"ok": true}

func _normalize_snapshot_action(raw_action) -> Dictionary:
	if raw_action == null or (typeof(raw_action) == TYPE_DICTIONARY and raw_action.is_empty()):
		return {"ok": true, "action": {}}
	if typeof(raw_action) != TYPE_DICTIONARY:
		return _fail("invalid_consumable_action", "Consumable snapshot action must be a dictionary.")
	var action: Dictionary = _duplicate_dictionary(raw_action)
	var action_result := _validate_action_shape(action)
	if not action_result.ok:
		return action_result
	return {"ok": true, "action": action}

func _normalize_snapshot_data_version(raw_data_version) -> Dictionary:
	if raw_data_version == null:
		return {"ok": true, "data_version": data_version}
	if typeof(raw_data_version) != TYPE_STRING:
		return _fail("invalid_consumable_data_version", "Consumable snapshot data version must be a string.")
	return {"ok": true, "data_version": String(raw_data_version)}

func _normalize_snapshot_next_action_id(raw_next_action_id) -> Dictionary:
	if typeof(raw_next_action_id) != TYPE_INT:
		return _fail("invalid_consumable_next_action_id", "Consumable snapshot next action id must be an integer.")
	var value := int(raw_next_action_id)
	if value < 1:
		return _fail("invalid_consumable_next_action_id", "Consumable snapshot next action id must be positive.")
	return {"ok": true, "next_action_id": value}

func _validate_snapshot_action_sequence(active_action: Dictionary, loaded_next_action_id: int) -> Dictionary:
	if active_action.is_empty():
		return {"ok": true}
	var action_id := String(active_action.action_id)
	var prefix := "consumable_action_"
	if not action_id.begins_with(prefix):
		return _fail("invalid_consumable_action", "Consumable snapshot action id was not generated by the service.")
	var action_number_text := action_id.substr(prefix.length())
	if action_number_text.length() != 6 or not action_number_text.is_valid_int():
		return _fail("invalid_consumable_action", "Consumable snapshot action id has an invalid sequence.")
	var action_number := int(action_number_text)
	if action_number != loaded_next_action_id - 1:
		return _fail("invalid_consumable_next_action_id", "Consumable snapshot next action id is inconsistent with active action.")
	return {"ok": true}

func _validate_action_shape(action: Dictionary) -> Dictionary:
	if action.get("completed", false):
		return _fail("completed_consumable_action", "Consumable action is already completed.")
	if action.get("interrupted", false):
		return _fail("interrupted_consumable_action", "Consumable action is interrupted.")
	if not action.has("action_id") or typeof(action.action_id) != TYPE_STRING or String(action.action_id).is_empty():
		return _fail("invalid_consumable_action", "Consumable action is missing identity.")
	if not action.has("item_id") or typeof(action.item_id) != TYPE_STRING:
		return _fail("invalid_consumable_action", "Consumable action item id must be a string.")
	var item_id := String(action.item_id)
	if item_id.is_empty() or not consumable_definitions.has(item_id):
		return _fail("unknown_consumable", "Unknown consumable definition: %s" % item_id)
	if not action.has("use_seconds") or typeof(action.use_seconds) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail("invalid_consumable_action", "Consumable action use seconds must be numeric.")
	var definition: ConsumableDefinition = consumable_definitions[item_id]
	var action_use_seconds := float(action.use_seconds)
	if action_use_seconds <= 0.0 or not is_finite(action_use_seconds):
		return _fail("invalid_consumable_action", "Consumable action use seconds must be positive.")
	if not is_equal_approx(action_use_seconds, float(definition.use_seconds)):
		return _fail("consumable_timing_mismatch", "Consumable action timing does not match current definition: %s" % item_id)
	if not action.has("elapsed_seconds") or typeof(action.elapsed_seconds) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail("invalid_consumable_action", "Consumable action elapsed seconds must be numeric.")
	var elapsed_seconds := float(action.elapsed_seconds)
	if elapsed_seconds < 0.0 or not is_finite(elapsed_seconds) or elapsed_seconds > action_use_seconds:
		return _fail("invalid_consumable_action", "Consumable action elapsed seconds are out of range.")
	if action.has("context") and typeof(action.context) != TYPE_DICTIONARY:
		return _fail("invalid_consumable_action", "Consumable action context must be a dictionary.")
	return {"ok": true}

func _validate_no_legacy_snapshot_authority(raw_owners) -> Dictionary:
	if raw_owners == null:
		return {"ok": true}
	if typeof(raw_owners) != TYPE_DICTIONARY:
		return _fail("invalid_consumable_action_owners", "Consumable action owners snapshot must be a dictionary.")
	if not raw_owners.is_empty():
		return _fail("legacy_consumable_action_owners", "Consumable action owner snapshots are no longer authoritative.")
	return {"ok": true}

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
