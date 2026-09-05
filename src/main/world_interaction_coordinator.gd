extends RefCounted
class_name WorldInteractionCoordinator

const AcquisitionEffect = preload("res://src/presentation/acquisition_effect.gd")
const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func submit_pointer_interaction(main, world_position: Vector2) -> bool:
	if main.has_pending_facility_placement():
		main._select_pending_facility_at(main.world_cell_from_world_position(world_position))
		return true
	main._dungeon_debug("클릭 상호작용: world=%s cell=%s" % [world_position, main.world_cell_from_world_position(world_position)])
	var ore_hit: Dictionary = dungeon_ore_target_near_cell(main, main.world_cell_from_world_position(world_position), 2)
	if not ore_hit.is_empty():
		main._dungeon_debug("클릭 광석 대상 발견: %s" % ore_hit)
		return queue_pointer_acquisition(main, ore_hit.target_id, ore_hit.cell)
	var landmark_hit: Dictionary = landmark_target_near_world_position(main, world_position)
	if not landmark_hit.is_empty():
		main._dungeon_debug("클릭 대상: required dungeon landmark %s" % landmark_hit)
		return queue_pointer_landmark(main, landmark_hit.target_id, landmark_hit.cell)
	var house_hit: Dictionary = large_house_target_near_world_position(main, world_position)
	if not house_hit.is_empty():
		main._dungeon_debug("클릭 대상: large house dungeon %s" % house_hit)
		return queue_pointer_landmark(main, house_hit.target_id, house_hit.cell)
	if pointer_enemy_clicked(main, world_position):
		submit_pointer_enemy_attack(main, world_position)
		return true
	var clicked_cell: Vector2i = main.world_cell_from_world_position(world_position)
	for cell in pointer_candidate_cells(main, clicked_cell):
		var target_id := interaction_target_id_for_cell(main, cell)
		if target_id.is_empty():
			continue
		if is_available_acquisition_target(main, target_id):
			return queue_pointer_acquisition(main, target_id, cell)
		if is_landmark_target(main, target_id):
			main._dungeon_debug("클릭 셀 대상: %s at %s" % [target_id, cell])
			return queue_pointer_landmark(main, target_id, cell)
		return main.submit_interaction_at_world_cell(cell)
	return false

func try_dungeon_interaction_from_input(main) -> bool:
	if main.player == null:
		return false
	var origin_cell: Vector2i = main.world_cell_from_world_position(main.player.global_position)
	var dungeon_target: Dictionary = dungeon_interaction_target_near_cell(main, origin_cell)
	if not dungeon_target.is_empty():
		main._dungeon_debug("E 대상 발견: %s" % dungeon_target)
		return main.submit_interaction_at_world_cell(dungeon_target.cell)
	var ore_target: Dictionary = dungeon_ore_target_near_cell(main, origin_cell, 1)
	if ore_target.is_empty():
		ore_target = acquisition_target_near_cell(main, origin_cell)
	if not ore_target.is_empty():
		main._dungeon_debug("E 광석 대상 발견: %s" % ore_target)
		return gather_dungeon_ore(main, String(ore_target.target_id), ore_target.cell)
	var enemy_cell: Vector2i = dungeon_enemy_cell_near(main, origin_cell)
	if enemy_cell != Vector2i(-1, -1):
		if is_dungeon_boss_cell(main, enemy_cell) and not main._dungeon_boss_combat_available():
			return main._begin_dungeon_boss_precombat_dialogue()
		activate_dungeon_enemy(main, enemy_cell)
		var direction := Vector2i(int(signf(float(enemy_cell.x - origin_cell.x))), int(signf(float(enemy_cell.y - origin_cell.y))))
		return main.submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, direction))
	var landmark: Dictionary = landmark_target_near_world_position(main, main.player.global_position, main._runtime_tile_size() * 2.5)
	if landmark.is_empty():
		landmark = large_house_target_near_world_position(main, main.player.global_position, main._runtime_tile_size() * 3.5)
	if landmark.is_empty():
		main._dungeon_debug("E 대상 없음: origin_cell=%s" % origin_cell)
		return false
	main._dungeon_debug("E 거리 대상 발견: %s" % landmark)
	return main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(landmark.target_id)}))

