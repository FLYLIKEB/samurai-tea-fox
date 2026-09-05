extends RefCounted
class_name FacilityBiomeCoordinator

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const FacilityPlacementPreview = preload("res://src/presentation/facility_placement_preview.gd")
const FacilityPlacementSession = preload("res://src/main/facility_placement_session.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class Ports:
	var is_in_dungeon_map: Callable
	var get_dungeon_runtime: Callable
	var combat_targets: Callable
	var dungeon_boss_combat_available: Callable
	var return_from_dungeon_map: Callable
	var save_current_run: Callable
	var configure_game_hud: Callable
	var get_game_hud: Callable
	var get_run_state: Callable
	var set_run_state: Callable
	var is_core_dungeon_target: Callable
	var handle_complete_dungeon_command: Callable
	var ensure_biome_progression_state: Callable
	var get_biome_progression_state: Callable
	var set_biome_progression_state: Callable
	var get_generated_world: Callable
	var set_generated_world: Callable
	var store_current_biome_runtime_aliases: Callable
	var restore_run_state_from_snapshot: Callable
	var configure_world_for_current_run: Callable
	var create_loading_overlay: Callable
	var set_loading_status: Callable
	var clear_loading_overlay: Callable
	var loading_biome_label: Callable
	var debug: Callable
	var get_crafting_service: Callable
	var get_inventory: Callable
	var get_facility_placement_service: Callable
	var get_world_data: Callable
	var get_player: Callable
	var player_world_cell: Callable
	var player_facility_metadata: Callable
	var crafting_context: Callable
	var clear_pointer_movement: Callable
	var clear_facility_placement_preview: Callable
	var update_facility_placement_preview: Callable
	var sync_runtime_world_render: Callable
	var sync_run_runtime_state: Callable
	var advance_time_for_turn: Callable
	var play_feedback_beep: Callable
	var queue_enemy_turn_after_player_action: Callable
	var content_image_asset_id: Callable
	var get_start_mode: Callable
	var get_catalog: Callable

var _session: FacilityPlacementSession
var _ports: Ports

func _init(session: FacilityPlacementSession, ports: Ports) -> void:
	_session = session
	_ports = ports

func handle_landmark_interaction(target_id: String) -> bool:
	if bool(_call_value(_ports.is_in_dungeon_map, false)) and target_id == "dungeon_entry":
		return _handle_dungeon_entry_return(target_id)
	if _call_bool(_ports.is_core_dungeon_target, [target_id]):
		_debug("던전 랜드마크 상호작용: %s" % target_id)
		var run_state = _call_value(_ports.get_run_state)
		if run_state != null and run_state.completed_dungeon_ids.has(String(run_state.current_biome_id)):
			var hud = _call_value(_ports.get_game_hud)
			if hud != null:
				hud.show_command_feedback("유적 수리 완료 · 이동은 텔레포트를 이용하세요")
			return true
		return _call_bool(_ports.handle_complete_dungeon_command, [GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"entry_only": true})])
	if target_id.begins_with("%s_" % WorldData.LANDMARK_BOSS_ANCHOR):
		_debug("보스 앵커 상호작용: %s" % target_id)
		var run_state = _call_value(_ports.get_run_state)
		if run_state != null and run_state.completed_dungeon_ids.has(String(run_state.current_biome_id)):
			var hud = _call_value(_ports.get_game_hud)
			if hud != null:
				hud.show_command_feedback("이미 정리한 보스 흔적입니다")
			return true
		return _call_bool(_ports.handle_complete_dungeon_command, [GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"entry_only": true, "target_id": target_id})])
	if target_id.begins_with("%s_" % WorldData.LANDMARK_RUIN):
		return _handle_ruin_landmark()
	if target_id.begins_with("%s_" % WorldData.LANDMARK_TELEPORT_ZONE):
		return _handle_teleport_landmark()
	return false

