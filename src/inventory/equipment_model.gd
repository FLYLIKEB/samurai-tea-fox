extends RefCounted
class_name EquipmentModel

signal changed(snapshot: Dictionary)
signal operation_failed(error: Dictionary)

const SNAPSHOT_SCHEMA_VERSION := 1
const ITEM_SOURCE := "items"

const SLOT_WEAPON := "weapon"
const SLOT_ARMOR := "armor"
const SLOT_TEA_WARE := "tea_ware"

const DATA_SLOT_WEAPON := "무기"
const DATA_SLOT_ARMOR := "방어구"
const DATA_SLOT_TEA_WARE := "다구"
const EFFECT_ATTACK := "공격"
const EFFECT_DEFENSE := "방어"
const EFFECT_TEA_OPERATION := "차 운용"
const METADATA_TEA_WARE_USE_COUNT := "tea_ware_use_count"
const SNAPSHOT_ACCOUNTED_TEA_COMPLETION_IDS := "accounted_tea_completion_ids"

const SLOT_KEYS := [SLOT_WEAPON, SLOT_ARMOR, SLOT_TEA_WARE]
const SLOT_FROM_DATA := {
	DATA_SLOT_WEAPON: SLOT_WEAPON,
	DATA_SLOT_ARMOR: SLOT_ARMOR,
	DATA_SLOT_TEA_WARE: SLOT_TEA_WARE
}

var data_version := ""
var item_definitions: Dictionary = {}
var equipped_slots := {
	SLOT_WEAPON: {},
	SLOT_ARMOR: {},
	SLOT_TEA_WARE: {}
}
var accounted_tea_completion_ids: Dictionary = {}

static func from_catalog(catalog) -> Dictionary:
	var definitions_result := _definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result
	var equipment: EquipmentModel = load("res://src/inventory/equipment_model.gd").new()
	var configure_result: Dictionary = equipment.configure(
		definitions_result.definitions,
		_catalog_data_version(catalog)
	)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "equipment": equipment}

func configure(definitions: Dictionary, new_data_version := "") -> Dictionary:
	if definitions.is_empty():
		return _fail("missing_definitions", "Equipment definitions must not be empty.")
	item_definitions = definitions.duplicate(true)
	data_version = new_data_version
	equipped_slots = _empty_equipped_slots()
	accounted_tea_completion_ids = {}
	_emit_changed()
	return {"ok": true}

func equip_from_inventory(inventory, inventory_slot_index: int) -> Dictionary:
	var inventory_result := _validate_inventory_api(inventory)
	if not inventory_result.ok:
		return _fail_and_emit(inventory_result)
	var slot: Dictionary = inventory.get_slot(inventory_slot_index)
	if _is_empty_slot(slot):
		return _fail_and_emit(_fail("empty_inventory_slot", "Inventory slot is empty: %d" % inventory_slot_index))

	var slot_key_result := _slot_key_for_item(String(slot.get("item_id", "")))
	if not slot_key_result.ok:
		return _fail_and_emit(slot_key_result)
	var slot_key: String = slot_key_result.slot_key
	var previous: Dictionary = _duplicate_dictionary(equipped_slots[slot_key])

	var extract_result: Dictionary = inventory.extract_slot(inventory_slot_index)
	if not extract_result.ok:
		return _fail_and_emit(extract_result)

	equipped_slots[slot_key] = extract_result.slot
	if not _is_empty_slot(previous):
		var insert_previous: Dictionary = inventory.insert_slot(previous, inventory_slot_index)
		if not insert_previous.ok:
			equipped_slots[slot_key] = previous
			inventory.insert_slot(extract_result.slot, inventory_slot_index)
			return _fail_and_emit(insert_previous)

	_emit_changed()
	return {
		"ok": true,
		"slot": slot_key,
		"equipped": _slot_payload(slot_key),
		"replaced": previous
	}

func unequip_to_inventory(slot_key: String, inventory, target_inventory_slot := -1) -> Dictionary:
	var normalized_slot_key := _normalize_slot_key(slot_key)
	if normalized_slot_key == "":
		return _fail_and_emit(_fail("invalid_equipment_slot", "Unknown equipment slot: %s" % slot_key))
	var inventory_result := _validate_inventory_api(inventory)
	if not inventory_result.ok:
		return _fail_and_emit(inventory_result)
	var equipped: Dictionary = equipped_slots[normalized_slot_key]
	if _is_empty_slot(equipped):
		return _fail_and_emit(_fail("empty_equipment_slot", "Equipment slot is empty: %s" % normalized_slot_key))
	var insert_result: Dictionary = inventory.insert_slot(equipped, target_inventory_slot)
	if not insert_result.ok:
		return _fail_and_emit(insert_result)
	equipped_slots[normalized_slot_key] = {}
	_emit_changed()
	return {"ok": true, "slot": normalized_slot_key, "inventory_slot": insert_result.slot_index}

