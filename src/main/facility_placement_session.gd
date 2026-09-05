extends RefCounted
class_name FacilityPlacementSession

const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const RunState = preload("res://src/save/run_state.gd")

var pending_placement: Dictionary = {}
var pending_origin := Vector2i(-1, -1)
var pending_result: Dictionary = {}
var pending_rotation := 0

func has_pending() -> bool:
	return not pending_placement.is_empty()

func begin_or_craft_recipe(recipe_id: String, crafting_service, inventory, crafting_context: Dictionary, facility_placement_service, world_data, player_cell: Vector2i, in_dungeon_map: bool, metadata: Dictionary, player_available := true) -> Dictionary:
	if crafting_service == null or inventory == null:
		return {"ok": false, "reason": "crafting_unavailable"}
	if recipe_id.is_empty():
		return {"ok": false, "reason": "missing_recipe_id"}
	var recipe: Dictionary = crafting_service.recipe_for(recipe_id)
	var result_item_id := String(recipe.get("result_item_id", ""))
	if not crafting_service.is_facility_item(result_item_id):
		return crafting_service.craft(recipe_id, inventory, crafting_context)
	if in_dungeon_map:
		return {"ok": false, "reason": "facility_installation_requires_overworld"}
	if facility_placement_service == null or world_data == null or not bool(player_available):
		return {"ok": false, "reason": "facility_placement_unavailable"}

	var availability: Dictionary = crafting_service.can_craft(recipe_id, inventory, crafting_context)
	if not availability.ok:
		return availability
	pending_placement = {
		"recipe_id": recipe_id,
		"facility_item_id": result_item_id,
		"metadata": metadata.duplicate(true)
	}
	pending_origin = Vector2i(-1, -1)
	pending_result.clear()
	pending_rotation = 0
	var initial_placement: Dictionary = facility_placement_service.find_placement_near(
		result_item_id,
		world_data,
		player_cell,
		placement_context()
	)
	return {
		"ok": true,
		"placement_pending": true,
		"recipe_id": recipe_id,
		"result_item_id": result_item_id,
		"initial_origin": _origin_from_result(initial_placement) if bool(initial_placement.get("ok", false)) else Vector2i(-1, -1)
	}

func placement_context() -> Dictionary:
	return {
		"rotation_quarter_turns": pending_rotation,
		"metadata": pending_placement.get("metadata", {}).duplicate(true)
	}

func validate_origin(origin: Vector2i, facility_placement_service, world_data, player_cell: Vector2i) -> Dictionary:
	if not has_pending() or facility_placement_service == null:
		return {"ok": false, "reason": "no_pending_facility"}
	var distance := absi(origin.x - player_cell.x) + absi(origin.y - player_cell.y)
	if distance == 0 or distance > FacilityPlacementService.DEFAULT_PLACEMENT_SEARCH_RADIUS:
		return {"ok": false, "reason": "placement_out_of_range"}
	return facility_placement_service.can_place_facility(
		String(pending_placement.get("facility_item_id", "")),
		world_data,
		origin,
		placement_context()
	)

func select_origin(origin: Vector2i, facility_placement_service, world_data, player_cell: Vector2i) -> Dictionary:
	pending_origin = origin
	var validation := validate_origin(origin, facility_placement_service, world_data, player_cell)
	if bool(validation.get("ok", false)):
		pending_result = validation.duplicate(true)
	else:
		pending_result.clear()
	return validation

func rotate(facility_placement_service, world_data, player_cell: Vector2i) -> Dictionary:
	if not has_pending():
		return {"ok": false, "reason": "no_pending_facility"}
	pending_rotation = (pending_rotation + 1) % 4
	if pending_origin.x >= 0:
		var validation := select_origin(pending_origin, facility_placement_service, world_data, player_cell)
		validation["rotation_changed"] = true
		return validation
	return {"ok": true, "rotation_changed": true, "rotation_quarter_turns": pending_rotation}

