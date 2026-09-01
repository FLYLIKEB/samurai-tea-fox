extends RefCounted
class_name TeaService

const BALANCE_DRINK_SECONDS_ID := "tea_drink_base_seconds"
const BALANCE_QUICKSLOT_COUNT_ID := "tea_quickslot_count"
const ITEM_SOURCE := "items"
const TEA_SOURCE := "teas"
const VESSEL_KIND := "다구"
const BREW_LEAF_UNITS := 1
const SNAPSHOT_SCHEMA_VERSION := 1
const DEFAULT_CARRY_USES := 1
const DEFAULT_RECOVERY_MODE := "instant"
const RECOVERY_INSTANT := "instant"
const RECOVERY_PROGRESSIVE := "progressive"
const RECOVERY_CONDITIONAL := "conditional"
const VALID_RECOVERY_MODES := {
	RECOVERY_INSTANT: true,
	RECOVERY_PROGRESSIVE: true,
	RECOVERY_CONDITIONAL: true
}

signal changed(snapshot: Dictionary)
signal operation_failed(error: Dictionary)
signal tea_prepared(prepared_tea: Dictionary)
signal drink_started(action: Dictionary)
signal drink_completed(result: Dictionary)
signal drink_interrupted(action: Dictionary)

var data_version := ""
var quickslot_count := 0
var drink_base_seconds := 0.0
var tea_definitions: Dictionary = {}
var vessel_definitions: Dictionary = {}
var quick_slots: Array = []
var next_prepared_id := 1
var next_action_id := 1

static func from_catalog(catalog) -> Dictionary:
	var quickslot_result := _required_positive_integer_balance(catalog, BALANCE_QUICKSLOT_COUNT_ID)
	if not quickslot_result.ok:
		return quickslot_result
	var drink_seconds_result := _required_positive_number_balance(catalog, BALANCE_DRINK_SECONDS_ID)
	if not drink_seconds_result.ok:
		return drink_seconds_result

	var definitions_result := _definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result

	var service: TeaService = load("res://src/tea/tea_service.gd").new()
	var configure_result: Dictionary = service.configure(
		quickslot_result.value,
		drink_seconds_result.value,
		definitions_result.teas,
		definitions_result.vessels,
		_catalog_data_version(catalog)
	)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "tea_service": service}

func configure(
	new_quickslot_count: int,
	new_drink_base_seconds: float,
	new_tea_definitions: Dictionary,
	new_vessel_definitions: Dictionary,
	new_data_version := ""
) -> Dictionary:
	if new_quickslot_count <= 0:
		return _fail("invalid_quickslot_count", "Tea quickslot count must be positive.")
	if new_drink_base_seconds <= 0.0 or not is_finite(new_drink_base_seconds):
		return _fail("invalid_drink_seconds", "Tea drink base seconds must be positive.")
	if new_tea_definitions.is_empty():
		return _fail("missing_tea_definitions", "Tea definitions must not be empty.")
	if new_vessel_definitions.is_empty():
		return _fail("missing_vessel_definitions", "Vessel definitions must not be empty.")

	quickslot_count = new_quickslot_count
	drink_base_seconds = new_drink_base_seconds
	tea_definitions = _duplicate_dictionary(new_tea_definitions)
	vessel_definitions = _duplicate_dictionary(new_vessel_definitions)
	data_version = new_data_version
	next_prepared_id = 1
	next_action_id = 1
	quick_slots.clear()
	for _index in range(quickslot_count):
		quick_slots.append({})
	_emit_changed()
	return {"ok": true}

