extends RefCounted
class_name InventoryCommandRuntime

const GameCommand = preload("res://src/core/commands/game_command.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")

signal read_model_changed(read_model: Dictionary)
signal operation_failed(error: Dictionary)

const SNAPSHOT_SCHEMA_VERSION := 1
const FILTER_ALL := "all"
const SORT_KIND_NAME := "kind_name"
const EQUIPPABLE_KINDS := {
	"무기": true,
	"방어구": true,
	"다구": true
}
const USABLE_KINDS := {
	"소모품": true
}

var data_version := ""
var inventory
var equipment
var consumable_service
var filter_kind := FILTER_ALL
var sort_mode := SORT_KIND_NAME
var selected_slot_index := -1

func configure(new_inventory, new_equipment = null, new_consumable_service = null, new_data_version := "") -> Dictionary:
	if new_inventory == null or not new_inventory.has_method("get_slot") or not new_inventory.has_method("definition_for"):
		return _fail("invalid_inventory", "Inventory command runtime requires an inventory model.")
	inventory = new_inventory
	equipment = new_equipment
	consumable_service = new_consumable_service
	data_version = new_data_version
	filter_kind = FILTER_ALL
	sort_mode = SORT_KIND_NAME
	selected_slot_index = _first_visible_slot_index()
	_emit_changed()
	return {"ok": true}

func read_model() -> Dictionary:
	var total_slots := _slot_count()
	var used_slots := 0
	var rows := []
	var kind_index := {FILTER_ALL: true}
	for index in range(total_slots):
		var slot := _slot_at(index)
		if not slot.is_empty():
			used_slots += 1
		var row := _row_for_slot(index, slot)
		if not row.kind.is_empty():
			kind_index[row.kind] = true
		if _row_matches_filter(row):
			rows.append(row)
	var kinds := kind_index.keys()
	kinds.sort()
	var selected_visible := false
	for row in rows:
		if int(row.slot_index) == selected_slot_index:
			selected_visible = true
			break
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"read_only": true,
		"filter_kind": filter_kind,
		"sort_mode": sort_mode,
		"selected_slot_index": selected_slot_index if selected_visible else -1,
		"capacity": {"used": used_slots, "total": total_slots, "empty": total_slots - used_slots, "full": used_slots >= total_slots},
		"available_filters": kinds,
		"slots": rows,
		"equipment": _equipment_read_model()
	}

func handle_command(command) -> Dictionary:
	if not command is GameCommand:
		return _fail_and_emit(_fail("invalid_command", "Inventory command runtime requires a GameCommand."))
	match command.type:
		GameCommand.Type.INVENTORY_SET_FILTER:
			return set_filter(String(command.payload.get("kind", FILTER_ALL)))
		GameCommand.Type.INVENTORY_SORT:
			return sort_inventory(String(command.payload.get("sort_mode", SORT_KIND_NAME)))
		GameCommand.Type.INVENTORY_SELECT_SLOT:
			return select_slot(_command_slot(command))
		GameCommand.Type.INVENTORY_NAVIGATE:
			return navigate(command.direction)
		GameCommand.Type.EQUIP_INVENTORY_SLOT:
			return equip_slot(_command_slot(command))
		GameCommand.Type.UNEQUIP_SLOT:
			return unequip_slot(String(command.payload.get("equipment_slot", "")), int(command.payload.get("target_slot", -1)))
		GameCommand.Type.USE_INVENTORY_SLOT:
			return use_slot(_command_slot(command))
		_:
			return _fail_and_emit(_fail("unsupported_command", "Unsupported inventory command."))

func set_filter(kind: String) -> Dictionary:
	filter_kind = FILTER_ALL if kind.is_empty() else kind
	selected_slot_index = _first_visible_slot_index()
	_emit_changed()
	return {"ok": true, "filter_kind": filter_kind, "read_model": read_model()}

