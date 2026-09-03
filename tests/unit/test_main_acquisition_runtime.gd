extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class DropSource:
	extends Node
	signal drop_requested(event: Dictionary)

class FailureProbe:
	extends RefCounted
	var reasons := []

	func record(error: Dictionary) -> void:
		reasons.append(String(error.get("reason", "")))

class MovementPlayer:
	extends Node2D

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "runtime acquisition fixture loads generated definitions")
	_assert_main_generates_current_biome(asserts, catalog, "mountain_region")
	_assert_main_generates_current_biome(asserts, catalog, "wasteland")
	_assert_main_generates_current_biome(asserts, catalog, "snowfield")
	_assert_main_generates_current_biome(asserts, catalog, "rainforest")
	var runtime := _configured_runtime(catalog, RunState.new())
	asserts.true_value(runtime.result.ok, "main configures acquisition against generated world data: %s" % runtime.result.get("error", ""))
	if not runtime.result.ok:
		runtime.main.free()
		return
	asserts.equal(runtime.main.acquisition_service.gatherable_for("resource_0").definition_id, "wood", "generated resource registers with its confirmed stable item id")
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "resource_0"})
	asserts.true_value(runtime.main.submit_mobile_action_command(command), "main routes target INTERACT into acquisition")
	asserts.equal(runtime.main.inventory.get_total_quantity("wood"), 1, "live interaction grants the confirmed resource")
	asserts.true_value(runtime.main.run_state.acquisitions.gatherables[0].depleted, "live acquisition changes persist into RunState")

	var desktop_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(desktop_runtime.result.ok, "desktop interaction fixture configures")
	asserts.true_value(desktop_runtime.main.submit_desktop_action_command("interact", Vector2i.RIGHT), "desktop interact resolves the forward world target")
	asserts.equal(desktop_runtime.main.inventory.get_total_quantity("wood"), 1, "desktop interact grants through the shared acquisition command")

	var mobile_button_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(mobile_button_runtime.result.ok, "mobile button interaction fixture configures")
	asserts.true_value(mobile_button_runtime.main.submit_mobile_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.RIGHT)), "mobile interact without target resolves through the shared nearby target path")
	asserts.equal(mobile_button_runtime.main.inventory.get_total_quantity("wood"), 1, "mobile interact without target grants through the shared acquisition command")

	var pointer_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.ZERO)
	asserts.true_value(pointer_runtime.result.ok, "pointer interaction fixture configures")
	var pointer_position: Vector2 = pointer_runtime.main.world_position_for_cell_center(Vector2i.ZERO)
	asserts.true_value(pointer_runtime.main.submit_pointer_interaction(pointer_position), "pointer click resolves the clicked interactable cell")
	asserts.equal(pointer_runtime.main.inventory.get_total_quantity("wood"), 1, "pointer click grants through the shared acquisition command")

	var near_pointer_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(near_pointer_runtime.result.ok, "nearby pointer interaction fixture configures")
	var near_pointer_position: Vector2 = near_pointer_runtime.main.world_position_for_cell_center(Vector2i.ZERO)
	asserts.true_value(near_pointer_runtime.main.submit_pointer_interaction(near_pointer_position), "pointer click tolerates one-cell sprite edge misses")
	asserts.equal(near_pointer_runtime.main.inventory.get_total_quantity("wood"), 1, "nearby pointer click grants through the shared acquisition command")

	var empty_click_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.ZERO)
	asserts.true_value(empty_click_runtime.result.ok, "empty pointer fixture configures")
	var inventory_before_empty_click: Dictionary = empty_click_runtime.main.inventory.to_snapshot()
	asserts.false_value(empty_click_runtime.main.submit_pointer_interaction(empty_click_runtime.main.world_position_for_cell_center(Vector2i(2, 0))), "empty pointer interaction ignores empty cells")
	asserts.equal(empty_click_runtime.main.inventory.to_snapshot(), inventory_before_empty_click, "empty pointer interaction does not mutate inventory")

	var movement_runtime := _configured_movement_runtime()
	asserts.true_value(movement_runtime.main.submit_pointer_movement(movement_runtime.main.world_position_for_cell_center(Vector2i(2, 0))), "empty walkable pointer click sets a movement target")
	var pointer_move = movement_runtime.main.movement_command_for_current_inputs(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	asserts.equal(pointer_move.direction, Vector2i.RIGHT, "pointer movement walks toward the clicked tile")
	asserts.true_value(movement_runtime.main.submit_mobile_movement_direction(Vector2i.DOWN), "mobile d-pad direction submits through the shared movement selector")
	var button_move = movement_runtime.main.movement_command_for_current_inputs(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	asserts.equal(button_move.direction, Vector2i.DOWN, "mobile d-pad movement overrides a prior pointer target")
	var keyboard_move := GameCommand.new(GameCommand.Type.MOVE, Vector2i.LEFT)
	var selected_keyboard = movement_runtime.main.movement_command_for_current_inputs(keyboard_move)
	asserts.equal(selected_keyboard.direction, Vector2i.LEFT, "keyboard movement has priority over pointer and d-pad movement")
	movement_runtime.main.world_data.set_terrain(Vector2i(3, 3), "water", false)
	asserts.false_value(movement_runtime.main.submit_pointer_movement(movement_runtime.main.world_position_for_cell_center(Vector2i(3, 3))), "pointer movement rejects blocked terrain")

	var tea_runtime := _configured_runtime(catalog, RunState.new())
	asserts.true_value(tea_runtime.result.ok, "tea command fixture configures")
	asserts.true_value(tea_runtime.main.inventory.add_item("tea_8", 1).ok, "generated tea leaf can be stocked for command routing")
	asserts.true_value(tea_runtime.main.inventory.add_item("humble_clay_bowl", 1).ok, "generated tea vessel can be stocked for command routing")
	asserts.true_value(tea_runtime.main.tea_service.brew("tea_8", "humble_clay_bowl", tea_runtime.main.inventory, 0).ok, "prepared tea can occupy quickslot 0")
	asserts.true_value(tea_runtime.main.submit_desktop_action_command("drink_tea", Vector2i.ZERO, 0), "desktop tea command routes into TeaService")
	asserts.false_value(tea_runtime.main.tea_service.has_prepared_tea(0), "routed tea command consumes the prepared quickslot use")

	var saved_state: RunState = RunState.from_dictionary(runtime.main.snapshot_run_state())
	var restored := _configured_runtime(catalog, saved_state)
	asserts.true_value(restored.result.ok, "main reloads acquisition state during world lifecycle configuration")
	asserts.equal(restored.main.inventory.get_total_quantity("wood"), 1, "reloaded runtime preserves inventory granted through live INTERACT")
	asserts.true_value(restored.main.acquisition_service.gatherable_for("resource_0").depleted, "reloaded runtime preserves generated resource depletion")

	var source := DropSource.new()
	var probe := FailureProbe.new()
	restored.main.acquisition_service.operation_failed.connect(probe.record)
	asserts.true_value(restored.main._connect_acquisition_combat_source(source).ok, "main connects combat drop source")
	source.drop_requested.emit({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.equal(restored.main.inventory.get_total_quantity("item_33"), 1, "generated road_bandit drop grants the exact related coin stable ID")
	var duplicate_result: Dictionary = restored.main.acquisition_service.process_drop_request({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.false_value(duplicate_result.ok, "duplicate generated drop request is rejected")
	asserts.equal(restored.main.inventory.get_total_quantity("item_33"), 1, "duplicate generated drop request does not grant twice")

	var dropped_state: RunState = RunState.from_dictionary(restored.main.snapshot_run_state())
	var drop_restored := _configured_runtime(catalog, dropped_state)
	asserts.true_value(drop_restored.result.ok, "fresh runtime restores generated drop acquisition state")
	asserts.equal(drop_restored.main.inventory.get_total_quantity("item_33"), 1, "generated road_bandit grant persists with inventory round-trip")
	asserts.true_value(drop_restored.main.acquisition_service.to_snapshot().processed_drop_request_ids.has("road_bandit_1"), "generated drop duplicate guard persists round-trip")
	var restored_probe := FailureProbe.new()
	drop_restored.main.acquisition_service.operation_failed.connect(restored_probe.record)
	var restored_duplicate: Dictionary = drop_restored.main.acquisition_service.process_drop_request({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.false_value(restored_duplicate.ok, "restored runtime rejects the persisted duplicate request")
	asserts.equal(drop_restored.main.inventory.get_total_quantity("item_33"), 1, "round-tripped duplicate guard prevents another grant")
	asserts.equal(restored_probe.reasons, ["drop_already_processed"], "round-tripped duplicate request remains rejected")
	asserts.equal(probe.reasons, ["drop_already_processed"], "duplicate drop failure is observable without mutating inventory")
	source.free()
	runtime.main.free()
	desktop_runtime.main.free()
	mobile_button_runtime.main.free()
	pointer_runtime.main.free()
	near_pointer_runtime.main.free()
	empty_click_runtime.main.free()
	tea_runtime.main.free()
	movement_runtime.player.free()
	movement_runtime.main.free()
	restored.main.free()
	drop_restored.main.free()

func _assert_main_generates_current_biome(asserts, catalog: DataCatalog, biome_id: String) -> void:
	var state := RunState.new()
	state.current_biome_id = biome_id
	state.teleport_states = {"common_region": "repaired", "mountain_region": "repaired", "wasteland": "broken"}
	var runtime := Main.new()
	var combat_source := DropSource.new()
	var world_root := Node2D.new()
	runtime.catalog = catalog
	runtime.run_state = state
	runtime.combat_dummy = combat_source
	runtime.world_visuals = world_root
	var services: Dictionary = runtime._configure_run_services(catalog)
	asserts.true_value(services.ok, "%s runtime fixture configures run services" % biome_id)
	if services.ok:
		var result: Dictionary = runtime._configure_world_for_current_run()
		asserts.true_value(result.ok, "main configures generated world for current %s biome: %s" % [biome_id, result.get("error", "")])
		asserts.equal(runtime.generated_world.get("biome_id", ""), biome_id, "main uses current_biome_id instead of hard-coded common_region")
		asserts.equal(runtime.generated_world.get("biome_generation_rule_id", ""), biome_id, "main feeds the current biome definition into WorldGenerator")
		asserts.true_value(runtime.world_render_result.get("ok", false), "%s runtime render uses generated renderer input" % biome_id)
		if biome_id == "wasteland":
			_assert_wasteland_runtime_sources(asserts, runtime)
		elif biome_id == "snowfield":
			_assert_snowfield_runtime_sources(asserts, runtime)
		elif biome_id == "rainforest":
			_assert_rainforest_runtime_sources(asserts, runtime)
	runtime.free()
	combat_source.free()
	world_root.free()

func _assert_wasteland_runtime_sources(asserts, runtime: Main) -> void:
	var owner_sources: Dictionary = runtime._owner_sprite_sources(runtime.generated_world)
	var has_iron_scrap_source := false
	for node in runtime.generated_world.get("resource_nodes", []):
		if String(node.get("resource_id", "")) != "item_28":
			continue
		var owner_id := String(node.get("id", ""))
		asserts.equal(String(node.get("source_id", "")), "asset_assets_sprites_objects_mining_iron_ore_32x32_png", "wasteland repair resource carries manifest asset id")
		asserts.equal(String(owner_sources.get(owner_id, "")), "asset_assets_sprites_objects_mining_iron_ore_32x32_png", "main maps wasteland repair resource owner to its manifest asset id")
		has_iron_scrap_source = true
	asserts.true_value(has_iron_scrap_source, "wasteland runtime generates sourced iron-scrap repair resources")

func _assert_snowfield_runtime_sources(asserts, runtime: Main) -> void:
	var owner_sources: Dictionary = runtime._owner_sprite_sources(runtime.generated_world)
	var has_conifer_source := false
	for node in runtime.generated_world.get("resource_nodes", []):
		if String(node.get("resource_id", "")) != "wood":
			continue
		var owner_id := String(node.get("id", ""))
		asserts.equal(String(node.get("source_id", "")), "asset_assets_tiles_terrain_snow_snowy_pine_tree_01_32x32_png", "snowfield conifer wood carries manifest asset id")
		asserts.equal(String(owner_sources.get(owner_id, "")), "asset_assets_tiles_terrain_snow_snowy_pine_tree_01_32x32_png", "main maps snowfield wood owner to its manifest asset id")
		has_conifer_source = true
	asserts.true_value(has_conifer_source, "snowfield runtime generates sourced conifer wood resources")

func _assert_rainforest_runtime_sources(asserts, runtime: Main) -> void:
	var owner_sources: Dictionary = runtime._owner_sprite_sources(runtime.generated_world)
	var has_agarwood_source := false
	var has_incense_gatherable := false
	for node in runtime.generated_world.get("resource_nodes", []):
		if String(node.get("resource_id", "")) == "item_5":
			var incense_owner_id := String(node.get("id", ""))
			asserts.equal(String(node.get("source_id", "")), "asset_assets_sprites_objects_natural_props_round_tree_large_32x32_png", "rainforest 침향 carries agarwood manifest asset id")
			asserts.equal(String(owner_sources.get(incense_owner_id, "")), "asset_assets_sprites_objects_natural_props_round_tree_large_32x32_png", "main maps rainforest 침향 owner to agarwood manifest asset id")
			asserts.equal(runtime.acquisition_service.gatherable_for(incense_owner_id).definition_id, "item_5", "main registers rainforest 침향 as a gatherable")
			has_incense_gatherable = true
		if String(node.get("resource_id", "")) != "wood":
			continue
		var owner_id := String(node.get("id", ""))
		asserts.equal(String(node.get("source_id", "")), "asset_assets_sprites_objects_natural_props_round_tree_large_32x32_png", "rainforest wood carries agarwood manifest asset id")
		asserts.equal(String(owner_sources.get(owner_id, "")), "asset_assets_sprites_objects_natural_props_round_tree_large_32x32_png", "main maps rainforest wood owner to its manifest asset id")
		has_agarwood_source = true
	asserts.true_value(has_agarwood_source, "rainforest runtime generates sourced agarwood resources")
	asserts.true_value(has_incense_gatherable, "rainforest runtime registers confirmed 침향 rare resources")

func _configured_runtime(catalog, state: RunState, resource_position := Vector2i.ZERO) -> Dictionary:
	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = state
	var services: Dictionary = runtime._configure_run_services(catalog)
	if not services.ok:
		return {"main": runtime, "result": services}
	var world := WorldData.new(3, 1, "grass", true)
	world.reserve_entity("resource_0", resource_position, Vector2i.ONE, true, {"resource_id": "wood"})
	runtime.generated_world = {
		"ok": true,
		"world_data": world.to_dictionary(),
		"resource_nodes": [{"id": "resource_0", "resource_id": "wood", "position": {"x": resource_position.x, "y": resource_position.y}}]
	}
	return {"main": runtime, "result": runtime._configure_acquisition_for_generated_world()}

func _configured_movement_runtime() -> Dictionary:
	var runtime := Main.new()
	runtime.world_data = WorldData.new(4, 4, "grass", true)
	var movement_player := MovementPlayer.new()
	runtime.player = movement_player
	movement_player.global_position = runtime.world_position_for_cell_center(Vector2i.ZERO)
	return {"main": runtime, "player": movement_player}