func brew(tea_id: String, vessel_id: String, inventory, slot_index := -1, context := {}) -> Dictionary:
	var definition_result := _build_prepared_tea(tea_id, get_vessel_modifier_query(vessel_id), context)
	if not definition_result.ok:
		return _fail_and_emit(definition_result)
	var prepared: Dictionary = definition_result.prepared_tea
	var serving_size := int(prepared.serving_size)
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("remove_item"):
		return _fail_and_emit(_fail("invalid_inventory", "Tea brewing requires an inventory model."))
	if inventory.get_total_quantity(tea_id) < serving_size:
		return _fail_and_emit(_fail("missing_tea_leaf", "Brewing requires tea leaf units: %s" % tea_id))
	if inventory.get_total_quantity(vessel_id) < 1:
		return _fail_and_emit(_fail("missing_vessel", "Brewing requires a carried vessel: %s" % vessel_id))

	var target_slot := slot_index
	if target_slot == -1:
		target_slot = first_empty_quickslot()
	var slot_result := _validate_quickslot_index(target_slot)
	if not slot_result.ok:
		return _fail_and_emit(slot_result)
	if not _is_empty_slot(quick_slots[target_slot]):
		return _fail_and_emit(_fail("quickslot_occupied", "Tea quickslot is already occupied: %d" % target_slot))

	var remove_result: Dictionary = inventory.remove_item(tea_id, serving_size)
	if not remove_result.ok:
		return _fail_and_emit(remove_result)

	prepared["prepared_id"] = _next_prepared_id()
	quick_slots[target_slot] = prepared
	tea_prepared.emit(_duplicate_dictionary(prepared))
	_emit_changed()
	return {"ok": true, "slot": target_slot, "prepared_tea": _duplicate_dictionary(prepared)}

func brew_with_modifier_query(tea_id: String, modifier_query: Dictionary, inventory, slot_index := -1, context := {}) -> Dictionary:
	var definition_result := _build_prepared_tea(tea_id, modifier_query, context)
	if not definition_result.ok:
		return _fail_and_emit(definition_result)
	var prepared: Dictionary = definition_result.prepared_tea
	var serving_size := int(prepared.serving_size)
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("remove_item"):
		return _fail_and_emit(_fail("invalid_inventory", "Tea brewing requires an inventory model."))
	if inventory.get_total_quantity(tea_id) < serving_size:
		return _fail_and_emit(_fail("missing_tea_leaf", "Brewing requires tea leaf units: %s" % tea_id))

	var target_slot := slot_index
	if target_slot == -1:
		target_slot = first_empty_quickslot()
	var slot_result := _validate_quickslot_index(target_slot)
	if not slot_result.ok:
		return _fail_and_emit(slot_result)
	if not _is_empty_slot(quick_slots[target_slot]):
		return _fail_and_emit(_fail("quickslot_occupied", "Tea quickslot is already occupied: %d" % target_slot))

	var remove_result: Dictionary = inventory.remove_item(tea_id, serving_size)
	if not remove_result.ok:
		return _fail_and_emit(remove_result)

	prepared["prepared_id"] = _next_prepared_id()
	quick_slots[target_slot] = prepared
	tea_prepared.emit(_duplicate_dictionary(prepared))
	_emit_changed()
	return {"ok": true, "slot": target_slot, "prepared_tea": _duplicate_dictionary(prepared)}

func get_vessel_modifier_query(vessel_id: String) -> Dictionary:
	if not vessel_definitions.has(vessel_id):
		return {}
	var vessel: Dictionary = vessel_definitions[vessel_id]
	return {
		"vessel_id": vessel_id,
		"vessel_name": vessel.name,
		"tea_recovery_multiplier": float(vessel.tea_recovery_multiplier),
		"tea_recovery_bonus": int(vessel.tea_recovery_bonus),
		"carry_use_bonus": int(vessel.carry_use_bonus),
		"drink_seconds_multiplier": float(vessel.drink_seconds_multiplier),
		"drink_seconds_bonus": float(vessel.drink_seconds_bonus),
		"sustain_modifier": float(vessel.sustain_modifier),
		"core_tea_ware": _checkbox_value(vessel.get("core_tea_ware", false)),
		"core_tea_ware_order": int(vessel.get("core_tea_ware_order", 0))
	}