func confirm(crafting_service, inventory, crafting_context: Dictionary, facility_placement_service, world_data) -> Dictionary:
	if not has_pending() or pending_origin.x < 0 or pending_result.is_empty():
		return {"ok": false, "reason": "no_pending_facility_placement"}
	if not bool(pending_result.get("ok", false)):
		return {"ok": false, "reason": "invalid_placement", "reselect": true}
	return place_selected(crafting_service, inventory, crafting_context, facility_placement_service, world_data, pending_result)

func place_selected(crafting_service, inventory, crafting_context: Dictionary, facility_placement_service, world_data, placement_result: Dictionary) -> Dictionary:
	if not has_pending():
		return {"ok": false, "reason": "no_pending_facility_placement"}
	var recipe_id := String(pending_placement.get("recipe_id", ""))
	var facility_item_id := String(pending_placement.get("facility_item_id", ""))
	var availability: Dictionary = crafting_service.can_craft(recipe_id, inventory, crafting_context)
	if not availability.ok:
		return placement_failed(String(availability.get("reason", "craft_unavailable")))
	var context := placement_context()
	if String(placement_result.get("facility_item_id", "")) != facility_item_id:
		return placement_failed("invalid_placement_result")
	var placed: Dictionary = facility_placement_service.place_validated_facility(
		placement_result,
		world_data,
		context
	)
	if not placed.ok:
		return placement_failed(String(placed.get("reason", "invalid_placement")))

	var crafted: Dictionary = crafting_service.craft(recipe_id, inventory, crafting_context, {"store_result": false})
	if not crafted.ok:
		world_data.release_footprint(String(placed.owner_id))
		return placement_failed(String(crafted.get("reason", "craft_failed")))
	crafted["installed"] = true
	crafted["placement"] = placed.duplicate(true)
	crafted["facility_item_id"] = facility_item_id
	return crafted

func placement_failed(reason: String) -> Dictionary:
	pending_result.clear()
	return {"ok": false, "reason": reason, "placement_pending": true}

func cancel() -> Dictionary:
	if not has_pending():
		return {"ok": false, "reason": "no_pending_facility"}
	clear()
	return {"ok": true, "cancelled": true}

func clear() -> void:
	pending_placement.clear()
	pending_origin = Vector2i(-1, -1)
	pending_result.clear()
	pending_rotation = 0

func footprint_for_pending_facility(facility_placement_service) -> Vector2i:
	if facility_placement_service == null:
		return Vector2i.ONE
	var definition: Dictionary = facility_placement_service.facility_for(String(pending_placement.get("facility_item_id", "")))
	var size: Vector2i = definition.get("footprint_size", Vector2i.ONE)
	return size if pending_rotation % 2 == 0 else Vector2i(size.y, size.x)

func player_facility_metadata(facility_item_id: String, facility_placement_service, source_id: String) -> Dictionary:
	var definition: Dictionary = facility_placement_service.facility_for(facility_item_id) if facility_placement_service != null else {}
	var resolved_source_id := source_id
	for key in ["source_id", "sprite_asset_id", "asset_id", "icon_asset_id", "icon"]:
		if not resolved_source_id.is_empty():
			break
		resolved_source_id = String(definition.get(key, ""))
		if not resolved_source_id.is_empty():
			break
	if resolved_source_id.is_empty():
		resolved_source_id = "asset_assets_sprites_objects_crafting_workbench_32x32_png"
	return {
		"facility_item_id": facility_item_id,
		"installed_by_player": true,
		"source_id": resolved_source_id
	}

func record_placed_facility(run_state: RunState, generated_world: Dictionary, placed: Dictionary) -> void:
	if run_state == null:
		return
	var reservation: Dictionary = placed.get("reservation", {})
	var record := {
		"biome_id": String(generated_world.get("biome_id", run_state.current_biome_id)),
		"facility_item_id": String(placed.get("facility_item_id", "")),
		"owner_id": String(placed.get("owner_id", "")),
		"origin": placed.get("origin", {}).duplicate(true),
		"metadata": reservation.get("metadata", {}).duplicate(true)
	}
	for existing in run_state.placed_facilities:
		if String(existing.get("owner_id", "")) == String(record.owner_id):
			return
	run_state.placed_facilities.append(record)

