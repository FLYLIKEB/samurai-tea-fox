extends RefCounted
class_name WorldGenerator

const DeterministicRng = preload("res://src/core/rng/deterministic_rng.gd")
const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")

func generate(seed: int, data_version: String, biome_definition: Dictionary, balance_definitions: Array) -> Dictionary:
	var rng := DeterministicRng.new(seed)
	var core_dungeon_count := _balance_value(balance_definitions, "biome_core_dungeon_count", 1)
	var teleport_zone_count := _balance_value(balance_definitions, "biome_teleport_zone_count", 1)
	var landmarks := []

	for index in range(int(core_dungeon_count)):
		landmarks.append(_landmark("core_dungeon", index, rng))

	for index in range(int(teleport_zone_count)):
		landmarks.append(_landmark("teleport_zone", index, rng))

	landmarks.append(_landmark("entry", 0, rng))

	var world := {
		"schema_version": 1,
		"data_version": data_version,
		"seed": seed,
		"biome_id": biome_definition.get("id", ""),
		"biome_progression_order": biome_definition.get("progression_order", null),
		"landmarks": landmarks,
		"chunks": _chunks(rng),
		"connectivity": {}
	}

	var validator := ConnectivityValidator.new()
	world.connectivity = validator.validate(world)
	return world

func _landmark(kind: String, index: int, rng: DeterministicRng) -> Dictionary:
	return {
		"id": "%s_%d" % [kind, index],
		"kind": kind,
		"position": {
			"x": rng.next_range(4, 59),
			"y": rng.next_range(4, 31)
		},
		"required": true
	}

func _chunks(rng: DeterministicRng) -> Array:
	var chunks := []
	for index in range(8):
		chunks.append({
			"id": "chunk_%d" % index,
			"variant": rng.next_range(0, 5),
			"position": {"x": rng.next_range(0, 7), "y": rng.next_range(0, 4)}
		})
	return chunks

func _balance_value(balance_definitions: Array, id: String, fallback: float) -> float:
	for item in balance_definitions:
		if item.get("id", "") == id:
			return float(item.get("value", fallback))
	return fallback