func has_prepared_tea(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= quickslot_count:
		return false
	return not _is_empty_slot(quick_slots[slot_index])

func get_prepared_tea(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= quickslot_count:
		return {}
	return _duplicate_dictionary(quick_slots[slot_index])

func first_empty_quickslot() -> int:
	for index in range(quick_slots.size()):
		if _is_empty_slot(quick_slots[index]):
			return index
	return -1

func start_drinking(slot_index: int, context := {}) -> Dictionary:
	var slot_result := _validate_quickslot_index(slot_index)
	if not slot_result.ok:
		return _fail_and_emit(slot_result)
	var prepared: Dictionary = quick_slots[slot_index]
	if _is_empty_slot(prepared):
		return _fail_and_emit(_fail("empty_quickslot", "Tea quickslot is empty: %d" % slot_index))

	var action := {
		"action_id": _next_action_id(),
		"slot": slot_index,
		"prepared_id": prepared.prepared_id,
		"tea_id": prepared.tea_id,
		"vessel_id": prepared.vessel_id,
		"elapsed_seconds": 0.0,
		"drink_seconds": float(prepared.drink_seconds),
		"recovery_mode": prepared.recovery_mode,
		"context": _duplicate_dictionary(context),
		"completed": false,
		"interrupted": false
	}
	drink_started.emit(_duplicate_dictionary(action))
	return {"ok": true, "action": action}

func tick_drinking(action: Dictionary, delta_seconds: float, resources = null) -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	if delta_seconds < 0.0 or not is_finite(delta_seconds):
		return _fail_and_emit(_fail("invalid_delta", "Tea drinking delta must be non-negative."))

	var updated_action := _duplicate_dictionary(action)
	updated_action.elapsed_seconds = min(
		float(updated_action.drink_seconds),
		float(updated_action.elapsed_seconds) + delta_seconds
	)
	if float(updated_action.elapsed_seconds) < float(updated_action.drink_seconds):
		return {"ok": true, "completed": false, "action": updated_action}
	return complete_drinking(updated_action, resources)

func complete_drinking(action: Dictionary, resources = null) -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	var slot_index := int(action.slot)
	var prepared: Dictionary = quick_slots[slot_index]
	if _is_empty_slot(prepared) or String(prepared.prepared_id) != String(action.prepared_id):
		return _fail_and_emit(_fail("stale_drink_action", "Prepared tea no longer matches the drinking action."))

	var effect_result := _apply_effect(prepared, action.get("context", {}), resources)
	if not effect_result.ok:
		return _fail_and_emit(effect_result)

	var remaining_uses := int(prepared.remaining_uses) - 1
	if remaining_uses <= 0:
		quick_slots[slot_index] = {}
	else:
		prepared.remaining_uses = remaining_uses
		quick_slots[slot_index] = prepared

	var completed_action := _duplicate_dictionary(action)
	completed_action.completed = true
	completed_action.elapsed_seconds = float(completed_action.drink_seconds)
	var result := {
		"ok": true,
		"action": completed_action,
		"slot": slot_index,
		"consumed": true,
		"remaining_uses": max(remaining_uses, 0),
		"effect": effect_result.effect
	}
	drink_completed.emit(_duplicate_dictionary(result))
	_emit_changed()
	return result

func interrupt_drinking(action: Dictionary, reason := "hit") -> Dictionary:
	var action_result := _validate_action(action)
	if not action_result.ok:
		return _fail_and_emit(action_result)
	var interrupted_action := _duplicate_dictionary(action)
	interrupted_action.interrupted = true
	interrupted_action.interrupt_reason = reason
	drink_interrupted.emit(_duplicate_dictionary(interrupted_action))
	return {"ok": true, "action": interrupted_action, "consumed": false}

func to_snapshot() -> Dictionary:
	var slots_snapshot: Array = []
	for slot in quick_slots:
		slots_snapshot.append(_duplicate_dictionary(slot))
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"quickslot_count": quickslot_count,
		"next_prepared_id": next_prepared_id,
		"next_action_id": next_action_id,
		"quick_slots": slots_snapshot
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported tea snapshot schema version.")
	var loaded_count := int(snapshot.get("quickslot_count", 0))
	if loaded_count != quickslot_count:
		return _fail("quickslot_count_mismatch", "Tea snapshot quickslot count does not match current balance data.")
	var loaded_slots = snapshot.get("quick_slots", [])
	if typeof(loaded_slots) != TYPE_ARRAY or loaded_slots.size() > quickslot_count:
		return _fail("invalid_quick_slots", "Tea snapshot quick slots are invalid.")

	var normalized_slots: Array = []
	for raw_slot in loaded_slots:
		var slot_result := _normalize_snapshot_slot(raw_slot)
		if not slot_result.ok:
			return slot_result
		normalized_slots.append(slot_result.slot)
	while normalized_slots.size() < quickslot_count:
		normalized_slots.append({})

	quick_slots = normalized_slots
	data_version = String(snapshot.get("data_version", data_version))
	next_prepared_id = max(1, int(snapshot.get("next_prepared_id", next_prepared_id)))
	next_action_id = max(1, int(snapshot.get("next_action_id", next_action_id)))
	_emit_changed()
	return {"ok": true}

static func _definitions_from_catalog(catalog) -> Dictionary:
	var teas: Dictionary = {}
	for row in _catalog_definitions(catalog, TEA_SOURCE):
		var tea_result := _tea_definition_from_row(row)
		if not tea_result.ok:
			return tea_result
		teas[tea_result.definition.id] = tea_result.definition

	var vessels: Dictionary = {}
	for row in _catalog_definitions(catalog, ITEM_SOURCE):
		if String(row.get("type", "")) != VESSEL_KIND:
			continue
		var vessel_result := _vessel_definition_from_row(row)
		if not vessel_result.ok:
			return vessel_result
		vessels[vessel_result.definition.id] = vessel_result.definition

	return {"ok": true, "teas": teas, "vessels": vessels}

static func _tea_definition_from_row(row: Dictionary) -> Dictionary:
	var recovery_result := _required_non_negative_integer(row, "ki_recovery")
	if not recovery_result.ok:
		return recovery_result
	var drink_seconds_result := _optional_positive_number(row, "drink_seconds", 0.0)
	if not drink_seconds_result.ok:
		return drink_seconds_result
	var carry_result := _optional_positive_integer(row, "carry_uses", DEFAULT_CARRY_USES)
	if not carry_result.ok:
		return carry_result
	var serving_result := _optional_positive_integer(row, "serving_size", BREW_LEAF_UNITS)
	if not serving_result.ok:
		return serving_result
	var sustain_result := _optional_number(row, "sustain_modifier", 0.0)
	if not sustain_result.ok:
		return sustain_result

	var recovery_mode := String(row.get("recovery_mode", DEFAULT_RECOVERY_MODE))
	if not VALID_RECOVERY_MODES.has(recovery_mode):
		return _fail("invalid_recovery_mode", "Unknown tea recovery mode: %s" % recovery_mode)

	return {"ok": true, "definition": {
		"id": String(row.id),
		"name": String(row.get("name", row.id)),
		"ki_recovery": recovery_result.value,
		"drink_seconds": drink_seconds_result.value,
		"carry_uses": carry_result.value,
		"serving_size": serving_result.value,
		"recovery_mode": recovery_mode,
		"condition_key": String(row.get("condition_key", "")),
		"requires_brewing_location": bool(row.get("requires_brewing_location", false)),
		"sustain_modifier": sustain_result.value
	}}

static func _vessel_definition_from_row(row: Dictionary) -> Dictionary:
	var recovery_multiplier_result := _optional_positive_number(row, "tea_recovery_multiplier", 1.0)
	if not recovery_multiplier_result.ok:
		return recovery_multiplier_result
	var recovery_bonus_result := _optional_integer(row, "tea_recovery_bonus", 0)
	if not recovery_bonus_result.ok:
		return recovery_bonus_result
	var carry_bonus_result := _optional_integer(row, "carry_use_bonus", 0)
	if not carry_bonus_result.ok:
		return carry_bonus_result
	var drink_multiplier_result := _optional_positive_number(row, "drink_seconds_multiplier", 1.0)
	if not drink_multiplier_result.ok:
		return drink_multiplier_result
	var drink_bonus_result := _optional_number(row, "drink_seconds_bonus", 0.0)
	if not drink_bonus_result.ok:
		return drink_bonus_result
	var sustain_result := _optional_number(row, "sustain_modifier", 0.0)
	if not sustain_result.ok:
		return sustain_result

	return {"ok": true, "definition": {
		"id": String(row.id),
		"name": String(row.get("name", row.id)),
		"core_tea_ware": _checkbox_value(row.get("core_tea_ware", false)),
		"core_tea_ware_order": int(row.get("core_tea_ware_order", 0)),
		"tea_recovery_multiplier": recovery_multiplier_result.value,
		"tea_recovery_bonus": recovery_bonus_result.value,
		"carry_use_bonus": carry_bonus_result.value,
		"drink_seconds_multiplier": drink_multiplier_result.value,
		"drink_seconds_bonus": drink_bonus_result.value,
		"sustain_modifier": sustain_result.value
	}}

func _build_prepared_tea(tea_id: String, modifier_query: Dictionary, context: Dictionary) -> Dictionary:
	if not tea_definitions.has(tea_id):
		return _fail("unknown_tea", "Unknown tea definition: %s" % tea_id)
	var modifier_result := _validate_modifier_query(modifier_query)
	if not modifier_result.ok:
		return modifier_result
	if bool(tea_definitions[tea_id].get("requires_brewing_location", false)) and not bool(context.get("has_brewing_location", false)):
		return _fail("missing_brewing_location", "Tea requires a valid brewing location: %s" % tea_id)

	var tea: Dictionary = tea_definitions[tea_id]
	var vessel: Dictionary = modifier_result.modifier
	var raw_recovery := float(tea.ki_recovery) * float(vessel.tea_recovery_multiplier) + float(vessel.tea_recovery_bonus)
	var ki_recovery: int = max(0, int(round(raw_recovery)))
	var remaining_uses: int = max(1, int(tea.carry_uses) + int(vessel.carry_use_bonus))
	var drink_seconds: float = float(tea.drink_seconds)
	if drink_seconds <= 0.0:
		drink_seconds = drink_base_seconds
	drink_seconds = drink_seconds * float(vessel.drink_seconds_multiplier) + float(vessel.drink_seconds_bonus)
	if drink_seconds <= 0.0 or not is_finite(drink_seconds):
		return _fail("invalid_prepared_drink_seconds", "Prepared tea drink seconds must be positive.")
	var sustain_modifier: float = float(tea.sustain_modifier) + float(vessel.sustain_modifier)

	return {"ok": true, "prepared_tea": {
		"prepared_id": "",
		"tea_id": tea_id,
		"vessel_id": vessel.vessel_id,
		"tea_name": tea.name,
		"vessel_name": vessel.vessel_name,
		"remaining_uses": remaining_uses,
		"drink_seconds": drink_seconds,
		"ki_recovery": ki_recovery,
		"serving_size": int(tea.serving_size),
		"recovery_mode": tea.recovery_mode,
		"condition_key": tea.condition_key,
		"sustain_modifier": sustain_modifier,
		"core_tea_ware": bool(vessel.get("core_tea_ware", false)),
		"core_tea_ware_order": int(vessel.get("core_tea_ware_order", 0))
	}}

func _validate_modifier_query(query: Dictionary) -> Dictionary:
	var vessel_id := String(query.get("vessel_id", ""))
	if vessel_id == "":
		return _fail("unknown_vessel", "Unknown tea vessel definition: %s" % vessel_id)
	for field in ["tea_recovery_multiplier", "drink_seconds_multiplier"]:
		var value = query.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
			return _fail("invalid_modifier_query", "Tea modifier field must be a positive number: %s.%s" % [vessel_id, field])
	for field in ["tea_recovery_bonus", "carry_use_bonus", "drink_seconds_bonus", "sustain_modifier"]:
		var value = query.get(field, 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return _fail("invalid_modifier_query", "Tea modifier field must be numeric: %s.%s" % [vessel_id, field])
	return {"ok": true, "modifier": {
		"vessel_id": vessel_id,
		"vessel_name": String(query.get("vessel_name", vessel_id)),
		"tea_recovery_multiplier": float(query.tea_recovery_multiplier),
		"tea_recovery_bonus": int(query.get("tea_recovery_bonus", 0)),
		"carry_use_bonus": int(query.get("carry_use_bonus", 0)),
		"drink_seconds_multiplier": float(query.drink_seconds_multiplier),
		"drink_seconds_bonus": float(query.get("drink_seconds_bonus", 0.0)),
		"sustain_modifier": float(query.get("sustain_modifier", 0.0)),
		"core_tea_ware": _checkbox_value(query.get("core_tea_ware", false)),
		"core_tea_ware_order": int(query.get("core_tea_ware_order", 0))
	}}

func _apply_effect(prepared: Dictionary, context, resources) -> Dictionary:
	var effect := {
		"mode": prepared.recovery_mode,
		"condition_passed": true,
		"ki_recovered": 0,
		"ki_recovery_requested": int(prepared.ki_recovery),
		"sustain_modifier": float(prepared.sustain_modifier)
	}
	if String(prepared.recovery_mode) == RECOVERY_CONDITIONAL:
		effect.condition_passed = _condition_passes(prepared, context)
	if not bool(effect.condition_passed):
		return {"ok": true, "effect": effect}
	if resources != null and not resources.has_method("recover_ki"):
		return _fail("invalid_resources", "Tea effect requires a resource model with recover_ki.")

	var recovered := int(prepared.ki_recovery)
	if resources != null:
		recovered = int(resources.recover_ki(int(prepared.ki_recovery)))
	effect.ki_recovered = recovered
	return {"ok": true, "effect": effect}

func _condition_passes(prepared: Dictionary, context) -> bool:
	var condition_key := String(prepared.get("condition_key", ""))
	if condition_key.is_empty():
		return true
	if typeof(context) != TYPE_DICTIONARY:
		return false
	if context.has(condition_key):
		return bool(context[condition_key])
	var conditions = context.get("conditions", {})
	if typeof(conditions) == TYPE_DICTIONARY and conditions.has(condition_key):
		return bool(conditions[condition_key])
	return false

func _normalize_snapshot_slot(raw_slot) -> Dictionary:
	if _is_empty_slot(raw_slot):
		return {"ok": true, "slot": {}}
	if typeof(raw_slot) != TYPE_DICTIONARY:
		return _fail("invalid_quickslot", "Prepared tea snapshot slot must be a dictionary.")
	var tea_id := String(raw_slot.get("tea_id", ""))
	var vessel_id := String(raw_slot.get("vessel_id", ""))
	if not tea_definitions.has(tea_id):
		return _fail("unknown_tea", "Prepared tea snapshot references unknown tea: %s" % tea_id)
	if not vessel_definitions.has(vessel_id):
		return _fail("unknown_vessel", "Prepared tea snapshot references unknown vessel: %s" % vessel_id)
	var remaining_uses := int(raw_slot.get("remaining_uses", 0))
	if remaining_uses <= 0:
		return _fail("invalid_remaining_uses", "Prepared tea snapshot remaining uses must be positive.")
	return {"ok": true, "slot": _duplicate_dictionary(raw_slot)}

func _validate_action(action: Dictionary) -> Dictionary:
	if action.get("completed", false):
		return _fail("completed_drink_action", "Tea drinking action is already completed.")
	if action.get("interrupted", false):
		return _fail("interrupted_drink_action", "Tea drinking action is interrupted.")
	var slot_index := int(action.get("slot", -1))
	var slot_result := _validate_quickslot_index(slot_index)
	if not slot_result.ok:
		return slot_result
	if not action.has("prepared_id") or String(action.prepared_id).is_empty():
		return _fail("invalid_drink_action", "Tea drinking action is missing prepared tea identity.")
	return {"ok": true}

func _validate_quickslot_index(index: int) -> Dictionary:
	if index < 0 or index >= quickslot_count:
		return _fail("invalid_quickslot", "Tea quickslot index is out of range: %d" % index)
	return {"ok": true}

func _next_prepared_id() -> String:
	var value := "tea_%06d" % next_prepared_id
	next_prepared_id += 1
	return value

func _next_action_id() -> String:
	var value := "tea_action_%06d" % next_action_id
	next_action_id += 1
	return value

func _emit_changed() -> void:
	changed.emit(to_snapshot())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

static func _required_positive_integer_balance(catalog, id: String) -> Dictionary:
	var value_result := _required_positive_number_balance(catalog, id)
	if not value_result.ok:
		return value_result
	if float(value_result.value) != floor(float(value_result.value)):
		return _fail("invalid_balance", "Tea balance value must be an integer: %s" % id)
	return {"ok": true, "value": int(value_result.value)}

static func _required_positive_number_balance(catalog, id: String) -> Dictionary:
	if not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Catalog cannot look up balance values.")
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return _fail("missing_balance", "Missing required tea balance value: %s" % id)
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
		return _fail("invalid_balance", "Tea balance value must be a positive number: %s" % id)
	return {"ok": true, "value": float(value)}

static func _required_non_negative_integer(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Tea definition is missing required field: %s.%s" % [row.get("id", ""), field])
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

static func _is_empty_slot(slot) -> bool:
	return typeof(slot) != TYPE_DICTIONARY or slot.is_empty()

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _checkbox_value(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_STRING:
		return String(value) == "__YES__"
	return bool(value)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
