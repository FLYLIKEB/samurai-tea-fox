extends RefCounted
class_name WorldRendererProjection

const WorldData = preload("res://src/world/data/world_data.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")

func project(world_data: Dictionary, progression_projection := {}) -> Dictionary:
	var bounds: Dictionary = world_data.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	var terrain_cells := []
	var facility_cells := []
	var entity_cells := []
	var interactable_cells := []
	var owner_source_ids := _owner_source_ids(world_data)

	for cell in world_data.get("cells", []):
		var position: Dictionary = cell.get("position", {})
		var vector := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		if vector.x < 0 or vector.y < 0 or vector.x >= width or vector.y >= height:
			continue

		var layers: Dictionary = cell.get("layers", {})
		var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
		var terrain_cell := {
			"position": position.duplicate(true),
			"source_id": terrain.get("render_id", terrain.get("id", ""))
		}
		var atlas_coords = terrain.get("atlas_coords", null)
		if typeof(atlas_coords) == TYPE_DICTIONARY:
			terrain_cell["atlas_coords"] = atlas_coords.duplicate(true)
		terrain_cells.append(terrain_cell)
		_add_owner_cells(facility_cells, position, layers.get(WorldData.LAYER_FACILITIES, []), owner_source_ids)
		_add_owner_cells(entity_cells, position, layers.get(WorldData.LAYER_ENTITIES, []), owner_source_ids)
		_add_owner_cells(interactable_cells, position, layers.get(WorldData.LAYER_INTERACTABLES, []), owner_source_ids)

	return {
		"schema_version": 1,
		"read_only": true,
		"tile_size": int(world_data.get("tile_size", RuntimeConstants.float_value("world.tile_size_pixels"))),
		"bounds": bounds.duplicate(true),
		"layers": [
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": terrain_cells},
			{"id": WorldData.LAYER_FACILITIES, "kind": "footprint", "cells": facility_cells},
			{"id": WorldData.LAYER_ENTITIES, "kind": "footprint", "cells": entity_cells},
			{"id": WorldData.LAYER_INTERACTABLES, "kind": "interaction", "cells": interactable_cells}
		],
		"required_landmarks": _project_landmarks(world_data, progression_projection)
	}

func _project_landmarks(world_data: Dictionary, progression_projection) -> Array:
	var landmarks: Array = world_data.get("required_landmarks", []).duplicate(true)
	if typeof(progression_projection) != TYPE_DICTIONARY:
		return landmarks
	var teleport_states: Dictionary = progression_projection.get("teleport_states", {})
	for landmark in landmarks:
		if String(landmark.get("kind", landmark.get("type", ""))) != WorldData.LANDMARK_TELEPORT_ZONE:
			continue
		var metadata: Dictionary = landmark.get("metadata", {})
		var biome_id := String(metadata.get("teleport_biome_id", metadata.get("biome_id", "")))
		if biome_id.is_empty() or not teleport_states.has(biome_id):
			continue
		landmark["teleport_biome_id"] = biome_id
		landmark["teleport_state"] = String(teleport_states[biome_id])
	return landmarks

func _add_owner_cells(output: Array, position: Dictionary, owners: Array, owner_source_ids: Dictionary) -> void:
	for owner_id in owners:
		var cell := {
			"position": position.duplicate(true),
			"owner_id": owner_id
		}
		var source_id := String(owner_source_ids.get(String(owner_id), ""))
		if not source_id.is_empty():
			cell["source_id"] = source_id
		var metadata: Dictionary = _owner_metadata.get(String(owner_id), {})
		if metadata.has("rotation_degrees"):
			cell["rotation_degrees"] = float(metadata.get("rotation_degrees", 0.0))
		output.append(cell)

var _owner_metadata: Dictionary = {}

func _owner_source_ids(world_data: Dictionary) -> Dictionary:
	var sources := {}
	_owner_metadata = {}
	for reservation in world_data.get("reservations", []):
		var owner_id := String(reservation.get("owner_id", ""))
		var metadata: Dictionary = reservation.get("metadata", {})
		var source_id := String(metadata.get("source_id", ""))
		if not owner_id.is_empty() and not source_id.is_empty():
			sources[owner_id] = source_id
		if not owner_id.is_empty():
			_owner_metadata[owner_id] = metadata.duplicate(true)
	return sources