func pointer_enemy_clicked(main, world_position: Vector2) -> bool:
	var hit_radius := maxf(main._runtime_tile_size() * 0.5, 16.0)
	for enemy in main._combat_targets():
		if enemy.global_position.distance_to(world_position) <= hit_radius:
			main.combat_dummy = enemy
			return true
	if main._in_dungeon_map and not main._dungeon_boss_combat_available():
		var boss: Node2D = main._dungeon_boss_node()
		if boss != null and boss.global_position.distance_to(world_position) <= hit_radius:
			return main._begin_dungeon_boss_precombat_dialogue()
	return false

func try_landmark_interaction_from_input(main) -> bool:
	if main.player == null:
		return false
	var target: Dictionary = landmark_target_near_world_position(main, main.player.global_position, main._runtime_tile_size() * 2.5)
	if target.is_empty():
		return false
	return main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(target.get("target_id", ""))}))

func is_dungeon_enemy_cell(main, cell: Vector2i) -> bool:
	if not main._in_dungeon_map or main.world_data == null:
		return false
	for owner_id in ["dungeon_enemy_0", "dungeon_enemy_1", "dungeon_enemy_2", main.DUNGEON_BOSS_OWNER_ID]:
		if owner_id in main.world_data.get_occupants(cell):
			return true
	return false

func acquisition_target_near_cell(main, origin_cell: Vector2i) -> Dictionary:
	return main._spatial_resolver.acquisition_target_near_cell(main.world_data, main._in_dungeon_map, origin_cell, main._resolved_grid_direction(Vector2i.ZERO), Callable(main, "_is_available_acquisition_target"))

func dungeon_ore_target_near_cell(main, origin_cell: Vector2i, radius: int) -> Dictionary:
	return main._spatial_resolver.dungeon_ore_target_near_cell(main._in_dungeon_map, main._dungeon_resources, main.acquisition_service, origin_cell, radius)

func gather_dungeon_ore(main, target_id: String, cell: Vector2i) -> bool:
	if main.acquisition_service == null:
		main._dungeon_debug("광석 채집 실패: acquisition_service 없음")
		return true
	if main.acquisition_service.gatherable_for(target_id).is_empty():
		var register_result: Dictionary = main.acquisition_service.register_gatherable(target_id, target_id, cell)
		if not register_result.ok:
			main._dungeon_debug("광석 재등록 실패: %s" % register_result)
			return true
	var result: Dictionary = main.acquisition_service.gather(target_id)
	main._dungeon_debug("광석 채집 결과: target=%s ok=%s reason=%s" % [target_id, result.get("ok", false), result.get("reason", "")])
	if result.ok:
		main._advance_time_for_turn()
		main._queue_enemy_turn_after_player_action()
	return true

func dungeon_enemy_cell_near(main, origin_cell: Vector2i) -> Vector2i:
	for y in range(origin_cell.y - 1, origin_cell.y + 2):
		for x in range(origin_cell.x - 1, origin_cell.x + 2):
			var cell := Vector2i(x, y)
			if is_dungeon_enemy_cell(main, cell) and cells_are_adjacent(main, origin_cell, cell):
				return cell
	return Vector2i(-1, -1)

func activate_dungeon_enemy(main, cell: Vector2i) -> void:
	for enemy in main._combat_targets():
		if main._combat_target_cell(enemy) == cell:
			main.combat_dummy = enemy
			return

func is_dungeon_boss_cell(main, cell: Vector2i) -> bool:
	return main.DUNGEON_BOSS_OWNER_ID in main.world_data.get_occupants(cell) if main.world_data != null else false

func queue_pointer_acquisition(main, target_id: String, target_cell: Vector2i) -> bool:
	if main.player == null:
		return gather_dungeon_ore(main, target_id, target_cell) if main._is_dungeon_resource_target(target_id) else main.submit_interaction_at_world_cell(target_cell)
	var player_cell: Vector2i = main.world_cell_from_world_position(main.player.global_position)
	if cells_are_adjacent(main, player_cell, target_cell):
		return gather_dungeon_ore(main, target_id, target_cell) if main._is_dungeon_resource_target(target_id) else main.submit_interaction_at_world_cell(target_cell)
	var approach_cell: Vector2i = nearest_walkable_adjacent_cell(main, target_cell, player_cell)
	if approach_cell == target_cell:
		return false
	begin_pointer_move_route(main, player_cell, approach_cell, target_id, target_cell)
	return main._has_pointer_move_target

