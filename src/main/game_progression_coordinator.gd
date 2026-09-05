extends RefCounted
class_name GameProgressionCoordinator

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")

func ensure_run_state(main) -> RunState:
	if main.run_state == null:
		main.run_state = RunState.new()
	return main.run_state

func final_room_gate_query(main) -> Dictionary:
	if main.core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	return main.core_tea_ware_collection.final_room_gate_query(ensure_run_state(main))

func final_room_state_read_model(main) -> Dictionary:
	if main.final_room_state_builder == null:
		return {"ok": false, "reason": "missing_final_room_state_builder", "error": "Final room state builder is not configured."}
	return main.final_room_state_builder.build(ensure_run_state(main))

func start_sen_rikyu_phase_one(main, meta_state = null) -> Dictionary:
	if main.sen_rikyu_phase_one_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_one", "error": "Sen Rikyu Phase 1 runtime is not configured."}
	return main.sen_rikyu_phase_one_runtime.start(ensure_run_state(main), meta_state)

func handle_sen_rikyu_phase_one_command(main, command_id: String, payload := {}, meta_state = null, resources = null) -> Dictionary:
	if main.sen_rikyu_phase_one_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_one", "error": "Sen Rikyu Phase 1 runtime is not configured."}
	return main.sen_rikyu_phase_one_runtime.handle_command(command_id, payload, ensure_run_state(main), meta_state, resources)

func start_sen_rikyu_phase_two(main, phase_one_transition_command) -> Dictionary:
	if main.sen_rikyu_phase_two_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_two", "error": "Sen Rikyu Phase 2 runtime is not configured."}
	return main.sen_rikyu_phase_two_runtime.start_from_phase_one(phase_one_transition_command)

func start_sen_rikyu_phase_three(main, phase_two_transition) -> Dictionary:
	if main.sen_rikyu_phase_three_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_three", "error": "Sen Rikyu Phase 3 runtime is not configured."}
	return main.sen_rikyu_phase_three_runtime.start(phase_two_transition, ensure_run_state(main))

func complete_sen_rikyu_phase_three(main, ability_id: String) -> Dictionary:
	if main.sen_rikyu_phase_three_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_three", "error": "Sen Rikyu Phase 3 runtime is not configured."}
	return main.sen_rikyu_phase_three_runtime.complete_with_ability(ability_id, ensure_run_state(main))

func ending_read_model(main) -> Dictionary:
	if main.ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	return main.ending_route_runtime.evaluate(ensure_run_state(main))

func record_ending_to_meta(main, meta_state, read_model := {}) -> Dictionary:
	if main.ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	var model: Dictionary = read_model
	if model.is_empty():
		var evaluated: Dictionary = ending_read_model(main)
		if not evaluated.ok:
			return evaluated
		model = evaluated.read_model
	return main.ending_route_runtime.record_to_meta(model, meta_state)

func request_new_run_after_credits(main, read_model: Dictionary) -> Dictionary:
	if main.ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	return main.ending_route_runtime.request_new_run_after_credits(read_model)

func sen_rikyu_phase_two_accepts_command(main, command) -> bool:
	return main.sen_rikyu_phase_two_runtime != null \
		and main.sen_rikyu_phase_two_runtime.to_projection().arena_state == SenRikyuPhaseTwoRuntime.ARENA_COMBAT \
		and command is GameCommand \
		and command.type in [GameCommand.Type.ATTACK, GameCommand.Type.DODGE, GameCommand.Type.CAST_ABILITY]

func handle_sen_rikyu_phase_two_action(main, command: GameCommand) -> bool:
	if main.player == null:
		return false
	match command.type:
		GameCommand.Type.ATTACK:
			if main.player.combat_state == null or main.player.resources == null:
				return false
			return bool(main.sen_rikyu_phase_two_runtime.handle_player_attack(main.player.combat_state, main.player.resources.ki).ok)
		GameCommand.Type.DODGE:
			return main.player.combat_state != null and bool(main.sen_rikyu_phase_two_runtime.handle_player_dodge(main.player.combat_state).ok)
		GameCommand.Type.CAST_ABILITY:
			if main.player.ability_runtime == null or main.player.resources == null:
				return false
			var context := {
				"source_id": main.player.get_combat_id() if main.player.has_method("get_combat_id") else "player",
				"resources": main.player.resources,
				"tail_query": main.player.ability_tail_query,
				"time_state": main.player.ability_time_state,
				"tea_effect_query": main.tea_service,
				"direction": Vector2(command.direction).normalized() if command.direction != Vector2i.ZERO else Vector2.RIGHT
			}
			var cast_result: Dictionary = main.sen_rikyu_phase_two_runtime.cast_player_ability(main.player.ability_runtime, command.slot, context)
			if cast_result.ok:
				main._sync_run_runtime_state()
			return bool(cast_result.ok)
	return false