func get_equipped_slot(slot_key: String) -> Dictionary:
	var normalized_slot_key := _normalize_slot_key(slot_key)
	if normalized_slot_key == "":
		return {}
	return _slot_payload(normalized_slot_key)

func get_weapon_combat_query() -> Dictionary:
	var payload := _slot_payload(SLOT_WEAPON)
	if payload.is_empty():
		return {}
	var definition: Dictionary = payload.definition
	return {
		"weapon_id": definition.id,
		"base_damage": int(definition.base_damage),
		"range": float(definition.range),
		"attack_speed": float(definition.attack_speed)
	}

func get_armor_combat_query() -> Dictionary:
	var payload := _slot_payload(SLOT_ARMOR)
	if payload.is_empty():
		return {}
	var definition: Dictionary = payload.definition
	return {
		"armor_id": definition.id,
		"defense": int(definition.defense)
	}

func get_tea_modifier_query() -> Dictionary:
	var payload := _slot_payload(SLOT_TEA_WARE)
	if payload.is_empty():
		return {}
	var definition: Dictionary = payload.definition
	var query := _tea_modifier_query_from_definition(definition)
	query["vessel_instance_id"] = String(payload.instance_id)
	query["attachment_description_key"] = _attachment_description_key_for_payload(payload)
	return query

func get_tea_ware_use_count() -> int:
	var payload := _slot_payload(SLOT_TEA_WARE)
	if payload.is_empty():
		return 0
	return max(0, int(payload.metadata.get(METADATA_TEA_WARE_USE_COUNT, 0)))

func get_tea_ware_attachment_description_key() -> String:
	var payload := _slot_payload(SLOT_TEA_WARE)
	if payload.is_empty():
		return ""
	return _attachment_description_key_for_payload(payload)

func record_tea_ware_use_completion(completion_result: Dictionary, inventory = null) -> Dictionary:
	if not bool(completion_result.get("ok", false)):
		return _fail("invalid_completion", "Tea ware use accounting requires a successful completion result.")
	if not bool(completion_result.get("consumed", false)):
		return _fail("incomplete_use", "Tea ware use accounting only accepts completed tea use events.")
	var action: Dictionary = _duplicate_dictionary(completion_result.get("action", {}))
	if not bool(action.get("completed", false)):
		return _fail("incomplete_use", "Tea ware use accounting only accepts completed tea use events.")
	var completion_id := _completion_identity(completion_result, action)
	if completion_id.is_empty():
		return _fail("missing_completion_identity", "Tea ware use accounting requires a stable completion identity.")
	if accounted_tea_completion_ids.has(completion_id):
		return {"ok": true, "accounted": false, "reason": "duplicate_completion", "completion_id": completion_id}

	var completed_instance_id := String(action.get("vessel_instance_id", completion_result.get("vessel_instance_id", "")))
	if completed_instance_id.is_empty():
		return {"ok": true, "accounted": false, "reason": "missing_vessel_instance_id"}
	var equipped_result := _record_equipped_tea_ware_use(completed_instance_id)
	if equipped_result.accounted:
		_mark_completion_accounted(completion_id)
		equipped_result["completion_id"] = completion_id
		_emit_changed()
		return equipped_result
	var inventory_result := _record_inventory_tea_ware_use(completed_instance_id, inventory)
	if inventory_result.accounted:
		_mark_completion_accounted(completion_id)
		inventory_result["completion_id"] = completion_id
		_emit_changed()
		return inventory_result
	return inventory_result

