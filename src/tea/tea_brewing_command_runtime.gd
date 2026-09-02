extends RefCounted
class_name TeaBrewingCommandRuntime

const GameCommand = preload("res://src/core/commands/game_command.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")

signal read_model_changed(read_model: Dictionary)
signal operation_failed(error: Dictionary)

const SNAPSHOT_SCHEMA_VERSION := 1
const TEA_LEAF_KIND := "찻잎"
const VESSEL_KIND := "다구"
const VESSEL_SOURCE_INVENTORY := "inventory"
const VESSEL_SOURCE_EQUIPPED := "equipped"
const NAVIGATION_LEAF := "leaf"
const NAVIGATION_VESSEL := "vessel"
const NAVIGATION_SLOT := "slot"

var data_version := ""
var tea_service
var inventory
var equipment
var context_provider: Callable
var selected_leaf_id := ""
var selected_vessel_key := ""
var selected_slot_index := 0

func configure(new_tea_service, new_inventory, new_equipment = null, new_context_provider := Callable(), new_data_version := "") -> Dictionary:
	if new_tea_service == null \
			or not new_tea_service.has_method("preview_brew") \
			or not new_tea_service.has_method("preview_brew_with_modifier_query") \
			or not new_tea_service.has_method("brew") \
			or not new_tea_service.has_method("brew_with_modifier_query") \
			or not new_tea_service.has_method("to_snapshot"):
		return _fail("invalid_tea_service", "Tea brewing command runtime requires the tea service public boundary.")
	if new_inventory == null or not new_inventory.has_method("get_slot") or not new_inventory.has_method("definition_for") or not new_inventory.has_method("get_total_quantity"):
		return _fail("invalid_inventory", "Tea brewing command runtime requires an inventory model.")
	tea_service = new_tea_service
	inventory = new_inventory
	equipment = new_equipment
	context_provider = new_context_provider
	data_version = new_data_version
	selected_leaf_id = _first_leaf_id()
	selected_vessel_key = _first_vessel_key()
	selected_slot_index = _first_brew_slot()
	_emit_changed()
	return {"ok": true}

func read_model() -> Dictionary:
	var leaves := _tea_leaf_rows()
	var vessels := _vessel_rows()
	if selected_leaf_id.is_empty() and not leaves.is_empty():
		selected_leaf_id = String(leaves[0].id)
	if selected_vessel_key.is_empty() and not vessels.is_empty():
		selected_vessel_key = String(vessels[0].selection_key)
	var quickslots := _quickslot_rows()
	if selected_slot_index < 0 and not quickslots.is_empty():
		selected_slot_index = int(quickslots[0].slot_index)
	for leaf in leaves:
		leaf["selected"] = String(leaf.id) == selected_leaf_id
	for vessel in vessels:
		vessel["selected"] = String(vessel.selection_key) == selected_vessel_key
	for slot in quickslots:
		slot["selected"] = int(slot.slot_index) == selected_slot_index
	var preview := _preview_for_selection()
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"read_only": true,
		"selected_leaf_id": selected_leaf_id,
		"selected_vessel_key": selected_vessel_key,
		"selected_slot_index": selected_slot_index,
		"has_brewing_location": bool(_brewing_context().get("has_brewing_location", false)),
		"leaves": leaves,
		"vessels": vessels,
		"quickslots": quickslots,
		"preview": preview,
		"can_brew": bool(preview.get("ok", false)) and not bool(preview.get("target_slot_occupied", false)),
		"commands": {
			"select_leaf": GameCommand.Type.TEA_BREW_SELECT_LEAF,
			"select_vessel": GameCommand.Type.TEA_BREW_SELECT_VESSEL,
			"select_slot": GameCommand.Type.TEA_BREW_SELECT_SLOT,
			"brew": GameCommand.Type.BREW_TEA,
			"navigate": GameCommand.Type.TEA_BREW_NAVIGATE
		}
	}