func queue_pointer_landmark(main, target_id: String, target_cell: Vector2i) -> bool:
	if main.player == null:
		return main.submit_interaction_at_world_cell(target_cell)
	var player_cell: Vector2i = main.world_cell_from_world_position(main.player.global_position)
	if player_can_interact_with_target(main, player_cell, target_id, target_cell):
		if is_landmark_target(main, target_id):
			return main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))
		return main.submit_interaction_at_world_cell(target_cell)
	var approach_cell: Vector2i = nearest_walkable_adjacent_cell_for_target(main, target_id, target_cell, player_cell)
	if approach_cell == target_cell:
		return false
	begin_pointer_move_route(main, player_cell, approach_cell, target_id, target_cell)
	return main._has_pointer_move_target

func begin_pointer_move_route(main, from_cell: Vector2i, destination_cell: Vector2i, target_id: String, target_cell: Vector2i) -> void:
	var result: Dictionary = main._pointer_route_controller.begin_route(
		main.world_data,
		from_cell,
		destination_cell,
		target_id,
		target_cell,
		target_footprint_cells(main, target_id, destination_cell),
		Callable(main, "world_position_for_cell_center")
	)
	if not result.ok:
		main._dungeon_debug("이동 경로 생성 실패: from=%s destination=%s target=%s" % [from_cell, destination_cell, target_id])
		return
	main._dungeon_debug("이동 경로 생성: %s -> %s, steps=%d, target=%s" % [from_cell, destination_cell, result.route.size(), target_id])
	main._movement_selector.submit_mobile_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))

func submit_pointer_enemy_attack(main, world_position: Vector2) -> bool:
	if main.player == null or not pointer_enemy_clicked(main, world_position):
		return false
	var dummy_position := Vector2(main.combat_dummy.global_position)
	var player_position := Vector2(main.player.global_position)
	var delta := dummy_position - player_position
	var direction := Vector2i(int(signf(delta.x)), int(signf(delta.y)))
	if direction == Vector2i.ZERO:
		direction = main._resolved_grid_direction(Vector2i.ZERO)
	clear_pointer_movement(main)
	return main.submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, direction))

func submit_pointer_movement(main, world_position: Vector2) -> bool:
	var target_cell: Vector2i = main.world_cell_from_world_position(world_position)
	if main.world_data == null or not main.world_data.is_walkable(target_cell):
		return false
	main._pointer_route_controller.submit_direct_movement(main.world_position_for_cell_center(target_cell))
	main._movement_selector.submit_mobile_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	return true

func submit_player_interaction(main, direction := Vector2i.ZERO) -> bool:
	var origin_cell := Vector2i.ZERO
	if main.player != null:
		origin_cell = main.world_cell_from_world_position(main.player.global_position)
	for cell in interaction_candidate_cells(main, origin_cell, direction):
		if main.submit_interaction_at_world_cell(cell):
			return true
	for y in range(origin_cell.y - 2, origin_cell.y + 3):
		for x in range(origin_cell.x - 2, origin_cell.x + 3):
			var nearby_cell := Vector2i(x, y)
			if abs(x - origin_cell.x) + abs(y - origin_cell.y) > 2:
				continue
			var nearby_target := interaction_target_id_for_cell(main, nearby_cell)
			if is_landmark_target(main, nearby_target) and main.submit_interaction_at_world_cell(nearby_cell):
				return true
	if main.player != null:
		var nearby_landmark: Dictionary = landmark_target_near_world_position(main, main.player.global_position, main._runtime_tile_size() * 2.5)
		if nearby_landmark.is_empty():
			nearby_landmark = large_house_target_near_world_position(main, main.player.global_position, main._runtime_tile_size() * 3.5)
		if not nearby_landmark.is_empty():
			return main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(nearby_landmark.target_id)}))
	main._play_sfx_event(SfxEventRouter.EVENT_INTERACT_FAIL, {"direction": direction}, "interact_empty")
	return false

func landmark_target_near_world_position(main, world_position: Vector2, max_distance := -1.0) -> Dictionary:
	return main._spatial_resolver.landmark_target_near_world_position(main.world_data, world_position, main._runtime_tile_size(), main._runtime_world_origin(), max_distance)

func large_house_target_near_world_position(main, world_position: Vector2, max_distance := -1.0) -> Dictionary:
	return main._spatial_resolver.large_house_target_near_world_position(main.generated_world, world_position, main._runtime_tile_size(), main._runtime_world_origin(), max_distance)

