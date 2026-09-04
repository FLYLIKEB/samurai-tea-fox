extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const ConnectivityValidator = preload("res://src/world/generation/connectivity_validator.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

const COMMON_STONE_SOURCE_ID := "small_rock_resource"
const MOUNTAIN_MINE_SOURCE_ID := "asset_assets_sprites_objects_mining_rock_cave_entrance_1x2_64x32_png"

class TestPlayer:
	extends Node2D
	var resources := PlayerResources.new(100, 100, 100, 35)

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "DEV-76 loads generated Notion export data")
	if not loaded.ok:
		return

	var asset_catalog := AssetCatalog.new()
	var manifest_loaded: Dictionary = asset_catalog.load_manifest()
	asserts.true_value(manifest_loaded.ok, "DEV-76 loads promoted runtime asset manifest")
	if not manifest_loaded.ok:
		return

	var generator := WorldGenerator.new()
	var common := _generate_world(catalog, generator, WorldGenerator.BIOME_COMMON, 11037)
	var common_repeat := _generate_world(catalog, generator, WorldGenerator.BIOME_COMMON, 11037)
	asserts.true_value(common.ok, "DEV-76 common biome generation succeeds")
	asserts.true_value(common_repeat.ok, "DEV-76 common biome repeat generation succeeds")
	if common.ok and common_repeat.ok:
		asserts.equal(_dev76_signature(common), _dev76_signature(common_repeat), "DEV-76 same seed and data_version reproduce stone renderer inputs")
		_assert_common_stone_renderer_contract(asserts, common, asset_catalog)
		_assert_stone_command_and_save_load(asserts, catalog, common)

	var mountain := _generate_world(catalog, generator, WorldGenerator.BIOME_MOUNTAIN, 22033)
	var mountain_repeat := _generate_world(catalog, generator, WorldGenerator.BIOME_MOUNTAIN, 22033)
	asserts.true_value(mountain.ok, "DEV-76 mountain biome generation succeeds")
	asserts.true_value(mountain_repeat.ok, "DEV-76 mountain biome repeat generation succeeds")
	if mountain.ok and mountain_repeat.ok:
		asserts.equal(_dev76_signature(mountain), _dev76_signature(mountain_repeat), "DEV-76 same seed and data_version reproduce mine renderer inputs")
		_assert_mountain_mine_renderer_contract(asserts, mountain, asset_catalog)

func _generate_world(catalog: DataCatalog, generator: WorldGenerator, biome_id: String, seed: int) -> Dictionary:
	var biome := catalog.find_by_id("biomes", biome_id)
	var world := generator.generate(
		seed,
		catalog.data_version,
		biome,
		catalog.get_definitions("balance"),
		catalog.get_definitions("items")
	)
	if bool(world.get("ok", false)):
		world["renderer_input"] = WorldRendererProjection.new().project(world["world_data"])
	return world

func _assert_common_stone_renderer_contract(asserts, world: Dictionary, asset_catalog: AssetCatalog) -> void:
	asserts.true_value(world.connectivity.valid, "DEV-76 common required landmarks remain connected")
	asserts.true_value(world.resource_accessibility.valid, "DEV-76 common resources remain entry-accessible")
	var entity_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_ENTITIES)
	var interactable_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_INTERACTABLES)
	var stone_count := 0
	for node in world.resource_nodes:
		if String(node.get("resource_id", "")) != "stone":
			continue
		stone_count += 1
		var owner_id := String(node.get("id", ""))
		asserts.false_value(node.has("source_id"), "DEV-76 common stone node stays semantic-only")
		asserts.equal(String(entity_sources.get(owner_id, "")), COMMON_STONE_SOURCE_ID, "DEV-76 common stone appears in renderer entity layer")
		asserts.equal(String(interactable_sources.get(owner_id, "")), COMMON_STONE_SOURCE_ID, "DEV-76 common stone appears in renderer interactable layer")
		asserts.true_value(not asset_catalog.id_for_reference(COMMON_STONE_SOURCE_ID).is_empty(), "DEV-76 common stone source resolves to an existing promoted asset")
		_assert_access_point_valid(asserts, world, node.get("access_position", {}), "DEV-76 common stone access point is reachable")
	asserts.true_value(stone_count >= 1, "DEV-76 common biome places at least one visible stone resource")