func handle_command(command) -> Dictionary:
	if not command is GameCommand:
		return _fail_and_emit(_fail("invalid_command", "Tea brewing runtime requires a GameCommand."))
	match command.type:
		GameCommand.Type.TEA_BREW_SELECT_LEAF:
			return select_leaf(String(command.payload.get("tea_id", command.payload.get("leaf_id", ""))))
		GameCommand.Type.TEA_BREW_SELECT_VESSEL:
			return select_vessel(String(command.payload.get("vessel_key", command.payload.get("selection_key", ""))))
		GameCommand.Type.TEA_BREW_SELECT_SLOT:
			return select_slot(_command_slot(command))
		GameCommand.Type.TEA_BREW_NAVIGATE:
			return navigate(String(command.payload.get("target", NAVIGATION_LEAF)), command.direction)
		GameCommand.Type.BREW_TEA:
			return brew_selected()
		_:
			return _fail_and_emit(_fail("unsupported_command", "Unsupported tea brewing command."))

func select_leaf(tea_id: String) -> Dictionary:
	if not _has_leaf(tea_id):
		return _fail_and_emit(_fail("unknown_tea_leaf", "Tea leaf is not available: %s" % tea_id))
	selected_leaf_id = tea_id
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func select_vessel(selection_key: String) -> Dictionary:
	if not _vessel_by_key(selection_key).ok:
		return _fail_and_emit(_fail("unknown_vessel", "Tea ware is not available: %s" % selection_key))
	selected_vessel_key = selection_key
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func select_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _quickslot_rows().size():
		return _fail_and_emit(_fail("invalid_quickslot", "Tea quickslot is outside the read model: %d" % slot_index))
	selected_slot_index = slot_index
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func navigate(target: String, direction: Vector2i) -> Dictionary:
	var offset := 1
	if direction.x < 0 or direction.y < 0:
		offset = -1
	match target:
		NAVIGATION_VESSEL:
			selected_vessel_key = _next_selection_key(_vessel_rows(), "selection_key", selected_vessel_key, offset)
		NAVIGATION_SLOT:
			selected_slot_index = int(_next_slot_index(offset))
		_:
			selected_leaf_id = _next_selection_key(_tea_leaf_rows(), "id", selected_leaf_id, offset)
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func brew_selected() -> Dictionary:
	var preview := _preview_for_selection()
	if not bool(preview.get("ok", false)):
		return _fail_and_emit(_fail(String(preview.get("reason", "invalid_brew_selection")), String(preview.get("error", "Tea brewing selection is invalid."))))
	if bool(preview.get("target_slot_occupied", false)):
		return _fail_and_emit(_fail("quickslot_occupied", "Tea quickslot is already occupied: %d" % selected_slot_index))
	var vessel_result := _vessel_by_key(selected_vessel_key)
	if not vessel_result.ok:
		return _fail_and_emit(vessel_result)
	var result: Dictionary
	if String(vessel_result.vessel.source) == VESSEL_SOURCE_EQUIPPED:
		result = tea_service.brew_with_modifier_query(selected_leaf_id, _modifier_for_vessel(vessel_result.vessel), inventory, selected_slot_index, _brewing_context())
	else:
		result = tea_service.brew(selected_leaf_id, String(vessel_result.vessel.id), inventory, selected_slot_index, _brewing_context())
	if not result.ok:
		return _fail_and_emit(result)
	selected_leaf_id = _first_leaf_id()
	selected_slot_index = _first_brew_slot()
	_emit_changed()
	result["read_model"] = read_model()
	return result

