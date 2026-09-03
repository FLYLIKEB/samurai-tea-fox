extends RefCounted
class_name FacilityPlacementService

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")

const ITEM_SOURCE := "items"
const DEFAULT_FOOTPRINT := Vector2i.ONE
static var DEFAULT_PLACEMENT_SEARCH_RADIUS := RuntimeConstants.int_value("placement.search_radius")
static var DEFAULT_USE_DISTANCE := RuntimeConstants.int_value("placement.use_distance")

signal operation_failed(error: Dictionary)
signal facility_placed(result: Dictionary)

var data_version := ""
var facility_definitions: Dictionary = {}

static func from_catalog(catalog) -> Dictionary:
	if not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Catalog cannot provide facility definitions.")
	var definitions: Dictionary = {}
	for row in catalog.get_definitions(ITEM_SOURCE):
		var definition_result := _facility_definition_from_row(row)
		if not definition_result.ok:
			return definition_result
		definitions[definition_result.definition.id] = definition_result.definition
	var service: FacilityPlacementService = load("res://src/world/placement/facility_placement_service.gd").new()
	var configure_result := service.configure(definitions, _catalog_data_version(catalog))
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "facility_placement_service": service}

func configure(new_facility_definitions: Dictionary, new_data_version := "") -> Dictionary:
	if new_facility_definitions.is_empty():
		return _fail("missing_facility_definitions", "Facility placement requires item definitions.")
	facility_definitions = _duplicate_dictionary(new_facility_definitions)
	data_version = new_data_version
	return {"ok": true}

func can_place_facility(facility_item_id: String, world_data, origin: Vector2i, context := {}) -> Dictionary:
	if not facility_definitions.has(facility_item_id):
		return _fail("unknown_facility", "Unknown facility item: %s" % facility_item_id)
	if world_data == null or not world_data.has_method("contains") or not world_data.has_method("is_walkable") or not world_data.has_method("reserve_facility"):
		return _fail("invalid_world_data", "Facility placement requires WorldData occupancy API.")

	var definition: Dictionary = facility_definitions[facility_item_id]
	var size: Vector2i = _footprint_size_for_context(definition.footprint_size, context)
	var footprint_result := _validate_open_footprint(world_data, origin, size)
	if not footprint_result.ok:
		return footprint_result

	var workspace_result := _validate_workspace(world_data, origin, size, context)
	if not workspace_result.ok:
		return workspace_result

	if bool(_context_value(context, "preserve_required_paths", true)):
		var path_result := _validate_required_paths_after_reservation(world_data, facility_item_id, origin, size, context)
		if not path_result.ok:
			return path_result

	return {
		"ok": true,
		"facility_item_id": facility_item_id,
		"owner_id": _owner_id(facility_item_id, origin, context),
		"origin": _position_dictionary(origin),
		"footprint_size": {"x": size.x, "y": size.y},
		"workspace_cells": _workspace_cells(world_data, origin, size, context)
	}

func place_facility(facility_item_id: String, world_data, origin: Vector2i, context := {}) -> Dictionary:
	var validation := can_place_facility(facility_item_id, world_data, origin, context)
	if not validation.ok:
		return _fail_and_emit(validation)
	var size := Vector2i(int(validation.footprint_size.x), int(validation.footprint_size.y))
	var metadata := _duplicate_dictionary(_context_value(context, "metadata", {}))
	metadata["facility_item_id"] = facility_item_id
	metadata["footprint_size"] = validation.footprint_size
	var reserved: Dictionary = world_data.reserve_facility(String(validation.owner_id), origin, size, true, metadata)
	if not reserved.ok:
		return _fail_and_emit(reserved)
	var result := _duplicate_dictionary(validation)
	result["reservation"] = reserved.reservation
	facility_placed.emit(_duplicate_dictionary(result))
	return result

func find_placement_near(facility_item_id: String, world_data, anchor: Vector2i, context := {}) -> Dictionary:
	var search_radius := maxi(1, int(_context_value(context, "search_radius", DEFAULT_PLACEMENT_SEARCH_RADIUS)))
	for offset in _placement_offsets(search_radius):
		var origin: Vector2i = anchor + Vector2i(offset)
		var validation: Dictionary = can_place_facility(facility_item_id, world_data, origin, context)
		if validation.ok:
			return validation
	return {
		"ok": false,
		"reason": "no_nearby_placement",
		"error": "No valid facility placement was found near the player.",
		"facility_item_id": facility_item_id,
		"anchor": _position_dictionary(anchor)
	}