func travel_to_biome(biome_id: String, travel_mode: String = "teleport") -> bool:
	var run_state = _call_value(_ports.get_run_state)
	if run_state == null or biome_id.is_empty():
		return false
	var current_id := String(run_state.current_biome_id)
	var progression: Dictionary = _call_dictionary(_ports.ensure_biome_progression_state)
	if not progression.ok or biome_id == current_id:
		return false
	var can_travel := false
	if travel_mode == "ruin":
		can_travel = run_state.completed_dungeon_ids.has(biome_id)
	else:
		can_travel = is_connected_biome(current_id, biome_id)
	if not can_travel:
		var hud = _call_value(_ports.get_game_hud)
		if hud != null:
			hud.show_command_feedback("텔레포트 연결 조건을 만족하지 않았습니다")
		return false
	var rollback_snapshot: Dictionary = run_state.to_dictionary()
	var rollback_generated_world: Dictionary = _call_dictionary(_ports.get_generated_world).duplicate(true)
	_call_void(_ports.store_current_biome_runtime_aliases, [current_id])
	run_state.current_biome_id = biome_id
	if travel_mode != "ruin":
		run_state.teleport_states[biome_id] = BiomeProgressionState.TELEPORT_BROKEN
	_call_void(_ports.set_biome_progression_state, [null])
	_call_void(_ports.create_loading_overlay)
	_call_void(_ports.set_loading_status, ["%s 지역으로 이동하는 중…" % String(_call_value(_ports.loading_biome_label, ""))])
	var world_result: Dictionary = _call_dictionary(_ports.configure_world_for_current_run)
	if not world_result.ok:
		_call_void(_ports.restore_run_state_from_snapshot, [rollback_snapshot])
		_call_void(_ports.set_generated_world, [rollback_generated_world.duplicate(true)])
		_call_void(_ports.set_biome_progression_state, [null])
		var rollback_world_result: Dictionary = _call_dictionary(_ports.configure_world_for_current_run)
		if not rollback_world_result.ok:
			push_error(String(rollback_world_result.get("error", "Failed to restore previous biome world after travel failure.")))
		_call_void(_ports.clear_loading_overlay)
		return false
	_call_void(_ports.clear_loading_overlay)
	_call_dictionary(_ports.save_current_run)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.show_status_event({
			"type": "biome_transition",
			"ok": true,
			"biome_id": biome_id,
			"event_id": "%s:%s" % [travel_mode, biome_id]
		})
	return true

func is_connected_biome(from_id: String, to_id: String) -> bool:
	var progression_state = _call_value(_ports.get_biome_progression_state)
	var run_state = _call_value(_ports.get_run_state)
	if progression_state == null or run_state == null:
		return false
	var ordered: Array = progression_state.to_projection().get("biome_order", [])
	var from_index := ordered.find(from_id)
	var to_index := ordered.find(to_id)
	if from_index < 0 or to_index < 0 or absi(from_index - to_index) != 1:
		return false
	var current_teleport_repaired: bool = String(run_state.teleport_states.get(from_id, "")) == BiomeProgressionState.TELEPORT_REPAIRED
	if not current_teleport_repaired:
		return false
	if to_index > from_index:
		return to_index == from_index + 1
	return run_state.completed_dungeon_ids.has(to_id) or String(run_state.teleport_states.get(to_id, "")) != "undiscovered"