func _preview_for_selection() -> Dictionary:
	if selected_leaf_id.is_empty():
		return _fail("missing_tea_leaf", "Select tea leaves before brewing.")
	var vessel_result := _vessel_by_key(selected_vessel_key)
	if not vessel_result.ok:
		return vessel_result
	var context := _brewing_context()
	var preview: Dictionary
	if String(vessel_result.vessel.source) == VESSEL_SOURCE_EQUIPPED:
		preview = tea_service.preview_brew_with_modifier_query(selected_leaf_id, _modifier_for_vessel(vessel_result.vessel), context)
	else:
		preview = tea_service.preview_brew(selected_leaf_id, String(vessel_result.vessel.id), context)
	if not preview.ok:
		return preview
	preview["target_slot_index"] = selected_slot_index
	preview["target_slot_occupied"] = selected_slot_index >= 0 and tea_service.has_prepared_tea(selected_slot_index)
	preview["required_leaf_units"] = int(preview.prepared_tea.get("serving_size", 1))
	preview["leaf_quantity"] = inventory.get_total_quantity(selected_leaf_id)
	preview["has_leaf_quantity"] = int(preview.leaf_quantity) >= int(preview.required_leaf_units)
	if not bool(preview.has_leaf_quantity):
		preview["ok"] = false
		preview["reason"] = "missing_tea_leaf"
		preview["error"] = "Brewing requires tea leaf units: %s" % selected_leaf_id
	return preview

func _tea_leaf_rows() -> Array:
	var rows := []
	for index in range(_slot_count()):
		var slot := _slot_at(index)
		if slot.is_empty():
			continue
		var item_id := String(slot.get("item_id", ""))
		var definition := _definition(item_id)
		if String(definition.get("kind", definition.get("type", ""))) != TEA_LEAF_KIND:
			continue
		rows.append({
			"id": item_id,
			"slot_index": index,
			"name": String(definition.get("name", item_id)),
			"quantity": int(slot.get("quantity", 0)),
			"serving_size": int(tea_service.tea_definitions.get(item_id, {}).get("serving_size", 1)),
			"requires_brewing_location": bool(tea_service.tea_definitions.get(item_id, {}).get("requires_brewing_location", false)),
			"selected": item_id == selected_leaf_id
		})
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.name) < String(right.name)
	)
	return rows

func _vessel_rows() -> Array:
	var rows := []
	for index in range(_slot_count()):
		var slot := _slot_at(index)
		if slot.is_empty():
			continue
		var item_id := String(slot.get("item_id", ""))
		var definition := _definition(item_id)
		if String(definition.get("kind", definition.get("type", ""))) != VESSEL_KIND:
			continue
		rows.append(_vessel_row(item_id, String(definition.get("name", item_id)), VESSEL_SOURCE_INVENTORY, index, "inventory:%s:%d" % [item_id, index], {}))
	var equipped := _equipped_tea_ware_payload()
	if not equipped.is_empty():
		rows.append(_vessel_row(String(equipped.item_id), String(equipped.name), VESSEL_SOURCE_EQUIPPED, -1, "equipped:%s" % String(equipped.instance_id), equipped))
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if String(left.source) == String(right.source):
			return String(left.name) < String(right.name)
		return String(left.source) < String(right.source)
	)
	return rows

func _vessel_row(item_id: String, name: String, source: String, inventory_slot_index: int, selection_key: String, payload: Dictionary) -> Dictionary:
	var modifier: Dictionary = tea_service.get_vessel_modifier_query(item_id)
	if source == VESSEL_SOURCE_EQUIPPED:
		modifier = _modifier_for_vessel({"id": item_id, "equipped_payload": payload})
	return {
		"id": item_id,
		"selection_key": selection_key,
		"name": name,
		"source": source,
		"inventory_slot_index": inventory_slot_index,
		"equipped_slot": EquipmentModel.SLOT_TEA_WARE if source == VESSEL_SOURCE_EQUIPPED else "",
		"instance_id": String(payload.get("instance_id", "")),
		"carry_use_bonus": int(modifier.get("carry_use_bonus", 0)),
		"tea_recovery_bonus": int(modifier.get("tea_recovery_bonus", 0)),
		"selected": selection_key == selected_vessel_key
	}