func record_boss_core_tea_ware_rewards(main, resolution_event: Dictionary) -> Dictionary:
	if main.core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	return main.core_tea_ware_collection.record_boss_resolution_rewards(resolution_event, ensure_run_state(main))

func configure_dungeon_runtime(main, progression_state, completion_resolver: Callable, additional_reward_hook := Callable()) -> Dictionary:
	if main.core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	var state := ensure_run_state(main)
	main.dungeon_runtime = DungeonRuntime.new()
	var reward_hook := func(clear_event: Dictionary) -> Dictionary:
		var active_state := ensure_run_state(main)
		var core_preflight: Dictionary = main.core_tea_ware_collection.validate_boss_resolution_rewards(clear_event, active_state)
		if not core_preflight.ok:
			return core_preflight
		if additional_reward_hook.is_valid():
			var normalized: Dictionary = main._normalize_reward_hook_result(additional_reward_hook.call(clear_event.duplicate(true)))
			if not normalized.ok:
				return normalized
		return record_boss_core_tea_ware_rewards(main, clear_event)
	return main.dungeon_runtime.configure(state, progression_state, completion_resolver, reward_hook)

func equip_default_playable_ability(main) -> Dictionary:
	if main.player == null or main.player.ability_runtime == null:
		return {"ok": true, "reason": "missing_player_ability_runtime"}
	if not main.player.ability_runtime.equipped_ability_id(0).is_empty():
		return {"ok": true, "state": "already_equipped"}
	var candidates: Dictionary = main.player.ability_runtime.ability_candidates({"tail_query": main})
	if not candidates.ok:
		return candidates
	var ids: Array = candidates.get("ability_ids", [])
	if ids.is_empty():
		return {"ok": false, "reason": "missing_playable_ability", "error": "No current-tail playable ability exists."}
	return main.player.equip_ability(0, String(ids[0]), main)

func targets_for_ability(main, source, definition, direction: Vector2) -> Array:
	var targets := []
	for enemy in main._combat_targets():
		if ability_target_is_in_range(source, definition, direction, enemy, main._runtime_tile_size()):
			targets.append(enemy)
	return targets

func ability_target_is_in_range(source, definition, direction: Vector2, target, tile_size: float) -> bool:
	if source == null or target == null:
		return false
	var source_position := Vector2(source.global_position) if source is Node2D else Vector2.ZERO
	var target_position := Vector2(target.global_position) if target is Node2D else Vector2.ZERO
	var offset := target_position - source_position
	var range_pixels := maxf(float(definition.range_tiles), 0.0) * tile_size
	if range_pixels > 0.0 and offset.length() > range_pixels:
		return false
	var aim := direction.normalized() if direction != Vector2.ZERO else offset.normalized()
	return aim == Vector2.ZERO or offset == Vector2.ZERO or offset.normalized().dot(aim) >= 0.35

func ensure_biome_progression_state(main) -> Dictionary:
	if main.biome_progression_state != null:
		return {"ok": true, "progression_state": main.biome_progression_state}
	var result: Dictionary = BiomeProgressionState.from_catalog(main.catalog, main.run_state)
	if result.ok:
		main.biome_progression_state = result.progression_state
	return result

func ensure_playable_dungeon_runtime(main) -> Dictionary:
	var progression_result := ensure_biome_progression_state(main)
	if not progression_result.ok:
		main._dungeon_debug("진행 상태 준비 실패: %s" % progression_result)
		return progression_result
	if main.dungeon_runtime != null:
		return {"ok": true, "runtime": main.dungeon_runtime}
	return configure_dungeon_runtime(main, main.biome_progression_state, func(payload: Dictionary, _projection: Dictionary) -> bool:
		return main._dungeon_completion_objective_met(payload))