func configure_acquisition_for_generated_world(main) -> Dictionary:
	if not main.generated_world.get("ok", false) or typeof(main.generated_world.get("world_data")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_generated_world", "error": "Acquisition requires a generated world snapshot."}
	var biome_id := String(main.generated_world.get("biome_id", main.run_state.current_biome_id if main.run_state != null else ""))
	main._prepare_runtime_state_aliases_for_biome(biome_id)
	var saved_acquisitions: Dictionary = main.run_state.acquisitions.duplicate(true) if main.run_state != null else {}
	main.world_data = WorldData.from_dictionary(main.generated_world.world_data)
	var facility_restore_result: Dictionary = main._restore_placed_facilities_for_current_biome()
	if not facility_restore_result.ok:
		return facility_restore_result
	var repair_restore_result: Dictionary = {"ok": true}
	if main.repair_interaction_service != null:
		repair_restore_result = main.repair_interaction_service.apply_saved_target_states(main.world_data, main.run_state)
	if not repair_restore_result.ok:
		return repair_restore_result
	main.acquisition_service = AcquisitionService.new()
	var definitions: Array = main._acquisition_definitions().confirmed_generated_resource_definitions(main.generated_world.get("resource_nodes", []))
	definitions.append_array(main._acquisition_definitions().terrain_tree_gatherable_definitions())
	definitions.append_array(main._acquisition_definitions().mountain_mineral_gatherable_definitions())
	var configured: Dictionary = main.acquisition_service.configure(main.inventory, main.world_data, definitions, generated_drop_definitions(main))
	if not configured.ok:
		return configured
	var definition_ids := {}
	for definition in definitions:
		definition_ids[String(definition.id)] = true
	for node in main.generated_world.get("resource_nodes", []):
		var resource_id := String(node.get("resource_id", ""))
		if not definition_ids.has(resource_id):
			continue
		var registered: Dictionary = main.acquisition_service.register_gatherable(
			String(node.get("id", "")),
			resource_id,
			main._vector_from_dictionary(node.get("position", {}))
		)
		if not registered.ok:
			return registered
	var terrain_tree_result: Dictionary = main._acquisition_definitions().register_terrain_tree_gatherables(definition_ids, main.acquisition_service)
	if not terrain_tree_result.ok:
		return terrain_tree_result
	var mountain_mineral_result: Dictionary = main._acquisition_definitions().register_mountain_mineral_gatherables(definition_ids, main.acquisition_service)
	if not mountain_mineral_result.ok:
		return mountain_mineral_result
	if not saved_acquisitions.is_empty():
		var loaded: Dictionary = main.acquisition_service.load_snapshot(saved_acquisitions)
		if not loaded.ok:
			return loaded
		terrain_tree_result = main._acquisition_definitions().register_terrain_tree_gatherables(definition_ids, main.acquisition_service)
		if not terrain_tree_result.ok:
			return terrain_tree_result
	main.generated_world["world_data"] = main.world_data.to_dictionary()
	var restored_renderer_input: Dictionary = WorldRendererProjection.new().project(main.generated_world["world_data"])
	main.generated_world["renderer_input"] = restored_renderer_input
	main.acquisition_service.changed.connect(main._on_acquisition_changed)
	main.acquisition_service.acquisition_completed.connect(main._on_acquisition_completed)
	main._on_acquisition_changed(main.acquisition_service.to_snapshot())
	return {"ok": true}

func is_repair_interaction_target(main, target_id: String) -> bool:
	return main.repair_interaction_service != null and main.repair_interaction_service.has_target(target_id)

func handle_repair_interaction_command(main, command: GameCommand) -> Dictionary:
	if main.repair_interaction_service == null:
		return {"ok": false, "reason": "missing_repair_interaction_service"}
	var result: Dictionary = main.repair_interaction_service.handle_command(
		String(command.payload.get("action_id", "")),
		String(command.payload.get("target_id", "")),
		main.inventory,
		main.run_state,
		main.world_data,
		String(main.generated_world.get("biome_id", main.run_state.current_biome_id if main.run_state != null else ""))
	)
	if not result.ok:
		return result
	main._store_current_biome_runtime_aliases()
	main.save_current_run()
	main._sync_runtime_world_render()
	main._configure_game_hud()
	return result

func generated_drop_definitions(main) -> Array:
	return main._acquisition_definitions().generated_drop_definitions()

func connect_acquisition_combat_source(main, source) -> Dictionary:
	if source == null or not source.has_signal("drop_requested"):
		return {"ok": false, "reason": "invalid_drop_source", "error": "Combat source must expose drop_requested."}
	var callback := Callable(main, "_on_combat_drop_requested").bind(source)
	if not source.is_connected("drop_requested", callback):
		source.connect("drop_requested", callback)
	return {"ok": true}

func acquisition_changed(main, snapshot: Dictionary) -> void:
	if main.run_state != null and not main._in_dungeon_map:
		main.run_state.acquisitions = snapshot.duplicate(true)
		main._store_current_biome_runtime_aliases()
	main._sync_runtime_world_render()

func acquisition_completed(main, result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not result.get("position", null) is Dictionary:
		return
	main._play_sfx_event(SfxEventRouter.event_id_for_acquisition(result), result, String(result.get("pickup_id", result.get("node_id", result.get("item_id", "acquisition")))))
	var item_id := String(result.get("item_id", ""))
	if item_id.is_empty():
		return
	var source_id := String(result.get("source_id", result.get("node_id", result.get("id", result.get("target_id", "")))))
	if main._is_mining_target(source_id) and main.world_data != null:
		main.world_data.release_footprint(source_id)
	var item_name := item_id
	if main.catalog != null and main.catalog.has_method("find_by_id"):
		var definition: Dictionary = main.catalog.find_by_id("items", item_id)
		item_name = String(definition.get("name", item_id))
	var effect := AcquisitionEffect.new()
	effect.name = "AcquisitionEffect"
	effect.configure(
		String(result.get("kind", AcquisitionService.PICKUP_KIND)),
		item_name,
		int(result.get("quantity", 0)),
		main.world_position_for_cell_center(main._vector_from_dictionary(result.position))
	)
	main.add_child(effect)
	if main.game_hud != null:
		main.game_hud.show_status_event({
			"type": "item_acquired",
			"ok": true,
			"item_id": item_id,
			"quantity": int(result.get("quantity", 0)),
			"event_id": String(result.get("pickup_id", result.get("node_id", result.get("id", result.get("target_id", "")))))
		})

func combat_drop_requested(main, event: Dictionary, source = null) -> void:
	if main.acquisition_service == null:
		return
	var normalized := event.duplicate(true)
	var drop_source = source if source is Node2D and is_instance_valid(source) else main.combat_dummy
	if not normalized.has("position") and drop_source is Node2D and is_instance_valid(drop_source):
		var drop_cell: Vector2i = main.world_cell_from_world_position(drop_source.global_position)
		normalized.position = {"x": drop_cell.x, "y": drop_cell.y}
	var evaluation_context := {
		"run_seed": int(main.run_state.seed) if main.run_state != null else main.FRESH_RUN_SEED,
		"time_phase": String(main.time_state.phase) if main.time_state != null else ""
	}
	var result: Dictionary = main.acquisition_service.process_drop_request(normalized, Vector2i.ZERO, evaluation_context)
	if not result.ok:
		push_error(result.error)

func combat_dummy_defeated(main, _event: Dictionary) -> void:
	if main.combat_dummy == null:
		return
	main.combat_dummy.visible = false
	main.combat_dummy.automatic_attacks = false
	main.combat_dummy.collision_layer = 0
	main.combat_dummy.collision_mask = 0
	main._save_progress_after_turn()

func snapshot_overworld_enemy_state(main) -> Dictionary:
	if main.combat_dummy == null or not is_instance_valid(main.combat_dummy):
		return {}
	var cell: Vector2i = main._combat_target_cell(main.combat_dummy)
	return {
		"cell": {"x": cell.x, "y": cell.y},
		"monster_id": String(main.combat_dummy.monster_id),
		"hp": int(main.combat_dummy.current_hp()) if main.combat_dummy.has_method("current_hp") else 0,
		"visible": main.combat_dummy.visible,
		"automatic_attacks": main.combat_dummy.automatic_attacks,
		"collision_layer": main.combat_dummy.collision_layer,
		"collision_mask": main.combat_dummy.collision_mask
	}

func restore_overworld_enemy_state(main) -> void:
	if main._in_dungeon_map or main.combat_dummy == null or not is_instance_valid(main.combat_dummy) or main.run_state == null:
		return
	var saved: Dictionary = main.run_state.overworld_enemy_state
	if saved.is_empty():
		return
	var saved_cell: Dictionary = saved.get("cell", {})
	if not saved_cell.is_empty():
		var cell: Vector2i = main._vector_from_dictionary(saved_cell)
		if main.world_data != null and main.world_data.contains(cell):
			main.combat_dummy.global_position = main.world_position_for_cell_center(cell)
	if main.combat_dummy.combatant != null:
		main.combat_dummy.combatant.hp = clampi(int(saved.get("hp", main.combat_dummy.combatant.hp)), 0, main.combat_dummy.combatant.hp_max)
	main.combat_dummy.visible = bool(saved.get("visible", true))
	main.combat_dummy.automatic_attacks = bool(saved.get("automatic_attacks", true))
	main.combat_dummy.collision_layer = int(saved.get("collision_layer", 2))
	main.combat_dummy.collision_mask = int(saved.get("collision_mask", 1))

func pointer_movement_command(main) -> GameCommand:
	if main.player == null:
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	return main._pointer_route_controller.movement_command(
		main.player.global_position,
		main.POINTER_MOVE_STOP_DISTANCE_PIXELS,
		Callable(main, "world_position_for_cell_center"),
		Callable(main, "_complete_pending_pointer_interaction_from_pointer_route")
	)

func clear_pointer_movement(main) -> void:
	main._pointer_route_controller.clear()

func complete_pending_pointer_interaction_from_pointer_route(main, target_id: String, target_cell: Vector2i) -> void:
	if target_id.is_empty() or (not is_available_acquisition_target(main, target_id) and not is_landmark_target(main, target_id)):
		main._dungeon_debug("이동 완료 후 대상 무효: target=%s" % target_id)
		return
	if main.player == null or not player_can_interact_with_target(main, main.world_cell_from_world_position(main.player.global_position), target_id, target_cell):
		main._dungeon_debug("이동 완료했지만 상호작용 거리 불충족: player_cell=%s target=%s target_cell=%s" % [main.world_cell_from_world_position(main.player.global_position) if main.player != null else "nil", target_id, target_cell])
		return
	main._dungeon_debug("입구 도착, 상호작용 실행: target=%s cell=%s" % [target_id, target_cell])
	if main._is_dungeon_resource_target(target_id):
		gather_dungeon_ore(main, target_id, target_cell)
	elif is_landmark_target(main, target_id):
		main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))
	else:
		main.submit_interaction_at_world_cell(target_cell)