func _quickslot_rows() -> Array:
	var rows := []
	for index in range(int(tea_service.quickslot_count)):
		var prepared: Dictionary = tea_service.get_prepared_tea(index)
		rows.append({
			"slot_index": index,
			"empty": prepared.is_empty(),
			"selected": index == selected_slot_index,
			"prepared_tea": prepared,
			"label": "차%d 빈 슬롯" % (index + 1) if prepared.is_empty() else "차%d %s x%d" % [index + 1, String(prepared.get("tea_name", prepared.get("tea_id", ""))), int(prepared.get("remaining_uses", 0))]
		})
	return rows

func _modifier_for_vessel(vessel: Dictionary) -> Dictionary:
	if String(vessel.get("source", "")) == VESSEL_SOURCE_EQUIPPED and equipment != null and equipment.has_method("get_tea_modifier_query"):
		return equipment.get_tea_modifier_query()
	if vessel.has("equipped_payload") and equipment != null and equipment.has_method("get_tea_modifier_query"):
		return equipment.get_tea_modifier_query()
	return tea_service.get_vessel_modifier_query(String(vessel.get("id", "")))

func _vessel_by_key(selection_key: String) -> Dictionary:
	for vessel in _vessel_rows():
		if String(vessel.selection_key) == selection_key:
			return {"ok": true, "vessel": vessel}
	return _fail("unknown_vessel", "Tea ware is not available: %s" % selection_key)

func _has_leaf(tea_id: String) -> bool:
	for row in _tea_leaf_rows():
		if String(row.id) == tea_id:
			return true
	return false

func _first_leaf_id() -> String:
	var leaves := _tea_leaf_rows()
	return String(leaves[0].id) if not leaves.is_empty() else ""

func _first_vessel_key() -> String:
	var vessels := _vessel_rows()
	return String(vessels[0].selection_key) if not vessels.is_empty() else ""

func _first_brew_slot() -> int:
	var empty: int = tea_service.first_empty_quickslot()
	return empty if empty >= 0 else 0

func _next_slot_index(offset: int) -> int:
	var count := int(tea_service.quickslot_count)
	if count <= 0:
		return -1
	return (selected_slot_index + offset + count) % count

func _next_selection_key(rows: Array, key: String, selected: String, offset: int) -> String:
	if rows.is_empty():
		return ""
	var index := 0
	for row_index in range(rows.size()):
		if String(rows[row_index].get(key, "")) == selected:
			index = row_index
			break
	return String(rows[(index + offset + rows.size()) % rows.size()].get(key, ""))

func _brewing_context() -> Dictionary:
	if context_provider.is_valid():
		var value = context_provider.call()
		if typeof(value) == TYPE_DICTIONARY:
			return value.duplicate(true)
	return {}

func _equipped_tea_ware_payload() -> Dictionary:
	if equipment == null or not equipment.has_method("get_equipped_slot"):
		return {}
	var payload: Dictionary = equipment.get_equipped_slot(EquipmentModel.SLOT_TEA_WARE)
	if payload.is_empty():
		return {}
	var definition: Dictionary = payload.get("definition", {})
	return {
		"item_id": String(payload.get("item_id", definition.get("id", ""))),
		"name": String(definition.get("name", payload.get("item_id", ""))),
		"instance_id": String(payload.get("instance_id", "")),
		"definition": definition
	}

func _slot_count() -> int:
	return int(inventory.get("slot_count")) if inventory != null and inventory.has_method("get") else 0

func _slot_at(index: int) -> Dictionary:
	var slot = inventory.get_slot(index)
	return slot.duplicate(true) if typeof(slot) == TYPE_DICTIONARY else {}

func _definition(item_id: String) -> Dictionary:
	var definition = inventory.definition_for(item_id)
	return definition.duplicate(true) if typeof(definition) == TYPE_DICTIONARY else {}

func _command_slot(command: GameCommand) -> int:
	if command.payload.has("slot_index"):
		return int(command.payload.slot_index)
	return int(command.slot)

func _emit_changed() -> void:
	read_model_changed.emit(read_model())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
