extends RefCounted
class_name InventoryModel

signal changed(snapshot: Dictionary)
signal operation_failed(error: Dictionary)

const SNAPSHOT_SCHEMA_VERSION := 1
const INVENTORY_BASE_SLOTS_ID := "inventory_base_slots"
const ITEM_SOURCE := "items"
const TEA_SOURCE := "teas"
const TEA_LEAF_KIND := "찻잎"
const INDIVIDUAL_ITEM_TYPES := {
	"무기": true,
	"방어구": true,
	"다구": true
}

var data_version := ""
var slot_count := 0
var slots: Array = []
var item_definitions: Dictionary = {}
var next_instance_id := 1

static func from_catalog(catalog) -> Dictionary:
	var slots_result := _required_positive_integer_balance(catalog, INVENTORY_BASE_SLOTS_ID)
	if not slots_result.ok:
		return slots_result

	var definitions_result := _definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result

	var inventory: InventoryModel = load("res://src/inventory/inventory_model.gd").new()
	var configure_result: Dictionary = inventory.configure(
		slots_result.value,
		definitions_result.definitions,
		_catalog_data_version(catalog)
	)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "inventory": inventory}

func configure(new_slot_count: int, definitions: Dictionary, new_data_version := "") -> Dictionary:
	if new_slot_count <= 0:
		return _fail("invalid_slot_count", "Inventory slot count must be positive.")
	if definitions.is_empty():
		return _fail("missing_definitions", "Inventory definitions must not be empty.")

	slot_count = new_slot_count
	data_version = new_data_version
	item_definitions = _duplicate_dictionary(definitions)
	next_instance_id = 1
	slots.clear()
	for _index in range(slot_count):
		slots.append({})
	_emit_changed()
	return {"ok": true}

func has_definition(item_id: String) -> bool:
	return item_definitions.has(item_id)

func definition_for(item_id: String) -> Dictionary:
	return _duplicate_dictionary(item_definitions.get(item_id, {}))

func add_item(item_id: String, quantity := 1, metadata := {}) -> Dictionary:
	var validation := _validate_quantity(item_id, quantity)
	if not validation.ok:
		return _fail_and_emit(validation)

	var definition: Dictionary = item_definitions[item_id]
	var max_owned := int(definition.get("max_owned", 0))
	if max_owned > 0 and get_total_quantity(item_id) + quantity > max_owned:
		return _fail_and_emit({"ok": false, "reason": "max_owned_exceeded", "error": "Item ownership limit exceeded: %s" % item_id})
	var candidate := _duplicate_slots(slots)
	var remaining := quantity
	if _requires_instance(definition):
		var empty_slots := _empty_slot_indexes(candidate)
		if empty_slots.size() < quantity:
			return _fail_and_emit({"ok": false, "reason": "inventory_full", "error": "Not enough empty inventory slots."})
		var created_instances: Array = []
		for index in range(quantity):
			var instance_id := _next_instance_id()
			candidate[empty_slots[index]] = _new_slot(item_id, 1, instance_id, metadata)
			created_instances.append(instance_id)
		slots = candidate
		_emit_changed()
		return {"ok": true, "added": quantity, "remaining": 0, "instance_ids": created_instances}

	for index in range(candidate.size()):
		if remaining <= 0:
			break
		var slot: Dictionary = candidate[index]
		if _is_empty_slot(slot) or slot.get("item_id", "") != item_id or slot.get("instance_id", "") != "":
			continue
		var free_space := int(definition.max_stack) - int(slot.quantity)
		if free_space <= 0:
			continue
		var amount: int = min(remaining, free_space)
		slot.quantity += amount
		candidate[index] = slot
		remaining -= amount

	for index in _empty_slot_indexes(candidate):
		if remaining <= 0:
			break
		var amount: int = min(remaining, int(definition.max_stack))
		candidate[index] = _new_slot(item_id, amount, "", metadata)
		remaining -= amount

	if remaining > 0:
		return _fail_and_emit({"ok": false, "reason": "inventory_full", "error": "Not enough inventory capacity."})

	slots = candidate
	_emit_changed()
	return {"ok": true, "added": quantity, "remaining": 0}

