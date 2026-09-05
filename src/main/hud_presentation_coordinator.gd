extends RefCounted
class_name HudPresentationCoordinator

const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")
const WorldPresentation = preload("res://src/main/world_presentation.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

class Ports:
	var get_scene_root: Callable
	var get_player: Callable
	var get_combat_target: Callable
	var get_world_visuals: Callable
	var get_world_tone_overlay: Callable
	var get_game_hud: Callable
	var get_catalog: Callable
	var get_inventory: Callable
	var get_inventory_command_runtime: Callable
	var get_map_read_model_builder: Callable
	var get_world_data: Callable
	var set_world_data: Callable
	var get_generated_world: Callable
	var set_generated_world: Callable
	var get_world_render_result: Callable
	var set_world_render_result: Callable
	var get_run_state: Callable
	var ensure_run_state: Callable
	var get_tea_service: Callable
	var get_tea_brewing_command_runtime: Callable
	var get_meta_codex_command_runtime: Callable
	var get_crafting_service: Callable
	var get_crafting_context: Callable
	var get_biome_progression_state: Callable
	var get_cheat_mode: Callable
	var get_time_state: Callable
	var get_biome_map_previews: Callable
	var runtime_world_origin: Callable
	var runtime_tile_size: Callable
	var world_position_for_cell_center: Callable
	var world_cell_from_world_position: Callable
	var ensure_saved_world_has_teleport_landmark: Callable
	var save_current_run: Callable
	var restore_overworld_enemy_state: Callable
	var connect_hud_commands: Callable
	var submit_mobile_action_command: Callable
	var current_meta_state_snapshot: Callable
	var get_narrative_session: Callable
	var get_narrative_runtime: Callable
	var get_run_start_event_selector: Callable
	var get_force_first_run_prologue: Callable
	var dungeon_precombat_dialogue_is_active: Callable
	var get_dungeon_runtime: Callable
	var dungeon_boss_cell: Callable
	var activate_dungeon_enemy: Callable
	var dungeon_debug: Callable
	var get_sfx_router: Callable
	var set_sfx_router: Callable
	var increment_feedback_beep_count: Callable
	var add_child: Callable
	var push_error: Callable
	var is_in_dungeon_map: Callable

var _ports: Ports

func _init(ports: Ports) -> void:
	_ports = ports

func render_generated_world(world: Dictionary) -> void:
	WorldPresentation.hide_prototype_visuals(_call_object(_ports.get_scene_root))
	var world_data = _call_object(_ports.get_world_data)
	if not _call_bool(_ports.is_in_dungeon_map) and world_data != null:
		var migrated := _call_bool(_ports.ensure_saved_world_has_teleport_landmark)
		world["world_data"] = world_data.to_dictionary()
		var biome_progression_state = _call_object(_ports.get_biome_progression_state)
		world["renderer_input"] = WorldRendererProjection.new().project(
			world["world_data"],
			biome_progression_state.to_projection() if biome_progression_state != null else {}
		)
		if migrated:
			_call_dictionary(_ports.save_current_run)
	_render_world_snapshot(world)
	var player = _call_object(_ports.get_player)
	if player != null and player.has_method("configure_grid_navigation"):
		var run_state = _call_object(_ports.get_run_state)
		var saved_cell: Dictionary = run_state.player_cell if run_state != null else {}
		var spawn_cell := WorldPresentation.entry_spawn_cell(world)
		if not saved_cell.is_empty():
			var candidate := Vector2i(int(saved_cell.get("x", spawn_cell.x)), int(saved_cell.get("y", spawn_cell.y)))
			if world_data != null and world_data.is_walkable(candidate):
				spawn_cell = candidate
		player.global_position = _call_value(_ports.world_position_for_cell_center, Vector2.ZERO, [spawn_cell])
		player.configure_grid_navigation(world_data, _call_vector2(_ports.runtime_world_origin), _call_float(_ports.runtime_tile_size))
	configure_runtime_camera()
	var combat_target = _call_object(_ports.get_combat_target)
	if combat_target != null and combat_target.has_method("configure_grid_navigation"):
		combat_target.configure_grid_navigation(world_data, _call_vector2(_ports.runtime_world_origin), _call_float(_ports.runtime_tile_size))
	_call_void(_ports.restore_overworld_enemy_state)

func sync_runtime_world_render() -> void:
	var world_visuals = _call_object(_ports.get_world_visuals)
	var world_data = _call_object(_ports.get_world_data)
	if world_visuals == null or world_data == null or _call_dictionary(_ports.get_world_render_result).is_empty():
		return
	var generated_world := _call_dictionary(_ports.get_generated_world)
	var world_snapshot: Dictionary = world_data.to_dictionary()
	var renderer_input: Dictionary = WorldRendererProjection.new().project(world_snapshot)
	WorldPresentation.apply_teleport_states(renderer_input, _call_object(_ports.get_run_state))
	generated_world["world_data"] = world_snapshot
	generated_world["renderer_input"] = renderer_input
	_call_void(_ports.set_generated_world, [generated_world])
	_render_world_snapshot(generated_world)
	configure_runtime_camera()
	var player = _call_object(_ports.get_player)
	if player != null and player.has_method("configure_grid_navigation"):
		player.configure_grid_navigation(world_data, _call_vector2(_ports.runtime_world_origin), _call_float(_ports.runtime_tile_size))
	var combat_target = _call_object(_ports.get_combat_target)
	if combat_target != null and combat_target.has_method("configure_grid_navigation"):
		combat_target.configure_grid_navigation(world_data, _call_vector2(_ports.runtime_world_origin), _call_float(_ports.runtime_tile_size))

func configure_runtime_camera() -> void:
	var player = _call_object(_ports.get_player)
	var world_data = _call_object(_ports.get_world_data)
	WorldPresentation.configure_camera(player, world_data, _call_vector2(_ports.runtime_world_origin), _call_float(_ports.runtime_tile_size))
	if player != null and world_data != null and player.get_node_or_null("Camera2D") != null:
		update_dungeon_sign_visibility()

func update_dungeon_sign_visibility() -> void:
	var player = _call_object(_ports.get_player)
	if player == null:
		return
	var player_cell: Vector2i = _call_value(_ports.world_cell_from_world_position, Vector2i.ZERO, [player.global_position])
	WorldPresentation.update_interaction_prompts(_call_object(_ports.get_world_visuals), player_cell, _call_float(_ports.runtime_tile_size))

func configure_game_hud() -> void:
	configure_world_tone_overlay()
	var game_hud = _call_object(_ports.get_game_hud)
	if game_hud == null:
		return
	_call_void(_ports.connect_hud_commands)
	var hud_callback := Callable(self, "on_hud_mobile_command_issued")
	if game_hud.has_signal("mobile_command_issued") and not game_hud.is_connected("mobile_command_issued", hud_callback):
		game_hud.connect("mobile_command_issued", hud_callback)
	game_hud.configure(_call_object(_ports.get_player), _call_dictionary(_ports.get_generated_world), _call_dictionary(_ports.get_world_render_result), {
		"catalog": _call_object(_ports.get_catalog),
		"inventory": _call_object(_ports.get_inventory),
		"inventory_command_runtime": _call_object(_ports.get_inventory_command_runtime),
		"map_read_model_builder": _call_object(_ports.get_map_read_model_builder),
		"world_data": _call_object(_ports.get_world_data),
		"combat_target": _call_object(_ports.get_combat_target),
		"run_state": _call_object(_ports.get_run_state),
		"tea_service": _call_object(_ports.get_tea_service),
		"tea_brewing_command_runtime": _call_object(_ports.get_tea_brewing_command_runtime),
		"meta_codex_command_runtime": _call_object(_ports.get_meta_codex_command_runtime),
		"crafting_service": _call_object(_ports.get_crafting_service),
		"crafting_context": _call_dictionary(_ports.get_crafting_context),
		"biome_progression_state": _call_object(_ports.get_biome_progression_state),
		"cheat_mode": _call_bool(_ports.get_cheat_mode),
		"time_state": _call_object(_ports.get_time_state),
		"world_origin": _call_vector2(_ports.runtime_world_origin),
		"biome_map_previews": _call_dictionary(_ports.get_biome_map_previews)
	})
	maybe_show_run_start_event()

func configure_world_tone_overlay() -> void:
	var world_tone_overlay = _call_object(_ports.get_world_tone_overlay)
	if world_tone_overlay != null and world_tone_overlay.has_method("configure"):
		world_tone_overlay.configure(_call_object(_ports.get_time_state))

func first_run_prologue_read_model(meta_state = null) -> Dictionary:
	var run_state = _call_object(_ports.ensure_run_state)
	var meta = meta_state if meta_state != null else _call_dictionary(_ports.current_meta_state_snapshot)
	return _call_object(_ports.get_narrative_session).first_run_prologue_read_model(
		_call_object(_ports.get_narrative_runtime),
		run_state,
		meta,
		_call_bool(_ports.get_force_first_run_prologue)
	)

func start_run_event_read_model(meta_state = null) -> Dictionary:
	var run_state = _call_object(_ports.ensure_run_state)
	var meta = meta_state if meta_state != null else _call_dictionary(_ports.current_meta_state_snapshot)
	return _call_object(_ports.get_narrative_session).start_run_event_read_model(
		_call_object(_ports.get_narrative_runtime),
		_call_object(_ports.get_run_start_event_selector),
		run_state,
		meta,
		_call_bool(_ports.get_force_first_run_prologue)
	)

func maybe_show_run_start_event() -> Dictionary:
	var game_hud = _call_object(_ports.get_game_hud)
	if game_hud == null or _call_object(_ports.get_narrative_runtime) == null:
		return {"ok": false, "reason": "missing_presentation", "error": "Run-start presentation is not ready."}
	var model_result := start_run_event_read_model()
	if not model_result.ok:
		if game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
		return model_result
	set_active_narrative_from_read_model(model_result.read_model)
	game_hud.show_narrative_dialogue(model_result.read_model)
	return {"ok": true, "read_model": model_result.read_model}

func handle_narrative_option_command(command) -> bool:
	var narrative_session = _call_object(_ports.get_narrative_session)
	var event_id := String(command.payload.get("event_id", narrative_session.active_event_id))
	var result: Dictionary = narrative_session.select_option(
		command,
		_call_object(_ports.get_narrative_runtime),
		_call_object(_ports.get_run_state),
		_call_dictionary(_ports.current_meta_state_snapshot)
	)
	if not bool(result.get("handled", false)):
		return false
	var game_hud = _call_object(_ports.get_game_hud)
	if bool(result.get("complete", false)):
		if _call_bool(_ports.dungeon_precombat_dialogue_is_active, [event_id]):
			var dungeon_runtime = _call_object(_ports.get_dungeon_runtime)
			var boss_start_result: Dictionary = dungeon_runtime.complete_boss_precombat_dialogue(event_id)
			if not boss_start_result.ok:
				_call_void(_ports.dungeon_debug, ["보스 전 대화 완료 처리 실패: %s" % boss_start_result])
				return false
			var boss_cell: Vector2i = _call_value(_ports.dungeon_boss_cell, Vector2i(-1, -1))
			if boss_cell != Vector2i(-1, -1):
				_call_void(_ports.activate_dungeon_enemy, [boss_cell])
		narrative_session.reset()
		if game_hud != null and game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
	else:
		var read_model: Dictionary = result.get("read_model", {})
		narrative_session.active_event_id = String(read_model.get("event_id", event_id))
		narrative_session.active_node_id = String(read_model.get("node_id", ""))
		if game_hud != null and game_hud.has_method("show_narrative_dialogue"):
			game_hud.show_narrative_dialogue(read_model)
	_call_dictionary(_ports.save_current_run)
	return true

func set_active_narrative_from_read_model(read_model: Dictionary) -> void:
	_call_object(_ports.get_narrative_session).begin_read_model(read_model)

func configure_audio_feedback() -> void:
	if _call_object(_ports.get_sfx_router) != null:
		return
	var sfx_router := SfxEventRouter.new()
	sfx_router.name = "SfxEventRouter"
	_call_void(_ports.set_sfx_router, [sfx_router])
	_call_void(_ports.add_child, [sfx_router])

func play_feedback_beep() -> void:
	play_sfx_event(SfxEventRouter.EVENT_UI_SELECT)

func play_sfx_event(event_id: String, payload := {}, dedupe_key := "") -> Dictionary:
	if _call_object(_ports.get_sfx_router) == null:
		configure_audio_feedback()
	var sfx_router = _call_object(_ports.get_sfx_router)
	if sfx_router == null:
		return {"ok": false, "reason": "missing_sfx_router", "event_id": event_id}
	var before_count: int = int(sfx_router.played_events.size())
	var result: Dictionary = sfx_router.play_event(event_id, payload, dedupe_key)
	if sfx_router.played_events.size() > before_count:
		_call_void(_ports.increment_feedback_beep_count)
	return result

func centered_world_origin(renderer_input: Dictionary) -> Vector2:
	return WorldPresentation.centered_world_origin(renderer_input)

func owner_sprite_sources(world: Dictionary) -> Dictionary:
	return WorldPresentation.owner_sprite_sources(world)

func _render_world_snapshot(world: Dictionary) -> void:
	var renderer_input: Dictionary = world.get("renderer_input", {})
	WorldPresentation.apply_teleport_states(renderer_input, _call_object(_ports.get_run_state))
	var result: Dictionary = WorldSceneRenderer.new().render(
		_call_object(_ports.get_world_visuals),
		renderer_input,
		WorldPresentation.owner_sprite_sources(world),
		WorldPresentation.centered_world_origin(renderer_input)
	)
	_call_void(_ports.set_world_render_result, [result])
	if not result.ok:
		_call_void(_ports.push_error, [result.error])

func on_hud_mobile_command_issued(command) -> void:
	_call_bool(_ports.submit_mobile_action_command, [command])

func _call_bool(callback: Callable, arguments := []) -> bool:
	return bool(_call_value(callback, false, arguments))

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	var value = _call_value(callback, {}, arguments)
	return value if value is Dictionary else {}

func _call_float(callback: Callable, arguments := []) -> float:
	return float(_call_value(callback, 0.0, arguments))

func _call_object(callback: Callable, arguments := []):
	return _call_value(callback, null, arguments)

func _call_vector2(callback: Callable, arguments := []) -> Vector2:
	var value = _call_value(callback, Vector2.ZERO, arguments)
	return value if value is Vector2 else Vector2.ZERO

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)

func _call_value(callback: Callable, default_value = null, arguments := []):
	if not callback.is_valid():
		return default_value
	return callback.callv(arguments)