func to_snapshot() -> Dictionary:
	var snapshot_slots := {}
	for slot_key in SLOT_KEYS:
		snapshot_slots[slot_key] = _duplicate_dictionary(equipped_slots[slot_key])
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"slots": snapshot_slots,
		SNAPSHOT_ACCOUNTED_TEA_COMPLETION_IDS: _accounted_completion_id_array()
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported equipment snapshot schema version.")
	var raw_slots = snapshot.get("slots", {})
	if typeof(raw_slots) != TYPE_DICTIONARY:
		return _fail("invalid_slots", "Equipment snapshot slots must be a dictionary.")

	var loaded_slots := _empty_equipped_slots()
	for slot_key in SLOT_KEYS:
		var raw_slot = raw_slots.get(slot_key, {})
		var slot_result := _normalize_equipment_snapshot_slot(slot_key, raw_slot)
		if not slot_result.ok:
			return slot_result
		loaded_slots[slot_key] = slot_result.slot

	equipped_slots = loaded_slots
	data_version = String(snapshot.get("data_version", data_version))
	accounted_tea_completion_ids = _normalize_accounted_completion_ids(snapshot.get(SNAPSHOT_ACCOUNTED_TEA_COMPLETION_IDS, []))
	_emit_changed()
	return {"ok": true}

static func _definitions_from_catalog(catalog) -> Dictionary:
	var definitions: Dictionary = {}
	for row in _catalog_definitions(catalog, ITEM_SOURCE):
		var result := _definition_from_item(row)
		if not result.ok:
			return result
		if not result.equippable:
			continue
		definitions[result.definition.id] = result.definition
	return {"ok": true, "definitions": definitions}

static func _definition_from_item(row: Dictionary) -> Dictionary:
	var item_id := String(row.get("id", ""))
	var data_slot := String(row.get("equipment_slot", ""))
	if data_slot == "":
		return {"ok": true, "equippable": false}
	if not SLOT_FROM_DATA.has(data_slot):
		return _fail("invalid_equipment_slot", "Unknown item equipment slot: %s.%s" % [item_id, data_slot])
	var slot_key: String = SLOT_FROM_DATA[data_slot]
	var item_type := String(row.get("type", ""))
	if item_type != data_slot:
		return _fail("equipment_type_mismatch", "Item type and equipment slot differ: %s" % item_id)

	var definition := {
		"id": item_id,
		"name": String(row.get("name", item_id)),
		"kind": item_type,
		"equipment_slot": slot_key,
		"core_tea_ware": _checkbox_value(row.get("core_tea_ware", false)),
		"core_tea_ware_order": int(row.get("core_tea_ware_order", 0))
	}

	if slot_key == SLOT_WEAPON:
		var damage_result := _required_positive_integer(row, "base_damage")
		if not damage_result.ok:
			return damage_result
		var range_result := _required_positive_number(row, "range")
		if not range_result.ok:
			return range_result
		var speed_result := _required_positive_number(row, "attack_speed")
		if not speed_result.ok:
			return speed_result
		if String(row.get("effect_type", "")) != EFFECT_ATTACK:
			return _fail("invalid_effect_type", "Weapon effect type must be attack: %s" % item_id)
		definition["base_damage"] = damage_result.value
		definition["range"] = range_result.value
		definition["attack_speed"] = speed_result.value
	elif slot_key == SLOT_ARMOR:
		var defense_result := _required_non_negative_integer(row, "defense")
		if not defense_result.ok:
			return defense_result
		if String(row.get("effect_type", "")) != EFFECT_DEFENSE:
			return _fail("invalid_effect_type", "Armor effect type must be defense: %s" % item_id)
		definition["defense"] = defense_result.value
	else:
		if String(row.get("effect_type", "")) != EFFECT_TEA_OPERATION:
			return _fail("invalid_effect_type", "Tea ware effect type must be tea operation: %s" % item_id)
		var effect_result := _optional_number(row, "effect_value", 0.0)
		if not effect_result.ok:
			return effect_result
		var recovery_multiplier_result := _optional_positive_number(row, "tea_recovery_multiplier", 1.0)
		if not recovery_multiplier_result.ok:
			return recovery_multiplier_result
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
		definition["effect_value"] = effect_result.value
		definition["tea_recovery_multiplier"] = recovery_multiplier_result.value
		definition["tea_recovery_bonus"] = _tea_recovery_bonus_from_effect(row)
		definition["carry_use_bonus"] = carry_bonus_result.value
		definition["drink_seconds_multiplier"] = drink_multiplier_result.value
		definition["drink_seconds_bonus"] = drink_bonus_result.value
		definition["sustain_modifier"] = sustain_result.value
		var attachment_result := _attachment_stage_definition_from_row(row, item_id)
		if not attachment_result.ok:
			return attachment_result
		definition["attachment_stage_thresholds"] = attachment_result.thresholds
		definition["attachment_description_keys"] = attachment_result.description_keys

	return {"ok": true, "equippable": true, "definition": definition}