func remove_item(item_id: String, quantity := 1) -> Dictionary:
	var validation := _validate_quantity(item_id, quantity)
	if not validation.ok:
		return _fail_and_emit(validation)
	if get_total_quantity(item_id) < quantity:
		return _fail_and_emit({"ok": false, "reason": "insufficient_quantity", "error": "Not enough item quantity: %s" % item_id})

	var candidate := _duplicate_slots(slots)
	var remaining := quantity
	for index in range(candidate.size()):
		if remaining <= 0:
			break
		var slot: Dictionary = candidate[index]
		if _is_empty_slot(slot) or slot.get("item_id", "") != item_id:
			continue
		var amount: int = min(remaining, int(slot.quantity))
		slot.quantity -= amount
		remaining -= amount
		candidate[index] = {} if int(slot.quantity) <= 0 else slot

	slots = candidate
	_emit_changed()
	return {"ok": true, "removed": quantity}

func split_slot(from_index: int, quantity: int, to_index := -1) -> Dictionary:
	var index_result := _validate_slot_index(from_index)
	if not index_result.ok:
		return _fail_and_emit(index_result)
	var from_slot: Dictionary = slots[from_index]
	if _is_empty_slot(from_slot):
		return _fail_and_emit({"ok": false, "reason": "empty_slot", "error": "Source slot is empty."})
	if from_slot.get("instance_id", "") != "":
		return _fail_and_emit({"ok": false, "reason": "instance_item", "error": "Instance items cannot be split."})
	if quantity <= 0 or quantity >= int(from_slot.quantity):
		return _fail_and_emit({"ok": false, "reason": "invalid_quantity", "error": "Split quantity must be less than source quantity."})

	var target_index := to_index
	if target_index == -1:
		target_index = _first_empty_slot_index(slots)
	var target_result := _validate_slot_index(target_index)
	if not target_result.ok:
		return _fail_and_emit(target_result)

	var candidate := _duplicate_slots(slots)
	var target_slot: Dictionary = candidate[target_index]
	if not _is_empty_slot(target_slot):
		if target_slot.get("item_id", "") != from_slot.item_id or target_slot.get("instance_id", "") != "":
			return _fail_and_emit({"ok": false, "reason": "occupied_slot", "error": "Target slot cannot accept split items."})
		var definition: Dictionary = item_definitions[from_slot.item_id]
		if int(target_slot.quantity) + quantity > int(definition.max_stack):
			return _fail_and_emit({"ok": false, "reason": "stack_limit", "error": "Split target would exceed max stack."})
		target_slot.quantity += quantity
		candidate[target_index] = target_slot
	else:
		candidate[target_index] = _new_slot(from_slot.item_id, quantity, "", from_slot.get("metadata", {}))

	from_slot.quantity -= quantity
	candidate[from_index] = from_slot
	slots = candidate
	_emit_changed()
	return {"ok": true, "from_slot": from_index, "to_slot": target_index, "quantity": quantity}

func move_slot(from_index: int, to_index: int) -> Dictionary:
	var from_result := _validate_slot_index(from_index)
	if not from_result.ok:
		return _fail_and_emit(from_result)
	var to_result := _validate_slot_index(to_index)
	if not to_result.ok:
		return _fail_and_emit(to_result)
	if from_index == to_index:
		return {"ok": true}
	var moving: Dictionary = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = moving
	_emit_changed()
	return {"ok": true}

func extract_slot(index: int) -> Dictionary:
	var index_result := _validate_slot_index(index)
	if not index_result.ok:
		return _fail_and_emit(index_result)
	var slot: Dictionary = slots[index]
	if _is_empty_slot(slot):
		return _fail_and_emit({"ok": false, "reason": "empty_slot", "error": "Inventory slot is empty: %d" % index})
	slots[index] = {}
	_emit_changed()
	return {"ok": true, "slot": _duplicate_dictionary(slot), "slot_index": index}

