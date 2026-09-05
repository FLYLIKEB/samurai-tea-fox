extends RefCounted
class_name AcquisitionService

const GameCommand = preload("res://src/core/commands/game_command.gd")
const DropEvaluator = preload("res://src/enemy/drop_evaluator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const POLICY_DIRECT := "direct"
const POLICY_PICKUP := "pickup"
const GATHERABLE_KIND := "gatherable"
const PICKUP_KIND := "pickup"

signal changed(snapshot: Dictionary)
signal acquisition_completed(result: Dictionary)
signal operation_failed(error: Dictionary)

var inventory
var world_data
var gatherable_definitions: Dictionary = {}
var drop_definitions: Dictionary = {}
var gatherables: Dictionary = {}
var pickups: Dictionary = {}
var processed_drop_request_ids: Array = []
var next_pickup_id := 1

func configure(
	new_inventory,
	new_world_data,
	new_gatherable_definitions: Array,
	new_drop_definitions: Array
) -> Dictionary:
	if new_inventory == null or not new_inventory.has_method("has_definition") or not new_inventory.has_method("add_item") or not new_inventory.has_method("get_total_quantity") or not new_inventory.has_method("to_snapshot") or not new_inventory.has_method("load_snapshot"):
		return _fail("invalid_inventory", "Acquisition requires the Inventory public API.")
	if new_world_data == null or not new_world_data.has_method("reserve_entity") or not new_world_data.has_method("release_footprint"):
		return _fail("invalid_world_data", "Acquisition requires the WorldData occupancy API.")

	var gather_result := _index_gatherable_definitions(new_gatherable_definitions, new_inventory)
	if not gather_result.ok:
		return gather_result
	var drop_result := _index_drop_definitions(new_drop_definitions, new_inventory)
	if not drop_result.ok:
		return drop_result

	inventory = new_inventory
	world_data = new_world_data
	gatherable_definitions = gather_result.definitions
	drop_definitions = drop_result.definitions
	gatherables.clear()
	pickups.clear()
	processed_drop_request_ids.clear()
	next_pickup_id = 1
	_emit_changed()
	return {"ok": true}

func register_gatherable(node_id: String, definition_id: String, position: Vector2i) -> Dictionary:
	if node_id.is_empty():
		return _fail_and_emit(_fail("missing_node_id", "Gatherable node id is required."))
	if gatherables.has(node_id) or pickups.has(node_id):
		return _fail_and_emit(_fail("duplicate_world_id", "World interaction id is already registered: %s" % node_id))
	if not gatherable_definitions.has(definition_id):
		return _fail_and_emit(_fail("unknown_gatherable_definition", "Unknown gatherable definition: %s" % definition_id))

	var reservation: Dictionary = world_data.reserve_entity(
		node_id,
		position,
		Vector2i.ONE,
		true,
		{"interaction_kind": GATHERABLE_KIND, "definition_id": definition_id}
	)
	if not reservation.ok:
		var adoption_result := _can_adopt_existing_gatherable(node_id, definition_id, position)
		if not adoption_result.ok:
			return _fail_and_emit(_world_failure(reservation))
	gatherables[node_id] = {
		"node_id": node_id,
		"definition_id": definition_id,
		"item_id": String(gatherable_definitions[definition_id].item_id),
		"required_tool_item_id": String(gatherable_definitions[definition_id].get("required_tool_item_id", "")),
		"position": _position_dictionary(position),
		"depleted": false
	}
	_emit_changed()
	return {"ok": true, "node": gatherables[node_id].duplicate(true)}

func handle_command(command) -> Dictionary:
	if not command is GameCommand or command.type != GameCommand.Type.INTERACT:
		return _fail_and_emit(_fail("invalid_command", "Acquisition accepts only INTERACT commands."))
	var target_id := String(command.payload.get("target_id", ""))
	if target_id.is_empty():
		return _fail_and_emit(_fail("missing_target_id", "INTERACT command requires target_id."))
	if gatherables.has(target_id):
		return gather(target_id)
	if pickups.has(target_id):
		return collect_pickup(target_id)
	return _fail_and_emit(_fail("unknown_target", "Unknown interaction target: %s" % target_id))

func gather(node_id: String) -> Dictionary:
	if not gatherables.has(node_id):
		return _fail_and_emit(_fail("unknown_gatherable", "Unknown gatherable node: %s" % node_id))
	var node: Dictionary = gatherables[node_id]
	if bool(node.depleted):
		return _fail_and_emit(_fail("depleted", "Gatherable node is depleted: %s" % node_id))

	var definition: Dictionary = gatherable_definitions[node.definition_id]
	var tool_result := _validate_required_tool(definition)
	if not tool_result.ok:
		return _fail_and_emit(tool_result)
	var position := _vector_from_dictionary(node.position)
	var result: Dictionary
	if definition.policy == POLICY_PICKUP:
		world_data.release_footprint(node_id)
		result = _spawn_pickup(definition.item_id, definition.quantity, position, {"source_kind": GATHERABLE_KIND, "source_id": node_id, "material_tag": String(definition.get("material_tag", ""))})
		if not result.ok:
			_restore_gatherable_reservation(node)
			return _fail_and_emit(result)
	else:
		result = inventory.add_item(definition.item_id, definition.quantity)
		if not result.ok:
			if String(result.get("reason", "")) != "inventory_full":
				return _fail_and_emit(result)
			world_data.release_footprint(node_id)
			result = _spawn_pickup(definition.item_id, definition.quantity, position, {"source_kind": GATHERABLE_KIND, "source_id": node_id, "material_tag": String(definition.get("material_tag", ""))})
			if not result.ok:
				_restore_gatherable_reservation(node)
				return _fail_and_emit(result)
		else:
			world_data.release_footprint(node_id)

	_apply_depleted_terrain(definition, position)
	node.depleted = true
	gatherables[node_id] = node
	var completed := {
		"ok": true,
		"kind": GATHERABLE_KIND,
		"node_id": node_id,
		"item_id": definition.item_id,
		"quantity": definition.quantity,
		"position": _position_dictionary(position),
		"required_tool_item_id": String(definition.get("required_tool_item_id", "")),
		"material_tag": String(definition.get("material_tag", "")),
		"delivery": result.get("delivery", POLICY_DIRECT),
		"pickup_id": result.get("pickup_id", "")
	}
	_emit_changed()
	acquisition_completed.emit(completed.duplicate(true))
	return completed

func process_drop_request(event: Dictionary, position := Vector2i.ZERO, evaluation_context := {}) -> Dictionary:
	if String(event.get("type", "")) != "monster_drop_requested":
		return _fail_and_emit(_fail("invalid_drop_event", "Expected monster_drop_requested event."))
	var monster_id := String(event.get("definition_id", event.get("monster_id", "")))
	if not drop_definitions.has(monster_id):
		return _fail_and_emit(_fail("unknown_drop_definition", "No drop definition for monster: %s" % monster_id))
	var request_id := String(event.get("combat_id", event.get("request_id", "")))
	if not request_id.is_empty() and processed_drop_request_ids.has(request_id):
		return _fail_and_emit(_fail("drop_already_processed", "Drop request was already processed: %s" % request_id))

	var origin := position
	if event.get("position", null) is Dictionary:
		origin = _vector_from_dictionary(event.position)
	var inventory_before: Dictionary = inventory.to_snapshot()
	var pickup_ids_before: Array = pickups.keys()
	var next_pickup_id_before := next_pickup_id
	var results: Array = []
	var drop_context: Dictionary = evaluation_context.duplicate(true) if evaluation_context is Dictionary else {}
	drop_context["request_id"] = request_id
	for grant in drop_definitions[monster_id].grants:
		var resolved: Dictionary = DropEvaluator.evaluate(grant, drop_context)
		if not resolved.ok:
			return _fail_and_emit(resolved)
		if not resolved.included:
			continue
		var grant_result := _deliver_grant(resolved.grant, origin, {"source_kind": "monster", "source_id": monster_id, "request_id": request_id, "drop_id": grant.drop_id})
		if not grant_result.ok:
			inventory.load_snapshot(inventory_before)
			_rollback_new_pickups(pickup_ids_before)
			next_pickup_id = next_pickup_id_before
			return _fail_and_emit(grant_result)
		grant_result.drop_id = grant.drop_id
		results.append(grant_result)
	if not request_id.is_empty():
		processed_drop_request_ids.append(request_id)
	var completed := {"ok": true, "kind": "monster_drop", "monster_id": monster_id, "request_id": request_id, "grants": results}
	_emit_changed()
	acquisition_completed.emit(completed.duplicate(true))
	return completed

func collect_pickup(pickup_id: String) -> Dictionary:
	if not pickups.has(pickup_id):
		return _fail_and_emit(_fail("unknown_pickup", "Unknown pickup: %s" % pickup_id))
	var pickup: Dictionary = pickups[pickup_id]
	var add_result: Dictionary = inventory.add_item(pickup.item_id, pickup.quantity)
	if not add_result.ok:
		return _fail_and_emit(add_result)
	world_data.release_footprint(pickup_id)
	pickups.erase(pickup_id)
	var completed := {
		"ok": true,
		"kind": PICKUP_KIND,
		"pickup_id": pickup_id,
		"item_id": pickup.item_id,
		"quantity": pickup.quantity,
		"position": pickup.position.duplicate(true),
		"delivery": POLICY_DIRECT
	}
	_emit_changed()
	acquisition_completed.emit(completed.duplicate(true))
	return completed

func pickup_for(pickup_id: String) -> Dictionary:
	return pickups.get(pickup_id, {}).duplicate(true)

func gatherable_for(node_id: String) -> Dictionary:
	return gatherables.get(node_id, {}).duplicate(true)

func to_snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"next_pickup_id": next_pickup_id,
		"gatherables": _sorted_dictionary_values(gatherables, "node_id"),
		"pickups": _sorted_dictionary_values(pickups, "pickup_id"),
		"processed_drop_request_ids": processed_drop_request_ids.duplicate()
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _fail("unsupported_schema_version", "Unsupported acquisition snapshot schema version.")
	var normalized_gatherables := _normalize_gatherable_snapshot(snapshot.get("gatherables", []))
	if not normalized_gatherables.ok:
		return normalized_gatherables
	var normalized_pickups := _normalize_pickup_snapshot(snapshot.get("pickups", []))
	if not normalized_pickups.ok:
		return normalized_pickups
	var request_ids = snapshot.get("processed_drop_request_ids", [])
	if typeof(request_ids) != TYPE_ARRAY:
		return _fail("invalid_drop_request_ids", "Processed drop request ids must be an array.")
	var preserved_metadata := _reservation_metadata_for(gatherables, pickups)

	# Prove every reservation against a detached world before mutating live state.
	var staged_world = WorldData.from_dictionary(world_data.to_dictionary())
	_release_reservations(staged_world, gatherables, pickups)
	var staged_restore := _restore_snapshot_reservations(staged_world, normalized_gatherables.values, normalized_pickups.values, preserved_metadata)
	if not staged_restore.ok:
		return staged_restore

	var previous_gatherables := gatherables
	var previous_pickups := pickups
	_release_runtime_reservations()
	gatherables = normalized_gatherables.values
	pickups = normalized_pickups.values
	var live_restore := _restore_snapshot_reservations(world_data, gatherables, pickups, preserved_metadata)
	if not live_restore.ok:
		_release_runtime_reservations()
		gatherables = previous_gatherables
		pickups = previous_pickups
		_restore_snapshot_reservations(world_data, gatherables, pickups)
		return live_restore
	_apply_depleted_terrains_from_snapshot()
	processed_drop_request_ids = request_ids.duplicate()
	next_pickup_id = max(1, int(snapshot.get("next_pickup_id", 1)))
	_emit_changed()
	return {"ok": true}

func _validate_required_tool(definition: Dictionary) -> Dictionary:
	var required_tool_item_id := String(definition.get("required_tool_item_id", ""))
	if required_tool_item_id.is_empty():
		return {"ok": true}
	if int(inventory.get_total_quantity(required_tool_item_id)) <= 0:
		return _fail("missing_required_tool", "Gatherable requires tool item: %s" % required_tool_item_id)
	return {"ok": true}

func _apply_depleted_terrains_from_snapshot() -> void:
	for node in gatherables.values():
		if bool(node.get("depleted", false)):
			var definition: Dictionary = gatherable_definitions.get(String(node.get("definition_id", "")), {})
			if not definition.is_empty():
				_apply_depleted_terrain(definition, _vector_from_dictionary(node.get("position", {})))

func _apply_depleted_terrain(definition: Dictionary, position: Vector2i) -> void:
	var terrain: Dictionary = definition.get("depleted_terrain", {})
	if terrain.is_empty() or world_data == null or not world_data.has_method("set_terrain"):
		return
	world_data.set_terrain(
		position,
		String(terrain.get("id", "ground")),
		bool(terrain.get("walkable", true))
	)

func _deliver_grant(grant: Dictionary, position: Vector2i, source: Dictionary) -> Dictionary:
	if grant.policy == POLICY_DIRECT:
		var direct_result: Dictionary = inventory.add_item(grant.item_id, grant.quantity)
		if direct_result.ok:
			return {"ok": true, "delivery": POLICY_DIRECT, "item_id": grant.item_id, "quantity": grant.quantity}
		if String(direct_result.get("reason", "")) != "inventory_full":
			return direct_result
	return _spawn_pickup(grant.item_id, grant.quantity, position, source)

func _spawn_pickup(item_id: String, quantity: int, preferred_position: Vector2i, source: Dictionary) -> Dictionary:
	var pickup_id := "pickup_%06d" % next_pickup_id
	var position_result := _reserve_pickup_position(pickup_id, preferred_position, item_id, quantity)
	if not position_result.ok:
		return position_result
	next_pickup_id += 1
	pickups[pickup_id] = {
		"pickup_id": pickup_id,
		"item_id": item_id,
		"quantity": quantity,
		"position": _position_dictionary(position_result.position),
		"source": source.duplicate(true)
	}
	return {"ok": true, "delivery": POLICY_PICKUP, "pickup_id": pickup_id, "item_id": item_id, "quantity": quantity}

func _reserve_pickup_position(pickup_id: String, preferred: Vector2i, item_id: String, quantity: int) -> Dictionary:
	for candidate in _pickup_position_candidates(preferred):
		var reservation: Dictionary = world_data.reserve_entity(
			pickup_id,
			candidate,
			Vector2i.ONE,
			true,
			{"interaction_kind": PICKUP_KIND, "item_id": item_id, "quantity": quantity}
		)
		if reservation.ok:
			return {"ok": true, "position": candidate}
	return _fail("no_pickup_space", "No world cell is available for pickup: %s" % item_id)

func _pickup_position_candidates(origin: Vector2i) -> Array:
	return [
		origin,
		origin + Vector2i.RIGHT,
		origin + Vector2i.DOWN,
		origin + Vector2i.LEFT,
		origin + Vector2i.UP
	]

func _restore_gatherable_reservation(node: Dictionary) -> Dictionary:
	var reservation: Dictionary = world_data.reserve_entity(
		node.node_id,
		_vector_from_dictionary(node.position),
		Vector2i.ONE,
		true,
		{"interaction_kind": GATHERABLE_KIND, "definition_id": node.definition_id}
	)
	return {"ok": true} if reservation.ok else _world_failure(reservation)

func _release_runtime_reservations() -> void:
	_release_reservations(world_data, gatherables, pickups)

func _release_reservations(target_world, source_gatherables: Dictionary, source_pickups: Dictionary) -> void:
	for node_id in source_gatherables:
		target_world.release_footprint(node_id)
	for pickup_id in source_pickups:
		target_world.release_footprint(pickup_id)

func _restore_snapshot_reservations(target_world, source_gatherables: Dictionary, source_pickups: Dictionary, preserved_metadata := {}) -> Dictionary:
	for node in source_gatherables.values():
		if bool(node.depleted):
			continue
		var metadata: Dictionary = preserved_metadata.get(String(node.node_id), {}).duplicate(true)
		if metadata.is_empty():
			metadata = {"interaction_kind": GATHERABLE_KIND, "definition_id": node.definition_id}
		var reservation: Dictionary = target_world.reserve_entity(
			node.node_id,
			_vector_from_dictionary(node.position),
			Vector2i.ONE,
			true,
			metadata
		)
		if not reservation.ok:
			return _world_failure(reservation)
	for pickup in source_pickups.values():
		var reservation: Dictionary = target_world.reserve_entity(
			pickup.pickup_id,
			_vector_from_dictionary(pickup.position),
			Vector2i.ONE,
			true,
			{"interaction_kind": PICKUP_KIND, "item_id": pickup.item_id, "quantity": pickup.quantity}
		)
		if not reservation.ok:
			return _world_failure(reservation)
	return {"ok": true}

func _reservation_metadata_for(source_gatherables: Dictionary, source_pickups: Dictionary) -> Dictionary:
	var metadata := {}
	for node_id in source_gatherables:
		var reservation: Dictionary = world_data.get_reservation(String(node_id))
		if not reservation.is_empty():
			metadata[String(node_id)] = reservation.get("metadata", {}).duplicate(true)
	for pickup_id in source_pickups:
		var reservation: Dictionary = world_data.get_reservation(String(pickup_id))
		if not reservation.is_empty():
			metadata[String(pickup_id)] = reservation.get("metadata", {}).duplicate(true)
	return metadata

func _rollback_new_pickups(existing_pickup_ids: Array) -> void:
	for pickup_id in pickups.keys():
		if existing_pickup_ids.has(pickup_id):
			continue
		world_data.release_footprint(pickup_id)
		pickups.erase(pickup_id)

func _can_adopt_existing_gatherable(node_id: String, definition_id: String, position: Vector2i) -> Dictionary:
	if not world_data.has_method("get_reservation"):
		return _fail("cannot_adopt_reservation", "WorldData cannot inspect an existing reservation.")
	var reservation: Dictionary = world_data.get_reservation(node_id)
	if reservation.is_empty() or not bool(reservation.get("interactable", false)):
		return _fail("cannot_adopt_reservation", "Existing reservation is not an interactable resource node.")
	if _vector_from_dictionary(reservation.get("origin", {})) != position:
		return _fail("cannot_adopt_reservation", "Existing resource reservation position does not match.")
	var metadata: Dictionary = reservation.get("metadata", {})
	var definition: Dictionary = gatherable_definitions[definition_id]
	var matches_generated_resource := String(metadata.get("resource_id", "")) == String(definition.item_id)
	var matches_gatherable_definition := String(metadata.get("definition_id", "")) == definition_id
	if not matches_generated_resource and not matches_gatherable_definition:
		return _fail("cannot_adopt_reservation", "Existing reservation metadata does not match gatherable definition.")
	return {"ok": true}

func _index_gatherable_definitions(rows: Array, target_inventory) -> Dictionary:
	var definitions := {}
	for row in rows:
		if not row is Dictionary:
			return _fail("invalid_gatherable_definition", "Gatherable definition must be a dictionary.")
		var id := String(row.get("id", ""))
		var grant_result := _normalize_grant(row, target_inventory)
		if id.is_empty() or definitions.has(id) or not grant_result.ok:
			return grant_result if not grant_result.ok else _fail("invalid_gatherable_definition", "Gatherable definition id must be unique and non-empty.")
		var required_tool_item_id := String(row.get("required_tool_item_id", ""))
		if not required_tool_item_id.is_empty() and not target_inventory.has_definition(required_tool_item_id):
			return _fail("unknown_required_tool", "Gatherable definition references unknown tool item: %s" % required_tool_item_id)
		definitions[id] = {
			"id": id,
			"item_id": grant_result.grant.item_id,
			"quantity": grant_result.grant.quantity,
			"policy": grant_result.grant.policy,
			"required_tool_item_id": required_tool_item_id,
			"material_tag": String(row.get("material_tag", row.get("interaction_tag", ""))),
			"depleted_terrain": row.get("depleted_terrain", {}).duplicate(true) if row.get("depleted_terrain", {}) is Dictionary else {}
		}
	return {"ok": true, "definitions": definitions}

func _index_drop_definitions(rows: Array, target_inventory) -> Dictionary:
	var definitions := {}
	for row in rows:
		if not row is Dictionary:
			return _fail("invalid_drop_definition", "Drop definition must be a dictionary.")
		var monster_id := String(row.get("monster_id", ""))
		var raw_grants = row.get("grants", [])
		if monster_id.is_empty() or definitions.has(monster_id) or typeof(raw_grants) != TYPE_ARRAY or raw_grants.is_empty():
			return _fail("invalid_drop_definition", "Drop definition requires a unique monster_id and grants.")
		var grants: Array = []
		for raw_grant in raw_grants:
			var grant_result := _normalize_grant(raw_grant, target_inventory)
			if not grant_result.ok:
				return grant_result
			grants.append(grant_result.grant)
		definitions[monster_id] = {"monster_id": monster_id, "grants": grants}
	return {"ok": true, "definitions": definitions}

func _normalize_grant(row, target_inventory) -> Dictionary:
	if not row is Dictionary:
		return _fail("invalid_grant", "Acquisition grant must be a dictionary.")
	var item_id := String(row.get("item_id", ""))
	var min_quantity := int(row.get("min_quantity", row.get("quantity", 0)))
	var max_quantity := int(row.get("max_quantity", row.get("quantity", 0)))
	var chance := float(row.get("chance", 1.0))
	var condition := String(row.get("condition", "항상"))
	var drop_id := String(row.get("drop_id", item_id))
	var policy := String(row.get("policy", POLICY_DIRECT))
	if item_id.is_empty() or not target_inventory.has_definition(item_id):
		return _fail("unknown_item", "Acquisition grant references unknown item: %s" % item_id)
	if min_quantity <= 0 or max_quantity < min_quantity:
		return _fail("invalid_quantity", "Acquisition quantity range must be positive and ordered.")
	if not is_finite(chance) or chance < 0.0 or chance > 1.0:
		return _fail("invalid_chance", "Acquisition chance must be between zero and one.")
	if condition.is_empty() or drop_id.is_empty():
		return _fail("invalid_drop_rule", "Acquisition drop id and condition must be non-empty.")
	if not DropEvaluator.SUPPORTED_CONDITIONS.has(condition):
		return _fail("unsupported_drop_condition", "Unsupported drop condition: %s" % condition)
	if policy != POLICY_DIRECT and policy != POLICY_PICKUP:
		return _fail("invalid_policy", "Acquisition policy must be direct or pickup.")
	return {"ok": true, "grant": {
		"drop_id": drop_id,
		"item_id": item_id,
		"quantity": min_quantity,
		"min_quantity": min_quantity,
		"max_quantity": max_quantity,
		"chance": chance,
		"condition": condition,
		"policy": policy
	}}

func _normalize_gatherable_snapshot(rows) -> Dictionary:
	if typeof(rows) != TYPE_ARRAY:
		return _fail("invalid_gatherables", "Gatherable snapshot must be an array.")
	var values := {}
	for row in rows:
		if not row is Dictionary:
			return _fail("invalid_gatherable", "Gatherable snapshot entry must be a dictionary.")
		var node_id := String(row.get("node_id", ""))
		var definition_id := String(row.get("definition_id", ""))
		if node_id.is_empty() or values.has(node_id) or not gatherable_definitions.has(definition_id) or not row.get("position", null) is Dictionary:
			return _fail("invalid_gatherable", "Gatherable snapshot entry is invalid: %s" % node_id)
		values[node_id] = {
			"node_id": node_id,
			"definition_id": definition_id,
			"item_id": String(gatherable_definitions[definition_id].item_id),
			"required_tool_item_id": String(gatherable_definitions[definition_id].get("required_tool_item_id", "")),
			"position": row.position.duplicate(true),
			"depleted": bool(row.get("depleted", false))
		}
	return {"ok": true, "values": values}

func _normalize_pickup_snapshot(rows) -> Dictionary:
	if typeof(rows) != TYPE_ARRAY:
		return _fail("invalid_pickups", "Pickup snapshot must be an array.")
	var values := {}
	for row in rows:
		if not row is Dictionary:
			return _fail("invalid_pickup", "Pickup snapshot entry must be a dictionary.")
		var pickup_id := String(row.get("pickup_id", ""))
		var item_id := String(row.get("item_id", ""))
		var quantity := int(row.get("quantity", 0))
		if pickup_id.is_empty() or values.has(pickup_id) or not inventory.has_definition(item_id) or quantity <= 0 or not row.get("position", null) is Dictionary:
			return _fail("invalid_pickup", "Pickup snapshot entry is invalid: %s" % pickup_id)
		values[pickup_id] = {
			"pickup_id": pickup_id,
			"item_id": item_id,
			"quantity": quantity,
			"position": row.position.duplicate(true),
			"source": row.get("source", {}).duplicate(true)
		}
	return {"ok": true, "values": values}

func _sorted_dictionary_values(values: Dictionary, id_field: String) -> Array:
	var rows: Array = []
	for value in values.values():
		rows.append(value.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a[id_field]) < String(b[id_field])
	)
	return rows

func _emit_changed() -> void:
	changed.emit(to_snapshot())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error

func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}

func _world_failure(result: Dictionary) -> Dictionary:
	return _fail("world_%s" % String(result.get("reason", "reservation_failed")), "WorldData could not reserve acquisition state.")

func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

func _vector_from_dictionary(position: Dictionary) -> Vector2i:
	return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
