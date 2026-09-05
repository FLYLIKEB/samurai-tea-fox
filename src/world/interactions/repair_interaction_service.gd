extends RefCounted
class_name RepairInteractionService

const ITEM_SOURCE := "items"

signal operation_failed(error: Dictionary)
signal interaction_completed(result: Dictionary)

var data_version := ""
var definitions_by_target_id: Dictionary = {}
var actions_by_id: Dictionary = {}

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Repair interactions require catalog item definitions.")
	var definitions := {}
	for row in catalog.get_definitions(ITEM_SOURCE):
		var interaction = row.get("interaction_definition", {})
		if typeof(interaction) != TYPE_DICTIONARY or interaction.is_empty():
			continue
		if not interaction.has("target") or not interaction.has("actions"):
			continue
		var normalized: Dictionary = _normalize_definition(interaction, String(row.get("id", "")))
		var validation: Dictionary = _validate_definition(normalized)
		if not validation.ok:
			return validation
		definitions[String(normalized.target.definition_id)] = normalized
	var service: RepairInteractionService = load("res://src/world/interactions/repair_interaction_service.gd").new()
	service.configure(definitions, _catalog_data_version(catalog))
	return {"ok": true, "repair_interaction_service": service}

func configure(new_definitions_by_target_id: Dictionary, new_data_version := "") -> Dictionary:
	definitions_by_target_id = _duplicate_dictionary(new_definitions_by_target_id)
	actions_by_id.clear()
	data_version = new_data_version
	for target_id in definitions_by_target_id:
		var definition: Dictionary = definitions_by_target_id[target_id]
		for action in definition.get("actions", []):
			actions_by_id[String(action.get("id", ""))] = {"target_id": String(target_id), "action": action.duplicate(true)}
	return {"ok": true}

func world_generation_targets_for_biome(biome_id: String) -> Array:
	var targets := []
	for target_id in definitions_by_target_id:
		var definition: Dictionary = definitions_by_target_id[target_id]
		var target: Dictionary = definition.get("target", {})
		if String(target.get("biome_id", "")) != biome_id:
			continue
		targets.append({
			"definition_id": String(target.get("definition_id", target_id)),
			"source_facility_item_id": String(target.get("source_facility_item_id", "")),
			"initial_state": String(target.get("initial_state", "broken")),
			"count_per_biome": int(target.get("count_per_biome", 1)),
			"placement": String(target.get("placement", "")),
			"biome_id": biome_id
		})
	targets.sort_custom(func(a, b): return String(a.definition_id) < String(b.definition_id))
	return targets

func has_target(target_id: String) -> bool:
	return definitions_by_target_id.has(target_id)

func handle_command(action_id: String, target_id: String, inventory, run_state, world_data, current_biome_id := "") -> Dictionary:
	var validation := _validate_action_request(action_id, target_id, inventory, run_state, world_data, current_biome_id)
	if not validation.ok:
		return _fail_and_emit(validation)
	var definition: Dictionary = validation.definition
	var action: Dictionary = validation.action
	var inventory_snapshot: Dictionary = inventory.to_snapshot()
	var interaction_snapshot: Dictionary = run_state.world_interactions.duplicate(true)
	var placed_snapshot: Array = run_state.placed_facilities.duplicate(true)

	for material in action.get("materials", []):
		var removed: Dictionary = inventory.remove_item(String(material.get("item_id", "")), int(material.get("quantity", 0)))
		if not removed.ok:
			_rollback(inventory, inventory_snapshot, run_state, interaction_snapshot, placed_snapshot)
			return _fail_and_emit(removed)
	for item in action.get("result", {}).get("inventory_items", []):
		var added: Dictionary = inventory.add_item(String(item.get("item_id", "")), int(item.get("quantity", 0)))
		if not added.ok:
			_rollback(inventory, inventory_snapshot, run_state, interaction_snapshot, placed_snapshot)
			return _fail_and_emit(added)

	run_state.world_interactions[target_id] = {
		"target_id": target_id,
		"biome_id": String(definition.get("target", {}).get("biome_id", current_biome_id)),
		"state": String(action.get("to", "")),
		"action_id": action_id
	}
	if String(action.get("to", "")) == "repaired":
		_record_fixed_facility(target_id, definition, validation.target_reservation, run_state)
	elif String(action.get("to", "")) == "recycled" and world_data != null and world_data.has_method("release_footprint"):
		if not world_data.release_footprint(target_id):
			_rollback(inventory, inventory_snapshot, run_state, interaction_snapshot, placed_snapshot)
			return _fail_and_emit(_fail("target_release_failed", "Repair target could not be depleted."))

	var result := {
		"ok": true,
		"action_id": action_id,
		"target_id": target_id,
		"state": String(action.get("to", "")),
		"turns": int(action.get("turns", 1)),
		"tool_consumed": bool(definition.get("tool_consumed", false))
	}
	interaction_completed.emit(result.duplicate(true))
	return result

