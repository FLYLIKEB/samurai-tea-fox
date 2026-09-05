extends RefCounted
class_name DungeonSceneCoordinator

const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func ensure_current_dungeon_entered(main) -> Dictionary:
	var projection: Dictionary = main.dungeon_runtime.to_projection() if main.dungeon_runtime != null else {}
	var lifecycle := String(projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE))
	if lifecycle == DungeonInstanceState.STATE_ACTIVE:
		return {"ok": true, "state": "already_active"}
	if lifecycle not in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED]:
		return {"ok": false, "reason": "dungeon_lifecycle_busy", "error": "Dungeon lifecycle is not ready for a new entry."}
	var definition: Dictionary = main.dungeon_definition_resolver.dungeon_entry_definition(main.catalog, main.narrative_runtime, main.run_state)
	if definition.is_empty():
		main._dungeon_debug("현재 바이옴 던전 정의 없음: biome=%s" % (main.run_state.current_biome_id if main.run_state != null else "nil"))
		return {"ok": false, "reason": "missing_current_dungeon", "error": "No dungeon definition exists for the current biome."}
	var biome_id := String(main.run_state.current_biome_id)
	var layout_result: Dictionary = main.dungeon_layout_builder.build(definition, func(item_id: String, action: String) -> String:
		return main._acquisition_definitions().node_kind_for_resource_action(item_id, action))
	var layout: WorldData = layout_result.layout
	main._dungeon_resources = layout_result.resources
	var enter_result: Dictionary = main.dungeon_runtime.enter_dungeon(
		"%s_%d" % [String(definition.id), main.run_state.seed],
		definition,
		layout,
		{"biome_id": biome_id, "world_seed": main.run_state.seed}
	)
	if enter_result.ok:
		main._enter_dungeon_map(layout, definition, true)
	else:
		main._dungeon_debug("main.dungeon_runtime.enter_dungeon 실패: %s" % enter_result)
	return enter_result

func is_dungeon_resource_target(main, target_id: String) -> bool:
	return target_id.begins_with("dungeon_iron_ore_") or target_id.begins_with("dungeon_stone_")

func is_mining_target(main, target_id: String) -> bool:
	return main._is_dungeon_resource_target(target_id) or target_id.begins_with("terrain_mountain_mineral_")

func dungeon_runtime_is_active(main) -> bool:
	return main.dungeon_runtime != null and String(main.dungeon_runtime.to_projection().get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) == DungeonInstanceState.STATE_ACTIVE

func dungeon_boss_combat_available(main) -> bool:
	if main.dungeon_runtime == null:
		return true
	return main.dungeon_runtime.boss_combat_available()

func dungeon_boss_action_locked(main, command) -> bool:
	if not main._in_dungeon_map or main._dungeon_boss_combat_available():
		return false
	if command.type == GameCommand.Type.NARRATIVE_SELECT_OPTION:
		return false
	if command.type == GameCommand.Type.INTERACT:
		var target_id := String(command.payload.get("target_id", ""))
		return target_id == main.DUNGEON_BOSS_OWNER_ID
	return [GameCommand.Type.ATTACK, GameCommand.Type.DODGE, GameCommand.Type.CAST_ABILITY, GameCommand.Type.COMPLETE_DUNGEON].has(command.type)

func dungeon_boss_node(main) -> Node2D:
	for enemy in main._dungeon_enemy_nodes:
		if is_instance_valid(enemy) and enemy.name == main.DUNGEON_BOSS_OWNER_ID:
			return enemy
	return null

func dungeon_boss_cell(main) -> Vector2i:
	var boss: Node2D = main._dungeon_boss_node()
	if boss == null:
		return Vector2i(-1, -1)
	return main.world_cell_from_world_position(boss.global_position)

func dungeon_precombat_dialogue_is_active(main, event_id: String) -> bool:
	if main.dungeon_runtime == null:
		return false
	var projection: Dictionary = main.dungeon_runtime.to_projection()
	return String(projection.get("boss_flow_state", "")) == DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE \
		and String(projection.get("pre_boss_dialogue_event_id", "")) == event_id