func handle_craft_recipe_command(command: GameCommand) -> bool:
	var crafting_service = _call_value(_ports.get_crafting_service)
	var inventory = _call_value(_ports.get_inventory)
	if crafting_service == null or inventory == null:
		return false
	var recipe_id := String(command.payload.get("recipe_id", ""))
	if recipe_id.is_empty():
		return false
	var result: Dictionary = craft_recipe_or_begin_facility_placement(recipe_id)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		if bool(result.get("placement_pending", false)):
			hud.show_command_feedback("설치할 타일을 선택하세요. (플레이어 기준 2칸 이내)")
		else:
			hud.show_command_feedback(
				"제작 완료: %s" % result.get("result_item_id", recipe_id)
				if result.ok
				else "제작 불가: %s" % String(result.get("reason", "unknown"))
			)
	if result.ok and not bool(result.get("placement_pending", false)):
		_call_void(_ports.sync_run_runtime_state)
		_call_dictionary(_ports.save_current_run)
		_call_void(_ports.configure_game_hud)
		if hud != null:
			hud.show_status_event({
				"type": "craft_completed",
				"ok": true,
				"result_item_id": String(result.get("result_item_id", "")),
				"quantity": int(result.get("result_quantity", 0)),
				"event_id": recipe_id
			})
	return bool(result.ok)

func craft_recipe_or_begin_facility_placement(recipe_id: String) -> Dictionary:
	var crafting_service = _call_value(_ports.get_crafting_service)
	var inventory = _call_value(_ports.get_inventory)
	var recipe: Dictionary = crafting_service.recipe_for(recipe_id)
	var result_item_id := String(recipe.get("result_item_id", ""))
	if not crafting_service.is_facility_item(result_item_id):
		return crafting_service.craft(recipe_id, inventory, _call_dictionary(_ports.crafting_context))
	if bool(_call_value(_ports.is_in_dungeon_map, false)):
		return {"ok": false, "reason": "facility_installation_requires_overworld"}
	var facility_placement_service = _call_value(_ports.get_facility_placement_service)
	var world_data = _call_value(_ports.get_world_data)
	var player = _call_value(_ports.get_player)
	if facility_placement_service == null or world_data == null or player == null:
		return {"ok": false, "reason": "facility_placement_unavailable"}
	var result := _session.begin_or_craft_recipe(
		recipe_id,
		crafting_service,
		inventory,
		_call_dictionary(_ports.crafting_context),
		facility_placement_service,
		world_data,
		_call_value(_ports.player_world_cell, Vector2i.ZERO),
		bool(_call_value(_ports.is_in_dungeon_map, false)),
		_call_dictionary(_ports.player_facility_metadata, [result_item_id])
	)
	if not result.ok:
		return result
	_call_void(_ports.clear_pointer_movement)
	_call_void(_ports.clear_facility_placement_preview)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.hide_menu()
		hud.show_facility_placement_controls()
	var initial_origin: Vector2i = result.get("initial_origin", Vector2i(-1, -1))
	if initial_origin.x >= 0:
		select_pending_facility_at(initial_origin)
	result.erase("initial_origin")
	return result

func has_pending_facility_placement() -> bool:
	return _session.has_pending()

func select_pending_facility_at(origin: Vector2i) -> void:
	var validation := _session.select_origin(
		origin,
		_call_value(_ports.get_facility_placement_service),
		_call_value(_ports.get_world_data),
		_call_value(_ports.player_world_cell, Vector2i.ZERO)
	)
	_call_void(_ports.update_facility_placement_preview, [validation])
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.update_facility_placement_controls(
			bool(validation.get("ok", false)),
			"설치 가능" if bool(validation.get("ok", false)) else facility_placement_reason(String(validation.get("reason", "invalid_placement")))
		)

func rotate_pending_facility() -> bool:
	var result := _session.rotate(
		_call_value(_ports.get_facility_placement_service),
		_call_value(_ports.get_world_data),
		_call_value(_ports.player_world_cell, Vector2i.ZERO)
	)
	if not bool(result.get("ok", false)):
		return false
	var hud = _call_value(_ports.get_game_hud)
	if _session.pending_origin.x >= 0:
		_call_void(_ports.update_facility_placement_preview, [result])
		if hud != null:
			hud.update_facility_placement_controls(
				bool(result.get("ok", false)),
				"설치 가능" if bool(result.get("ok", false)) else facility_placement_reason(String(result.get("reason", "invalid_placement")))
			)
	elif hud != null:
		hud.update_facility_placement_controls(true, "방향 %d°" % (_session.pending_rotation * 90))
	return true