func available_facility_item_ids(crafting_service, facility_placement_service, world_data, run_state: RunState, generated_world: Dictionary, player_cell: Vector2i) -> Array:
	var ids: Array = []
	if crafting_service == null:
		return ids
	if facility_placement_service != null:
		for facility_item_id in facility_placement_service.facility_item_ids_near(world_data, player_cell):
			if not ids.has(String(facility_item_id)):
				ids.append(String(facility_item_id))
	if run_state != null:
		var current_biome_id := String(generated_world.get("biome_id", run_state.current_biome_id))
		for record_value in run_state.placed_facilities:
			if typeof(record_value) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_value
			if String(record.get("biome_id", current_biome_id)) != current_biome_id:
				continue
			var origin := _vector_from_dictionary(record.get("origin", {}))
			if maxi(absi(player_cell.x - origin.x), absi(player_cell.y - origin.y)) > FacilityPlacementService.DEFAULT_USE_DISTANCE:
				continue
			var facility_item_id := String(record.get("facility_item_id", ""))
			if not facility_item_id.is_empty() and not ids.has(facility_item_id):
				ids.append(facility_item_id)
	var name_to_id = crafting_service.get("item_name_to_id")
	if typeof(name_to_id) != TYPE_DICTIONARY:
		return ids
	for node in generated_world.get("facility_nodes", []):
		var position := _vector_from_dictionary(node.get("position", {}))
		if absi(player_cell.x - position.x) + absi(player_cell.y - position.y) > FacilityPlacementService.DEFAULT_USE_DISTANCE:
			continue
		var facility_key := String(node.get("facility_id", node.get("facility_term", "")))
		if name_to_id.has(facility_key) and not ids.has(String(name_to_id[facility_key])):
			ids.append(String(name_to_id[facility_key]))
	ids.sort()
	return ids

func restore_placed_facilities_for_current_biome(facility_placement_service, world_data, run_state: RunState, generated_world: Dictionary) -> Dictionary:
	if facility_placement_service == null or world_data == null or run_state == null:
		return {"ok": true, "restored": 0}
	var current_biome_id := String(generated_world.get("biome_id", run_state.current_biome_id))
	var restored := 0
	for record_value in run_state.placed_facilities:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		if String(record.get("biome_id", "")) != current_biome_id:
			continue
		var owner_id := String(record.get("owner_id", ""))
		if not owner_id.is_empty() and not world_data.get_reservation(owner_id).is_empty():
			continue
		var facility_item_id := String(record.get("facility_item_id", ""))
		var origin := _vector_from_dictionary(record.get("origin", {}))
		var metadata: Dictionary = record.get("metadata", {}).duplicate(true)
		var placement: Dictionary = facility_placement_service.place_facility(facility_item_id, world_data, origin, {
			"owner_id": owner_id,
			"rotation_quarter_turns": int(metadata.get("rotation_quarter_turns", 0)),
			"metadata": metadata
		})
		if not placement.ok:
			return {
				"ok": false,
				"reason": "placed_facility_restore_failed",
				"facility_item_id": facility_item_id,
				"owner_id": owner_id,
				"cause": placement
			}
		restored += 1
	return {"ok": true, "restored": restored}

static func reason_message(reason: String) -> String:
	match reason:
		"blocked":
			return "설치 불가: 막힌 타일"
		"out_of_bounds":
			return "설치 불가: 맵 밖"
		"missing_workspace":
			return "설치 불가: 작업 공간 부족"
		"placement_out_of_range":
			return "설치 불가: 너무 멂"
		_:
			return "설치 불가"

static func _origin_from_result(result: Dictionary) -> Vector2i:
	return _vector_from_dictionary(result.get("origin", {}))

static func _vector_from_dictionary(data) -> Vector2i:
	if typeof(data) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