func facility_item_ids_near(world_data, position: Vector2i, max_distance := -1) -> Array:
	var ids: Array = []
	if world_data == null or not world_data.has_method("to_dictionary"):
		return ids
	var distance_limit := DEFAULT_USE_DISTANCE if int(max_distance) < 0 else maxi(0, int(max_distance))
	for reservation in world_data.to_dictionary().get("reservations", []):
		if String(reservation.get("kind", "")) != "facility":
			continue
		var metadata: Dictionary = reservation.get("metadata", {})
		var facility_item_id := String(metadata.get("facility_item_id", ""))
		if facility_item_id.is_empty() or ids.has(facility_item_id):
			continue
		for cell_value in reservation.get("cells", []):
			var cell := _vector_from_value(cell_value)
			# Interaction range is tile-based: diagonal neighbors are just as
			# close as cardinal neighbors. Manhattan distance incorrectly hid a
			# facility when the player stood diagonally beside it.
			if maxi(absi(position.x - cell.x), absi(position.y - cell.y)) <= distance_limit:
				ids.append(facility_item_id)
				break
	ids.sort()
	return ids

func facility_for(facility_item_id: String) -> Dictionary:
	return _duplicate_dictionary(facility_definitions.get(facility_item_id, {}))

func _validate_open_footprint(world_data, origin: Vector2i, size: Vector2i) -> Dictionary:
	if size.x <= 0 or size.y <= 0:
		return _fail("invalid_size", "Facility footprint size must be positive.")
	for position in _footprint_cells(origin, size):
		if not world_data.contains(position):
			return {"ok": false, "reason": "out_of_bounds", "position": _position_dictionary(position)}
		if not world_data.is_walkable(position):
			return {"ok": false, "reason": "blocked", "position": _position_dictionary(position)}
	return {"ok": true}

func _footprint_size_for_context(size: Vector2i, context) -> Vector2i:
	var turns := int(_context_value(context, "rotation_quarter_turns", 0))
	return size if absi(turns) % 2 == 0 else Vector2i(size.y, size.x)

func _validate_workspace(world_data, origin: Vector2i, size: Vector2i, context) -> Dictionary:
	var required_count := int(_context_value(context, "required_workspace_cells", 1))
	if required_count <= 0:
		return {"ok": true}
	var cells := _workspace_cells(world_data, origin, size, context)
	if cells.size() < required_count:
		return {
			"ok": false,
			"reason": "missing_workspace",
			"required_workspace_cells": required_count,
			"available_workspace_cells": cells.size()
		}
	return {"ok": true}

func _validate_required_paths_after_reservation(world_data, facility_item_id: String, origin: Vector2i, size: Vector2i, context) -> Dictionary:
	if not world_data.has_method("to_dictionary"):
		return {"ok": true}
	var snapshot: Dictionary = world_data.to_dictionary()
	if not snapshot.has("required_landmarks") or snapshot.required_landmarks.is_empty():
		return {"ok": true}
	var clone: WorldData = WorldData.from_dictionary(snapshot)
	var owner_id := _owner_id(facility_item_id, origin, context)
	var reserve_result: Dictionary = clone.reserve_facility(owner_id, origin, size, true, {"facility_item_id": facility_item_id})
	if not reserve_result.ok:
		return reserve_result
	var validation := ConnectivityValidator.new().validate_world_data(clone.to_dictionary())
	if not bool(validation.get("valid", false)):
		return {
			"ok": false,
			"reason": "blocks_required_path",
			"unreachable_required_landmarks": validation.get("unreachable_required_landmarks", [])
		}
	return {"ok": true}

func _workspace_cells(world_data, origin: Vector2i, size: Vector2i, context) -> Array:
	var configured = _context_value(context, "workspace_offsets", [])
	var candidates: Array = []
	if typeof(configured) == TYPE_ARRAY and not configured.is_empty():
		for value in configured:
			candidates.append(origin + _vector_from_value(value))
	else:
		candidates = _adjacent_cells(origin, size)

	var open_cells: Array = []
	var seen := {}
	for position in candidates:
		var key := "%d,%d" % [position.x, position.y]
		if seen.has(key):
			continue
		seen[key] = true
		if world_data.contains(position) and world_data.is_walkable(position):
			open_cells.append(_position_dictionary(position))
	return open_cells