func restore_dungeon_boss_precombat_dialogue_if_needed(main) -> void:
	if main.dungeon_runtime == null or main.narrative_runtime == null or main.run_state == null:
		return
	var projection: Dictionary = main.dungeon_runtime.to_projection()
	if String(projection.get("boss_flow_state", "")) != DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE:
		return
	var event_id := String(projection.get("pre_boss_dialogue_event_id", ""))
	if event_id.is_empty():
		return
	var model_result: Dictionary = main.narrative_runtime.read_model_for_event(event_id, main.run_state, main._current_meta_state_snapshot())
	if not model_result.ok:
		main._dungeon_debug("저장된 보스 전 대화 복원 실패: %s" % model_result)
		return
	main._active_narrative_event_id = String(model_result.read_model.event_id)
	main._active_narrative_node_id = String(model_result.read_model.node_id)
	if main.game_hud != null and main.game_hud.has_method("show_narrative_dialogue"):
		main.game_hud.show_narrative_dialogue(model_result.read_model)

func begin_dungeon_boss_precombat_dialogue(main) -> bool:
	if main.dungeon_runtime == null or main.narrative_runtime == null or main.run_state == null:
		return false
	if not main._dungeon_regular_combat_targets().is_empty():
		if main.game_hud != null and main.game_hud.has_method("show_command_feedback"):
			main.game_hud.show_command_feedback("남은 적을 먼저 정리해야 합니다")
		return false
	var projection: Dictionary = main.dungeon_runtime.to_projection()
	if String(projection.get("boss_flow_state", DungeonInstanceState.BOSS_FLOW_NONE)) == DungeonInstanceState.BOSS_FLOW_NONE:
		var definition: Dictionary = main._current_biome_dungeon_definition()
		var biome_id := String(main.run_state.current_biome_id)
		var boss_definition: Dictionary = main._current_biome_boss_definition(biome_id, String(definition.get("id", "")))
		var prepare_result: Dictionary = main.dungeon_runtime.prepare_boss_encounter({
			"boss_id": String(boss_definition.get("id", "")),
			"pre_boss_dialogue_event_id": main._pre_boss_dialogue_event_id_for(definition, boss_definition)
		})
		if not prepare_result.ok:
			main._dungeon_debug("보스 전 대화 준비 실패: %s" % prepare_result)
			if main.game_hud != null and main.game_hud.has_method("show_command_feedback"):
				main.game_hud.show_command_feedback("보스 대화 데이터가 아직 연결되지 않았습니다")
			return false
	var begin_result: Dictionary = main.dungeon_runtime.begin_boss_precombat_dialogue()
	if not begin_result.ok:
		main._dungeon_debug("보스 전 대화 시작 실패: %s" % begin_result)
		return false
	var event_id := String(begin_result.get("event_id", ""))
	if event_id.is_empty():
		return false
	var model_result: Dictionary = main.narrative_runtime.read_model_for_event(event_id, main.run_state, main._current_meta_state_snapshot())
	if not model_result.ok:
		main._dungeon_debug("보스 전 대화 이벤트 로드 실패: %s" % model_result)
		if main.game_hud != null and main.game_hud.has_method("show_command_feedback"):
			main.game_hud.show_command_feedback("보스 대화 이벤트를 불러올 수 없습니다")
		return false
	main._active_narrative_event_id = String(model_result.read_model.event_id)
	main._active_narrative_node_id = String(model_result.read_model.node_id)
	if main.game_hud != null and main.game_hud.has_method("show_narrative_dialogue"):
		main.game_hud.show_narrative_dialogue(model_result.read_model)
	main.save_current_run()
	return true

func dungeon_debug(main, message: String) -> void:
	if main.DUNGEON_DEBUG_LOGGING:
		print("[DungeonDebug] %s" % message)

