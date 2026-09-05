extends RefCounted
class_name RunBootstrapCoordinator

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const MemoryTeaCutsceneRuntime = preload("res://src/narrative/memory_tea_cutscene_runtime.gd")
const MetaCodexCommandRuntime = preload("res://src/meta/meta_codex_command_runtime.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const RunRuntimeStateBinder = preload("res://src/save/run_runtime_state_binder.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const RunServiceFactory = preload("res://src/main/run_service_factory.gd")
const RunStartEventSelector = preload("res://src/narrative/run_start_event_selector.gd")
const RunState = preload("res://src/save/run_state.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")
const TeaBrewingCommandRuntime = preload("res://src/tea/tea_brewing_command_runtime.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

class Ports:
	var get_catalog: Callable
	var get_run_state: Callable
	var set_run_state: Callable
	var get_save_store: Callable
	var get_run_runtime_state_binder: Callable
	var set_run_runtime_state_binder: Callable
	var runtime_state_entries: Callable
	var ensure_playable_dungeon_runtime: Callable
	var prepare_runtime_state_aliases_for_biome: Callable
	var configure_acquisition_for_generated_world: Callable
	var ensure_saved_world_has_teleport_landmark: Callable
	var connect_acquisition_combat_source: Callable
	var render_generated_world: Callable
	var dungeon_runtime_is_active: Callable
	var restore_dungeon_map_from_runtime: Callable
	var record_current_map_discovery: Callable
	var configure_game_hud: Callable
	var get_repair_interaction_service: Callable
	var get_time_state: Callable
	var get_combat_dummy: Callable
	var get_player: Callable
	var get_generated_world: Callable
	var set_generated_world: Callable
	var set_biome_map_previews: Callable
	var set_biome_progression_state: Callable
	var set_inventory: Callable
	var set_equipment: Callable
	var set_tea_service: Callable
	var set_time_state: Callable
	var set_crafting_service: Callable
	var set_facility_placement_service: Callable
	var set_repair_interaction_service: Callable
	var set_consumable_service: Callable
	var set_core_tea_ware_collection: Callable
	var set_final_room_state_builder: Callable
	var set_sen_rikyu_phase_one_runtime: Callable
	var set_sen_rikyu_phase_two_runtime: Callable
	var set_sen_rikyu_phase_three_runtime: Callable
	var set_ending_route_runtime: Callable
	var set_inventory_command_runtime: Callable
	var set_map_read_model_builder: Callable
	var set_tea_brewing_command_runtime: Callable
	var set_meta_codex_command_runtime: Callable
	var set_memory_tea_cutscene_runtime: Callable
	var set_narrative_runtime: Callable
	var set_run_start_event_selector: Callable
	var clear_active_tea_drink_action: Callable
	var tea_brewing_context: Callable
	var current_run_state_snapshot: Callable
	var current_meta_state_snapshot: Callable
	var on_tea_drink_completed: Callable
	var get_run_lifecycle_service: Callable
	var get_inventory: Callable
	var activate_run_state: Callable
	var show_the_end_and_return_to_start: Callable
	var push_error: Callable

var _ports: Ports
var _fresh_run_seed: int

func _init(ports: Ports, fresh_run_seed: int) -> void:
	_ports = ports
	_fresh_run_seed = fresh_run_seed

func ready(main) -> void:
	main._create_loading_overlay()
	main._set_loading_status("게임 데이터 불러오는 중…")
	await main.get_tree().process_frame
	main._configure_audio_feedback()
	main._consume_start_mode()
	main._set_loading_status("입력 장치 연결 중…")
	await main.get_tree().process_frame
	main.catalog = DataCatalog.new()
	main._set_loading_status("콘텐츠 카탈로그 준비 중…")
	await main.get_tree().process_frame
	var result: Dictionary = main.catalog.load_from_directory("res://data/generated")
	if not result.ok:
		main.push_error(result.error)
		return
	main._set_loading_status("저장 데이터 확인 중…")
	await main.get_tree().process_frame
	var loaded_run: Dictionary = main.load_or_create_run_state()
	if not loaded_run.ok:
		main.push_error(loaded_run.error)
		return
	main._set_loading_status("게임 시스템 준비 중…")
	await main.get_tree().process_frame
	var runtime_result: Dictionary = main._configure_run_services(main.catalog)
	if not runtime_result.ok:
		main.push_error(runtime_result.error)
		return
	var cheat_result: Dictionary = main._apply_cheat_start_inventory()
	main._set_loading_status("플레이어와 전투 준비 중…")
	await main.get_tree().process_frame
	if not cheat_result.ok:
		main.push_error(cheat_result.error)
		return
	var combat_result: Dictionary = configure_combat_lifecycle(main)
	if not combat_result.ok:
		main.push_error(combat_result.error)
		return
	if main.run_state == null:
		main.run_state = RunState.new()
	main.run_state.data_version = main.catalog.data_version
	if main.run_state.seed == 0:
		main.run_state.seed = main.DEFAULT_RUN_SEED
	main._set_loading_status("%s 월드 생성 중…" % main._loading_biome_label())
	await main.get_tree().process_frame
	main._set_loading_status("%s 바이옴 지형·오브젝트 배치 중…" % main._loading_biome_label())
	await main.get_tree().process_frame
	var world_result: Dictionary = main._configure_world_for_current_run()
	if not world_result.ok:
		main.push_error(world_result.error)
		return
	main._set_loading_status("카메라와 HUD 준비 중…")
	await main.get_tree().process_frame
	if bool(cheat_result.get("applied", false)):
		main._normalize_cheat_progression_state()
		var save_result: Dictionary = main.save_current_run()
		if not save_result.ok:
			main.push_error(save_result.error)
			return
	main._maybe_show_run_start_event()
	main._clear_loading_overlay()

func configure_combat_lifecycle(main) -> Dictionary:
	var player_combat_result: Dictionary = main.player.configure_combat(main.catalog)
	if not player_combat_result.ok:
		return player_combat_result
	if main.run_state != null and not main.run_state.player_resources.is_empty():
		var resource_restore: Dictionary = main.player.resources.load_snapshot(main.run_state.player_resources)
		if not resource_restore.ok:
			return resource_restore
	connect_player_feedback_signals(main)
	var lifecycle_result: Dictionary = RunLifecycleService.from_catalog(main.catalog)
	if not lifecycle_result.ok:
		return lifecycle_result
	main.run_lifecycle_service = lifecycle_result.run_lifecycle_service
	if not main.player.resources.hp_depleted.is_connected(main._on_player_hp_depleted):
		main.player.resources.hp_depleted.connect(main._on_player_hp_depleted)
	var dummy_result: Dictionary = main.combat_dummy.configure_combat(main.catalog, main.player, main.player.combat_config)
	if not dummy_result.ok:
		return dummy_result
	if main.player.has_method("configure_ability_context"):
		main.player.configure_ability_context(main, main.time_state, main, main.tea_service)
		var ability_result: Dictionary = main._equip_default_playable_ability()
		if not ability_result.ok:
			return ability_result
	if main.combat_dummy.has_signal("defeat_event") and not main.combat_dummy.is_connected("defeat_event", Callable(main, "_on_combat_dummy_defeated")):
		main.combat_dummy.connect("defeat_event", Callable(main, "_on_combat_dummy_defeated"))
	main._connect_combat_sfx_source(main.combat_dummy)
	if main.player.has_signal("grid_step_finished") and not main.player.is_connected("grid_step_finished", Callable(main, "_on_player_grid_step_finished")):
		main.player.connect("grid_step_finished", Callable(main, "_on_player_grid_step_finished"))
	return {"ok": true}

func connect_player_feedback_signals(main) -> void:
	var callbacks := {
		&"attack_started": Callable(main, "_on_player_attack_feedback"),
		&"ability_cast": Callable(main, "_on_player_activity_feedback"),
		&"damage_received": Callable(main, "_on_player_damage_feedback"),
		&"dodge_started": Callable(main, "_on_player_dodge_feedback"),
		&"grid_step_blocked": Callable(main, "_on_player_grid_step_blocked")
	}
	for signal_name in callbacks:
		var callback: Callable = callbacks[signal_name]
		if main.player.has_signal(signal_name) and not main.player.is_connected(signal_name, callback):
			main.player.connect(signal_name, callback)

func configure_world_for_current_run() -> Dictionary:
	var catalog = _call_object(_ports.get_catalog)
	var run_state: RunState = _call_object(_ports.get_run_state)
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		return progression_result
	_call_void(_ports.set_biome_progression_state, [progression_result.progression_state])
	var dungeon_runtime_result := _call_dictionary(_ports.ensure_playable_dungeon_runtime)
	if not dungeon_runtime_result.ok:
		return dungeon_runtime_result
	var projection: Dictionary = progression_result.progression_state.to_projection()
	var current_biome_id := String(projection.get("current_biome_id", ""))
	var current_biome: Dictionary = catalog.find_by_id("biomes", current_biome_id)
	if current_biome.is_empty():
		return {"ok": false, "reason": "missing_current_biome", "error": "No current biome data loaded for %s." % current_biome_id}
	_call_void(_ports.prepare_runtime_state_aliases_for_biome, [current_biome_id])
	var generated_world := _generate_world_for_biome(generator, current_biome, projection)
	if not generated_world.get("ok", false):
		return {"ok": false, "reason": "world_generation_failed", "error": String(generated_world.get("failure_reason", "World generation failed."))}
	generated_world["renderer_input"] = WorldRendererProjection.new().project(generated_world["world_data"], projection)
	_call_void(_ports.set_generated_world, [generated_world])
	_call_void(_ports.set_biome_map_previews, [_biome_map_previews(generator, current_biome_id, projection)])
	var combat_pool_result := configure_overworld_combat_from_spawn_pool()
	if not combat_pool_result.ok:
		return combat_pool_result
	var acquisition_result := _call_dictionary(_ports.configure_acquisition_for_generated_world)
	if not acquisition_result.ok:
		return acquisition_result
	if bool(_call_value(_ports.ensure_saved_world_has_teleport_landmark, false)):
		var migration_save := save_current_run(_ports.current_run_state_snapshot)
		if not migration_save.ok:
			_call_void(_ports.push_error, [String(migration_save.get("error", "Failed to save teleport landmark migration."))])
	var drop_connection := _call_dictionary(_ports.connect_acquisition_combat_source, [_call_object(_ports.get_combat_dummy)])
	if not drop_connection.ok:
		return drop_connection
	_call_void(_ports.render_generated_world, [_call_dictionary(_ports.get_generated_world)])
	if bool(_call_value(_ports.dungeon_runtime_is_active, false)):
		_call_void(_ports.restore_dungeon_map_from_runtime)
	_call_void(_ports.record_current_map_discovery)
	_call_void(_ports.configure_game_hud)
	return {"ok": true}

func configure_overworld_combat_from_spawn_pool() -> Dictionary:
	var combat_dummy = _call_object(_ports.get_combat_dummy)
	var generated_world := _call_dictionary(_ports.get_generated_world)
	var catalog = _call_object(_ports.get_catalog)
	var player = _call_object(_ports.get_player)
	var run_state: RunState = _call_object(_ports.get_run_state)
	if combat_dummy == null or not combat_dummy.has_method("configure_combat"):
		generated_world["active_monster_spawn"] = {
			"source": "unconfigured_combat_source",
			"reason": "combat source does not expose configure_combat"
		}
		_call_void(_ports.set_generated_world, [generated_world])
		return {"ok": true, "source": "unconfigured_combat_source"}
	var selected_entry := selected_overworld_spawn_entry(generated_world)
	if selected_entry.is_empty():
		combat_dummy.monster_id = "road_bandit"
		var fallback_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
		if not fallback_result.ok:
			return fallback_result
		generated_world["active_monster_spawn"] = {
			"source": "fallback",
			"monster_id": combat_dummy.monster_id,
			"reason": "empty_or_invalid_spawn_pool"
		}
		_call_void(_ports.set_generated_world, [generated_world])
		return {"ok": true, "source": "fallback", "combat": fallback_result}
	combat_dummy.monster_id = String(selected_entry.get("monster_id", ""))
	var spawn_context := {
		"combat_id": "%s_%s_%d" % [
			String(selected_entry.get("id", combat_dummy.monster_id)),
			String(generated_world.get("time_phase", "")),
			int(run_state.seed) if run_state != null else 0
		]
	}
	var behavior_type_override := String(selected_entry.get("behavior_type_override", ""))
	if not behavior_type_override.is_empty():
		spawn_context["behavior_type_override"] = behavior_type_override
	var pool_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config, spawn_context)
	if not pool_result.ok:
		combat_dummy.monster_id = "road_bandit"
		var fallback_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
		if not fallback_result.ok:
			return fallback_result
		generated_world["active_monster_spawn"] = {
			"source": "fallback",
			"monster_id": combat_dummy.monster_id,
			"reason": "invalid_spawn_pool_entry",
			"entry": selected_entry.duplicate(true)
		}
		_call_void(_ports.set_generated_world, [generated_world])
		return {"ok": true, "source": "fallback", "combat": fallback_result, "invalid_entry": selected_entry.duplicate(true)}
	generated_world["active_monster_spawn"] = {
		"source": "monster_spawn_pool",
		"entry": selected_entry.duplicate(true),
		"monster_id": combat_dummy.monster_id,
		"behavior_type": String(pool_result.get("behavior_type", "")),
		"spawn_context": spawn_context.duplicate(true)
	}
	_call_void(_ports.set_generated_world, [generated_world])
	return {"ok": true, "source": "monster_spawn_pool", "entry": selected_entry.duplicate(true), "combat": pool_result}

func selected_overworld_spawn_entry(generated_world: Dictionary) -> Dictionary:
	var pool: Dictionary = generated_world.get("monster_spawn_pool", {})
	var entries = pool.get("entries", [])
	if not entries is Array or entries.is_empty():
		return {}
	for entry in entries:
		if entry is Dictionary and bool(entry.get("rare", false)) and not String(entry.get("monster_id", "")).is_empty():
			return entry.duplicate(true)
	for entry in entries:
		if entry is Dictionary and not String(entry.get("monster_id", "")).is_empty():
			return entry.duplicate(true)
	return {}

func save_current_run(snapshot: Callable) -> Dictionary:
	var save_store = _call_object(_ports.get_save_store)
	var run_state: RunState = _call_object(_ports.get_run_state)
	if save_store == null:
		return {"ok": false, "reason": "missing_save_store", "error": "Save store is not configured."}
	var result: Dictionary = save_store.save_run(snapshot.call())
	if not bool(result.get("ok", false)) and String(result.get("reason", "")) == "stale_run_save":
		run_state.lifecycle_epoch += 1
		result = save_store.save_run(snapshot.call())
	return result

func configure_run_services(loaded_catalog) -> Dictionary:
	var services := RunServiceFactory.create(loaded_catalog)
	if not services.ok:
		return services
	if _call_object(_ports.get_run_runtime_state_binder) == null:
		_call_void(_ports.set_run_runtime_state_binder, [RunRuntimeStateBinder.new()])
	_call_void(_ports.set_inventory, [services.inventory])
	_call_void(_ports.set_equipment, [services.equipment])
	_call_void(_ports.set_tea_service, [services.tea_service])
	_call_void(_ports.set_time_state, [services.time_state])
	_call_void(_ports.set_crafting_service, [services.crafting_service])
	_call_void(_ports.set_facility_placement_service, [services.facility_placement_service])
	_call_void(_ports.set_repair_interaction_service, [services.repair_interaction_service])
	_call_void(_ports.set_consumable_service, [services.consumable_service])
	_call_void(_ports.set_core_tea_ware_collection, [services.core_tea_ware_collection])
	_call_void(_ports.set_final_room_state_builder, [services.final_room_state_builder])
	_call_void(_ports.clear_active_tea_drink_action)
	_call_void(_ports.set_sen_rikyu_phase_one_runtime, [null])
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("events", SenRikyuPhaseOneRuntime.EVENT_ID).is_empty():
		var phase_one_result: Dictionary = SenRikyuPhaseOneRuntime.from_catalog(loaded_catalog, services.tea_service)
		if not phase_one_result.ok:
			return phase_one_result
		_call_void(_ports.set_sen_rikyu_phase_one_runtime, [phase_one_result.runtime])
	_call_void(_ports.set_sen_rikyu_phase_two_runtime, [null])
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("bosses", SenRikyuPhaseTwoRuntime.BOSS_ID).is_empty():
		var phase_two_result: Dictionary = SenRikyuPhaseTwoRuntime.from_catalog(loaded_catalog)
		if not phase_two_result.ok:
			return phase_two_result
		_call_void(_ports.set_sen_rikyu_phase_two_runtime, [phase_two_result.runtime])
	_call_void(_ports.set_sen_rikyu_phase_three_runtime, [null])
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("events", SenRikyuPhaseThreeRuntime.EVENT_ID).is_empty():
		var phase_three_result: Dictionary = SenRikyuPhaseThreeRuntime.from_catalog(loaded_catalog)
		if not phase_three_result.ok:
			return phase_three_result
		_call_void(_ports.set_sen_rikyu_phase_three_runtime, [phase_three_result.runtime])
	_call_void(_ports.set_ending_route_runtime, [null])
	var ending_result: Dictionary = EndingRouteRuntime.from_catalog(loaded_catalog)
	if ending_result.ok:
		_call_void(_ports.set_ending_route_runtime, [ending_result.runtime])
	var inventory_command_runtime := InventoryCommandRuntime.new()
	var inventory_command_result: Dictionary = inventory_command_runtime.configure(services.inventory, services.equipment, services.consumable_service, loaded_catalog.data_version)
	if not inventory_command_result.ok:
		return inventory_command_result
	_call_void(_ports.set_inventory_command_runtime, [inventory_command_runtime])
	var map_read_model_builder := MapReadModelBuilder.new()
	var map_result: Dictionary = map_read_model_builder.configure(loaded_catalog.data_version)
	if not map_result.ok:
		return map_result
	_call_void(_ports.set_map_read_model_builder, [map_read_model_builder])
	var tea_brewing_command_runtime := TeaBrewingCommandRuntime.new()
	var tea_brewing_result: Dictionary = tea_brewing_command_runtime.configure(services.tea_service, services.inventory, services.equipment, _ports.tea_brewing_context, loaded_catalog.data_version)
	if not tea_brewing_result.ok:
		return tea_brewing_result
	_call_void(_ports.set_tea_brewing_command_runtime, [tea_brewing_command_runtime])
	var meta_codex_command_runtime := MetaCodexCommandRuntime.new()
	var meta_codex_result: Dictionary = meta_codex_command_runtime.configure(loaded_catalog, _ports.current_run_state_snapshot, _ports.current_meta_state_snapshot, loaded_catalog.data_version)
	if not meta_codex_result.ok:
		return meta_codex_result
	_call_void(_ports.set_meta_codex_command_runtime, [meta_codex_command_runtime])
	if not services.tea_service.drink_completed.is_connected(_ports.on_tea_drink_completed):
		services.tea_service.drink_completed.connect(_ports.on_tea_drink_completed)
	var memory_tea_cutscene_runtime := MemoryTeaCutsceneRuntime.new()
	var memory_runtime_result: Dictionary = memory_tea_cutscene_runtime.configure(loaded_catalog.data_version)
	if not memory_runtime_result.ok:
		return memory_runtime_result
	_call_void(_ports.set_memory_tea_cutscene_runtime, [memory_tea_cutscene_runtime])
	var run_state: RunState = _call_object(_ports.get_run_state)
	if run_state != null:
		var hydrate_result: Dictionary = _call_object(_ports.get_run_runtime_state_binder).hydrate_from_run_state(run_state, _call_array(_ports.runtime_state_entries))
		if not hydrate_result.ok:
			return hydrate_result
	var narrative_runtime := NarrativeRuntime.new()
	var narrative_result: Dictionary = narrative_runtime.from_catalog(loaded_catalog)
	if not narrative_result.ok:
		return narrative_result
	_call_void(_ports.set_narrative_runtime, [narrative_runtime])
	var run_start_event_selector := RunStartEventSelector.new()
	var start_selector_result: Dictionary = run_start_event_selector.configure(loaded_catalog)
	if not start_selector_result.ok:
		return start_selector_result
	_call_void(_ports.set_run_start_event_selector, [run_start_event_selector])
	return {"ok": true}

func on_player_hp_depleted() -> Dictionary:
	var run_lifecycle_service = _call_object(_ports.get_run_lifecycle_service)
	var player = _call_object(_ports.get_player)
	if run_lifecycle_service == null:
		return {"ok": false, "reason": "missing_run_lifecycle", "error": "Run lifecycle service is not configured."}
	var result: Dictionary = run_lifecycle_service.resolve_lethal_hp(
		player.resources,
		_call_object(_ports.get_inventory),
		player.combat_state,
		player.get_combat_id()
	)
	if not result.ok:
		_call_void(_ports.push_error, [result.error])
		return result
	if String(result.get("state", "")) != "death_pending":
		return result
	var replacement := replace_confirmed_dead_run()
	if not replacement.ok:
		_call_void(_ports.push_error, [replacement.error])
	return replacement

func replace_confirmed_dead_run() -> Dictionary:
	var run_lifecycle_service = _call_object(_ports.get_run_lifecycle_service)
	var save_store = _call_object(_ports.get_save_store)
	var run_state: RunState = _call_object(_ports.get_run_state)
	var confirmed: Dictionary = run_lifecycle_service.confirm_death(save_store, run_state)
	if not confirmed.ok:
		return confirmed
	if bool(confirmed.get("preserved_newer_run", false)):
		var preserved_run = confirmed.get("current_run_state")
		if not preserved_run is RunState:
			var loaded: Dictionary = save_store.load_run()
			if not loaded.ok:
				return loaded
			preserved_run = loaded.run_state
		var preserved_activation := _call_dictionary(_ports.activate_run_state, [preserved_run])
		if not preserved_activation.ok:
			return preserved_activation
		return {
			"ok": true,
			"state": "preserved_run_activated",
			"preserved_newer_run": true,
			"invalidated_lifecycle_epoch": int(confirmed.get("invalidated_lifecycle_epoch", 0)),
			"current_lifecycle_epoch": preserved_run.lifecycle_epoch
		}
	var fresh_run: RunState = run_lifecycle_service.create_fresh_run_after_confirmed_death(
		int(confirmed.invalidated_lifecycle_epoch),
		_fresh_run_seed
	)
	var save_result: Dictionary = save_store.save_run(fresh_run)
	if not save_result.ok:
		return save_result
	_call_void(_ports.show_the_end_and_return_to_start)
	return {
		"ok": true,
		"state": "fresh_run",
		"invalidated_lifecycle_epoch": int(confirmed.invalidated_lifecycle_epoch),
		"lifecycle_epoch": fresh_run.lifecycle_epoch
	}

func _biome_map_previews(generator: WorldGenerator, current_biome_id: String, projection: Dictionary) -> Dictionary:
	var catalog = _call_object(_ports.get_catalog)
	var previews := {}
	for biome_definition in catalog.get_definitions("biomes"):
		var preview_id := String(biome_definition.get("id", ""))
		if preview_id.is_empty() or preview_id == current_biome_id:
			continue
		var preview := _generate_world_for_biome(generator, biome_definition, projection)
		if bool(preview.get("ok", false)):
			preview["renderer_input"] = WorldRendererProjection.new().project(preview["world_data"], projection)
			previews[preview_id] = preview
	return previews

func _generate_world_for_biome(generator: WorldGenerator, biome_definition: Dictionary, projection: Dictionary) -> Dictionary:
	var catalog = _call_object(_ports.get_catalog)
	var run_state: RunState = _call_object(_ports.get_run_state)
	return generator.generate(run_state.seed, catalog.data_version, biome_definition, catalog.get_definitions("balance"), catalog.get_definitions("items"), _world_generation_options(projection))

func _world_generation_options(projection: Dictionary) -> Dictionary:
	var catalog = _call_object(_ports.get_catalog)
	var repair_interaction_service = _call_object(_ports.get_repair_interaction_service)
	var time_state = _call_object(_ports.get_time_state)
	return {
		"progression_projection": projection,
		"monster_definitions": catalog.get_definitions("monsters"),
		"dungeon_definitions": catalog.get_definitions("dungeons"),
		"boss_character_definitions": catalog.get_definitions("characters"),
		"repair_interaction_targets": repair_interaction_service.world_generation_targets_for_biome(String(projection.get("current_biome_id", ""))) if repair_interaction_service != null else [],
		"time_phase": String(time_state.phase) if time_state != null else "day"
	}

func _call_object(callback: Callable):
	if not callback.is_valid():
		return null
	return callback.call()

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	var value = _call_value(callback, {}, arguments)
	return value if typeof(value) == TYPE_DICTIONARY else {}

func _call_array(callback: Callable, arguments := []) -> Array:
	var value = _call_value(callback, [], arguments)
	return value if value is Array else []

func _call_value(callback: Callable, default_value = null, arguments := []):
	if not callback.is_valid():
		return default_value
	return callback.callv(arguments)

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)
