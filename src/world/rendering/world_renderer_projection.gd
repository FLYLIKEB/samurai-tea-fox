extends RefCounted
class_name WorldRendererProjection

const WorldData = preload("res://src/world/data/world_data.gd")

func project(world_data: Dictionary) -> Dictionary:
	var bounds: Dictionary = world_data.get("bounds", {})
	var width := int(bounds.get("width", 0))
	var height := int(bounds.get("height", 0))
	var terrain_cells := []
	var facility_cells := []
	var entity_cells := []
	var interactable_cells := []

	for cell in world_data.get("cells", []):
		var position: Dictionary = cell.get("position", {})
		var vector := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		if vector.x < 0 or vector.y < 0 or vector.x >= width or vector.y >= height:
			continue

		var layers: Dictionary = cell.get("layers", {})
		var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
		terrain_cells.append({
			"position": position.duplicate(true),
			"source_id": terrain.get("render_id", terrain.get("id", ""))
		})
		_add_owner_cells(facility_cells, position, layers.get(WorldData.LAYER_FACILITIES, []))
		_add_owner_cells(entity_cells, position, layers.get(WorldData.LAYER_ENTITIES, []))
		_add_owner_cells(interactable_cells, position, layers.get(WorldData.LAYER_INTERACTABLES, []))

	return {
		"schema_version": 1,
		"read_only": true,
		"tile_size": int(world_data.get("tile_size", 32)),
		"bounds": bounds.duplicate(true),
		"layers": [
			{"id": WorldData.LAYER_TERRAIN, "kind": "tile", "cells": terrain_cells},
			{"id": WorldData.LAYER_FACILITIES, "kind": "footprint", "cells": facility_cells},
			{"id": WorldData.LAYER_ENTITIES, "kind": "footprint", "cells": entity_cells},
			{"id": WorldData.LAYER_INTERACTABLES, "kind": "interaction", "cells": interactable_cells}
		],
		"required_landmarks": world_data.get("required_landmarks", []).duplicate(true)
	}

func _add_owner_cells(output: Array, position: Dictionary, owners: Array) -> void:
	for owner_id in owners:
		output.append({
			"position": position.duplicate(true),
			"owner_id": owner_id
		})