func _assert_mountain_mine_renderer_contract(asserts, world: Dictionary, asset_catalog: AssetCatalog) -> void:
	asserts.true_value(world.connectivity.valid, "DEV-76 mountain required landmarks remain connected")
	asserts.true_value(world.resource_accessibility.valid, "DEV-76 mountain resources remain entry-accessible")
	asserts.true_value(world.facility_accessibility.valid, "DEV-76 mountain facilities remain entry-accessible")
	var facility_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_FACILITIES)
	var interactable_sources := _layer_source_ids_by_owner(world.renderer_input, WorldData.LAYER_INTERACTABLES)
	var mine_count := 0
	for node in world.facility_nodes:
		if String(node.get("facility_term", "")) != "광산":
			continue
		mine_count += 1
		var owner_id := String(node.get("id", ""))
		asserts.false_value(node.has("source_id"), "DEV-76 mountain mine node stays semantic-only")
		asserts.equal(String(facility_sources.get(owner_id, "")), MOUNTAIN_MINE_SOURCE_ID, "DEV-76 mountain mine appears in renderer facility layer")
		asserts.equal(String(interactable_sources.get(owner_id, "")), MOUNTAIN_MINE_SOURCE_ID, "DEV-76 mountain mine appears in renderer interactable layer")
		asserts.true_value(not asset_catalog.id_for_reference(MOUNTAIN_MINE_SOURCE_ID).is_empty(), "DEV-76 mountain mine source resolves to an existing promoted asset")
		_assert_access_point_valid(asserts, world, node.get("access_position", {}), "DEV-76 mountain mine access point is reachable")
	asserts.equal(mine_count, 1, "DEV-76 mountain biome places exactly one mine facility")

	var root := Node2D.new()
	var render_result: Dictionary = WorldSceneRenderer.new().render(root, world.renderer_input)
	asserts.true_value(render_result.ok, "DEV-76 headless renderer accepts mountain mine renderer input")
	if render_result.ok:
		asserts.true_value(int(render_result.counts.get(WorldData.LAYER_FACILITIES, 0)) >= 1, "DEV-76 headless renderer creates facility sprites")
		asserts.false_value(MOUNTAIN_MINE_SOURCE_ID in render_result.asset_report.missing_references, "DEV-76 headless renderer resolves the mine asset reference")
	root.free()

