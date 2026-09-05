extends RefCounted

const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const RepairInteractionService = preload("res://src/world/interactions/repair_interaction_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "repair target world generation loads generated catalog")
	var repair_service_result: Dictionary = RepairInteractionService.from_catalog(catalog)
	asserts.true_value(repair_service_result.ok, "repair target generation reads item interaction definition")
	var targets: Array = repair_service_result.repair_interaction_service.world_generation_targets_for_biome("wasteland")
	var wasteland: Dictionary = catalog.find_by_id("biomes", "wasteland")
	var generated: Dictionary = WorldGenerator.new().generate(34033, catalog.data_version, wasteland, catalog.get_definitions("balance"), catalog.get_definitions("items"), {
		"dungeon_definitions": catalog.get_definitions("dungeons"),
		"boss_character_definitions": catalog.get_definitions("characters"),
		"repair_interaction_targets": targets
	})
	asserts.true_value(generated.ok, "wasteland generation succeeds with repair target")
	asserts.equal(generated.repair_interaction_targets.size(), 1, "wasteland places one repair interaction target")
	var node: Dictionary = generated.repair_interaction_targets[0]
	asserts.equal(node.id, "wasteland_abandoned_workbench", "repair target uses the confirmed stable runtime id")
	asserts.equal(node.target_id, "wasteland_abandoned_workbench", "repair target carries the confirmed target id")
	asserts.equal(_manhattan_distance(node.position, node.access_position), 1, "repair target has adjacent access cell")
	var renderer_input: Dictionary = WorldRendererProjection.new().project(generated.world_data)
	var interactable_owner_ids := _interactable_owner_ids(renderer_input)
	var facility_sources := _layer_source_ids_by_owner(renderer_input, WorldData.LAYER_FACILITIES)
	asserts.true_value(interactable_owner_ids.has(node.id), "repair target appears in renderer interactables")
	asserts.equal(String(facility_sources.get(node.id, "")), "asset_assets_sprites_objects_crafting_workbench_32x32_png", "repair target reuses existing workbench art source")
	var access_validation: Dictionary = ConnectivityValidator.new().validate_access_points(generated.world_data, [node.access_position])
	asserts.true_value(access_validation.valid, "repair target access point is entry-reachable")

func _interactable_owner_ids(renderer_input: Dictionary) -> Dictionary:
	var ids := {}
	for layer in renderer_input.get("layers", []):
		if String(layer.get("id", "")) != WorldData.LAYER_INTERACTABLES:
			continue
		for cell in layer.get("cells", []):
			ids[String(cell.get("owner_id", ""))] = true
	return ids

func _layer_source_ids_by_owner(renderer_input: Dictionary, layer_id: String) -> Dictionary:
	var source_ids := {}
	for layer in renderer_input.get("layers", []):
		if String(layer.get("id", "")) != layer_id:
			continue
		for cell in layer.get("cells", []):
			var owner_id := String(cell.get("owner_id", ""))
			var source_id := String(cell.get("source_id", ""))
			if not owner_id.is_empty() and not source_id.is_empty():
				source_ids[owner_id] = source_id
	return source_ids

func _manhattan_distance(a, b) -> int:
	return absi(int(a.x) - int(b.x)) + absi(int(a.y) - int(b.y))