func insert_slot(slot: Dictionary, to_index := -1) -> Dictionary:
	var slot_result := _normalize_snapshot_slot(slot)
	if not slot_result.ok:
		return _fail_and_emit(slot_result)
	var normalized_slot: Dictionary = slot_result.slot
	if _is_empty_slot(normalized_slot):
		return _fail_and_emit({"ok": false, "reason": "empty_slot", "error": "Cannot insert an empty inventory slot."})

	var target_index := to_index
	if target_index == -1:
		target_index = _first_empty_slot_index(slots)
	var index_result := _validate_slot_index(target_index)
	if not index_result.ok:
		return _fail_and_emit(index_result)
	if not _is_empty_slot(slots[target_index]):
		return _fail_and_emit({"ok": false, "reason": "occupied_slot", "error": "Inventory slot is occupied: %d" % target_index})

	var candidate := _duplicate_slots(slots)
	candidate[target_index] = normalized_slot
	var max_owned_result := _validate_max_owned(candidate)
	if not max_owned_result.ok:
		return _fail_and_emit(max_owned_result)
	slots = candidate
	_emit_changed()
	return {"ok": true, "slot_index": target_index, "slot": _duplicate_dictionary(normalized_slot)}

func sort_slots() -> Dictionary:
	var occupied: Array = []
	for slot in slots:
		if not _is_empty_slot(slot):
			occupied.append(_duplicate_dictionary(slot))
	occupied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _slot_sort_key(a) < _slot_sort_key(b)
	)
	slots.clear()
	for slot in occupied:
		slots.append(slot)
	while slots.size() < slot_count:
		slots.append({})
	_emit_changed()
	return {"ok": true}