func sort_inventory(new_sort_mode := SORT_KIND_NAME) -> Dictionary:
	if not inventory.has_method("sort_slots"):
		return _fail_and_emit(_fail("invalid_inventory", "Inventory cannot sort slots."))
	sort_mode = SORT_KIND_NAME if String(new_sort_mode).is_empty() else String(new_sort_mode)
	var result: Dictionary = inventory.sort_slots()
	if not result.ok:
		return _fail_and_emit(result)
	selected_slot_index = _first_visible_slot_index()
	_emit_changed()
	return {"ok": true, "sort_mode": sort_mode, "read_model": read_model()}

func select_slot(slot_index: int) -> Dictionary:
	var row := _row_by_slot_index(slot_index)
	if row.is_empty():
		return _fail_and_emit(_fail("invalid_inventory_slot", "Inventory slot is outside the current read model: %d" % slot_index))
	selected_slot_index = slot_index
	_emit_changed()
	return {"ok": true, "selected_slot_index": selected_slot_index, "read_model": read_model()}

func navigate(direction: Vector2i) -> Dictionary:
	var indexes := _visible_slot_indexes()
	if indexes.is_empty():
		selected_slot_index = -1
		_emit_changed()
		return {"ok": true, "selected_slot_index": -1, "read_model": read_model()}
	var offset := 1
	if direction.x < 0 or direction.y < 0:
		offset = -1
	var current := indexes.find(selected_slot_index)
	if current < 0:
		current = 0 if offset > 0 else indexes.size() - 1
	else:
		current = (current + offset + indexes.size()) % indexes.size()
	selected_slot_index = int(indexes[current])
	_emit_changed()
	return {"ok": true, "selected_slot_index": selected_slot_index, "read_model": read_model()}

func equip_slot(slot_index: int) -> Dictionary:
	if equipment == null or not equipment.has_method("equip_from_inventory"):
		return _fail_and_emit(_fail("missing_equipment", "Equipment model is required to equip inventory slots."))
	var row := _row_by_slot_index(slot_index)
	if row.is_empty() or not bool(row.can_equip):
		return _fail_and_emit(_fail("not_equippable", "Inventory slot cannot be equipped: %d" % slot_index))
	var result: Dictionary = equipment.equip_from_inventory(inventory, slot_index)
	if not result.ok:
		return _fail_and_emit(result)
	selected_slot_index = _nearest_visible_slot_index(slot_index)
	_emit_changed()
	result["read_model"] = read_model()
	return result

func unequip_slot(equipment_slot: String, target_slot := -1) -> Dictionary:
	if equipment == null or not equipment.has_method("unequip_to_inventory"):
		return _fail_and_emit(_fail("missing_equipment", "Equipment model is required to unequip slots."))
	var result: Dictionary = equipment.unequip_to_inventory(equipment_slot, inventory, target_slot)
	if not result.ok:
		return _fail_and_emit(result)
	selected_slot_index = int(result.get("inventory_slot", _first_visible_slot_index()))
	_emit_changed()
	result["read_model"] = read_model()
	return result

func use_slot(slot_index: int) -> Dictionary:
	var row := _row_by_slot_index(slot_index)
	if row.is_empty() or not bool(row.can_use):
		return _fail_and_emit(_fail("not_usable", "Inventory slot cannot be used: %d" % slot_index))
	if bool(row.can_equip):
		return equip_slot(slot_index)
	if consumable_service != null and consumable_service.has_method("start_use") and consumable_service.has_definition(String(row.item_id)):
		var result: Dictionary = consumable_service.start_use(String(row.item_id), inventory, {"inventory_slot_index": slot_index})
		if not result.ok:
			return _fail_and_emit(result)
		_emit_changed()
		result["read_model"] = read_model()
		return result
	return _fail_and_emit(_fail("unsupported_use", "Inventory slot use is not supported for item: %s" % String(row.item_id)))