func cells_are_adjacent(main, first: Vector2i, second: Vector2i) -> bool:
	return main._spatial_resolver.cells_are_adjacent(first, second)

func nearest_walkable_adjacent_cell(main, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	return main._spatial_resolver.nearest_walkable_adjacent_cell(main.world_data, target_cell, player_cell)

func nearest_walkable_adjacent_cell_for_target(main, target_id: String, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	return main._spatial_resolver.nearest_walkable_adjacent_cell_for_target(main.world_data, target_id, target_cell, player_cell)

func interaction_candidate_cells(main, origin_cell: Vector2i, direction := Vector2i.ZERO) -> Array:
	return main._spatial_resolver.interaction_candidate_cells(origin_cell, main._resolved_grid_direction(direction))

func pointer_candidate_cells(main, clicked_cell: Vector2i) -> Array:
	return main._spatial_resolver.pointer_candidate_cells(clicked_cell)

func interaction_target_id_for_cell(main, cell: Vector2i) -> String:
	return main._spatial_resolver.interaction_target_id_for_cell(main.world_data, main._in_dungeon_map, cell, Callable(main, "_is_available_acquisition_target"))

func player_can_interact_with_target(main, player_cell: Vector2i, target_id: String, target_cell: Vector2i) -> bool:
	return main._spatial_resolver.player_can_interact_with_target(main.world_data, main._in_dungeon_map, player_cell, target_id, target_cell)

func target_footprint_cells(main, target_id: String, fallback_cell: Vector2i) -> Array:
	return main._spatial_resolver.target_footprint_cells(main.world_data, target_id, fallback_cell)

func dungeon_interaction_target_near_cell(main, origin_cell: Vector2i) -> Dictionary:
	return main._spatial_resolver.dungeon_interaction_target_near_cell(main.world_data, main._in_dungeon_map, origin_cell, main._resolved_grid_direction(Vector2i.ZERO))

func is_landmark_target(main, target_id: String) -> bool:
	return main._spatial_resolver.is_landmark_target(main._in_dungeon_map, target_id)

func is_core_dungeon_target(main, target_id: String) -> bool:
	return main._spatial_resolver.is_core_dungeon_target(target_id)

func is_available_acquisition_target(main, target_id: String) -> bool:
	if main.acquisition_service == null or target_id.is_empty():
		return false
	var gatherable: Dictionary = main.acquisition_service.gatherable_for(target_id)
	if not gatherable.is_empty():
		return not bool(gatherable.get("depleted", false))
	return not main.acquisition_service.pickup_for(target_id).is_empty()