func _slot_payload(slot_key: String) -> Dictionary:
	var slot: Dictionary = equipped_slots.get(slot_key, {})
	if _is_empty_slot(slot):
		return {}
	var item_id := String(slot.get("item_id", ""))
	return {
		"slot": slot_key,
		"item_id": item_id,
		"instance_id": String(slot.get("instance_id", "")),
		"metadata": _duplicate_dictionary(slot.get("metadata", {})),
		"definition": _duplicate_dictionary(item_definitions.get(item_id, {}))
	}

func _slot_key_for_item(item_id: String) -> Dictionary:
	if not item_definitions.has(item_id):
		return _fail("not_equippable", "Item is not equippable: %s" % item_id)
	return {"ok": true, "slot_key": String(item_definitions[item_id].equipment_slot)}

func _normalize_equipment_snapshot_slot(slot_key: String, raw_slot) -> Dictionary:
	if _is_empty_slot(raw_slot):
		return {"ok": true, "slot": {}}
	if typeof(raw_slot) != TYPE_DICTIONARY:
		return _fail("invalid_slot", "Equipment snapshot slot must be a dictionary: %s" % slot_key)
	var item_id := String(raw_slot.get("item_id", ""))
	var slot_key_result := _slot_key_for_item(item_id)
	if not slot_key_result.ok:
		return slot_key_result
	if String(slot_key_result.slot_key) != slot_key:
		return _fail("equipment_slot_mismatch", "Equipment snapshot item is in the wrong slot: %s" % item_id)
	if int(raw_slot.get("quantity", 0)) != 1:
		return _fail("invalid_quantity", "Equipped item quantity must be one: %s" % item_id)
	if String(raw_slot.get("instance_id", "")).is_empty():
		return _fail("missing_instance_id", "Equipped item is missing instance id: %s" % item_id)
	return {"ok": true, "slot": _new_slot(item_id, String(raw_slot.instance_id), raw_slot.get("metadata", {}))}

static func _tea_modifier_query_from_definition(definition: Dictionary) -> Dictionary:
	return {
		"vessel_id": String(definition.id),
		"vessel_name": String(definition.name),
		"core_tea_ware": bool(definition.get("core_tea_ware", false)),
		"core_tea_ware_order": int(definition.get("core_tea_ware_order", 0)),
		"tea_recovery_multiplier": float(definition.get("tea_recovery_multiplier", 1.0)),
		"tea_recovery_bonus": int(definition.get("tea_recovery_bonus", 0)),
		"carry_use_bonus": int(definition.get("carry_use_bonus", 0)),
		"drink_seconds_multiplier": float(definition.get("drink_seconds_multiplier", 1.0)),
		"drink_seconds_bonus": float(definition.get("drink_seconds_bonus", 0.0)),
		"sustain_modifier": float(definition.get("sustain_modifier", 0.0)),
		"effect_value": float(definition.get("effect_value", 0.0)),
		"attachment_stage_thresholds": _duplicate_array(definition.get("attachment_stage_thresholds", [])),
		"attachment_description_keys": _duplicate_array(definition.get("attachment_description_keys", []))
	}

static func _attachment_stage_definition_from_row(row: Dictionary, item_id: String) -> Dictionary:
	var thresholds_result := _required_integer_array_field(row, "attachment_stage_thresholds")
	if not thresholds_result.ok:
		return thresholds_result
	var thresholds: Array = thresholds_result.values
	if thresholds.size() < 3:
		return _fail("invalid_attachment_stages", "Tea ware attachment requires at least three stage thresholds: %s" % item_id)
	var previous := -1
	for threshold in thresholds:
		var value := int(threshold)
		if value < 0 or value <= previous:
			return _fail("invalid_attachment_stages", "Tea ware attachment thresholds must be ascending non-negative integers: %s" % item_id)
		previous = value

	var keys_result := _required_string_array_field(row, "attachment_description_keys")
	if not keys_result.ok:
		return keys_result
	var description_keys: Array = keys_result.values
	if description_keys.size() < thresholds.size():
		return _fail("invalid_attachment_stages", "Tea ware attachment description keys must cover every threshold: %s" % item_id)

	return {"ok": true, "thresholds": thresholds, "description_keys": description_keys}