func apply_saved_target_states(world_data, run_state) -> Dictionary:
	if world_data == null or run_state == null:
		return {"ok": true, "applied": 0}
	var applied := 0
	for target_id_value in run_state.world_interactions.keys():
		var target_id := String(target_id_value)
		var state: Dictionary = run_state.world_interactions[target_id]
		if not _saved_state_matches_definition(target_id, state, run_state):
			continue
		if String(state.get("state", "")) == "recycled" and world_data.has_method("release_footprint"):
			if world_data.release_footprint(target_id):
				applied += 1
	return {"ok": true, "applied": applied}

func _saved_state_matches_definition(target_id: String, state: Dictionary, run_state) -> bool:
	if not definitions_by_target_id.has(target_id):
		return false
	var definition: Dictionary = definitions_by_target_id[target_id]
	var action_id := String(state.get("action_id", ""))
	if not actions_by_id.has(action_id):
		return false
	var action_entry: Dictionary = actions_by_id[action_id]
	if String(action_entry.get("target_id", "")) != target_id:
		return false
	var action: Dictionary = action_entry.get("action", {})
	if String(action.get("to", "")) != String(state.get("state", "")):
		return false
	var biome_id := String(definition.get("target", {}).get("biome_id", ""))
	if String(state.get("biome_id", "")) != biome_id:
		return false
	return run_state == null or String(run_state.current_biome_id) == biome_id or String(run_state.current_biome_id).is_empty()

func _validate_action_request(action_id: String, target_id: String, inventory, run_state, world_data, current_biome_id: String) -> Dictionary:
	if action_id.is_empty() or not actions_by_id.has(action_id):
		return _fail("unknown_repair_action", "Unknown repair interaction action: %s" % action_id)
	var action_entry: Dictionary = actions_by_id[action_id]
	if target_id.is_empty():
		target_id = String(action_entry.target_id)
	if target_id != String(action_entry.target_id):
		return _fail("target_action_mismatch", "Repair action does not target %s." % target_id)
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("to_snapshot") or not inventory.has_method("load_snapshot"):
		return _fail("invalid_inventory", "Repair interactions require snapshot-capable inventory.")
	if run_state == null:
		return _fail("missing_run_state", "Repair interactions require run state.")
	if world_data == null or not world_data.has_method("get_reservation"):
		return _fail("invalid_world_data", "Repair interactions require world target state.")
	var definition: Dictionary = definitions_by_target_id[target_id]
	var target: Dictionary = definition.get("target", {})
	var biome_id := String(target.get("biome_id", ""))
	if not current_biome_id.is_empty() and biome_id != current_biome_id:
		return _fail("wrong_biome", "Repair target is not in the current biome.")
	if not run_state.crafting_unlocks.has(biome_id):
		return _fail("interaction_locked", "Repair interaction is locked until the biome run unlock is active.")
	var target_reservation: Dictionary = world_data.get_reservation(target_id)
	if target_reservation.is_empty():
		return _fail("missing_target", "Repair target is not present in the current world.")
	if String(run_state.teleport_states.get(biome_id, "")) != "repaired" and not run_state.repaired_teleports.has(biome_id):
		return _fail("interaction_locked", "Repair interaction is locked until the biome teleport is repaired.")
	var current_state := _target_state(target_id, definition, run_state)
	var action: Dictionary = action_entry.action
	if current_state != String(action.get("from", "")):
		return _fail("target_state_mismatch", "Repair target is already resolved.")
	var required_tool_id := String(definition.get("required_tool_item_id", ""))
	var required_tool_quantity := int(definition.get("required_tool_quantity", 1))
	if inventory.get_total_quantity(required_tool_id) < required_tool_quantity:
		return _fail("missing_tool", "Required repair tool is not available.")
	for material in action.get("materials", []):
		if inventory.get_total_quantity(String(material.get("item_id", ""))) < int(material.get("quantity", 0)):
			return _fail("missing_material", "Repair interaction materials are insufficient.")
	var capacity_result := _precheck_inventory_capacity(inventory, action.get("result", {}).get("inventory_items", []))
	if not capacity_result.ok:
		return capacity_result
	return {
		"ok": true,
		"definition": definition,
		"action": action,
		"target_reservation": target_reservation
	}