func get_total_quantity(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if not _is_empty_slot(slot) and slot.get("item_id", "") == item_id:
			total += int(slot.quantity)
	return total

func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slot_count:
		return {}
	return _duplicate_dictionary(slots[index])

func first_slot_with_item(item_id: String) -> int:
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		if not _is_empty_slot(slot) and slot.get("item_id", "") == item_id:
			return index
	return -1

func to_snapshot() -> Dictionary:
	var snapshot_slots: Array = []
	for slot in slots:
		snapshot_slots.append(_duplicate_dictionary(slot))
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"slot_count": slot_count,
		"next_instance_id": next_instance_id,
		"slots": snapshot_slots
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported inventory snapshot schema version.")
	var loaded_slot_count := int(snapshot.get("slot_count", 0))
	if loaded_slot_count <= 0:
		return _fail("invalid_slot_count", "Inventory snapshot slot count must be positive.")
	var loaded_slots = snapshot.get("slots", [])
	if typeof(loaded_slots) != TYPE_ARRAY or loaded_slots.size() > loaded_slot_count:
		return _fail("invalid_slots", "Inventory snapshot slots are invalid.")

	var normalized_slots: Array = []
	for raw_slot in loaded_slots:
		var slot_result := _normalize_snapshot_slot(raw_slot)
		if not slot_result.ok:
			return slot_result
		normalized_slots.append(slot_result.slot)
	while normalized_slots.size() < loaded_slot_count:
		normalized_slots.append({})
	var max_owned_result := _validate_max_owned(normalized_slots)
	if not max_owned_result.ok:
		return max_owned_result

	slot_count = loaded_slot_count
	data_version = String(snapshot.get("data_version", ""))
	next_instance_id = max(1, int(snapshot.get("next_instance_id", 1)))
	slots = normalized_slots
	_emit_changed()
	return {"ok": true}

static func _definitions_from_catalog(catalog) -> Dictionary:
	var definitions: Dictionary = {}
	for row in _catalog_definitions(catalog, ITEM_SOURCE):
		var result := _definition_from_item(row)
		if not result.ok:
			return result
		definitions[result.definition.id] = result.definition
	for row in _catalog_definitions(catalog, TEA_SOURCE):
		var result := _definition_from_tea(row)
		if not result.ok:
			return result
		if definitions.has(result.definition.id):
			return {"ok": false, "reason": "duplicate_item_id", "error": "Duplicate inventory item id: %s" % result.definition.id}
		definitions[result.definition.id] = result.definition
	return {"ok": true, "definitions": definitions}

static func _definition_from_item(row: Dictionary) -> Dictionary:
	var max_stack_result := _optional_positive_integer(row, "max_stack", 1)
	if not max_stack_result.ok:
		return max_stack_result
	var max_owned_result := _optional_non_negative_integer(row, "max_owned", 0)
	if not max_owned_result.ok:
		return max_owned_result
	var kind := String(row.get("type", ""))
	var definition := {
		"id": String(row.id),
		"name": String(row.get("name", row.id)),
		"kind": kind,
		"source": ITEM_SOURCE,
		"max_stack": max_stack_result.value,
		"max_owned": max_owned_result.value,
		"effect_type": _normalized_item_effect_type(row),
		"requires_instance": bool(INDIVIDUAL_ITEM_TYPES.get(kind, false))
	}
	return {"ok": true, "definition": definition}

static func _definition_from_tea(row: Dictionary) -> Dictionary:
	var max_stack_result := _optional_positive_integer(row, "max_stack", 1)
	if not max_stack_result.ok:
		return max_stack_result
	var max_owned_result := _optional_non_negative_integer(row, "max_owned", 0)
	if not max_owned_result.ok:
		return max_owned_result
	var definition := {
		"id": String(row.id),
		"name": String(row.get("name", row.id)),
		"kind": TEA_LEAF_KIND,
		"source": TEA_SOURCE,
		"max_stack": max_stack_result.value,
		"max_owned": max_owned_result.value,
		"effect_type": _normalized_item_effect_type(row),
		"requires_instance": false
	}
	return {"ok": true, "definition": definition}

static func _required_positive_integer_balance(catalog, id: String) -> Dictionary:
	if not catalog.has_method("find_by_id"):
		return {"ok": false, "reason": "invalid_catalog", "error": "Catalog cannot look up balance values."}
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return {"ok": false, "reason": "missing_balance", "error": "Missing required inventory balance value: %s" % id}
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return {"ok": false, "reason": "invalid_balance", "error": "Inventory balance value must be numeric: %s" % id}
	if float(value) != floor(float(value)) or int(value) <= 0:
		return {"ok": false, "reason": "invalid_balance", "error": "Inventory balance value must be a positive integer: %s" % id}
	return {"ok": true, "value": int(value)}

static func _optional_positive_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return {"ok": false, "reason": "invalid_definition", "error": "Inventory definition field must be numeric: %s.%s" % [row.get("id", ""), field]}
	if float(value) != floor(float(value)) or int(value) <= 0:
		return {"ok": false, "reason": "invalid_definition", "error": "Inventory definition field must be a positive integer: %s.%s" % [row.get("id", ""), field]}
	return {"ok": true, "value": int(value)}

static func _optional_non_negative_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return {"ok": false, "reason": "invalid_definition", "error": "Inventory definition field must be numeric: %s.%s" % [row.get("id", ""), field]}
	if float(value) != floor(float(value)) or int(value) < 0:
		return {"ok": false, "reason": "invalid_definition", "error": "Inventory definition field must be a non-negative integer: %s.%s" % [row.get("id", ""), field]}
	return {"ok": true, "value": int(value)}

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

func _validate_quantity(item_id: String, quantity: int) -> Dictionary:
	if not item_definitions.has(item_id):
		return {"ok": false, "reason": "unknown_item", "error": "Unknown inventory item: %s" % item_id}
	if quantity <= 0:
		return {"ok": false, "reason": "invalid_quantity", "error": "Quantity must be positive."}
	return {"ok": true}

func _normalize_snapshot_slot(raw_slot) -> Dictionary:
	if typeof(raw_slot) != TYPE_DICTIONARY:
		return _fail("invalid_slot", "Inventory snapshot slot must be a dictionary.")
	if _is_empty_slot(raw_slot):
		return {"ok": true, "slot": {}}
	var item_id := String(raw_slot.get("item_id", ""))
	if not item_definitions.has(item_id):
		return _fail("unknown_item", "Inventory snapshot references unknown item: %s" % item_id)
	var definition: Dictionary = item_definitions[item_id]
	var quantity := int(raw_slot.get("quantity", 0))
	if quantity <= 0 or quantity > int(definition.max_stack):
		return _fail("invalid_quantity", "Inventory snapshot quantity is outside max stack: %s" % item_id)
	var instance_id := String(raw_slot.get("instance_id", ""))
	if _requires_instance(definition) and instance_id.is_empty():
		return _fail("missing_instance_id", "Inventory snapshot instance item is missing an instance id: %s" % item_id)
	return {"ok": true, "slot": _new_slot(item_id, quantity, instance_id, raw_slot.get("metadata", {}))}

func _validate_max_owned(source_slots: Array) -> Dictionary:
	var quantities := {}
	for slot in source_slots:
		if _is_empty_slot(slot):
			continue
		var item_id := String(slot.get("item_id", ""))
		quantities[item_id] = int(quantities.get(item_id, 0)) + int(slot.get("quantity", 0))
	for item_id in quantities:
		var definition: Dictionary = item_definitions.get(item_id, {})
		var max_owned := int(definition.get("max_owned", 0))
		if max_owned > 0 and int(quantities[item_id]) > max_owned:
			return _fail("max_owned_exceeded", "Item ownership limit exceeded: %s" % item_id)
	return {"ok": true}

func _next_instance_id() -> String:
	var value := "inst_%06d" % next_instance_id
	next_instance_id += 1
	return value

func _empty_slot_indexes(source_slots: Array) -> Array:
	var indexes: Array = []
	for index in range(source_slots.size()):
		if _is_empty_slot(source_slots[index]):
			indexes.append(index)
	return indexes

func _first_empty_slot_index(source_slots: Array) -> int:
	for index in range(source_slots.size()):
		if _is_empty_slot(source_slots[index]):
			return index
	return -1

func _validate_slot_index(index: int) -> Dictionary:
	if index < 0 or index >= slot_count:
		return {"ok": false, "reason": "invalid_slot", "error": "Inventory slot index is out of range: %d" % index}
	return {"ok": true}

func _emit_changed() -> void:
	changed.emit(to_snapshot())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}

static func _requires_instance(definition: Dictionary) -> bool:
	return bool(definition.get("requires_instance", false))

static func _normalized_item_effect_type(row: Dictionary) -> String:
	var raw := String(row.get("effect_type", row.get("effect", ""))).strip_edges()
	match raw:
		"부활", "resurrection":
			return "resurrection"
		_:
			return raw

static func _new_slot(item_id: String, quantity: int, instance_id := "", metadata := {}) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": quantity,
		"instance_id": instance_id,
		"metadata": _duplicate_dictionary(metadata)
	}

static func _is_empty_slot(slot) -> bool:
	return typeof(slot) != TYPE_DICTIONARY or slot.is_empty()

static func _duplicate_slots(source_slots: Array) -> Array:
	var copy: Array = []
	for slot in source_slots:
		copy.append(_duplicate_dictionary(slot))
	return copy

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

func _slot_sort_key(slot: Dictionary) -> String:
	var item_id := String(slot.get("item_id", ""))
	if item_id.is_empty():
		return "zzzz"
	var definition: Dictionary = item_definitions.get(item_id, {})
	return "%s|%s|%s|%s" % [
		String(definition.get("source", "")),
		String(definition.get("kind", "")),
		item_id,
		String(slot.get("instance_id", ""))
	]