func _assert_stone_command_and_save_load(asserts, catalog: DataCatalog, generated_world: Dictionary) -> void:
	var stone_node := _first_resource_node(generated_world, "stone")
	asserts.true_value(not stone_node.is_empty(), "DEV-76 command fixture uses generated common stone")
	if stone_node.is_empty():
		return
	var stone_id := String(stone_node.get("id", ""))
	var stone_cell := _vector_from_dictionary(stone_node.get("position", {}))
	var access_cell := _vector_from_dictionary(stone_node.get("access_position", {}))
	var direction := Vector2i(int(sign(stone_cell.x - access_cell.x)), int(sign(stone_cell.y - access_cell.y)))

	var mobile_runtime := _configured_main(catalog, generated_world.duplicate(true), RunState.new())
	asserts.true_value(mobile_runtime.result.ok, "DEV-76 mobile stone runtime configures acquisition service")
	if mobile_runtime.result.ok:
		asserts.equal(mobile_runtime.main.acquisition_service.gatherable_for(stone_id).definition_id, "stone", "DEV-76 stone registers by stable item id")
		asserts.true_value(mobile_runtime.main.submit_mobile_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": stone_id})), "DEV-76 mobile INTERACT target gathers stone")
		asserts.equal(mobile_runtime.main.inventory.get_total_quantity("stone"), 1, "DEV-76 mobile INTERACT increases stone inventory")
		asserts.true_value(mobile_runtime.main.acquisition_service.gatherable_for(stone_id).depleted, "DEV-76 gathered stone becomes depleted")
		var saved_state: RunState = RunState.from_dictionary(mobile_runtime.main.snapshot_run_state())
		var restored_runtime := _configured_main(catalog, generated_world.duplicate(true), saved_state)
		asserts.true_value(restored_runtime.result.ok, "DEV-76 stone depleted state restores")
		if restored_runtime.result.ok:
			asserts.equal(restored_runtime.main.inventory.get_total_quantity("stone"), 1, "DEV-76 restored runtime preserves stone inventory")
			asserts.true_value(restored_runtime.main.acquisition_service.gatherable_for(stone_id).depleted, "DEV-76 restored runtime preserves depleted stone")
		restored_runtime.main.free()
	mobile_runtime.main.free()

	var desktop_runtime := _configured_main(catalog, generated_world.duplicate(true), RunState.new())
	asserts.true_value(desktop_runtime.result.ok, "DEV-76 desktop stone runtime configures acquisition service")
	if desktop_runtime.result.ok:
		var desktop_player := _set_test_player(desktop_runtime.main, access_cell)
		asserts.true_value(desktop_runtime.main.submit_desktop_action_command("interact", direction), "DEV-76 desktop interact gathers adjacent stone through command layer")
		asserts.equal(desktop_runtime.main.inventory.get_total_quantity("stone"), 1, "DEV-76 desktop interact increases stone inventory")
		desktop_player.free()
	desktop_runtime.main.free()

	var pointer_runtime := _configured_main(catalog, generated_world.duplicate(true), RunState.new())
	asserts.true_value(pointer_runtime.result.ok, "DEV-76 pointer stone runtime configures acquisition service")
	if pointer_runtime.result.ok:
		var pointer_player := _set_test_player(pointer_runtime.main, access_cell)
		asserts.true_value(pointer_runtime.main.submit_pointer_interaction(pointer_runtime.main.world_position_for_cell_center(stone_cell)), "DEV-76 pointer interact gathers adjacent stone through command layer")
		asserts.equal(pointer_runtime.main.inventory.get_total_quantity("stone"), 1, "DEV-76 pointer interact increases stone inventory")
		pointer_player.free()
	pointer_runtime.main.free()

func _configured_main(catalog: DataCatalog, generated_world: Dictionary, run_state: RunState) -> Dictionary:
	var main := Main.new()
	main.catalog = catalog
	main.run_state = run_state
	main.generated_world = generated_world
	var services: Dictionary = main._configure_run_services(catalog)
	if not services.ok:
		return {"main": main, "result": services, "player": null}
	var acquisition_result: Dictionary = main._configure_acquisition_for_generated_world()
	return {"main": main, "result": acquisition_result, "player": null}

func _set_test_player(main: Main, cell: Vector2i) -> TestPlayer:
	var player := TestPlayer.new()
	main.player = player
	player.global_position = main.world_position_for_cell_center(cell)
	return player

func _first_resource_node(world: Dictionary, resource_id: String) -> Dictionary:
	for node in world.get("resource_nodes", []):
		if String(node.get("resource_id", "")) == resource_id:
			return node
	return {}

func _assert_access_point_valid(asserts, world: Dictionary, access_position, message: String) -> void:
	var validation := ConnectivityValidator.new().validate_access_points(world.world_data, [access_position])
	asserts.true_value(validation.valid, message)

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

func _dev76_signature(world: Dictionary) -> Dictionary:
	var resource_rows := []
	for node in world.get("resource_nodes", []):
		resource_rows.append("%s|%s|%s|%s" % [
			String(node.get("id", "")),
			String(node.get("resource_id", "")),
			_key(_vector_from_dictionary(node.get("position", {}))),
			_key(_vector_from_dictionary(node.get("access_position", {})))
		])
	resource_rows.sort()
	var facility_rows := []
	for node in world.get("facility_nodes", []):
		facility_rows.append("%s|%s|%s|%s" % [
			String(node.get("id", "")),
			String(node.get("facility_term", "")),
			_key(_vector_from_dictionary(node.get("position", {}))),
			_key(_vector_from_dictionary(node.get("access_position", {})))
		])
	facility_rows.sort()
	var renderer_rows := []
	for layer in world.renderer_input.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		for cell in layer.get("cells", []):
			var owner_id := String(cell.get("owner_id", ""))
			if owner_id.is_empty():
				continue
			renderer_rows.append("%s|%s|%s|%s" % [
				layer_id,
				owner_id,
				String(cell.get("source_id", "")),
				_key(_vector_from_dictionary(cell.get("position", {})))
			])
	renderer_rows.sort()
	return {
		"data_version": String(world.get("data_version", "")),
		"resources": resource_rows,
		"facilities": facility_rows,
		"renderer": renderer_rows
	}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]