func confirm_pending_facility() -> bool:
	if not has_pending_facility_placement() or _session.pending_origin.x < 0 or _session.pending_result.is_empty():
		return false
	if not bool(_session.pending_result.get("ok", false)):
		select_pending_facility_at(_session.pending_origin)
		return false
	var placed := place_pending_facility(_session.pending_result)
	return bool(placed.get("ok", false))

func place_pending_facility(placement_result: Dictionary) -> Dictionary:
	var result := _session.place_selected(
		_call_value(_ports.get_crafting_service),
		_call_value(_ports.get_inventory),
		_call_dictionary(_ports.crafting_context),
		_call_value(_ports.get_facility_placement_service),
		_call_value(_ports.get_world_data),
		placement_result
	)
	if not bool(result.get("ok", false)):
		return facility_placement_failed(String(result.get("reason", "invalid_placement")))
	record_placed_facility(result.placement)
	_call_void(_ports.sync_runtime_world_render)
	_session.clear()
	_call_void(_ports.clear_facility_placement_preview)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.hide_facility_placement_controls()
	_call_void(_ports.sync_run_runtime_state)
	_call_dictionary(_ports.save_current_run)
	_call_void(_ports.configure_game_hud)
	if hud != null:
		hud.show_command_feedback("제작·설치 완료: %s" % String(result.get("facility_item_id", "")))
	_call_void(_ports.advance_time_for_turn)
	_call_void(_ports.play_feedback_beep)
	_call_void(_ports.queue_enemy_turn_after_player_action)
	return result

func facility_placement_failed(reason: String) -> Dictionary:
	var result := _session.placement_failed(reason)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.update_facility_placement_controls(false, facility_placement_reason(reason))
	return result

func facility_placement_reason(reason: String) -> String:
	return FacilityPlacementSession.reason_message(reason)

func cancel_pending_facility_placement() -> bool:
	var result := _session.cancel()
	if not bool(result.get("ok", false)):
		return false
	_call_void(_ports.clear_facility_placement_preview)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.hide_facility_placement_controls()
		hud.show_command_feedback("시설 설치를 취소했습니다.")
	return true

func facility_footprint_for_pending_facility() -> Vector2i:
	return _session.footprint_for_pending_facility(_call_value(_ports.get_facility_placement_service))

func player_facility_metadata(facility_item_id: String) -> Dictionary:
	return _session.player_facility_metadata(
		facility_item_id,
		_call_value(_ports.get_facility_placement_service),
		String(_call_value(_ports.content_image_asset_id, "", ["items", facility_item_id]))
	)

func record_placed_facility(placed: Dictionary) -> void:
	var run_state = _call_value(_ports.get_run_state)
	if run_state == null:
		run_state = RunState.new()
		_call_void(_ports.set_run_state, [run_state])
	_session.record_placed_facility(run_state, _call_dictionary(_ports.get_generated_world), placed)

func available_facility_item_ids() -> Array:
	if _call_value(_ports.get_player) == null:
		return []
	return _session.available_facility_item_ids(
		_call_value(_ports.get_crafting_service),
		_call_value(_ports.get_facility_placement_service),
		_call_value(_ports.get_world_data),
		_call_value(_ports.get_run_state),
		_call_dictionary(_ports.get_generated_world),
		_call_value(_ports.player_world_cell, Vector2i.ZERO)
	)

func restore_placed_facilities_for_current_biome() -> Dictionary:
	return _session.restore_placed_facilities_for_current_biome(
		_call_value(_ports.get_facility_placement_service),
		_call_value(_ports.get_world_data),
		_call_value(_ports.get_run_state),
		_call_dictionary(_ports.get_generated_world)
	)