static func _required_integer_array_field(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Definition is missing required field: %s.%s" % [row.get("id", ""), field])
	var raw_values := _array_from_field(row[field])
	if raw_values.is_empty():
		return _fail("invalid_definition", "Definition field must be a non-empty array: %s.%s" % [row.get("id", ""), field])
	var values: Array = []
	for raw in raw_values:
		if typeof(raw) == TYPE_STRING:
			var text := String(raw).strip_edges()
			if not text.is_valid_int():
				return _fail("invalid_definition", "Definition array field must contain integers: %s.%s" % [row.get("id", ""), field])
			values.append(int(text))
			continue
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)) or float(raw) != floor(float(raw)):
			return _fail("invalid_definition", "Definition array field must contain integers: %s.%s" % [row.get("id", ""), field])
		values.append(int(raw))
	return {"ok": true, "values": values}

static func _required_string_array_field(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Definition is missing required field: %s.%s" % [row.get("id", ""), field])
	var raw_values := _array_from_field(row[field])
	if raw_values.is_empty():
		return _fail("invalid_definition", "Definition field must be a non-empty array: %s.%s" % [row.get("id", ""), field])
	var values: Array = []
	for raw in raw_values:
		var value := String(raw).strip_edges()
		if value.is_empty():
			return _fail("invalid_definition", "Definition array field must contain non-empty strings: %s.%s" % [row.get("id", ""), field])
		values.append(value)
	return {"ok": true, "values": values}

static func _array_from_field(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	if typeof(value) == TYPE_STRING:
		var values: Array = []
		for part in String(value).split(",", false):
			values.append(String(part).strip_edges())
		return values
	return []

static func _attachment_description_key_for_payload(payload: Dictionary) -> String:
	var slot := {
		"item_id": String(payload.item_id),
		"metadata": _duplicate_dictionary(payload.get("metadata", {}))
	}
	return _attachment_description_key_for_definition(payload.definition, slot)

func _attachment_description_key_for_slot(slot: Dictionary) -> String:
	var item_id := String(slot.get("item_id", ""))
	return _attachment_description_key_for_definition(item_definitions.get(item_id, {}), slot)

static func _attachment_description_key_for_definition(definition: Dictionary, slot: Dictionary) -> String:
	var thresholds: Array = _duplicate_array(definition.get("attachment_stage_thresholds", []))
	var description_keys: Array = _duplicate_array(definition.get("attachment_description_keys", []))
	if thresholds.is_empty() or description_keys.is_empty():
		return ""
	var use_count: int = max(0, int(_duplicate_dictionary(slot.get("metadata", {})).get(METADATA_TEA_WARE_USE_COUNT, 0)))
	var stage_index := 0
	for index in range(thresholds.size()):
		if use_count >= int(thresholds[index]):
			stage_index = index
	return String(description_keys[min(stage_index, description_keys.size() - 1)])

func _record_equipped_tea_ware_use(completed_instance_id: String) -> Dictionary:
	var current: Dictionary = equipped_slots[SLOT_TEA_WARE]
	if _is_empty_slot(current):
		return {"ok": true, "accounted": false, "reason": "no_equipped_tea_ware"}
	if completed_instance_id != String(current.get("instance_id", "")):
		return {"ok": true, "accounted": false, "reason": "vessel_instance_mismatch"}
	var result := _increment_tea_ware_slot_metadata(current)
	equipped_slots[SLOT_TEA_WARE] = result.slot
	return {
		"ok": true,
		"accounted": true,
		"source": "equipment",
		"use_count": result.use_count,
		"previous_description_key": result.previous_description_key,
		"description_key": result.description_key
	}

func _record_inventory_tea_ware_use(completed_instance_id: String, inventory) -> Dictionary:
	if inventory == null or not inventory.has_method("to_snapshot") or not inventory.has_method("load_snapshot"):
		return {"ok": true, "accounted": false, "reason": "vessel_instance_mismatch"}
	var snapshot: Dictionary = inventory.to_snapshot()
	var slots = snapshot.get("slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return {"ok": true, "accounted": false, "reason": "invalid_inventory_snapshot"}
	for index in range(slots.size()):
		var slot = slots[index]
		if _is_empty_slot(slot) or String(slot.get("instance_id", "")) != completed_instance_id:
			continue
		var item_id := String(slot.get("item_id", ""))
		if not item_definitions.has(item_id) or String(item_definitions[item_id].equipment_slot) != SLOT_TEA_WARE:
			return {"ok": true, "accounted": false, "reason": "vessel_instance_mismatch"}
		var result := _increment_tea_ware_slot_metadata(slot)
		slots[index] = result.slot
		snapshot["slots"] = slots
		var load_result: Dictionary = inventory.load_snapshot(snapshot)
		if not load_result.ok:
			return load_result
		return {
			"ok": true,
			"accounted": true,
			"source": "inventory",
			"inventory_slot": index,
			"use_count": result.use_count,
			"previous_description_key": result.previous_description_key,
			"description_key": result.description_key
		}
	return {"ok": true, "accounted": false, "reason": "vessel_instance_mismatch"}

func _increment_tea_ware_slot_metadata(slot: Dictionary) -> Dictionary:
	var updated_slot := _duplicate_dictionary(slot)
	var metadata: Dictionary = _duplicate_dictionary(updated_slot.get("metadata", {}))
	var before_count: int = max(0, int(metadata.get(METADATA_TEA_WARE_USE_COUNT, 0)))
	var before_key := _attachment_description_key_for_slot(updated_slot)
	metadata[METADATA_TEA_WARE_USE_COUNT] = before_count + 1
	updated_slot["metadata"] = metadata
	var after_key := _attachment_description_key_for_slot(updated_slot)
	return {
		"slot": updated_slot,
		"use_count": before_count + 1,
		"previous_description_key": before_key,
		"description_key": after_key
	}

func _mark_completion_accounted(completion_id: String) -> void:
	accounted_tea_completion_ids[completion_id] = true

func _accounted_completion_id_array() -> Array:
	var ids: Array = accounted_tea_completion_ids.keys()
	ids.sort()
	return ids

static func _normalize_accounted_completion_ids(raw_ids) -> Dictionary:
	var ids := {}
	if typeof(raw_ids) != TYPE_ARRAY:
		return ids
	for raw_id in raw_ids:
		var completion_id := String(raw_id)
		if not completion_id.is_empty():
			ids[completion_id] = true
	return ids

static func _completion_identity(completion_result: Dictionary, action: Dictionary) -> String:
	var action_id := String(action.get("action_id", completion_result.get("action_id", "")))
	if not action_id.is_empty():
		return action_id
	var prepared_id := String(action.get("prepared_id", completion_result.get("prepared_id", "")))
	if not prepared_id.is_empty():
		return prepared_id
	return ""

static func _tea_recovery_bonus_from_effect(row: Dictionary) -> int:
	if String(row.get("effect_type", "")) == EFFECT_TEA_OPERATION:
		return int(round(float(row.get("effect_value", 0.0))))
	return 0

static func _validate_inventory_api(inventory) -> Dictionary:
	for method in ["get_slot", "extract_slot", "insert_slot"]:
		if inventory == null or not inventory.has_method(method):
			return _fail("invalid_inventory", "Equipment requires an inventory model with %s." % method)
	return {"ok": true}

static func _normalize_slot_key(slot_key: String) -> String:
	if SLOT_KEYS.has(slot_key):
		return slot_key
	if SLOT_FROM_DATA.has(slot_key):
		return SLOT_FROM_DATA[slot_key]
	return ""

static func _empty_equipped_slots() -> Dictionary:
	return {
		SLOT_WEAPON: {},
		SLOT_ARMOR: {},
		SLOT_TEA_WARE: {}
	}

func _emit_changed() -> void:
	changed.emit(to_snapshot())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

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

static func _required_positive_integer(row: Dictionary, field: String) -> Dictionary:
	var value_result := _required_non_negative_integer(row, field)
	if not value_result.ok:
		return value_result
	if int(value_result.value) <= 0:
		return _fail("invalid_definition", "Definition field must be a positive integer: %s.%s" % [row.get("id", ""), field])
	return value_result

static func _required_non_negative_integer(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Definition is missing required field: %s.%s" % [row.get("id", ""), field])
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	if float(value) != floor(float(value)) or int(value) < 0:
		return _fail("invalid_definition", "Definition field must be a non-negative integer: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": int(value)}

static func _required_positive_number(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Definition is missing required field: %s.%s" % [row.get("id", ""), field])
	var value_result := _optional_positive_number(row, field, 0.0)
	if not value_result.ok:
		return value_result
	return value_result

static func _optional_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	if float(value) != floor(float(value)):
		return _fail("invalid_definition", "Definition field must be an integer: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": int(value)}

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

static func _new_slot(item_id: String, instance_id: String, metadata := {}) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": 1,
		"instance_id": instance_id,
		"metadata": _duplicate_dictionary(metadata)
	}

static func _is_empty_slot(slot) -> bool:
	return typeof(slot) != TYPE_DICTIONARY or slot.is_empty()

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _duplicate_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _checkbox_value(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_STRING:
		return String(value) == "__YES__"
	return bool(value)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