func _precheck_inventory_capacity(inventory, items: Array) -> Dictionary:
	if items.is_empty():
		return {"ok": true}
	var snapshot: Dictionary = inventory.to_snapshot()
	for item in items:
		var result: Dictionary = inventory.add_item(String(item.get("item_id", "")), int(item.get("quantity", 0)))
		if not result.ok:
			inventory.load_snapshot(snapshot)
			return result
	inventory.load_snapshot(snapshot)
	return {"ok": true}

func _target_state(target_id: String, definition: Dictionary, run_state) -> String:
	var saved: Dictionary = run_state.world_interactions.get(target_id, {})
	if not saved.is_empty():
		return String(saved.get("state", ""))
	return String(definition.get("target", {}).get("initial_state", "broken"))

func _record_fixed_facility(target_id: String, definition: Dictionary, target_reservation: Dictionary, run_state) -> void:
	var target: Dictionary = definition.get("target", {})
	var origin: Dictionary = target_reservation.get("origin", {})
	var metadata: Dictionary = target_reservation.get("metadata", {}).duplicate(true)
	metadata["facility_item_id"] = String(target.get("source_facility_item_id", ""))
	metadata["fixed_repair_target_id"] = target_id
	var record := {
		"biome_id": String(target.get("biome_id", "")),
		"facility_item_id": String(target.get("source_facility_item_id", "")),
		"owner_id": target_id,
		"origin": origin.duplicate(true),
		"metadata": metadata
	}
	for existing in run_state.placed_facilities:
		if typeof(existing) == TYPE_DICTIONARY and String(existing.get("owner_id", "")) == target_id:
			return
	run_state.placed_facilities.append(record)

func _rollback(inventory, inventory_snapshot: Dictionary, run_state, interaction_snapshot: Dictionary, placed_snapshot: Array) -> void:
	inventory.load_snapshot(inventory_snapshot)
	run_state.world_interactions = interaction_snapshot
	run_state.placed_facilities = placed_snapshot

static func _normalize_definition(definition: Dictionary, fallback_tool_item_id: String) -> Dictionary:
	var normalized := definition.duplicate(true)
	if String(normalized.get("required_tool_item_id", "")).is_empty():
		normalized["required_tool_item_id"] = fallback_tool_item_id
	return normalized

static func _validate_definition(definition: Dictionary) -> Dictionary:
	for field in ["required_tool_item_id", "target", "actions"]:
		if not definition.has(field):
			return _fail("invalid_repair_definition", "Repair interaction definition is missing %s." % field)
	if typeof(definition.target) != TYPE_DICTIONARY or String(definition.target.get("definition_id", "")).is_empty():
		return _fail("invalid_repair_target", "Repair interaction target is invalid.")
	if typeof(definition.actions) != TYPE_ARRAY or definition.actions.is_empty():
		return _fail("invalid_repair_actions", "Repair interaction actions are invalid.")
	for action in definition.actions:
		if typeof(action) != TYPE_DICTIONARY or String(action.get("id", "")).is_empty():
			return _fail("invalid_repair_action", "Repair interaction action is invalid.")
	return {"ok": true}

static func _duplicate_dictionary(value: Dictionary) -> Dictionary:
	return value.duplicate(true)

static func _catalog_data_version(catalog) -> String:
	var value = catalog.get("data_version") if catalog.has_method("get") else ""
	return "" if value == null else String(value)

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error