func unlocked_biome_ids() -> Array:
	var ids: Array = []
	var catalog = _call_value(_ports.get_catalog)
	if String(_call_value(_ports.get_start_mode, "")) == "cheat" and catalog != null and catalog.has_method("get_definitions"):
		for definition in catalog.get_definitions("biomes"):
			var cheat_id := String(definition.get("id", ""))
			if not cheat_id.is_empty() and not ids.has(cheat_id):
				ids.append(cheat_id)
		return ids
	var run_state = _call_value(_ports.get_run_state)
	if run_state != null:
		for biome_id in run_state.crafting_unlocks:
			var id := String(biome_id)
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
		var current_id := String(run_state.current_biome_id)
		if not current_id.is_empty() and not ids.has(current_id):
			ids.append(current_id)
	return ids

func _handle_dungeon_entry_return(target_id: String) -> bool:
	var dungeon_runtime = _call_value(_ports.get_dungeon_runtime)
	if dungeon_runtime == null:
		return false
	var run_state = _call_value(_ports.get_run_state)
	var lifecycle := String(dungeon_runtime.to_projection().get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE))
	if lifecycle == DungeonInstanceState.STATE_ACTIVE and _call_array(_ports.combat_targets).is_empty() and _call_bool(_ports.dungeon_boss_combat_available):
		var clear_result: Dictionary = dungeon_runtime.complete_dungeon({"objective_complete": true, "resolution_type": "combat", "choice_key": "dungeon_boss_defeated", "run_flag": "dungeon_boss_defeated", "reward_item_ids": [], "progression_unlock_ids": [String(run_state.current_biome_id)]})
		if not clear_result.ok:
			return false
		lifecycle = DungeonInstanceState.STATE_COMPLETED
	if lifecycle != DungeonInstanceState.STATE_COMPLETED:
		return false
	if not dungeon_runtime.begin_return().ok or not dungeon_runtime.finish_return().ok:
		return false
	_call_void(_ports.return_from_dungeon_map)
	_call_dictionary(_ports.save_current_run)
	_call_void(_ports.configure_game_hud)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.show_command_feedback("던전에서 귀환")
		hud.show_status_event({
			"type": "dungeon_exited",
			"ok": true,
			"dungeon_id": String(dungeon_runtime.to_projection().get("dungeon_id", "")),
			"event_id": "return:%s" % target_id
		})
	return true

func _handle_ruin_landmark() -> bool:
	var run_state = _call_value(_ports.get_run_state)
	var current_biome_id := String(run_state.current_biome_id) if run_state != null else ""
	var dungeon_cleared: bool = run_state != null and run_state.completed_dungeon_ids.has(current_biome_id)
	var hud = _call_value(_ports.get_game_hud)
	if dungeon_cleared:
		if hud != null:
			hud.show_ruin_travel_menu()
		return true
	if hud != null:
		hud.show_command_feedback("유적 연결은 던전 클리어 후 이용할 수 있습니다")
	return true

func _handle_teleport_landmark() -> bool:
	var run_state = _call_value(_ports.get_run_state)
	var biome_id := String(run_state.current_biome_id) if run_state != null else ""
	var progression: Dictionary = _call_dictionary(_ports.ensure_biome_progression_state)
	if not progression.ok:
		return false
	var dungeon_runtime = _call_value(_ports.get_dungeon_runtime)
	if dungeon_runtime != null and bool(_call_value(_ports.is_in_dungeon_map, false)) and _call_array(_ports.combat_targets).is_empty() and _call_bool(_ports.dungeon_boss_combat_available):
		var clear_result: Dictionary = dungeon_runtime.complete_dungeon({"objective_complete": true, "resolution_type": "combat", "choice_key": "dungeon_boss_defeated", "run_flag": "dungeon_boss_defeated", "reward_item_ids": [], "progression_unlock_ids": [biome_id]})
		if clear_result.ok:
			_debug("유적 접근 전 미기록 던전 클리어 보정 완료")
	var progression_state = _call_value(_ports.get_biome_progression_state)
	var teleport_state: String = String(run_state.teleport_states.get(biome_id, "")) if run_state != null else progression_state.teleport_state_for(biome_id)
	if teleport_state != BiomeProgressionState.TELEPORT_REPAIRED:
		return handle_biome_progression_command(GameCommand.new(GameCommand.Type.REPAIR_TELEPORT, Vector2i.ZERO, -1, {"biome_id": biome_id}))
	var hud = _call_value(_ports.get_game_hud)
	if hud != null:
		hud.show_teleport_travel_menu()
	return true