func _row_for_slot(index: int, slot: Dictionary) -> Dictionary:
	if slot.is_empty():
		return {
			"slot_index": index,
			"empty": true,
			"selected": index == selected_slot_index,
			"label": "%02d 빈 슬롯" % (index + 1),
			"item_id": "",
			"name": "",
			"kind": "",
			"quantity": 0,
			"max_stack": 0,
			"stack_label": "0/0",
			"can_equip": false,
			"can_use": false,
			"commands": _commands_for_slot(index, false, false)
		}
	var item_id := String(slot.get("item_id", ""))
	var definition := _definition(item_id)
	var kind := String(definition.get("kind", definition.get("type", "")))
	var max_stack: int = max(1, int(definition.get("max_stack", slot.get("quantity", 1))))
	var can_equip := bool(EQUIPPABLE_KINDS.get(kind, false))
	var can_use := can_equip or _can_use_consumable(kind, item_id)
	return {
		"slot_index": index,
		"empty": false,
		"selected": index == selected_slot_index,
		"item_id": item_id,
		"instance_id": String(slot.get("instance_id", "")),
		"name": String(definition.get("name", item_id)),
		"kind": kind,
		"quantity": int(slot.get("quantity", 0)),
		"max_stack": max_stack,
		"stack_label": "%d/%d" % [int(slot.get("quantity", 0)), max_stack],
		"metadata": _dictionary_value(slot.get("metadata", {})),
		"can_equip": can_equip,
		"can_use": can_use,
		"label": "%02d %s x%d (%d/%d)" % [index + 1, String(definition.get("name", item_id)), int(slot.get("quantity", 0)), int(slot.get("quantity", 0)), max_stack],
		"commands": _commands_for_slot(index, can_equip, can_use)
	}

func _commands_for_slot(index: int, can_equip: bool, can_use: bool) -> Dictionary:
	var commands := {
		"select": {"type": GameCommand.Type.INVENTORY_SELECT_SLOT, "slot": index, "payload": {"slot_index": index}}
	}
	if can_equip:
		commands["equip"] = {"type": GameCommand.Type.EQUIP_INVENTORY_SLOT, "slot": index, "payload": {"slot_index": index}}
	if can_use:
		commands["use"] = {"type": GameCommand.Type.USE_INVENTORY_SLOT, "slot": index, "payload": {"slot_index": index}}
	return commands

func _can_use_consumable(kind: String, item_id: String) -> bool:
	return bool(USABLE_KINDS.get(kind, false)) \
		and consumable_service != null \
		and consumable_service.has_method("has_definition") \
		and consumable_service.has_definition(item_id)

func _equipment_read_model() -> Dictionary:
	var result := {}
	if equipment == null or not equipment.has_method("get_equipped_slot"):
		return result
	for slot_key in EquipmentModel.SLOT_KEYS:
		result[slot_key] = equipment.get_equipped_slot(slot_key)
	return result

func _row_matches_filter(row: Dictionary) -> bool:
	return filter_kind == FILTER_ALL or String(row.get("kind", "")) == filter_kind

func _row_by_slot_index(slot_index: int) -> Dictionary:
	for row in read_model().slots:
		if int(row.slot_index) == slot_index:
			return row
	return {}

func _visible_slot_indexes() -> Array:
	var indexes := []
	for row in read_model().slots:
		indexes.append(int(row.slot_index))
	return indexes

func _first_visible_slot_index() -> int:
	var indexes := _visible_slot_indexes_without_read_model()
	return -1 if indexes.is_empty() else int(indexes[0])

func _nearest_visible_slot_index(previous_index: int) -> int:
	var indexes := _visible_slot_indexes_without_read_model()
	if indexes.is_empty():
		return -1
	for index in indexes:
		if int(index) >= previous_index:
			return int(index)
	return int(indexes[indexes.size() - 1])

func _visible_slot_indexes_without_read_model() -> Array:
	var indexes := []
	for index in range(_slot_count()):
		var row := _row_for_slot(index, _slot_at(index))
		if _row_matches_filter(row):
			indexes.append(index)
	return indexes

func _slot_count() -> int:
	return int(inventory.get("slot_count")) if inventory != null and inventory.has_method("get") else 0

func _slot_at(index: int) -> Dictionary:
	if inventory == null or not inventory.has_method("get_slot"):
		return {}
	return _dictionary_value(inventory.get_slot(index))

func _definition(item_id: String) -> Dictionary:
	if inventory != null and inventory.has_method("definition_for"):
		return _dictionary_value(inventory.definition_for(item_id))
	return {}

func _command_slot(command: GameCommand) -> int:
	return int(command.payload.get("slot_index", command.slot))

func _emit_changed() -> void:
	read_model_changed.emit(read_model())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