func _adjacent_cells(origin: Vector2i, size: Vector2i) -> Array:
	var cells: Array = []
	for x in range(origin.x, origin.x + size.x):
		cells.append(Vector2i(x, origin.y - 1))
		cells.append(Vector2i(x, origin.y + size.y))
	for y in range(origin.y, origin.y + size.y):
		cells.append(Vector2i(origin.x - 1, y))
		cells.append(Vector2i(origin.x + size.x, y))
	return cells

func _placement_offsets(radius: int) -> Array:
	var offsets: Array = []
	for distance in range(1, radius + 1):
		for y in range(-distance, distance + 1):
			for x in range(-distance, distance + 1):
				if absi(x) + absi(y) == distance:
					offsets.append(Vector2i(x, y))
	return offsets

static func _manhattan_distance(left: Vector2i, right: Vector2i) -> int:
	return absi(left.x - right.x) + absi(left.y - right.y)

static func _facility_definition_from_row(row: Dictionary) -> Dictionary:
	var id := String(row.get("id", ""))
	if id.is_empty():
		return _fail("missing_facility_id", "Facility item is missing a stable id.")
	var footprint_result := _footprint_size_from_row(row)
	if not footprint_result.ok:
		return footprint_result
	var definition := _duplicate_dictionary(row)
	definition["id"] = id
	definition["footprint_size"] = footprint_result.value
	return {"ok": true, "definition": definition}

static func _footprint_size_from_row(row: Dictionary) -> Dictionary:
	if row.has("footprint_size") and typeof(row.footprint_size) == TYPE_DICTIONARY:
		return _footprint_from_components(row.footprint_size.get("x", 1), row.footprint_size.get("y", 1), row.get("id", ""))
	if row.has("footprint") and row.footprint != null:
		var text := String(row.footprint).strip_edges().to_lower()
		var parts := text.split("x")
		if parts.size() == 2 and String(parts[0]).is_valid_int() and String(parts[1]).is_valid_int():
			return _footprint_from_components(int(parts[0]), int(parts[1]), row.get("id", ""))
		return _fail("invalid_footprint", "Facility footprint must be WIDTHxHEIGHT: %s" % row.get("id", ""))
	if row.has("footprint_width") or row.has("footprint_height"):
		return _footprint_from_components(row.get("footprint_width", 1), row.get("footprint_height", 1), row.get("id", ""))
	return {"ok": true, "value": DEFAULT_FOOTPRINT}

static func _footprint_from_components(width_value, height_value, id) -> Dictionary:
	if typeof(width_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(height_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail("invalid_footprint", "Facility footprint components must be numeric: %s" % id)
	if float(width_value) != floor(float(width_value)) or float(height_value) != floor(float(height_value)):
		return _fail("invalid_footprint", "Facility footprint components must be integers: %s" % id)
	var size := Vector2i(int(width_value), int(height_value))
	if size.x <= 0 or size.y <= 0:
		return _fail("invalid_footprint", "Facility footprint components must be positive: %s" % id)
	return {"ok": true, "value": size}

func _owner_id(facility_item_id: String, origin: Vector2i, context) -> String:
	var configured := String(_context_value(context, "owner_id", ""))
	if not configured.is_empty():
		return configured
	return "%s@%d,%d" % [facility_item_id, origin.x, origin.y]

static func _context_value(context, key: String, fallback):
	if typeof(context) != TYPE_DICTIONARY or not context.has(key):
		return fallback
	return context[key]

static func _footprint_cells(origin: Vector2i, size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			cells.append(Vector2i(x, y))
	return cells

static func _vector_from_value(value) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO

static func _position_dictionary(position: Vector2i) -> Dictionary:
	return {"x": position.x, "y": position.y}

static func _catalog_data_version(catalog) -> String:
	var value = catalog.get("data_version") if catalog.has_method("get") else ""
	return "" if value == null else String(value)

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