func handle_biome_progression_command(command: GameCommand) -> bool:
	var progression_result: Dictionary = _call_dictionary(_ports.ensure_biome_progression_state)
	if not progression_result.ok:
		return false
	var run_state = _call_value(_ports.get_run_state)
	if not command.payload.has("biome_id") and run_state != null:
		command.payload["biome_id"] = String(run_state.current_biome_id)
	_debug("바이옴 진행 상태: biome=%s completed=%s teleport=%s" % [
		String(command.payload.get("biome_id", "")),
		str(run_state.completed_dungeon_ids if run_state != null else []),
		str(run_state.teleport_states if run_state != null else {})
	])
	var rollback_snapshot: Dictionary = run_state.to_dictionary() if run_state != null else {}
	var rollback_generated_world := _call_dictionary(_ports.get_generated_world).duplicate(true)
	var previous_biome_id := String(run_state.current_biome_id) if run_state != null else ""
	if command.type == GameCommand.Type.ADVANCE_BIOME:
		_call_void(_ports.store_current_biome_runtime_aliases, [previous_biome_id])
	var biome_progression_state = _call_value(_ports.get_biome_progression_state)
	var result: Dictionary = biome_progression_state.apply_command(command)
	if not result.ok:
		_debug("바이옴 진행 명령 실패: type=%s biome=%s reason=%s" % [command.type, String(command.payload.get("biome_id", "")), String(result.get("reason", "unknown"))])
		var hud = _call_value(_ports.get_game_hud)
		if hud != null and hud.has_method("show_command_feedback"):
			hud.show_command_feedback("수리 불가: %s" % String(result.get("reason", "unknown")))
		return false
	var world_result: Dictionary = _call_dictionary(_ports.configure_world_for_current_run)
	if not world_result.ok:
		if command.type == GameCommand.Type.ADVANCE_BIOME and not rollback_snapshot.is_empty():
			_call_void(_ports.restore_run_state_from_snapshot, [rollback_snapshot])
			_call_void(_ports.set_generated_world, [rollback_generated_world.duplicate(true)])
			_call_void(_ports.set_biome_progression_state, [null])
			var rollback_world_result: Dictionary = _call_dictionary(_ports.configure_world_for_current_run)
			if not rollback_world_result.ok:
				push_error(String(rollback_world_result.get("error", "Failed to restore previous biome world after transition failure.")))
		return false
	_call_dictionary(_ports.save_current_run)
	var hud = _call_value(_ports.get_game_hud)
	if hud != null and command.type == GameCommand.Type.ADVANCE_BIOME:
		hud.show_status_event({
			"type": "biome_transition",
			"ok": true,
			"biome_id": String(run_state.current_biome_id),
			"event_id": "advance:%s" % String(run_state.current_biome_id)
		})
	return true

func _debug(message: String) -> void:
	_call_void(_ports.debug, [message])

func _call_bool(callback: Callable, arguments := []) -> bool:
	return bool(_call_value(callback, false, arguments))

func _call_array(callback: Callable, arguments := []) -> Array:
	var value = _call_value(callback, [], arguments)
	return value if value is Array else []

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	var value = _call_value(callback, {}, arguments)
	return value if value is Dictionary else {}

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)

func _call_value(callback: Callable, default_value = null, arguments := []):
	if not callback.is_valid():
		return default_value
	return callback.callv(arguments)