func enter_dungeon_map(main, layout: WorldData, definition: Dictionary, is_new_entry := false) -> void:
	if main._in_dungeon_map:
		return
	main._enemy_turn_queued = false
	main._overworld_generated_world = main.generated_world.duplicate(true)
	main._overworld_world_data_snapshot = main.world_data.to_dictionary() if main.world_data != null else {}
	main._overworld_player_cell = main._player_world_cell()
	main._overworld_combat_dummy_cell = main._combat_target_cell(main.combat_dummy) if main.combat_dummy != null else Vector2i.ZERO
	main._overworld_combat_dummy = main.combat_dummy
	main._overworld_combat_dummy_state = {}
	if main._overworld_combat_dummy != null:
		if main._overworld_combat_dummy.has_method("suspend_for_world_transition"):
			main._overworld_combat_dummy_state = main._overworld_combat_dummy.suspend_for_world_transition()
		else:
			main._overworld_combat_dummy_state = {"visible": main._overworld_combat_dummy.visible}
			main._overworld_combat_dummy.visible = false
	var dungeon_data := layout.to_dictionary()
	var dungeon_projection := WorldRendererProjection.new().project(dungeon_data)
	main.generated_world = {
		"ok": true,
		"biome_id": String(definition.get("biome_id", main.run_state.current_biome_id)),
		"biome_generation_rule_id": String(definition.get("id", "dungeon")),
		"world_data": dungeon_data,
		"renderer_input": dungeon_projection,
		"required_landmarks": dungeon_projection.get("required_landmarks", []),
		"resource_nodes": main._dungeon_resources
	}
	main.world_data = layout
	main._in_dungeon_map = true
	if main.acquisition_service != null:
		main.acquisition_service = AcquisitionService.new()
		var dungeon_definitions := []
		for node in main._dungeon_resources:
			var item_id := String(node.get("resource_id", "iron_ore"))
			var node_kind := String(node.get("node_kind", ""))
			if node_kind.is_empty():
				node_kind = main._acquisition_definitions().node_kind_for_resource_action(item_id, "mine")
			dungeon_definitions.append({"id": String(node.id), "item_id": item_id, "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT, "material_tag": String(node.get("material_tag", "")), "required_tool_item_id": main._acquisition_definitions().required_tool_for_resource_interaction(item_id, node_kind)})
		var dungeon_acquisition_result: Dictionary = main.acquisition_service.configure(main.inventory, main.world_data, dungeon_definitions, main._generated_drop_definitions())
		if not dungeon_acquisition_result.ok:
			main._dungeon_debug("광석 상호작용 설정 실패: %s" % dungeon_acquisition_result)
		else:
			main.acquisition_service.changed.connect(Callable(main, "_on_acquisition_changed"))
			main.acquisition_service.acquisition_completed.connect(Callable(main, "_on_acquisition_completed"))
			for node in main._dungeon_resources:
				var register_result: Dictionary = main.acquisition_service.register_gatherable(String(node.id), String(node.id), main._vector_from_dictionary(node.position))
				if not register_result.ok:
					main._dungeon_debug("광석 노드 등록 실패: %s" % register_result)
			var saved_dungeon_acquisitions: Dictionary = main.run_state.dungeon_runtime_state.get("acquisitions", {}) if main.run_state != null else {}
			if not saved_dungeon_acquisitions.is_empty():
				var normalized_acquisitions := saved_dungeon_acquisitions.duplicate(true)
				var normalized_gatherables: Array = []
				for saved_node in normalized_acquisitions.get("gatherables", []):
					if typeof(saved_node) != TYPE_DICTIONARY:
						continue
					var node_snapshot: Dictionary = saved_node.duplicate(true)
					var node_id := String(node_snapshot.get("node_id", ""))
					if main._is_dungeon_resource_target(node_id):
						# Older saves stored the item id as definition_id; dungeon
						# definitions are keyed by their stable node id.
						node_snapshot["definition_id"] = node_id
					normalized_gatherables.append(node_snapshot)
				normalized_acquisitions["gatherables"] = normalized_gatherables
				var acquisition_restore: Dictionary = main.acquisition_service.load_snapshot(normalized_acquisitions)
				if not acquisition_restore.ok:
					main._dungeon_debug("던전 채집 상태 복원 실패: %s" % acquisition_restore)
	main._render_generated_world(main.generated_world)
	var spawn_cell := Vector2i(1, 1)
	var saved_player_cell: Dictionary = main.run_state.dungeon_runtime_state.get("player_cell", {}) if main.run_state != null else {}
	var saved_cell: Vector2i = main._vector_from_dictionary(saved_player_cell)
	if not saved_player_cell.is_empty() and main.world_data.contains(saved_cell) and main.world_data.is_walkable(saved_cell):
		spawn_cell = saved_cell
	main.player.global_position = main.world_position_for_cell_center(spawn_cell)
	main._spawn_dungeon_combatants(is_new_entry)
	main._configure_game_hud()
	main._restore_dungeon_boss_precombat_dialogue_if_needed()
	main._save_progress_after_turn()

func spawn_dungeon_combatants(main, allow_default_spawn := false) -> void:
	main._clear_dungeon_combatants(false)
	if main._overworld_combat_dummy == null or not main._overworld_combat_dummy.has_method("configure_combat"):
		return
	var regular_monster_ids: Array = main._dungeon_regular_monster_ids(3)
	var specs := [
		{"id": "dungeon_enemy_0", "cell": Vector2i(7, 2), "monster_id": regular_monster_ids[0], "sprite_id": main._monster_sprite_asset_id(String(regular_monster_ids[0]))},
		{"id": "dungeon_enemy_1", "cell": Vector2i(9, 5), "monster_id": regular_monster_ids[1], "sprite_id": main._monster_sprite_asset_id(String(regular_monster_ids[1]))},
		{"id": "dungeon_enemy_2", "cell": Vector2i(5, 7), "monster_id": regular_monster_ids[2], "sprite_id": main._monster_sprite_asset_id(String(regular_monster_ids[2]))},
		{"id": main.DUNGEON_BOSS_OWNER_ID, "cell": Vector2i(10, 7), "monster_id": "road_bandit", "sprite_id": "asset_assets_sprites_characters_bosses_chr_6_yokai_tea_master_yokai_tea_master_front_32x32_png", "boss": true}
	]
	var saved_states: Dictionary = main.run_state.dungeon_runtime_state.get("enemy_states", {}) if main.run_state != null else {}
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var saved_state: Dictionary = saved_states.get(String(spec.id), {})
		if not allow_default_spawn and not saved_states.has(String(spec.id)):
			# A resumed save is authoritative. Do not recreate enemies that were
			# absent from its state, including legacy saves with no enemy snapshot.
			main.world_data.release_footprint(String(spec.id))
			continue
		if not saved_state.is_empty() and not bool(saved_state.get("visible", true)):
			continue
		var enemy = main._overworld_combat_dummy.duplicate()
		main.add_child(enemy)
		enemy.name = String(spec.id)
		enemy.monster_id = String(spec.monster_id)
		enemy.sprite_asset_id = String(spec.sprite_id)
		enemy.collision_layer = 2
		enemy.collision_mask = 1
		enemy.visible = true
		var enemy_cell: Vector2i = main._vector_from_dictionary(saved_state.get("cell", {})) if not saved_state.is_empty() else spec.cell
		enemy.global_position = main.world_position_for_cell_center(enemy_cell)
		var configured: Dictionary = enemy.configure_combat(main.catalog, main.player, main.player.combat_config)
		if configured.ok and bool(spec.get("boss", false)):
			enemy.combatant.hp_max *= 3
			enemy.combatant.hp = enemy.combatant.hp_max
			enemy.combatant.attack *= 2
		if configured.ok and not saved_state.is_empty():
			enemy.combatant.hp = clampi(int(saved_state.get("hp", enemy.combatant.hp)), 0, enemy.combatant.hp_max)
		if enemy.has_method("_apply_sprite"):
			enemy._apply_sprite()
		if enemy.has_signal("defeat_event"):
			var defeat_callback := Callable(main, "_on_dungeon_enemy_defeated").bind(enemy, String(spec.id))
			if not enemy.is_connected("defeat_event", defeat_callback):
				enemy.connect("defeat_event", defeat_callback)
		main._connect_combat_sfx_source(enemy)
		main._connect_acquisition_combat_source(enemy)
		if enemy.has_method("configure_grid_navigation"):
			enemy.configure_grid_navigation(main.world_data, main._runtime_world_origin(), main._runtime_tile_size())
		main._dungeon_enemy_nodes.append(enemy)
		main._dungeon_debug("실제 던전 몬스터 생성: id=%s ok=%s" % [spec.id, configured.get("ok", false)])
	main.combat_dummy = main._dungeon_enemy_nodes.back() if not main._dungeon_enemy_nodes.is_empty() else main._overworld_combat_dummy

func dungeon_regular_monster_ids(main, count: int) -> Array:
	return main.dungeon_combatant_session.regular_monster_ids(count, main.generated_world, main.catalog)

func monster_sprite_asset_id(main, monster_id: String) -> String:
	var sprite_id: String = main._content_image_asset_id("monsters", monster_id)
	if not sprite_id.is_empty():
		return sprite_id
	return "monster_%s_front_idle" % monster_id

func clear_dungeon_combatants(main, restore_overworld := true) -> void:
	var result: Dictionary = main.dungeon_combatant_session.clear_dungeon_combatants(restore_overworld)
	if restore_overworld and result.combat_target != null:
		main.combat_dummy = result.combat_target

func on_dungeon_enemy_defeated(main, _event: Dictionary, enemy, owner_id: String) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.visible = false
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	if main.world_data != null:
		main.world_data.release_footprint(owner_id)
	var remaining: int = main._combat_targets().size()
	main._dungeon_debug("던전 몬스터 처치: %s, remaining=%d" % [owner_id, remaining])
	var defeated_monster_id := String(_event.get("monster_id", _event.get("definition_id", "")))
	if defeated_monster_id.is_empty():
		defeated_monster_id = String(enemy.get("monster_id"))
	if defeated_monster_id.is_empty():
		var enemy_combatant = enemy.get("combatant")
		if enemy_combatant != null:
			defeated_monster_id = String(enemy_combatant.get("definition_id"))
	var dungeon_cleared := false
	if owner_id == main.DUNGEON_BOSS_OWNER_ID and main.dungeon_runtime != null:
		if not main._dungeon_regular_combat_targets().is_empty():
			main._dungeon_debug("일반 몬스터가 남아 있어 보스 클리어 보류")
			return
		var projection: Dictionary = main.dungeon_runtime.to_projection()
		var clear_result: Dictionary = main.dungeon_runtime.complete_boss_encounter({
			"event_type": "boss_encounter_resolved",
			"boss_id": String(projection.get("boss_id", "")),
			"encounter_id": String(projection.get("boss_encounter_id", "")),
			"dungeon_id": String(projection.get("dungeon_id", "")),
			"biome_id": String(projection.get("biome_id", "")),
			"resolution_type": "combat",
			"choice_key": "dungeon_boss_defeated",
			"run_flag": "dungeon_boss_defeated",
			"reward_item_ids": [],
			"progression_unlock_ids": [String(main.run_state.current_biome_id)]
		})
		main._dungeon_debug("던전 보스 클리어 기록: ok=%s reason=%s" % [clear_result.get("ok", false), clear_result.get("reason", "")])
		if not clear_result.ok:
			return
		dungeon_cleared = true
	elif remaining == 0 and main.dungeon_runtime != null and main._dungeon_boss_combat_available():
		var clear_result: Dictionary = main.dungeon_runtime.complete_dungeon({
			"objective_complete": true,
			"resolution_type": "combat",
			"choice_key": "dungeon_boss_defeated",
			"run_flag": "dungeon_boss_defeated",
			"reward_item_ids": [],
			"progression_unlock_ids": [String(main.run_state.current_biome_id)]
		})
		main._dungeon_debug("던전 클리어 기록: ok=%s reason=%s" % [clear_result.get("ok", false), clear_result.get("reason", "")])
		if not clear_result.ok:
			return
		dungeon_cleared = true
	if main.game_hud != null:
		if not defeated_monster_id.is_empty():
			main.game_hud.show_status_event({
				"type": "enemy_defeated",
				"ok": true,
				"monster_id": defeated_monster_id,
				"event_id": owner_id
			})
		else:
			main.game_hud.show_status_toast("적을 처치했다!")
		if dungeon_cleared:
			main.game_hud.show_status_event({"type": "dungeon_floor_changed", "ok": true, "event_id": "dungeon_cleared"})
			main.game_hud.show_status_toast("던전 클리어! 유적으로 돌아가세요.")
	main._save_progress_after_turn()

func restore_dungeon_map_from_runtime(main) -> void:
	var projection: Dictionary = main.dungeon_runtime.to_projection()
	var saved_world: Dictionary = projection.get("world_data", {})
	if saved_world.is_empty():
		return
	var definition: Dictionary = main._current_biome_dungeon_definition()
	if definition.is_empty():
		return
	definition["biome_id"] = String(main.run_state.current_biome_id)
	main._enter_dungeon_map(WorldData.from_dictionary(saved_world), definition)

func return_from_dungeon_map(main) -> void:
	if not main._in_dungeon_map:
		return
	main._enemy_turn_queued = false
	main.generated_world = main._overworld_generated_world
	main.world_data = WorldData.from_dictionary(main._overworld_world_data_snapshot)
	main._in_dungeon_map = false
	main._clear_dungeon_combatants()
	main._configure_acquisition_for_generated_world()
	main._render_generated_world(main.generated_world)
	main.player.global_position = main.world_position_for_cell_center(main._overworld_player_cell)
	if main.combat_dummy != null:
		main.combat_dummy.global_position = main.world_position_for_cell_center(main._overworld_combat_dummy_cell)
		if main.combat_dummy.has_method("configure_grid_navigation"):
			main.combat_dummy.configure_grid_navigation(main.world_data, main._runtime_world_origin(), main._runtime_tile_size())
	main._configure_game_hud()

func ensure_saved_world_has_teleport_landmark(main) -> bool:
	if main._in_dungeon_map or main.world_data == null:
		return false
	for landmark in main.world_data.get_required_landmarks():
		if String(landmark.get("kind", landmark.get("type", ""))) == WorldData.LANDMARK_TELEPORT_ZONE:
			return false
	var width: int = int(main.world_data.width)
	var height: int = int(main.world_data.height)
	var center_x: int = maxi(1, width / 2)
	var center_y: int = maxi(1, height / 2)
	var candidate: Vector2i = Vector2i(center_x, center_y)
	for radius in range(maxi(width, height)):
		for offset in [Vector2i.ZERO, Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
			var cell: Vector2i = candidate + offset
			if not main.world_data.contains(cell) or not main.world_data.is_walkable(cell):
				continue
			var id := "%s_0" % WorldData.LANDMARK_TELEPORT_ZONE
			var metadata := {"teleport_biome_id": String(main.run_state.current_biome_id), "migrated": true}
			main.world_data.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, id, cell, metadata)
			main.generated_world["world_data"] = main.world_data.to_dictionary()
			main.generated_world["landmarks"] = main.world_data.get_required_landmarks()
			var projection: Dictionary = main.biome_progression_state.to_projection() if main.biome_progression_state != null else {}
			main.generated_world["renderer_input"] = WorldRendererProjection.new().project(main.generated_world["world_data"], projection)
			main._dungeon_debug("기존 세이브에 텔레포트 추가: id=%s cell=%s" % [id, cell])
			return true
	return false

func current_biome_dungeon_definition(main) -> Dictionary:
	return main.dungeon_definition_resolver.current_biome_dungeon_definition(main.catalog, main.run_state)

func current_biome_boss_definition(main, biome_id: String, dungeon_id: String) -> Dictionary:
	return main.dungeon_definition_resolver.current_biome_boss_definition(main.catalog, biome_id, dungeon_id)

func pre_boss_dialogue_event_id_for(main, dungeon_definition: Dictionary, boss_definition := {}) -> String:
	return main.dungeon_definition_resolver.pre_boss_dialogue_event_id_for(main.catalog, main.narrative_runtime, dungeon_definition, boss_definition)

func sync_runtime_save_state(main) -> void:
	if not main._in_dungeon_map or main.dungeon_runtime == null or main.world_data == null or main.player == null:
		return
	var enemy_states := {}
	for enemy in main._dungeon_enemy_nodes:
		if not is_instance_valid(enemy):
			continue
		var cell := combat_target_cell(main, enemy)
		var owner_id := String(enemy.name)
		enemy_states[owner_id] = {
			"cell": {"x": cell.x, "y": cell.y},
			"hp": int(enemy.current_hp()) if enemy.has_method("current_hp") else 0,
			"visible": enemy.visible
		}
		sync_enemy_reservation(main, owner_id, cell, enemy.visible)
	var acquisitions: Dictionary = main.acquisition_service.to_snapshot() if main.acquisition_service != null else {}
	main.dungeon_runtime.sync_active_world_state(main.world_data, main._player_world_cell(), enemy_states, acquisitions)

func sync_enemy_reservation(main, owner_id: String, cell: Vector2i, active: bool) -> void:
	var existing: Dictionary = main.world_data.get_reservation(owner_id)
	if not existing.is_empty():
		var existing_origin: Vector2i = main._vector_from_dictionary(existing.get("origin", {}))
		if existing_origin == cell and active:
			return
		main.world_data.release_footprint(owner_id)
	if active and main.world_data.contains(cell) and main.world_data.is_walkable(cell):
		main.world_data.reserve_entity(owner_id, cell, Vector2i.ONE, false, {"role": "dungeon_enemy"})

func combat_target_cell(main, enemy) -> Vector2i:
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("current_grid_cell"):
		return enemy.current_grid_cell()
	if enemy is Node2D:
		return main.world_cell_from_world_position(enemy.global_position)
	return Vector2i.ZERO

static func normalize_reward_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": result, "reason": "additional_reward_hook_rejected", "error": "Additional dungeon reward hook rejected completion."}
	return {"ok": true, "value": result}
