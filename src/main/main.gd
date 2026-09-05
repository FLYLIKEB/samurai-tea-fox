extends Node2D

const PlayerItemActions = preload("res://src/main/player_item_actions.gd")

const RunServiceFactory = preload("res://src/main/run_service_factory.gd")

const WorldPresentation = preload("res://src/main/world_presentation.gd")

const CheatStartConfigurator = preload("res://src/main/cheat_start_configurator.gd")
const AcquisitionDefinitionBuilder = preload("res://src/main/acquisition_definition_builder.gd")

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const MemoryTeaCutsceneRuntime = preload("res://src/narrative/memory_tea_cutscene_runtime.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const RunStartEventSelector = preload("res://src/narrative/run_start_event_selector.gd")
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const TeaBrewingCommandRuntime = preload("res://src/tea/tea_brewing_command_runtime.gd")
const MetaCodexCommandRuntime = preload("res://src/meta/meta_codex_command_runtime.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const RunRuntimeStateBinder = preload("res://src/save/run_runtime_state_binder.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")
const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const FacilityPlacementSession = preload("res://src/main/facility_placement_session.gd")
const FacilityPlacementPreview = preload("res://src/presentation/facility_placement_preview.gd")
const AcquisitionEffect = preload("res://src/presentation/acquisition_effect.gd")
const MainSceneOverlays = preload("res://src/main/main_scene_overlays.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")
const DungeonDefinitionResolver = preload("res://src/main/dungeon_definition_resolver.gd")
const DungeonLayoutBuilder = preload("res://src/main/dungeon_layout_builder.gd")
const NarrativeSession = preload("res://src/main/narrative_session.gd")
const PointerRouteController = preload("res://src/main/pointer_route_controller.gd")
const SpatialInteractionResolver = preload("res://src/main/spatial_interaction_resolver.gd")

static var DEFAULT_RUN_SEED := RuntimeConstants.int_value("world.default_seed")
const FRESH_RUN_SEED := 0
static var POINTER_MOVE_STOP_DISTANCE_PIXELS := RuntimeConstants.float_value("input.pointer_stop_distance_pixels")
const START_MODE_META := "muchau_start_mode"
const START_MODE_NEW := "new"
const START_MODE_CHEAT := "cheat"
const START_MODE_RESUME := "resume"
const DUNGEON_DEBUG_LOGGING := true
const DUNGEON_TILESET_SOURCE_ID := "terrain_dungeon_mossy_dojo_tileset"
const DUNGEON_BOSS_OWNER_ID = DungeonLayoutBuilder.BOSS_OWNER_ID
const START_SCREEN_SCENE_PATH := "res://scenes/ui/start_screen.tscn"
static var THE_END_DURATION_SECONDS := RuntimeConstants.float_value("narrative.the_end_duration_seconds")

@onready var player = $Player
@onready var combat_dummy = $CombatDummy
@onready var world_visuals: Node2D = $WorldVisuals
@onready var world_tone_overlay = $WorldToneOverlay
@onready var game_hud = $GameHud

var catalog
var inventory
var equipment
var inventory_command_runtime
var map_read_model_builder
var tea_service
var tea_brewing_command_runtime
var meta_codex_command_runtime
var crafting_service
var facility_placement_service
var consumable_service
var time_state
var core_tea_ware_collection
var final_room_state_builder
var sen_rikyu_phase_one_runtime
var sen_rikyu_phase_two_runtime
var sen_rikyu_phase_three_runtime
var memory_tea_cutscene_runtime
var narrative_runtime
var run_start_event_selector
var ending_route_runtime
var acquisition_service
var repair_interaction_service
var dungeon_runtime
var run_lifecycle_service
var run_runtime_state_binder := RunRuntimeStateBinder.new()
var dungeon_definition_resolver := DungeonDefinitionResolver.new()
var dungeon_layout_builder := DungeonLayoutBuilder.new()
var narrative_session := NarrativeSession.new()
var biome_progression_state
var save_store = SaveStore.new()
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
var _biome_map_previews: Dictionary = {}
var world_render_result: Dictionary = {}
var _overworld_generated_world: Dictionary = {}
var _overworld_world_data_snapshot: Dictionary = {}
var _overworld_player_cell := Vector2i.ZERO
var _overworld_combat_dummy_cell := Vector2i.ZERO
var _overworld_combat_dummy = null
var _overworld_combat_dummy_state: Dictionary = {}
var _in_dungeon_map := false
var _dungeon_resources: Array = []
var _dungeon_enemy_nodes: Array = []
var _desktop_adapter := DesktopCommandAdapter.new()
var _command_dispatcher := CommandDispatcher.new()
var _movement_selector := MovementCommandSelector.new()
var _pointer_route_controller := PointerRouteController.new()
var _spatial_resolver := SpatialInteractionResolver.new()
var _has_pointer_move_target: bool:
	get:
		return _pointer_route_controller.has_pointer_move_target
	set(value):
		_pointer_route_controller.has_pointer_move_target = value
var _pointer_move_target_world: Vector2:
	get:
		return _pointer_route_controller.pointer_move_target_world
	set(value):
		_pointer_route_controller.pointer_move_target_world = value
var _pointer_move_route: Array:
	get:
		return _pointer_route_controller.pointer_move_route
	set(value):
		_pointer_route_controller.pointer_move_route = value
var _pending_pointer_interaction_target_id: String:
	get:
		return _pointer_route_controller.pending_pointer_interaction_target_id
	set(value):
		_pointer_route_controller.pending_pointer_interaction_target_id = value
var _pending_pointer_interaction_cell: Vector2i:
	get:
		return _pointer_route_controller.pending_pointer_interaction_cell
	set(value):
		_pointer_route_controller.pending_pointer_interaction_cell = value
var _facility_placement_session := FacilityPlacementSession.new()
var _pending_facility_placement: Dictionary:
	get:
		return _facility_placement_session.pending_placement
	set(value):
		_facility_placement_session.pending_placement = value
var _pending_facility_origin: Vector2i:
	get:
		return _facility_placement_session.pending_origin
	set(value):
		_facility_placement_session.pending_origin = value
var _pending_facility_result: Dictionary:
	get:
		return _facility_placement_session.pending_result
	set(value):
		_facility_placement_session.pending_result = value
var _pending_facility_rotation: int:
	get:
		return _facility_placement_session.pending_rotation
	set(value):
		_facility_placement_session.pending_rotation = int(value)
var _facility_placement_preview: FacilityPlacementPreview
var _preview_asset_catalog := AssetCatalog.new()
var _preview_asset_catalog_ready := false
var _preview_content_image_map_ready := false
var feedback_beep_count := 0
var _sfx_router: SfxEventRouter
var _enemy_turn_queued := false
var _active_narrative_event_id: String:
	get:
		return narrative_session.active_event_id
	set(value):
		narrative_session.active_event_id = value
var _active_narrative_node_id: String:
	get:
		return narrative_session.active_node_id
	set(value):
		narrative_session.active_node_id = value
var _start_mode := START_MODE_RESUME
var _force_first_run_prologue := false
var _death_transition_active := false
var _loading_label: Label
var _player_item_actions := PlayerItemActions.new(
	_sync_run_runtime_state, save_current_run, _configure_game_hud,
	_advance_time_for_turn, _queue_enemy_turn_after_player_action
)

func _ready() -> void:
	_create_loading_overlay()
	_set_loading_status("게임 데이터 불러오는 중…")
	await get_tree().process_frame
	_configure_audio_feedback()
	_consume_start_mode()
	_set_loading_status("입력 장치 연결 중…")
	await get_tree().process_frame
	catalog = DataCatalog.new()
	_set_loading_status("콘텐츠 카탈로그 준비 중…")
	await get_tree().process_frame
	var result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
		return
	_set_loading_status("저장 데이터 확인 중…")
	await get_tree().process_frame
	var loaded_run := load_or_create_run_state()
	if not loaded_run.ok:
		push_error(loaded_run.error)
		return
	_set_loading_status("게임 시스템 준비 중…")
	await get_tree().process_frame
	var runtime_result := _configure_run_services(catalog)
	if not runtime_result.ok:
		push_error(runtime_result.error)
		return
	var cheat_result := _apply_cheat_start_inventory()
	_set_loading_status("플레이어와 전투 준비 중…")
	await get_tree().process_frame
	if not cheat_result.ok:
		push_error(cheat_result.error)
		return
	var combat_lifecycle_result := _configure_combat_lifecycle()
	if not combat_lifecycle_result.ok:
		push_error(combat_lifecycle_result.error)
		return

	if run_state == null:
		run_state = RunState.new()
	run_state.data_version = catalog.data_version
	if run_state.seed == 0:
		run_state.seed = DEFAULT_RUN_SEED
	_set_loading_status("%s 월드 생성 중…" % _loading_biome_label())
	await get_tree().process_frame
	_set_loading_status("%s 바이옴 지형·오브젝트 배치 중…" % _loading_biome_label())
	await get_tree().process_frame
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		push_error(world_result.error)
	else:
		_set_loading_status("카메라와 HUD 준비 중…")
		await get_tree().process_frame
		if bool(cheat_result.get("applied", false)):
			# World/progression construction may initialize an empty run state;
			# reapply the completed-save flags after that lifecycle step.
			_normalize_cheat_progression_state()
		if bool(cheat_result.get("applied", false)):
			var cheat_save_result := save_current_run()
			if not cheat_save_result.ok:
				push_error(cheat_save_result.error)
				return
		_maybe_show_run_start_event()
		_clear_loading_overlay()

func _create_loading_overlay() -> void:
	_loading_label = MainSceneOverlays.create_loading(self)

func _set_loading_status(message: String) -> void:
	if _loading_label != null:
		_loading_label.text = message

func _clear_loading_overlay() -> void:
	var overlay := get_node_or_null("LoadingOverlay")
	if overlay != null:
		overlay.queue_free()

func _loading_biome_label() -> String:
	if catalog != null and run_state != null and catalog.has_method("find_by_id"):
		var definition: Dictionary = catalog.find_by_id("biomes", String(run_state.current_biome_id))
		var name := String(definition.get("name", ""))
		if not name.is_empty():
			return name
	return String(run_state.current_biome_id) if run_state != null and not String(run_state.current_biome_id).is_empty() else "현재"

func _configure_combat_lifecycle() -> Dictionary:
	var player_combat_result: Dictionary = player.configure_combat(catalog)
	if not player_combat_result.ok:
		return player_combat_result
	if run_state != null and not run_state.player_resources.is_empty():
		var resource_restore: Dictionary = player.resources.load_snapshot(run_state.player_resources)
		if not resource_restore.ok:
			return resource_restore
	_connect_player_feedback_signals()
	var lifecycle_result: Dictionary = RunLifecycleService.from_catalog(catalog)
	if not lifecycle_result.ok:
		return lifecycle_result
	run_lifecycle_service = lifecycle_result.run_lifecycle_service
	if not player.resources.hp_depleted.is_connected(_on_player_hp_depleted):
		player.resources.hp_depleted.connect(_on_player_hp_depleted)
	var dummy_combat_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
	if not dummy_combat_result.ok:
		return dummy_combat_result
	if player.has_method("configure_ability_context"):
		player.configure_ability_context(self, time_state, self, tea_service)
		var ability_result := _equip_default_playable_ability()
		if not ability_result.ok:
			return ability_result
	if combat_dummy.has_signal("defeat_event") and not combat_dummy.is_connected("defeat_event", Callable(self, "_on_combat_dummy_defeated")):
		combat_dummy.connect("defeat_event", Callable(self, "_on_combat_dummy_defeated"))
	_connect_combat_sfx_source(combat_dummy)
	if player.has_signal("grid_step_finished") and not player.is_connected("grid_step_finished", Callable(self, "_on_player_grid_step_finished")):
		player.connect("grid_step_finished", Callable(self, "_on_player_grid_step_finished"))
	return {"ok": true}

func _connect_player_feedback_signals() -> void:
	var signal_callbacks := {
		&"attack_started": Callable(self, "_on_player_attack_feedback"),
		&"ability_cast": Callable(self, "_on_player_activity_feedback"),
		&"damage_received": Callable(self, "_on_player_damage_feedback"),
		&"dodge_started": Callable(self, "_on_player_dodge_feedback"),
		&"grid_step_blocked": Callable(self, "_on_player_grid_step_blocked")
	}
	for signal_name in signal_callbacks:
		var callback: Callable = signal_callbacks[signal_name]
		if player.has_signal(signal_name) and not player.is_connected(signal_name, callback):
			player.connect(signal_name, callback)

func _on_player_activity_feedback(_a = null, _b = null, _c = null) -> void:
	_play_feedback_beep()

func _on_player_attack_feedback(swing: Dictionary) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_ATTACK_SWING, swing, String(swing.get("swing_id", "attack")))

func _on_player_damage_feedback(event: Dictionary, applied_damage: int) -> void:
	_interrupt_consumable_use("hit")
	_play_sfx_event(SfxEventRouter.EVENT_PLAYER_HIT, {"event": event, "applied_damage": applied_damage}, String(event.get("source_id", "player_hit")))

func _on_player_dodge_feedback(direction: Vector2, distance_pixels: float) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_DODGE, {"direction": direction, "distance_pixels": distance_pixels}, "player_dodge")

func _on_player_grid_step_blocked(from_cell: Vector2i, to_cell: Vector2i) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_INTERACT_FAIL, {"from_cell": from_cell, "to_cell": to_cell}, "grid_blocked:%s:%s" % [from_cell, to_cell])

func _on_player_grid_step_finished(cell: Vector2i) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_STEP, {"cell": cell}, "step:%s" % cell)
	_advance_time_for_turn()
	_queue_enemy_turn_after_player_action()

func _configure_world_for_current_run() -> Dictionary:
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		return progression_result
	biome_progression_state = progression_result.progression_state
	# Rehydrate the dungeon lifecycle before deciding which map to render.
	# Without this, a saved active dungeon is mistaken for an overworld run.
	var dungeon_runtime_result := _ensure_playable_dungeon_runtime()
	if not dungeon_runtime_result.ok:
		return dungeon_runtime_result
	var projection: Dictionary = biome_progression_state.to_projection()
	var current_biome_id := String(projection.get("current_biome_id", ""))
	var current_biome: Dictionary = catalog.find_by_id("biomes", current_biome_id)
	if current_biome.is_empty():
		return {"ok": false, "reason": "missing_current_biome", "error": "No current biome data loaded for %s." % current_biome_id}
	_prepare_runtime_state_aliases_for_biome(current_biome_id)
	generated_world = _generate_world_for_biome(generator, current_biome, projection)
	if not generated_world.get("ok", false):
		return {"ok": false, "reason": "world_generation_failed", "error": String(generated_world.get("failure_reason", "World generation failed."))}
	generated_world["renderer_input"] = WorldRendererProjection.new().project(generated_world["world_data"], projection)
	_biome_map_previews.clear()
	for biome_definition in catalog.get_definitions("biomes"):
		var preview_id := String(biome_definition.get("id", ""))
		if preview_id.is_empty() or preview_id == current_biome_id:
			continue
		var preview := _generate_world_for_biome(generator, biome_definition, projection)
		if bool(preview.get("ok", false)):
			preview["renderer_input"] = WorldRendererProjection.new().project(preview["world_data"], projection)
			_biome_map_previews[preview_id] = preview
	var combat_pool_result := _configure_overworld_combat_from_spawn_pool()
	if not combat_pool_result.ok:
		return combat_pool_result
	var acquisition_result := _configure_acquisition_for_generated_world()
	if not acquisition_result.ok:
		return acquisition_result
	if _ensure_saved_world_has_teleport_landmark():
		var migration_save := save_current_run()
		if not migration_save.ok:
			push_error(String(migration_save.get("error", "Failed to save teleport landmark migration.")))
	var drop_connection := _connect_acquisition_combat_source(combat_dummy)
	if not drop_connection.ok:
		return drop_connection
	_render_generated_world(generated_world)
	if _dungeon_runtime_is_active():
		_restore_dungeon_map_from_runtime()
	_record_current_map_discovery()
	_configure_game_hud()
	return {"ok": true}

func _generate_world_for_biome(generator: WorldGenerator, biome_definition: Dictionary, projection: Dictionary) -> Dictionary:
	return generator.generate(run_state.seed, catalog.data_version, biome_definition, catalog.get_definitions("balance"), catalog.get_definitions("items"), _world_generation_options(projection))

func _world_generation_options(projection: Dictionary) -> Dictionary:
	return {
		"progression_projection": projection,
		"monster_definitions": catalog.get_definitions("monsters"),
		"dungeon_definitions": catalog.get_definitions("dungeons"),
		"boss_character_definitions": catalog.get_definitions("characters"),
		"repair_interaction_targets": repair_interaction_service.world_generation_targets_for_biome(String(projection.get("current_biome_id", ""))) if repair_interaction_service != null else [],
		"time_phase": String(time_state.phase) if time_state != null else "day"
	}

func _configure_overworld_combat_from_spawn_pool() -> Dictionary:
	if combat_dummy == null or not combat_dummy.has_method("configure_combat"):
		generated_world["active_monster_spawn"] = {
			"source": "unconfigured_combat_source",
			"reason": "combat source does not expose configure_combat"
		}
		return {"ok": true, "source": "unconfigured_combat_source"}
	var selected_entry := _selected_overworld_spawn_entry()
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
		return {"ok": true, "source": "fallback", "combat": fallback_result, "invalid_entry": selected_entry.duplicate(true)}
	generated_world["active_monster_spawn"] = {
		"source": "monster_spawn_pool",
		"entry": selected_entry.duplicate(true),
		"monster_id": combat_dummy.monster_id,
		"behavior_type": String(pool_result.get("behavior_type", "")),
		"spawn_context": spawn_context.duplicate(true)
	}
	return {"ok": true, "source": "monster_spawn_pool", "entry": selected_entry.duplicate(true), "combat": pool_result}

func _selected_overworld_spawn_entry() -> Dictionary:
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

func _physics_process(_delta: float) -> void:
	if _death_transition_active:
		return
	tick_tea_runtime(_delta)
	tick_consumable_runtime(_delta)
	_update_dungeon_sign_visibility()
	if has_pending_facility_placement():
		return
	_record_current_map_discovery()
	var desktop_frame: Dictionary = _desktop_adapter.poll_frame_input()
	var desktop_command = _desktop_adapter.movement_command_from_frame(desktop_frame)
	player.submit_command(movement_command_for_current_inputs(desktop_command))
	var dungeon_interaction_handled := false
	if _desktop_adapter.frame_action_pressed(desktop_frame, "attack"):
		_dungeon_debug("E/attack 입력 감지: player_cell=%s in_dungeon=%s" % [world_cell_from_world_position(player.global_position) if player != null else "nil", _in_dungeon_map])
		dungeon_interaction_handled = _try_dungeon_interaction_from_input()
		if not dungeon_interaction_handled:
			dungeon_interaction_handled = _try_landmark_interaction_from_input()
		_dungeon_debug("E/attack 처리 결과: dungeon_handled=%s in_dungeon=%s" % [dungeon_interaction_handled, _in_dungeon_map])
		if not dungeon_interaction_handled:
			submit_desktop_action_command("attack", desktop_command.direction)
	for action in _desktop_adapter.general_front_action_names(desktop_frame):
		submit_desktop_action_command(action, desktop_command.direction)
	var tea_brewing_open := _is_hud_menu_open("tea_brewing")
	for action in _desktop_adapter.tea_brewing_action_names(desktop_frame, tea_brewing_open):
		submit_desktop_action_command(action)
	for action in _desktop_adapter.general_middle_action_names(desktop_frame, not dungeon_interaction_handled):
		submit_desktop_action_command(action, desktop_command.direction)
	for action in _desktop_adapter.menu_open_action_names(desktop_frame):
		submit_desktop_action_command(action)
	var inventory_open := _is_hud_menu_open("inventory")
	for action in _desktop_adapter.inventory_action_names(desktop_frame, inventory_open):
		var slot := _selected_inventory_slot_index() if action in ["inventory_use_selected", "inventory_equip_selected"] else 0
		submit_desktop_action_command(action, Vector2i.ZERO, slot)
	var meta_codex_open := _is_hud_menu_open("meta_codex")
	for action in _desktop_adapter.meta_codex_action_names(desktop_frame, meta_codex_open):
		submit_desktop_action_command(action)
	for action in _desktop_adapter.general_back_action_names(desktop_frame):
		submit_desktop_action_command(action)

func _unhandled_input(event) -> void:
	var handled := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world_position := world_position_from_viewport_position(event.position)
		handled = submit_pointer_interaction(mouse_world_position)
		if not handled:
			handled = submit_pointer_movement(mouse_world_position)
	elif event is InputEventScreenTouch and event.pressed:
		var touch_world_position := world_position_from_viewport_position(event.position)
		handled = submit_pointer_interaction(touch_world_position)
		if not handled:
			handled = submit_pointer_movement(touch_world_position)
	if handled:
		get_viewport().set_input_as_handled()

func submit_mobile_movement_command(command) -> bool:
	var accepted := _movement_selector.submit_mobile_command(command)
	if accepted and command.direction != Vector2i.ZERO:
		_clear_pointer_movement()
	return accepted

func submit_mobile_movement_direction(direction: Vector2i) -> bool:
	return submit_mobile_movement_command(GameCommand.new(GameCommand.Type.MOVE, direction))

func submit_mobile_action_command(command) -> bool:
	if command is GameCommand and command.type == GameCommand.Type.MOVE:
		return submit_mobile_movement_command(command)
	return submit_action_command(command)

func submit_desktop_action_command(action: String, direction := Vector2i.ZERO, slot := 0) -> bool:
	var command = _desktop_adapter.command_for_action(action, direction, slot)
	if not command is GameCommand:
		return false
	if command.type == GameCommand.Type.INTERACT and String(command.payload.get("target_id", "")).is_empty():
		return submit_player_interaction(direction)
	return submit_action_command(command)

func _is_hud_menu_open(menu_id: String) -> bool:
	return game_hud != null and game_hud.has_method("active_menu_id") and String(game_hud.active_menu_id()) == menu_id

func submit_pointer_interaction(world_position: Vector2) -> bool:
	if has_pending_facility_placement():
		_select_pending_facility_at(world_cell_from_world_position(world_position))
		return true
	_dungeon_debug("클릭 상호작용: world=%s cell=%s" % [world_position, world_cell_from_world_position(world_position)])
	var ore_hit := _dungeon_ore_target_near_cell(world_cell_from_world_position(world_position), 2)
	if not ore_hit.is_empty():
		_dungeon_debug("클릭 광석 대상 발견: %s" % ore_hit)
		return _queue_pointer_acquisition(ore_hit.target_id, ore_hit.cell)
	var landmark_hit := _landmark_target_near_world_position(world_position)
	if not landmark_hit.is_empty():
		_dungeon_debug("클릭 대상: required dungeon landmark %s" % landmark_hit)
		return _queue_pointer_landmark(landmark_hit.target_id, landmark_hit.cell)
	var house_hit := _large_house_target_near_world_position(world_position)
	if not house_hit.is_empty():
		_dungeon_debug("클릭 대상: large house dungeon %s" % house_hit)
		return _queue_pointer_landmark(house_hit.target_id, house_hit.cell)
	if _pointer_enemy_clicked(world_position):
		_submit_pointer_enemy_attack(world_position)
		return true
	var clicked_cell := world_cell_from_world_position(world_position)
	for cell in _pointer_candidate_cells(clicked_cell):
		var target_id := _interaction_target_id_for_cell(cell)
		if target_id.is_empty():
			continue
		if _is_available_acquisition_target(target_id):
			return _queue_pointer_acquisition(target_id, cell)
		if _is_landmark_target(target_id):
			_dungeon_debug("클릭 셀 대상: %s at %s" % [target_id, cell])
			return _queue_pointer_landmark(target_id, cell)
		return submit_interaction_at_world_cell(cell)
	return false

func _try_dungeon_interaction_from_input() -> bool:
	if player == null:
		return false
	var origin_cell := world_cell_from_world_position(player.global_position)
	var dungeon_target := _dungeon_interaction_target_near_cell(origin_cell)
	if not dungeon_target.is_empty():
		_dungeon_debug("E 대상 발견: %s" % dungeon_target)
		return submit_interaction_at_world_cell(dungeon_target.cell)
	var ore_target := _dungeon_ore_target_near_cell(origin_cell, 1)
	if ore_target.is_empty():
		ore_target = _acquisition_target_near_cell(origin_cell)
	if not ore_target.is_empty():
		_dungeon_debug("E 광석 대상 발견: %s" % ore_target)
		return _gather_dungeon_ore(String(ore_target.target_id), ore_target.cell)
	var enemy_cell := _dungeon_enemy_cell_near(origin_cell)
	if enemy_cell != Vector2i(-1, -1):
		if _is_dungeon_boss_cell(enemy_cell) and not _dungeon_boss_combat_available():
			return _begin_dungeon_boss_precombat_dialogue()
		_activate_dungeon_enemy(enemy_cell)
		var direction := Vector2i(int(signf(float(enemy_cell.x - origin_cell.x))), int(signf(float(enemy_cell.y - origin_cell.y))))
		return submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, direction))
	var landmark := _landmark_target_near_world_position(player.global_position, _runtime_tile_size() * 2.5)
	if landmark.is_empty():
		landmark = _large_house_target_near_world_position(player.global_position, _runtime_tile_size() * 3.5)
	if landmark.is_empty():
		_dungeon_debug("E 대상 없음: origin_cell=%s" % origin_cell)
		return false
	_dungeon_debug("E 거리 대상 발견: %s" % landmark)
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(landmark.target_id)}))

func _pointer_enemy_clicked(world_position: Vector2) -> bool:
	var hit_radius := maxf(_runtime_tile_size() * 0.5, 16.0)
	for enemy in _combat_targets():
		if enemy.global_position.distance_to(world_position) <= hit_radius:
			combat_dummy = enemy
			return true
	if _in_dungeon_map and not _dungeon_boss_combat_available():
		var boss: Node2D = _dungeon_boss_node()
		if boss != null and boss.global_position.distance_to(world_position) <= hit_radius:
			return _begin_dungeon_boss_precombat_dialogue()
	return false

func _try_landmark_interaction_from_input() -> bool:
	if player == null:
		return false
	var target := _landmark_target_near_world_position(player.global_position, _runtime_tile_size() * 2.5)
	if target.is_empty():
		return false
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(target.get("target_id", ""))}))

func _is_dungeon_enemy_cell(cell: Vector2i) -> bool:
	if not _in_dungeon_map or world_data == null:
		return false
	for owner_id in ["dungeon_enemy_0", "dungeon_enemy_1", "dungeon_enemy_2", DUNGEON_BOSS_OWNER_ID]:
		if owner_id in world_data.get_occupants(cell):
			return true
	return false

func _acquisition_target_near_cell(origin_cell: Vector2i) -> Dictionary:
	return _spatial_resolver.acquisition_target_near_cell(world_data, _in_dungeon_map, origin_cell, _resolved_grid_direction(Vector2i.ZERO), Callable(self, "_is_available_acquisition_target"))
func _dungeon_ore_target_near_cell(origin_cell: Vector2i, radius: int) -> Dictionary:
	return _spatial_resolver.dungeon_ore_target_near_cell(_in_dungeon_map, _dungeon_resources, acquisition_service, origin_cell, radius)
func _gather_dungeon_ore(target_id: String, cell: Vector2i) -> bool:
	if acquisition_service == null:
		_dungeon_debug("광석 채집 실패: acquisition_service 없음")
		return true
	if acquisition_service.gatherable_for(target_id).is_empty():
		var register_result: Dictionary = acquisition_service.register_gatherable(target_id, target_id, cell)
		if not register_result.ok:
			_dungeon_debug("광석 재등록 실패: %s" % register_result)
			return true
	var result: Dictionary = acquisition_service.gather(target_id)
	_dungeon_debug("광석 채집 결과: target=%s ok=%s reason=%s" % [target_id, result.get("ok", false), result.get("reason", "")])
	if result.ok:
		_advance_time_for_turn()
		_queue_enemy_turn_after_player_action()
	return true

func _dungeon_enemy_cell_near(origin_cell: Vector2i) -> Vector2i:
	for y in range(origin_cell.y - 1, origin_cell.y + 2):
		for x in range(origin_cell.x - 1, origin_cell.x + 2):
			var cell := Vector2i(x, y)
			if _is_dungeon_enemy_cell(cell) and _cells_are_adjacent(origin_cell, cell):
				return cell
	return Vector2i(-1, -1)

func _activate_dungeon_enemy(cell: Vector2i) -> void:
	for enemy in _combat_targets():
		if _combat_target_cell(enemy) == cell:
			combat_dummy = enemy
			return

func _is_dungeon_boss_cell(cell: Vector2i) -> bool:
	return DUNGEON_BOSS_OWNER_ID in world_data.get_occupants(cell) if world_data != null else false

func _queue_pointer_acquisition(target_id: String, target_cell: Vector2i) -> bool:
	if player == null:
		return _gather_dungeon_ore(target_id, target_cell) if _is_dungeon_resource_target(target_id) else submit_interaction_at_world_cell(target_cell)
	var player_cell := world_cell_from_world_position(player.global_position)
	if _cells_are_adjacent(player_cell, target_cell):
		return _gather_dungeon_ore(target_id, target_cell) if _is_dungeon_resource_target(target_id) else submit_interaction_at_world_cell(target_cell)
	var approach_cell := _nearest_walkable_adjacent_cell(target_cell, player_cell)
	if approach_cell == target_cell:
		return false
	_begin_pointer_move_route(player_cell, approach_cell, target_id, target_cell)
	if not _has_pointer_move_target:
		return false
	return true

func _queue_pointer_landmark(target_id: String, target_cell: Vector2i) -> bool:
	if player == null:
		return submit_interaction_at_world_cell(target_cell)
	var player_cell := world_cell_from_world_position(player.global_position)
	if _player_can_interact_with_target(player_cell, target_id, target_cell):
		if _is_landmark_target(target_id):
			return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))
		return submit_interaction_at_world_cell(target_cell)
	var approach_cell := _nearest_walkable_adjacent_cell_for_target(target_id, target_cell, player_cell)
	if approach_cell == target_cell:
		return false
	_begin_pointer_move_route(player_cell, approach_cell, target_id, target_cell)
	if not _has_pointer_move_target:
		return false
	return true

func _begin_pointer_move_route(from_cell: Vector2i, destination_cell: Vector2i, target_id: String, target_cell: Vector2i) -> void:
	var result: Dictionary = _pointer_route_controller.begin_route(
		world_data,
		from_cell,
		destination_cell,
		target_id,
		target_cell,
		_target_footprint_cells(target_id, destination_cell),
		Callable(self, "world_position_for_cell_center")
	)
	if not result.ok:
		_dungeon_debug("이동 경로 생성 실패: from=%s destination=%s target=%s" % [from_cell, destination_cell, target_id])
		return
	_dungeon_debug("이동 경로 생성: %s -> %s, steps=%d, target=%s" % [from_cell, destination_cell, result.route.size(), target_id])
	_movement_selector.submit_mobile_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
func _submit_pointer_enemy_attack(world_position: Vector2) -> bool:
	if player == null \
			or not _pointer_enemy_clicked(world_position):
		return false
	var dummy_position := Vector2(combat_dummy.global_position)
	var player_position := Vector2(player.global_position)
	var delta := dummy_position - player_position
	var direction := Vector2i(int(signf(delta.x)), int(signf(delta.y)))
	if direction == Vector2i.ZERO:
		direction = _resolved_grid_direction(Vector2i.ZERO)
	_clear_pointer_movement()
	var accepted := submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, direction))
	return accepted

func submit_pointer_movement(world_position: Vector2) -> bool:
	var target_cell := world_cell_from_world_position(world_position)
	if world_data == null or not world_data.is_walkable(target_cell):
		return false
	_pointer_route_controller.submit_direct_movement(world_position_for_cell_center(target_cell))
	_movement_selector.submit_mobile_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	return true
func submit_player_interaction(direction := Vector2i.ZERO) -> bool:
	var origin_cell := Vector2i.ZERO
	if player != null:
		origin_cell = world_cell_from_world_position(player.global_position)
	var cells := _interaction_candidate_cells(origin_cell, direction)
	for cell in cells:
		if submit_interaction_at_world_cell(cell):
			return true
	# A 2x2 dungeon sprite extends beyond its anchor cell. Accept E from the
	# visible building edge so the player does not need pixel-perfect alignment.
	for y in range(origin_cell.y - 2, origin_cell.y + 3):
		for x in range(origin_cell.x - 2, origin_cell.x + 3):
			var nearby_cell := Vector2i(x, y)
			if abs(x - origin_cell.x) + abs(y - origin_cell.y) > 2:
				continue
			var nearby_target := _interaction_target_id_for_cell(nearby_cell)
			if _is_landmark_target(nearby_target) and submit_interaction_at_world_cell(nearby_cell):
				return true
	if player != null:
		var nearby_landmark := _landmark_target_near_world_position(player.global_position, _runtime_tile_size() * 2.5)
		if nearby_landmark.is_empty():
			nearby_landmark = _large_house_target_near_world_position(player.global_position, _runtime_tile_size() * 3.5)
		if not nearby_landmark.is_empty():
			return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": String(nearby_landmark.target_id)}))
	_play_sfx_event(SfxEventRouter.EVENT_INTERACT_FAIL, {"direction": direction}, "interact_empty")
	return false

func _landmark_target_near_world_position(world_position: Vector2, max_distance := -1.0) -> Dictionary:
	return _spatial_resolver.landmark_target_near_world_position(world_data, world_position, _runtime_tile_size(), _runtime_world_origin(), max_distance)
func _large_house_target_near_world_position(world_position: Vector2, max_distance := -1.0) -> Dictionary:
	return _spatial_resolver.large_house_target_near_world_position(generated_world, world_position, _runtime_tile_size(), _runtime_world_origin(), max_distance)
func submit_interaction_at_world_cell(cell: Vector2i) -> bool:
	var target_id := _interaction_target_id_for_cell(cell)
	if target_id.is_empty():
		return false
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))

func submit_action_command(command) -> bool:
	if not command is GameCommand:
		return false
	if _dungeon_boss_action_locked(command):
		return false
	var result: Dictionary = _execute_action_command(command)
	_apply_action_command_result(result)
	return bool(result.get("accepted", false))

func _execute_action_command(command: GameCommand) -> Dictionary:
	match command.type:
		GameCommand.Type.NARRATIVE_SELECT_OPTION:
			return _command_dispatcher.result_for(command, _handle_narrative_option_command(command))
		GameCommand.Type.INTERACT:
			var target_id := String(command.payload.get("target_id", ""))
			if target_id.is_empty():
				return _command_dispatcher.result_for(command, submit_player_interaction(command.direction), {"consumes_turn": false, "queues_enemy_turn": false})
			if _is_landmark_target(target_id):
				var landmark_accepted := _handle_landmark_interaction(target_id)
				if landmark_accepted:
					_play_sfx_event(SfxEventRouter.EVENT_INTERACT_SUCCESS, {"target_id": target_id}, "landmark:%s" % target_id)
				return _command_dispatcher.result_for(command, landmark_accepted, {"consumes_turn": false, "queues_enemy_turn": false, "interact_failure_sfx": false})
			if _is_repair_interaction_target(target_id):
				var repair_result := _handle_repair_interaction_command(command)
				return _command_dispatcher.result_for(command, repair_result.ok, {"consumes_turn": bool(repair_result.get("ok", false)), "queues_enemy_turn": bool(repair_result.get("ok", false))})
			var accepted: bool = acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.DRINK_TEA:
			return _command_dispatcher.result_for(command, _handle_tea_command(command))
		GameCommand.Type.USE_CONSUMABLE:
			return _command_dispatcher.result_for(command, _handle_consumable_command(command))
		GameCommand.Type.SLEEP:
			return _command_dispatcher.result_for(command, _handle_sleep_command())
		GameCommand.Type.COMPLETE_DUNGEON:
			return _command_dispatcher.result_for(command, _handle_complete_dungeon_command(command))
		GameCommand.Type.REPAIR_TELEPORT, GameCommand.Type.ADVANCE_BIOME:
			return _command_dispatcher.result_for(command, _handle_biome_progression_command(command))
		GameCommand.Type.TRAVEL_TO_BIOME:
			return _command_dispatcher.result_for(command, _travel_to_biome(String(command.payload.get("biome_id", "")), String(command.payload.get("travel_mode", "teleport"))))
		GameCommand.Type.FACILITY_ROTATE:
			return _command_dispatcher.result_for(command, _rotate_pending_facility())
		GameCommand.Type.FACILITY_CONFIRM:
			return _command_dispatcher.result_for(command, _confirm_pending_facility())
		GameCommand.Type.FACILITY_CANCEL:
			return _command_dispatcher.result_for(command, _cancel_pending_facility_placement())
		GameCommand.Type.OPEN_TEA_BREWING:
			var accepted: bool = game_hud != null and game_hud.show_tea_brewing_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "tea_brewing"}, "menu:tea_brewing")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.TEA_BREW_SELECT_LEAF, GameCommand.Type.TEA_BREW_SELECT_VESSEL, GameCommand.Type.TEA_BREW_SELECT_SLOT, GameCommand.Type.TEA_BREW_NAVIGATE, GameCommand.Type.BREW_TEA:
			return _command_dispatcher.result_for(command, _handle_tea_brewing_command(command))
		GameCommand.Type.OPEN_META_CODEX:
			var accepted: bool = game_hud != null and game_hud.show_meta_codex_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "meta_codex"}, "menu:meta_codex")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.META_CODEX_SET_TAB, GameCommand.Type.META_CODEX_SET_FILTER, GameCommand.Type.META_CODEX_SELECT_DETAIL, GameCommand.Type.META_CODEX_NAVIGATE:
			return _command_dispatcher.result_for(command, _handle_meta_codex_command(command))
		GameCommand.Type.OPEN_INVENTORY:
			var accepted: bool = game_hud != null and game_hud.show_inventory_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "inventory"}, "menu:inventory")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.OPEN_CRAFTING:
			_configure_game_hud()
			var accepted: bool = game_hud != null and game_hud.show_crafting_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "crafting"}, "menu:crafting")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.OPEN_FACILITIES:
			_configure_game_hud()
			var accepted: bool = game_hud != null and game_hud.show_facilities_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "facilities"}, "menu:facilities")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.OPEN_MAP:
			var accepted: bool = game_hud != null and game_hud.show_map_menu()
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "map"}, "menu:map")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.HIDE_MENU:
			var placement_cancelled := _cancel_pending_facility_placement()
			var accepted: bool = (game_hud != null and game_hud.hide_menu()) or placement_cancelled
			if accepted:
				_play_sfx_event(SfxEventRouter.EVENT_UI_MENU_CLOSE, {"placement_cancelled": placement_cancelled}, "menu:hide")
			return _command_dispatcher.result_for(command, accepted)
		GameCommand.Type.CRAFT_RECIPE:
			var accepted: bool = _handle_craft_recipe_command(command)
			return _command_dispatcher.result_for(command, accepted, {"placement_pending": accepted and has_pending_facility_placement()})
		GameCommand.Type.INVENTORY_SET_FILTER, GameCommand.Type.INVENTORY_SORT, GameCommand.Type.INVENTORY_SELECT_SLOT, GameCommand.Type.INVENTORY_NAVIGATE, GameCommand.Type.EQUIP_INVENTORY_SLOT, GameCommand.Type.UNEQUIP_SLOT, GameCommand.Type.USE_INVENTORY_SLOT:
			return _command_dispatcher.result_for(command, _handle_inventory_command(command))
		_:
			if _sen_rikyu_phase_two_accepts_command(command):
				var accepted: bool = _handle_sen_rikyu_phase_two_action(command)
				return _command_dispatcher.result_for(command, accepted, {"consumes_turn": true, "queues_enemy_turn": true, "feedback_beep": true})
			var accepted: bool = player != null and player.submit_command(command)
			return _command_dispatcher.result_for(command, accepted)

func _apply_action_command_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var command = result.get("command")
	if bool(result.get("interact_failure_sfx", false)) and command is GameCommand:
		var target_id := String(command.payload.get("target_id", ""))
		_play_sfx_event(SfxEventRouter.EVENT_INTERACT_FAIL, {"target_id": target_id}, "interact_failed:%s" % target_id)
	if not bool(result.get("accepted", false)):
		return
	if bool(result.get("sync_tea_runtime", false)):
		_sync_run_runtime_state()
	if bool(result.get("consumes_turn", false)):
		_advance_time_for_turn()
	if bool(result.get("feedback_beep", false)):
		_play_feedback_beep()
	if bool(result.get("queues_enemy_turn", false)):
		_queue_enemy_turn_after_player_action()

func movement_command_for_current_inputs(desktop_command) -> GameCommand:
	if desktop_command is GameCommand and desktop_command.type == GameCommand.Type.MOVE and desktop_command.direction != Vector2i.ZERO:
		_clear_pointer_movement()
		return desktop_command
	var pointer_command: GameCommand = _pointer_movement_command()
	if pointer_command.direction != Vector2i.ZERO:
		return pointer_command
	return _movement_selector.select(desktop_command)

func restore_run_state(state) -> Dictionary:
	if not state is RunState:
		return {"ok": false, "reason": "invalid_run_state", "error": "Main runtime requires a RunState."}
	var hydrate_result: Dictionary = run_runtime_state_binder.hydrate_from_run_state(state, _run_runtime_state_entries())
	if not hydrate_result.ok:
		return hydrate_result
	run_state = state
	_configure_game_hud()
	return {"ok": true}

func _connect_hud_commands() -> void:
	if game_hud == null or not game_hud.has_signal("movement_button_changed"):
		return
	var callback := Callable(self, "_on_hud_movement_button_changed")
	if not game_hud.is_connected("movement_button_changed", callback):
		game_hud.connect("movement_button_changed", callback)

func _on_hud_movement_button_changed(direction: Vector2i) -> void:
	submit_mobile_movement_direction(direction)

func snapshot_run_state() -> Dictionary:
	if run_state == null:
		run_state = RunState.new()
	if player != null:
		var player_resources = player.get("resources")
		if player_resources != null and player_resources.has_method("to_dictionary"):
			run_state.player_resources = player_resources.to_dictionary()
	if not _in_dungeon_map and combat_dummy != null and is_instance_valid(combat_dummy):
		run_state.overworld_enemy_state = _snapshot_overworld_enemy_state()
	if player != null and _in_dungeon_map:
		_sync_dungeon_runtime_save_state()
	elif player != null:
		var cell := _player_world_cell()
		run_state.player_cell = {"x": cell.x, "y": cell.y}
	var snapshot_result: Dictionary = run_runtime_state_binder.snapshot_to_run_state(run_state, _run_runtime_state_entries())
	if not snapshot_result.ok:
		push_error(snapshot_result.error)
	else:
		_store_current_biome_runtime_aliases()
	return run_state.to_dictionary()

func load_or_create_run_state() -> Dictionary:
	if run_state != null:
		return {"ok": true, "state": "provided", "run_state": run_state}
	if _start_mode in [START_MODE_NEW, START_MODE_CHEAT]:
		return _create_new_run_state_from_start_request()
	if save_store != null and FileAccess.file_exists(save_store.run_path):
		var loaded: Dictionary = save_store.load_run()
		if not loaded.ok:
			return loaded
		run_state = loaded.run_state
		return {"ok": true, "state": "loaded", "run_state": run_state}
	run_state = RunState.new()
	return {"ok": true, "state": "created", "run_state": run_state}

func _consume_start_mode() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root == null or not root.has_meta(START_MODE_META):
		return
	_start_mode = String(root.get_meta(START_MODE_META, START_MODE_RESUME))
	root.remove_meta(START_MODE_META)
	_force_first_run_prologue = _start_mode in [START_MODE_NEW, START_MODE_CHEAT]

func _create_new_run_state_from_start_request() -> Dictionary:
	run_state = RunState.new()
	if catalog != null:
		run_state.data_version = catalog.data_version
	run_state.seed = DEFAULT_RUN_SEED
	if save_store == null:
		return {"ok": true, "state": "created_new_start", "run_state": run_state}
	var invalidation := save_store.invalidate_run()
	if not invalidation.ok and String(invalidation.get("reason", "")) != "missing_invalidation":
		return invalidation
	run_state.lifecycle_epoch = int(invalidation.get("invalidated_lifecycle_epoch", 0)) + 1
	var saved := save_store.save_run(run_state)
	if not saved.ok:
		return saved
	return {"ok": true, "state": "created_new_start", "run_state": run_state}

func _apply_cheat_start_inventory() -> Dictionary:
	if _start_mode != START_MODE_CHEAT:
		return {"ok": true, "applied": false}
	return CheatStartConfigurator.new(catalog, inventory, equipment, run_state).apply(_sync_run_runtime_state)

func _normalize_cheat_progression_state() -> void:
	if _start_mode == START_MODE_CHEAT:
		CheatStartConfigurator.new(catalog, inventory, equipment, run_state).normalize_cheat_progression_state()

func save_current_run() -> Dictionary:
	if save_store == null:
		return {"ok": false, "reason": "missing_save_store", "error": "Save store is not configured."}
	var result: Dictionary = save_store.save_run(snapshot_run_state())
	# A start/death transition can leave the in-memory run one epoch behind the
	# invalidation high-water mark. Advance once and retry the active run save.
	if not bool(result.get("ok", false)) and String(result.get("reason", "")) == "stale_run_save":
		run_state.lifecycle_epoch += 1
		result = save_store.save_run(snapshot_run_state())
	return result

func _catalog_declares_time_balance(loaded_catalog) -> bool:
	return RunServiceFactory.catalog_declares_time_balance(loaded_catalog)

func _configure_run_services(loaded_catalog) -> Dictionary:
	var services := RunServiceFactory.create(loaded_catalog)
	if not services.ok:
		return services
	if run_runtime_state_binder == null:
		run_runtime_state_binder = RunRuntimeStateBinder.new()
	inventory = services.inventory
	equipment = services.equipment
	tea_service = services.tea_service
	time_state = services.time_state
	crafting_service = services.crafting_service
	facility_placement_service = services.facility_placement_service
	repair_interaction_service = services.repair_interaction_service
	consumable_service = services.consumable_service
	core_tea_ware_collection = services.core_tea_ware_collection
	final_room_state_builder = services.final_room_state_builder
	_player_item_actions.active_tea_drink_action = {}
	sen_rikyu_phase_one_runtime = null
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("events", SenRikyuPhaseOneRuntime.EVENT_ID).is_empty():
		var phase_one_result: Dictionary = SenRikyuPhaseOneRuntime.from_catalog(loaded_catalog, tea_service)
		if not phase_one_result.ok:
			return phase_one_result
		sen_rikyu_phase_one_runtime = phase_one_result.runtime
	sen_rikyu_phase_two_runtime = null
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("bosses", SenRikyuPhaseTwoRuntime.BOSS_ID).is_empty():
		var phase_two_result: Dictionary = SenRikyuPhaseTwoRuntime.from_catalog(loaded_catalog)
		if not phase_two_result.ok:
			return phase_two_result
		sen_rikyu_phase_two_runtime = phase_two_result.runtime
	sen_rikyu_phase_three_runtime = null
	if loaded_catalog.has_method("find_by_id") and not loaded_catalog.find_by_id("events", SenRikyuPhaseThreeRuntime.EVENT_ID).is_empty():
		var phase_three_result: Dictionary = SenRikyuPhaseThreeRuntime.from_catalog(loaded_catalog)
		if not phase_three_result.ok:
			return phase_three_result
		sen_rikyu_phase_three_runtime = phase_three_result.runtime
	ending_route_runtime = null
	var ending_result: Dictionary = EndingRouteRuntime.from_catalog(loaded_catalog)
	if ending_result.ok:
		ending_route_runtime = ending_result.runtime
	inventory_command_runtime = InventoryCommandRuntime.new()
	var inventory_command_result: Dictionary = inventory_command_runtime.configure(inventory, equipment, consumable_service, loaded_catalog.data_version)
	if not inventory_command_result.ok:
		return inventory_command_result
	map_read_model_builder = MapReadModelBuilder.new()
	var map_result: Dictionary = map_read_model_builder.configure(loaded_catalog.data_version)
	if not map_result.ok:
		return map_result
	tea_brewing_command_runtime = TeaBrewingCommandRuntime.new()
	var tea_brewing_result: Dictionary = tea_brewing_command_runtime.configure(tea_service, inventory, equipment, Callable(self, "_tea_brewing_context"), loaded_catalog.data_version)
	if not tea_brewing_result.ok:
		return tea_brewing_result
	meta_codex_command_runtime = MetaCodexCommandRuntime.new()
	var meta_codex_result: Dictionary = meta_codex_command_runtime.configure(loaded_catalog, Callable(self, "_current_run_state_snapshot"), Callable(self, "_current_meta_state_snapshot"), loaded_catalog.data_version)
	if not meta_codex_result.ok:
		return meta_codex_result
	tea_service.drink_completed.connect(_on_tea_drink_completed)
	memory_tea_cutscene_runtime = MemoryTeaCutsceneRuntime.new()
	var memory_runtime_result: Dictionary = memory_tea_cutscene_runtime.configure(loaded_catalog.data_version)
	if not memory_runtime_result.ok:
		return memory_runtime_result
	if run_state != null:
		var hydrate_result: Dictionary = run_runtime_state_binder.hydrate_from_run_state(run_state, _run_runtime_state_entries())
		if not hydrate_result.ok:
			return hydrate_result
	narrative_runtime = NarrativeRuntime.new()
	var narrative_result: Dictionary = narrative_runtime.from_catalog(loaded_catalog)
	if not narrative_result.ok:
		return narrative_result
	run_start_event_selector = RunStartEventSelector.new()
	var start_selector_result: Dictionary = run_start_event_selector.configure(loaded_catalog)
	if not start_selector_result.ok:
		return start_selector_result
	return {"ok": true}

func final_room_gate_query() -> Dictionary:
	if core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return core_tea_ware_collection.final_room_gate_query(run_state)

func final_room_state_read_model() -> Dictionary:
	if final_room_state_builder == null:
		return {"ok": false, "reason": "missing_final_room_state_builder", "error": "Final room state builder is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return final_room_state_builder.build(run_state)

func start_sen_rikyu_phase_one(meta_state = null) -> Dictionary:
	if sen_rikyu_phase_one_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_one", "error": "Sen Rikyu Phase 1 runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return sen_rikyu_phase_one_runtime.start(run_state, meta_state)

func handle_sen_rikyu_phase_one_command(command_id: String, payload := {}, meta_state = null, resources = null) -> Dictionary:
	if sen_rikyu_phase_one_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_one", "error": "Sen Rikyu Phase 1 runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return sen_rikyu_phase_one_runtime.handle_command(command_id, payload, run_state, meta_state, resources)

func start_sen_rikyu_phase_two(phase_one_transition_command) -> Dictionary:
	if sen_rikyu_phase_two_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_two", "error": "Sen Rikyu Phase 2 runtime is not configured."}
	return sen_rikyu_phase_two_runtime.start_from_phase_one(phase_one_transition_command)

func start_sen_rikyu_phase_three(phase_two_transition) -> Dictionary:
	if sen_rikyu_phase_three_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_three", "error": "Sen Rikyu Phase 3 runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return sen_rikyu_phase_three_runtime.start(phase_two_transition, run_state)

func complete_sen_rikyu_phase_three(ability_id: String) -> Dictionary:
	if sen_rikyu_phase_three_runtime == null:
		return {"ok": false, "reason": "missing_sen_rikyu_phase_three", "error": "Sen Rikyu Phase 3 runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return sen_rikyu_phase_three_runtime.complete_with_ability(ability_id, run_state)

func ending_read_model() -> Dictionary:
	if ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return ending_route_runtime.evaluate(run_state)

func record_ending_to_meta(meta_state, read_model := {}) -> Dictionary:
	if ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	var model := read_model
	if model.is_empty():
		var evaluated := ending_read_model()
		if not evaluated.ok:
			return evaluated
		model = evaluated.read_model
	return ending_route_runtime.record_to_meta(model, meta_state)

func request_new_run_after_credits(read_model: Dictionary) -> Dictionary:
	if ending_route_runtime == null:
		return {"ok": false, "reason": "missing_ending_route_runtime", "error": "Ending route runtime is not configured."}
	return ending_route_runtime.request_new_run_after_credits(read_model)

func _sen_rikyu_phase_two_accepts_command(command) -> bool:
	return sen_rikyu_phase_two_runtime != null \
		and sen_rikyu_phase_two_runtime.to_projection().arena_state == SenRikyuPhaseTwoRuntime.ARENA_COMBAT \
		and command is GameCommand \
		and command.type in [GameCommand.Type.ATTACK, GameCommand.Type.DODGE, GameCommand.Type.CAST_ABILITY]

func _handle_sen_rikyu_phase_two_action(command: GameCommand) -> bool:
	if player == null:
		return false
	match command.type:
		GameCommand.Type.ATTACK:
			if player.combat_state == null or player.resources == null:
				return false
			return bool(sen_rikyu_phase_two_runtime.handle_player_attack(player.combat_state, player.resources.ki).ok)
		GameCommand.Type.DODGE:
			return player.combat_state != null and bool(sen_rikyu_phase_two_runtime.handle_player_dodge(player.combat_state).ok)
		GameCommand.Type.CAST_ABILITY:
			if player.ability_runtime == null or player.resources == null:
				return false
			var context := {
				"source_id": player.get_combat_id() if player.has_method("get_combat_id") else "player",
				"resources": player.resources,
				"tail_query": player.ability_tail_query,
				"time_state": player.ability_time_state,
				"tea_effect_query": tea_service,
				"direction": Vector2(command.direction).normalized() if command.direction != Vector2i.ZERO else Vector2.RIGHT
			}
			var cast_result: Dictionary = sen_rikyu_phase_two_runtime.cast_player_ability(player.ability_runtime, command.slot, context)
			if cast_result.ok:
				_sync_run_runtime_state()
			return bool(cast_result.ok)
	return false

func record_boss_core_tea_ware_rewards(resolution_event: Dictionary) -> Dictionary:
	if core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	if run_state == null:
		run_state = RunState.new()
	return core_tea_ware_collection.record_boss_resolution_rewards(resolution_event, run_state)

func configure_dungeon_runtime(progression_state, completion_resolver: Callable, additional_reward_hook := Callable()) -> Dictionary:
	if core_tea_ware_collection == null:
		return {"ok": false, "reason": "missing_core_tea_ware_collection", "error": "Core tea ware collection is not configured."}
	if run_state == null:
		run_state = RunState.new()
	dungeon_runtime = DungeonRuntime.new()
	var reward_hook := func(clear_event: Dictionary) -> Dictionary:
		var core_preflight: Dictionary = core_tea_ware_collection.validate_boss_resolution_rewards(clear_event, run_state)
		if not core_preflight.ok:
			return core_preflight
		if additional_reward_hook.is_valid():
			var additional_result = additional_reward_hook.call(clear_event.duplicate(true))
			var normalized_additional: Dictionary = _normalize_reward_hook_result(additional_result)
			if not normalized_additional.ok:
				return normalized_additional
		return record_boss_core_tea_ware_rewards(clear_event)
	return dungeon_runtime.configure(run_state, progression_state, completion_resolver, reward_hook)

func _equip_default_playable_ability() -> Dictionary:
	if player == null or player.ability_runtime == null:
		return {"ok": true, "reason": "missing_player_ability_runtime"}
	if not player.ability_runtime.equipped_ability_id(0).is_empty():
		return {"ok": true, "state": "already_equipped"}
	var candidates: Dictionary = player.ability_runtime.ability_candidates({"tail_query": self})
	if not candidates.ok:
		return candidates
	var ids: Array = candidates.get("ability_ids", [])
	if ids.is_empty():
		return {"ok": false, "reason": "missing_playable_ability", "error": "No current-tail playable ability exists."}
	return player.equip_ability(0, String(ids[0]), self)

func can_use_ability(_ability_id: String, tail_requirement: int) -> bool:
	if run_state == null:
		return int(tail_requirement) <= 1
	return int(run_state.tails) >= int(tail_requirement)

func targets_for_ability(source, definition, direction: Vector2) -> Array:
	var targets := []
	for enemy in _combat_targets():
		if _ability_target_is_in_range(source, definition, direction, enemy):
			targets.append(enemy)
	return targets

func _combat_targets() -> Array:
	var targets := []
	if _in_dungeon_map:
		for enemy in _dungeon_enemy_nodes:
			if is_instance_valid(enemy) and enemy.visible and enemy.has_method("current_hp") and int(enemy.current_hp()) > 0:
				if enemy.name == DUNGEON_BOSS_OWNER_ID and not _dungeon_boss_combat_available():
					continue
				targets.append(enemy)
	elif combat_dummy != null and is_instance_valid(combat_dummy) and combat_dummy.visible and combat_dummy.has_method("current_hp") and int(combat_dummy.current_hp()) > 0:
		targets.append(combat_dummy)
	return targets

func _dungeon_regular_combat_targets() -> Array:
	var targets := []
	if not _in_dungeon_map:
		return targets
	for enemy in _dungeon_enemy_nodes:
		if is_instance_valid(enemy) and enemy.name != DUNGEON_BOSS_OWNER_ID and enemy.visible and enemy.has_method("current_hp") and int(enemy.current_hp()) > 0:
			targets.append(enemy)
	return targets

func _ability_target_is_in_range(source, definition, direction: Vector2, target) -> bool:
	if source == null or target == null:
		return false
	var source_position := Vector2(source.global_position) if source is Node2D else Vector2.ZERO
	var target_position := Vector2(target.global_position) if target is Node2D else Vector2.ZERO
	var offset := target_position - source_position
	var range_pixels := maxf(float(definition.range_tiles), 0.0) * _runtime_tile_size()
	if range_pixels > 0.0 and offset.length() > range_pixels:
		return false
	var aim := direction.normalized() if direction != Vector2.ZERO else offset.normalized()
	if aim == Vector2.ZERO or offset == Vector2.ZERO:
		return true
	return offset.normalized().dot(aim) >= 0.35

func _ensure_biome_progression_state() -> Dictionary:
	if biome_progression_state != null:
		return {"ok": true, "progression_state": biome_progression_state}
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if progression_result.ok:
		biome_progression_state = progression_result.progression_state
	return progression_result

func _ensure_playable_dungeon_runtime() -> Dictionary:
	var progression_result := _ensure_biome_progression_state()
	if not progression_result.ok:
		_dungeon_debug("진행 상태 준비 실패: %s" % progression_result)
		return progression_result
	if dungeon_runtime != null:
		return {"ok": true, "runtime": dungeon_runtime}
	return configure_dungeon_runtime(
		biome_progression_state,
		func(payload: Dictionary, _projection: Dictionary) -> bool:
			return _dungeon_completion_objective_met(payload)
	)

func _dungeon_completion_objective_met(payload: Dictionary) -> bool:
	if bool(payload.get("objective_complete", false)):
		return true
	return _in_dungeon_map and _combat_targets().is_empty() and _dungeon_boss_combat_available()

func _ensure_current_dungeon_entered() -> Dictionary:
	var projection: Dictionary = dungeon_runtime.to_projection() if dungeon_runtime != null else {}
	var lifecycle := String(projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE))
	if lifecycle == DungeonInstanceState.STATE_ACTIVE:
		return {"ok": true, "state": "already_active"}
	if lifecycle not in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED]:
		return {"ok": false, "reason": "dungeon_lifecycle_busy", "error": "Dungeon lifecycle is not ready for a new entry."}
	var definition := dungeon_definition_resolver.dungeon_entry_definition(catalog, narrative_runtime, run_state)
	if definition.is_empty():
		_dungeon_debug("현재 바이옴 던전 정의 없음: biome=%s" % (run_state.current_biome_id if run_state != null else "nil"))
		return {"ok": false, "reason": "missing_current_dungeon", "error": "No dungeon definition exists for the current biome."}
	var biome_id := String(run_state.current_biome_id)
	var layout_result: Dictionary = dungeon_layout_builder.build(definition, func(item_id: String, action: String) -> String:
		return _acquisition_definitions().node_kind_for_resource_action(item_id, action))
	var layout: WorldData = layout_result.layout
	_dungeon_resources = layout_result.resources
	var enter_result: Dictionary = dungeon_runtime.enter_dungeon(
		"%s_%d" % [String(definition.id), run_state.seed],
		definition,
		layout,
		{"biome_id": biome_id, "world_seed": run_state.seed}
	)
	if enter_result.ok:
		_enter_dungeon_map(layout, definition, true)
	else:
		_dungeon_debug("dungeon_runtime.enter_dungeon 실패: %s" % enter_result)
	return enter_result

func _is_dungeon_resource_target(target_id: String) -> bool:
	return target_id.begins_with("dungeon_iron_ore_") or target_id.begins_with("dungeon_stone_")

func _is_mining_target(target_id: String) -> bool:
	return _is_dungeon_resource_target(target_id) or target_id.begins_with("terrain_mountain_mineral_")

func _dungeon_runtime_is_active() -> bool:
	return dungeon_runtime != null and String(dungeon_runtime.to_projection().get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) == DungeonInstanceState.STATE_ACTIVE

func _dungeon_boss_combat_available() -> bool:
	if dungeon_runtime == null:
		return true
	return dungeon_runtime.boss_combat_available()

func _dungeon_boss_action_locked(command) -> bool:
	if not _in_dungeon_map or _dungeon_boss_combat_available():
		return false
	if command.type == GameCommand.Type.NARRATIVE_SELECT_OPTION:
		return false
	if command.type == GameCommand.Type.INTERACT:
		var target_id := String(command.payload.get("target_id", ""))
		return target_id == DUNGEON_BOSS_OWNER_ID
	return [GameCommand.Type.ATTACK, GameCommand.Type.DODGE, GameCommand.Type.CAST_ABILITY, GameCommand.Type.COMPLETE_DUNGEON].has(command.type)

func _dungeon_boss_node() -> Node2D:
	for enemy in _dungeon_enemy_nodes:
		if is_instance_valid(enemy) and enemy.name == DUNGEON_BOSS_OWNER_ID:
			return enemy
	return null

func _dungeon_boss_cell() -> Vector2i:
	var boss: Node2D = _dungeon_boss_node()
	if boss == null:
		return Vector2i(-1, -1)
	return world_cell_from_world_position(boss.global_position)

func _dungeon_precombat_dialogue_is_active(event_id: String) -> bool:
	if dungeon_runtime == null:
		return false
	var projection: Dictionary = dungeon_runtime.to_projection()
	return String(projection.get("boss_flow_state", "")) == DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE \
		and String(projection.get("pre_boss_dialogue_event_id", "")) == event_id

func _restore_dungeon_boss_precombat_dialogue_if_needed() -> void:
	if dungeon_runtime == null or narrative_runtime == null or run_state == null:
		return
	var projection: Dictionary = dungeon_runtime.to_projection()
	if String(projection.get("boss_flow_state", "")) != DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE:
		return
	var event_id := String(projection.get("pre_boss_dialogue_event_id", ""))
	if event_id.is_empty():
		return
	var model_result: Dictionary = narrative_runtime.read_model_for_event(event_id, run_state, _current_meta_state_snapshot())
	if not model_result.ok:
		_dungeon_debug("저장된 보스 전 대화 복원 실패: %s" % model_result)
		return
	_active_narrative_event_id = String(model_result.read_model.event_id)
	_active_narrative_node_id = String(model_result.read_model.node_id)
	if game_hud != null and game_hud.has_method("show_narrative_dialogue"):
		game_hud.show_narrative_dialogue(model_result.read_model)

func _begin_dungeon_boss_precombat_dialogue() -> bool:
	if dungeon_runtime == null or narrative_runtime == null or run_state == null:
		return false
	if not _dungeon_regular_combat_targets().is_empty():
		if game_hud != null and game_hud.has_method("show_command_feedback"):
			game_hud.show_command_feedback("남은 적을 먼저 정리해야 합니다")
		return false
	var projection: Dictionary = dungeon_runtime.to_projection()
	if String(projection.get("boss_flow_state", DungeonInstanceState.BOSS_FLOW_NONE)) == DungeonInstanceState.BOSS_FLOW_NONE:
		var definition := _current_biome_dungeon_definition()
		var biome_id := String(run_state.current_biome_id)
		var boss_definition := _current_biome_boss_definition(biome_id, String(definition.get("id", "")))
		var prepare_result: Dictionary = dungeon_runtime.prepare_boss_encounter({
			"boss_id": String(boss_definition.get("id", "")),
			"pre_boss_dialogue_event_id": _pre_boss_dialogue_event_id_for(definition, boss_definition)
		})
		if not prepare_result.ok:
			_dungeon_debug("보스 전 대화 준비 실패: %s" % prepare_result)
			if game_hud != null and game_hud.has_method("show_command_feedback"):
				game_hud.show_command_feedback("보스 대화 데이터가 아직 연결되지 않았습니다")
			return false
	var begin_result: Dictionary = dungeon_runtime.begin_boss_precombat_dialogue()
	if not begin_result.ok:
		_dungeon_debug("보스 전 대화 시작 실패: %s" % begin_result)
		return false
	var event_id := String(begin_result.get("event_id", ""))
	if event_id.is_empty():
		return false
	var model_result: Dictionary = narrative_runtime.read_model_for_event(event_id, run_state, _current_meta_state_snapshot())
	if not model_result.ok:
		_dungeon_debug("보스 전 대화 이벤트 로드 실패: %s" % model_result)
		if game_hud != null and game_hud.has_method("show_command_feedback"):
			game_hud.show_command_feedback("보스 대화 이벤트를 불러올 수 없습니다")
		return false
	_active_narrative_event_id = String(model_result.read_model.event_id)
	_active_narrative_node_id = String(model_result.read_model.node_id)
	if game_hud != null and game_hud.has_method("show_narrative_dialogue"):
		game_hud.show_narrative_dialogue(model_result.read_model)
	save_current_run()
	return true

func _dungeon_debug(message: String) -> void:
	if DUNGEON_DEBUG_LOGGING:
		print("[DungeonDebug] %s" % message)

func _enter_dungeon_map(layout: WorldData, definition: Dictionary, is_new_entry := false) -> void:
	if _in_dungeon_map:
		return
	_enemy_turn_queued = false
	_overworld_generated_world = generated_world.duplicate(true)
	_overworld_world_data_snapshot = world_data.to_dictionary() if world_data != null else {}
	_overworld_player_cell = _player_world_cell()
	_overworld_combat_dummy_cell = _combat_target_cell(combat_dummy) if combat_dummy != null else Vector2i.ZERO
	_overworld_combat_dummy = combat_dummy
	_overworld_combat_dummy_state = {}
	if _overworld_combat_dummy != null:
		if _overworld_combat_dummy.has_method("suspend_for_world_transition"):
			_overworld_combat_dummy_state = _overworld_combat_dummy.suspend_for_world_transition()
		else:
			_overworld_combat_dummy_state = {"visible": _overworld_combat_dummy.visible}
			_overworld_combat_dummy.visible = false
	var dungeon_data := layout.to_dictionary()
	var dungeon_projection := WorldRendererProjection.new().project(dungeon_data)
	generated_world = {
		"ok": true,
		"biome_id": String(definition.get("biome_id", run_state.current_biome_id)),
		"biome_generation_rule_id": String(definition.get("id", "dungeon")),
		"world_data": dungeon_data,
		"renderer_input": dungeon_projection,
		"required_landmarks": dungeon_projection.get("required_landmarks", []),
		"resource_nodes": _dungeon_resources
	}
	world_data = layout
	_in_dungeon_map = true
	if acquisition_service != null:
		acquisition_service = AcquisitionService.new()
		var dungeon_definitions := []
		for node in _dungeon_resources:
			var item_id := String(node.get("resource_id", "iron_ore"))
			var node_kind := String(node.get("node_kind", ""))
			if node_kind.is_empty():
				node_kind = _acquisition_definitions().node_kind_for_resource_action(item_id, "mine")
			dungeon_definitions.append({"id": String(node.id), "item_id": item_id, "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT, "material_tag": String(node.get("material_tag", "")), "required_tool_item_id": _acquisition_definitions().required_tool_for_resource_interaction(item_id, node_kind)})
		var dungeon_acquisition_result: Dictionary = acquisition_service.configure(inventory, world_data, dungeon_definitions, _generated_drop_definitions())
		if not dungeon_acquisition_result.ok:
			_dungeon_debug("광석 상호작용 설정 실패: %s" % dungeon_acquisition_result)
		else:
			acquisition_service.changed.connect(_on_acquisition_changed)
			acquisition_service.acquisition_completed.connect(_on_acquisition_completed)
			for node in _dungeon_resources:
				var register_result: Dictionary = acquisition_service.register_gatherable(String(node.id), String(node.id), _vector_from_dictionary(node.position))
				if not register_result.ok:
					_dungeon_debug("광석 노드 등록 실패: %s" % register_result)
			var saved_dungeon_acquisitions: Dictionary = run_state.dungeon_runtime_state.get("acquisitions", {}) if run_state != null else {}
			if not saved_dungeon_acquisitions.is_empty():
				var normalized_acquisitions := saved_dungeon_acquisitions.duplicate(true)
				var normalized_gatherables: Array = []
				for saved_node in normalized_acquisitions.get("gatherables", []):
					if typeof(saved_node) != TYPE_DICTIONARY:
						continue
					var node_snapshot: Dictionary = saved_node.duplicate(true)
					var node_id := String(node_snapshot.get("node_id", ""))
					if _is_dungeon_resource_target(node_id):
						# Older saves stored the item id as definition_id; dungeon
						# definitions are keyed by their stable node id.
						node_snapshot["definition_id"] = node_id
					normalized_gatherables.append(node_snapshot)
				normalized_acquisitions["gatherables"] = normalized_gatherables
				var acquisition_restore: Dictionary = acquisition_service.load_snapshot(normalized_acquisitions)
				if not acquisition_restore.ok:
					_dungeon_debug("던전 채집 상태 복원 실패: %s" % acquisition_restore)
	_render_generated_world(generated_world)
	var spawn_cell := Vector2i(1, 1)
	var saved_player_cell: Dictionary = run_state.dungeon_runtime_state.get("player_cell", {}) if run_state != null else {}
	var saved_cell := _vector_from_dictionary(saved_player_cell)
	if not saved_player_cell.is_empty() and world_data.contains(saved_cell) and world_data.is_walkable(saved_cell):
		spawn_cell = saved_cell
	player.global_position = world_position_for_cell_center(spawn_cell)
	_spawn_dungeon_combatants(is_new_entry)
	_configure_game_hud()
	_restore_dungeon_boss_precombat_dialogue_if_needed()
	_save_progress_after_turn()

func _spawn_dungeon_combatants(allow_default_spawn := false) -> void:
	_clear_dungeon_combatants(false)
	if _overworld_combat_dummy == null or not _overworld_combat_dummy.has_method("configure_combat"):
		return
	var regular_monster_ids := _dungeon_regular_monster_ids(3)
	var specs := [
		{"id": "dungeon_enemy_0", "cell": Vector2i(7, 2), "monster_id": regular_monster_ids[0], "sprite_id": _monster_sprite_asset_id(String(regular_monster_ids[0]))},
		{"id": "dungeon_enemy_1", "cell": Vector2i(9, 5), "monster_id": regular_monster_ids[1], "sprite_id": _monster_sprite_asset_id(String(regular_monster_ids[1]))},
		{"id": "dungeon_enemy_2", "cell": Vector2i(5, 7), "monster_id": regular_monster_ids[2], "sprite_id": _monster_sprite_asset_id(String(regular_monster_ids[2]))},
		{"id": DUNGEON_BOSS_OWNER_ID, "cell": Vector2i(10, 7), "monster_id": "road_bandit", "sprite_id": "asset_assets_sprites_characters_bosses_chr_6_yokai_tea_master_yokai_tea_master_front_32x32_png", "boss": true}
	]
	var saved_states: Dictionary = run_state.dungeon_runtime_state.get("enemy_states", {}) if run_state != null else {}
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var saved_state: Dictionary = saved_states.get(String(spec.id), {})
		if not allow_default_spawn and not saved_states.has(String(spec.id)):
			# A resumed save is authoritative. Do not recreate enemies that were
			# absent from its state, including legacy saves with no enemy snapshot.
			world_data.release_footprint(String(spec.id))
			continue
		if not saved_state.is_empty() and not bool(saved_state.get("visible", true)):
			continue
		var enemy = _overworld_combat_dummy.duplicate()
		add_child(enemy)
		enemy.name = String(spec.id)
		enemy.monster_id = String(spec.monster_id)
		enemy.sprite_asset_id = String(spec.sprite_id)
		enemy.collision_layer = 2
		enemy.collision_mask = 1
		enemy.visible = true
		var enemy_cell: Vector2i = _vector_from_dictionary(saved_state.get("cell", {})) if not saved_state.is_empty() else spec.cell
		enemy.global_position = world_position_for_cell_center(enemy_cell)
		var configured: Dictionary = enemy.configure_combat(catalog, player, player.combat_config)
		if configured.ok and bool(spec.get("boss", false)):
			enemy.combatant.hp_max *= 3
			enemy.combatant.hp = enemy.combatant.hp_max
			enemy.combatant.attack *= 2
		if configured.ok and not saved_state.is_empty():
			enemy.combatant.hp = clampi(int(saved_state.get("hp", enemy.combatant.hp)), 0, enemy.combatant.hp_max)
		if enemy.has_method("_apply_sprite"):
			enemy._apply_sprite()
		if enemy.has_signal("defeat_event"):
			var defeat_callback := Callable(self, "_on_dungeon_enemy_defeated").bind(enemy, String(spec.id))
			if not enemy.is_connected("defeat_event", defeat_callback):
				enemy.connect("defeat_event", defeat_callback)
		_connect_combat_sfx_source(enemy)
		_connect_acquisition_combat_source(enemy)
		if enemy.has_method("configure_grid_navigation"):
			enemy.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
		_dungeon_enemy_nodes.append(enemy)
		_dungeon_debug("실제 던전 몬스터 생성: id=%s ok=%s" % [spec.id, configured.get("ok", false)])
	combat_dummy = _dungeon_enemy_nodes.back() if not _dungeon_enemy_nodes.is_empty() else _overworld_combat_dummy

func _dungeon_regular_monster_ids(count: int) -> Array:
	var ids: Array = []
	var source_world: Dictionary = _overworld_generated_world if not _overworld_generated_world.is_empty() else generated_world
	var pool: Dictionary = source_world.get("monster_spawn_pool", {})
	var entries = pool.get("entries", [])
	if entries is Array:
		for entry in entries:
			if not entry is Dictionary:
				continue
			var monster_id := String(entry.get("monster_id", ""))
			if monster_id.is_empty() or ids.has(monster_id):
				continue
			if catalog != null and catalog.has_method("find_by_id") and catalog.find_by_id("monsters", monster_id).is_empty():
				continue
			ids.append(monster_id)
	if ids.is_empty():
		ids.append("road_bandit")
	var source_count := ids.size()
	while ids.size() < count:
		ids.append(ids[ids.size() % source_count])
	return ids.slice(0, count)

func _monster_sprite_asset_id(monster_id: String) -> String:
	var sprite_id := _content_image_asset_id("monsters", monster_id)
	if not sprite_id.is_empty():
		return sprite_id
	return "monster_%s_front_idle" % monster_id

func _clear_dungeon_combatants(restore_overworld := true) -> void:
	for enemy in _dungeon_enemy_nodes:
		if not is_instance_valid(enemy) or enemy == _overworld_combat_dummy:
			continue
		if enemy.has_method("deactivate_runtime"):
			enemy.deactivate_runtime()
		else:
			enemy.visible = false
		enemy.queue_free()
	_dungeon_enemy_nodes.clear()
	if restore_overworld and _overworld_combat_dummy != null:
		combat_dummy = _overworld_combat_dummy
		if combat_dummy.has_method("restore_after_world_transition"):
			combat_dummy.restore_after_world_transition(_overworld_combat_dummy_state)
		else:
			combat_dummy.visible = bool(_overworld_combat_dummy_state.get("visible", true))
		_overworld_combat_dummy_state.clear()

func _on_dungeon_enemy_defeated(_event: Dictionary, enemy, owner_id: String) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.visible = false
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	if world_data != null:
		world_data.release_footprint(owner_id)
	var remaining := _combat_targets().size()
	_dungeon_debug("던전 몬스터 처치: %s, remaining=%d" % [owner_id, remaining])
	var defeated_monster_id := String(_event.get("monster_id", _event.get("definition_id", "")))
	if defeated_monster_id.is_empty():
		defeated_monster_id = String(enemy.get("monster_id"))
	if defeated_monster_id.is_empty():
		var enemy_combatant = enemy.get("combatant")
		if enemy_combatant != null:
			defeated_monster_id = String(enemy_combatant.get("definition_id"))
	var dungeon_cleared := false
	if owner_id == DUNGEON_BOSS_OWNER_ID and dungeon_runtime != null:
		if not _dungeon_regular_combat_targets().is_empty():
			_dungeon_debug("일반 몬스터가 남아 있어 보스 클리어 보류")
			return
		var projection: Dictionary = dungeon_runtime.to_projection()
		var clear_result: Dictionary = dungeon_runtime.complete_boss_encounter({
			"event_type": "boss_encounter_resolved",
			"boss_id": String(projection.get("boss_id", "")),
			"encounter_id": String(projection.get("boss_encounter_id", "")),
			"dungeon_id": String(projection.get("dungeon_id", "")),
			"biome_id": String(projection.get("biome_id", "")),
			"resolution_type": "combat",
			"choice_key": "dungeon_boss_defeated",
			"run_flag": "dungeon_boss_defeated",
			"reward_item_ids": [],
			"progression_unlock_ids": [String(run_state.current_biome_id)]
		})
		_dungeon_debug("던전 보스 클리어 기록: ok=%s reason=%s" % [clear_result.get("ok", false), clear_result.get("reason", "")])
		if not clear_result.ok:
			return
		dungeon_cleared = true
	elif remaining == 0 and dungeon_runtime != null and _dungeon_boss_combat_available():
		var clear_result: Dictionary = dungeon_runtime.complete_dungeon({
			"objective_complete": true,
			"resolution_type": "combat",
			"choice_key": "dungeon_boss_defeated",
			"run_flag": "dungeon_boss_defeated",
			"reward_item_ids": [],
			"progression_unlock_ids": [String(run_state.current_biome_id)]
		})
		_dungeon_debug("던전 클리어 기록: ok=%s reason=%s" % [clear_result.get("ok", false), clear_result.get("reason", "")])
		if not clear_result.ok:
			return
		dungeon_cleared = true
	if game_hud != null:
		if not defeated_monster_id.is_empty():
			game_hud.show_status_event({
				"type": "enemy_defeated",
				"ok": true,
				"monster_id": defeated_monster_id,
				"event_id": owner_id
			})
		else:
			game_hud.show_status_toast("적을 처치했다!")
		if dungeon_cleared:
			game_hud.show_status_event({"type": "dungeon_floor_changed", "ok": true, "event_id": "dungeon_cleared"})
			game_hud.show_status_toast("던전 클리어! 유적으로 돌아가세요.")
	_save_progress_after_turn()

func _restore_dungeon_map_from_runtime() -> void:
	var projection: Dictionary = dungeon_runtime.to_projection()
	var saved_world: Dictionary = projection.get("world_data", {})
	if saved_world.is_empty():
		return
	var definition := _current_biome_dungeon_definition()
	if definition.is_empty():
		return
	definition["biome_id"] = String(run_state.current_biome_id)
	_enter_dungeon_map(WorldData.from_dictionary(saved_world), definition)

func _return_from_dungeon_map() -> void:
	if not _in_dungeon_map:
		return
	_enemy_turn_queued = false
	generated_world = _overworld_generated_world
	world_data = WorldData.from_dictionary(_overworld_world_data_snapshot)
	_in_dungeon_map = false
	_clear_dungeon_combatants()
	_configure_acquisition_for_generated_world()
	_render_generated_world(generated_world)
	player.global_position = world_position_for_cell_center(_overworld_player_cell)
	if combat_dummy != null:
		combat_dummy.global_position = world_position_for_cell_center(_overworld_combat_dummy_cell)
		if combat_dummy.has_method("configure_grid_navigation"):
			combat_dummy.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
	_configure_game_hud()

func _ensure_saved_world_has_teleport_landmark() -> bool:
	if _in_dungeon_map or world_data == null:
		return false
	for landmark in world_data.get_required_landmarks():
		if String(landmark.get("kind", landmark.get("type", ""))) == WorldData.LANDMARK_TELEPORT_ZONE:
			return false
	var width: int = int(world_data.width)
	var height: int = int(world_data.height)
	var center_x: int = maxi(1, width / 2)
	var center_y: int = maxi(1, height / 2)
	var candidate: Vector2i = Vector2i(center_x, center_y)
	for radius in range(maxi(width, height)):
		for offset in [Vector2i.ZERO, Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
			var cell: Vector2i = candidate + offset
			if not world_data.contains(cell) or not world_data.is_walkable(cell):
				continue
			var id := "%s_0" % WorldData.LANDMARK_TELEPORT_ZONE
			var metadata := {"teleport_biome_id": String(run_state.current_biome_id), "migrated": true}
			world_data.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, id, cell, metadata)
			generated_world["world_data"] = world_data.to_dictionary()
			generated_world["landmarks"] = world_data.get_required_landmarks()
			var projection: Dictionary = biome_progression_state.to_projection() if biome_progression_state != null else {}
			generated_world["renderer_input"] = WorldRendererProjection.new().project(generated_world["world_data"], projection)
			_dungeon_debug("기존 세이브에 텔레포트 추가: id=%s cell=%s" % [id, cell])
			return true
	return false

func _current_biome_dungeon_definition() -> Dictionary:
	return dungeon_definition_resolver.current_biome_dungeon_definition(catalog, run_state)

func _current_biome_boss_definition(biome_id: String, dungeon_id: String) -> Dictionary:
	return dungeon_definition_resolver.current_biome_boss_definition(catalog, biome_id, dungeon_id)

func _pre_boss_dialogue_event_id_for(dungeon_definition: Dictionary, boss_definition := {}) -> String:
	return dungeon_definition_resolver.pre_boss_dialogue_event_id_for(catalog, narrative_runtime, dungeon_definition, boss_definition)

func _normalize_reward_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": result, "reason": "additional_reward_hook_rejected", "error": "Additional dungeon reward hook rejected completion."}
	return {"ok": true, "value": result}

func _configure_acquisition_for_generated_world() -> Dictionary:
	if not generated_world.get("ok", false) or typeof(generated_world.get("world_data")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_generated_world", "error": "Acquisition requires a generated world snapshot."}
	var biome_id := String(generated_world.get("biome_id", run_state.current_biome_id if run_state != null else ""))
	_prepare_runtime_state_aliases_for_biome(biome_id)
	var saved_acquisitions := run_state.acquisitions.duplicate(true) if run_state != null else {}
	world_data = WorldData.from_dictionary(generated_world.world_data)
	var facility_restore_result := _restore_placed_facilities_for_current_biome()
	if not facility_restore_result.ok:
		return facility_restore_result
	var repair_restore_result: Dictionary = {"ok": true}
	if repair_interaction_service != null:
		repair_restore_result = repair_interaction_service.apply_saved_target_states(world_data, run_state)
	if not repair_restore_result.ok:
		return repair_restore_result
	acquisition_service = AcquisitionService.new()
	var definitions := _acquisition_definitions().confirmed_generated_resource_definitions(generated_world.get("resource_nodes", []))
	definitions.append_array(_acquisition_definitions().terrain_tree_gatherable_definitions())
	definitions.append_array(_acquisition_definitions().mountain_mineral_gatherable_definitions())
	var configured: Dictionary = acquisition_service.configure(inventory, world_data, definitions, _generated_drop_definitions())
	if not configured.ok:
		return configured
	var definition_ids := {}
	for definition in definitions:
		definition_ids[String(definition.id)] = true
	for node in generated_world.get("resource_nodes", []):
		var resource_id := String(node.get("resource_id", ""))
		if not definition_ids.has(resource_id):
			continue
		var registered: Dictionary = acquisition_service.register_gatherable(
			String(node.get("id", "")),
			resource_id,
			_vector_from_dictionary(node.get("position", {}))
		)
		if not registered.ok:
			return registered
	var terrain_tree_result := _acquisition_definitions().register_terrain_tree_gatherables(definition_ids, acquisition_service)
	if not terrain_tree_result.ok:
		return terrain_tree_result
	var mountain_mineral_result := _acquisition_definitions().register_mountain_mineral_gatherables(definition_ids, acquisition_service)
	if not mountain_mineral_result.ok:
		return mountain_mineral_result
	if not saved_acquisitions.is_empty():
		var loaded: Dictionary = acquisition_service.load_snapshot(saved_acquisitions)
		if not loaded.ok:
			return loaded
		terrain_tree_result = _acquisition_definitions().register_terrain_tree_gatherables(definition_ids, acquisition_service)
		if not terrain_tree_result.ok:
			return terrain_tree_result
	# Acquisition restore and player facilities mutate the runtime WorldData.
	# Refresh the generated projection before the first render so a resumed run
	# does not briefly show the pristine generated map.
	generated_world["world_data"] = world_data.to_dictionary()
	var restored_renderer_input: Dictionary = WorldRendererProjection.new().project(generated_world["world_data"])
	generated_world["renderer_input"] = restored_renderer_input
	acquisition_service.changed.connect(_on_acquisition_changed)
	acquisition_service.acquisition_completed.connect(_on_acquisition_completed)
	_on_acquisition_changed(acquisition_service.to_snapshot())
	return {"ok": true}

func _is_repair_interaction_target(target_id: String) -> bool:
	return repair_interaction_service != null and repair_interaction_service.has_target(target_id)

func _handle_repair_interaction_command(command: GameCommand) -> Dictionary:
	if repair_interaction_service == null:
		return {"ok": false, "reason": "missing_repair_interaction_service"}
	var result: Dictionary = repair_interaction_service.handle_command(
		String(command.payload.get("action_id", "")),
		String(command.payload.get("target_id", "")),
		inventory,
		run_state,
		world_data,
		String(generated_world.get("biome_id", run_state.current_biome_id if run_state != null else ""))
	)
	if not result.ok:
		return result
	_store_current_biome_runtime_aliases()
	save_current_run()
	_sync_runtime_world_render()
	_configure_game_hud()
	return result

func _node_kind_for_resource_context(item_id: String, biome_id: String) -> String:
	return _acquisition_definitions().node_kind_for_resource_context(item_id, biome_id)

func _generated_drop_definitions() -> Array:
	return _acquisition_definitions().generated_drop_definitions()

func _connect_acquisition_combat_source(source) -> Dictionary:
	if source == null or not source.has_signal("drop_requested"):
		return {"ok": false, "reason": "invalid_drop_source", "error": "Combat source must expose drop_requested."}
	var callback := Callable(self, "_on_combat_drop_requested").bind(source)
	if not source.is_connected("drop_requested", callback):
		source.connect("drop_requested", callback)
	return {"ok": true}

func _connect_combat_sfx_source(source) -> void:
	if source == null or not source.has_signal("damaged"):
		return
	var callback := Callable(self, "_on_combat_target_damaged")
	if not source.is_connected("damaged", callback):
		source.connect("damaged", callback)

func _on_combat_target_damaged(event: Dictionary, applied_damage: int) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_COMBAT_HIT, {"event": event, "applied_damage": applied_damage}, String(event.get("swing_id", "combat_hit")))

func _on_acquisition_changed(snapshot: Dictionary) -> void:
	if run_state != null and not _in_dungeon_map:
		run_state.acquisitions = snapshot.duplicate(true)
		_store_current_biome_runtime_aliases()
	_sync_runtime_world_render()

func _on_acquisition_completed(result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not result.get("position", null) is Dictionary:
		return
	_play_sfx_event(SfxEventRouter.event_id_for_acquisition(result), result, String(result.get("pickup_id", result.get("node_id", result.get("item_id", "acquisition")))))
	var item_id := String(result.get("item_id", ""))
	if item_id.is_empty():
		return
	var source_id := String(result.get("source_id", result.get("node_id", result.get("id", result.get("target_id", "")))))
	if _is_mining_target(source_id) and world_data != null:
		# Direct dungeon gathering grants the item immediately, so clear the
		# reservation as soon as the node is depleted to keep the tile walkable.
		world_data.release_footprint(source_id)
	var item_name := item_id
	if catalog != null and catalog.has_method("find_by_id"):
		var definition: Dictionary = catalog.find_by_id("items", item_id)
		item_name = String(definition.get("name", item_id))
	var effect := AcquisitionEffect.new()
	effect.name = "AcquisitionEffect"
	effect.configure(
		String(result.get("kind", AcquisitionService.PICKUP_KIND)),
		item_name,
		int(result.get("quantity", 0)),
		world_position_for_cell_center(_vector_from_dictionary(result.position))
	)
	add_child(effect)
	if game_hud != null:
		game_hud.show_status_event({
			"type": "item_acquired",
			"ok": true,
			"item_id": item_id,
			"quantity": int(result.get("quantity", 0)),
			"event_id": String(result.get("pickup_id", result.get("node_id", result.get("id", result.get("target_id", "")))))
		})

func _on_combat_drop_requested(event: Dictionary, source = null) -> void:
	if acquisition_service == null:
		return
	var normalized := event.duplicate(true)
	var drop_source = source if source is Node2D and is_instance_valid(source) else combat_dummy
	if not normalized.has("position") and drop_source is Node2D and is_instance_valid(drop_source):
		var drop_cell := world_cell_from_world_position(drop_source.global_position)
		normalized.position = {
			"x": drop_cell.x,
			"y": drop_cell.y
		}
	var evaluation_context := {
		"run_seed": int(run_state.seed) if run_state != null else FRESH_RUN_SEED,
		"time_phase": String(time_state.phase) if time_state != null else ""
	}
	var result: Dictionary = acquisition_service.process_drop_request(normalized, Vector2i.ZERO, evaluation_context)
	if not result.ok:
		push_error(result.error)

func _on_combat_dummy_defeated(_event: Dictionary) -> void:
	if combat_dummy == null:
		return
	combat_dummy.visible = false
	combat_dummy.automatic_attacks = false
	combat_dummy.collision_layer = 0
	combat_dummy.collision_mask = 0
	_save_progress_after_turn()

func _snapshot_overworld_enemy_state() -> Dictionary:
	if combat_dummy == null or not is_instance_valid(combat_dummy):
		return {}
	var cell := _combat_target_cell(combat_dummy)
	return {
		"cell": {"x": cell.x, "y": cell.y},
		"monster_id": String(combat_dummy.monster_id),
		"hp": int(combat_dummy.current_hp()) if combat_dummy.has_method("current_hp") else 0,
		"visible": combat_dummy.visible,
		"automatic_attacks": combat_dummy.automatic_attacks,
		"collision_layer": combat_dummy.collision_layer,
		"collision_mask": combat_dummy.collision_mask
	}

func _restore_overworld_enemy_state() -> void:
	if _in_dungeon_map or combat_dummy == null or not is_instance_valid(combat_dummy) or run_state == null:
		return
	var saved: Dictionary = run_state.overworld_enemy_state
	if saved.is_empty():
		return
	var saved_cell: Dictionary = saved.get("cell", {})
	if not saved_cell.is_empty():
		var cell := _vector_from_dictionary(saved_cell)
		if world_data != null and world_data.contains(cell):
			combat_dummy.global_position = world_position_for_cell_center(cell)
	if combat_dummy.combatant != null:
		combat_dummy.combatant.hp = clampi(int(saved.get("hp", combat_dummy.combatant.hp)), 0, combat_dummy.combatant.hp_max)
	combat_dummy.visible = bool(saved.get("visible", true))
	combat_dummy.automatic_attacks = bool(saved.get("automatic_attacks", true))
	combat_dummy.collision_layer = int(saved.get("collision_layer", 2))
	combat_dummy.collision_mask = int(saved.get("collision_mask", 1))

func _queue_enemy_turn_after_player_action() -> void:
	if _enemy_turn_queued:
		return
	_enemy_turn_queued = true
	call_deferred("_run_enemy_turn_after_player_action")

func _run_enemy_turn_after_player_action() -> void:
	if not _enemy_turn_queued:
		return
	if player != null and player.has_method("is_grid_step_active") and player.is_grid_step_active():
		var scene_tree := get_tree()
		if scene_tree == null:
			_enemy_turn_queued = false
			return
		scene_tree.process_frame.connect(Callable(self, "_run_enemy_turn_after_player_action"), CONNECT_ONE_SHOT)
		return
	for enemy in _combat_targets():
		if enemy.has_method("is_grid_step_active") and enemy.is_grid_step_active():
			var scene_tree := get_tree()
			if scene_tree != null:
				scene_tree.process_frame.connect(Callable(self, "_run_enemy_turn_after_player_action"), CONNECT_ONE_SHOT)
			return
	_enemy_turn_queued = false
	if player == null:
		return
	for enemy in _combat_targets():
		if enemy.has_method("take_turn"):
			enemy.take_turn(player)
	_save_progress_after_turn()

func _save_progress_after_turn() -> void:
	if run_state == null or save_store == null:
		return
	var result: Dictionary = save_current_run()
	if not bool(result.get("ok", false)):
		push_error(String(result.get("error", "Failed to save run progress.")))

func _advance_time_for_turn() -> void:
	var player_resources = player.get("resources") if player != null else null
	if time_state == null or player_resources == null:
		return
	time_state.tick(_time_seconds_per_turn(), player_resources)

func _time_seconds_per_turn() -> float:
	return RuntimeConstants.float_value("game.turn_seconds")

func _on_player_hp_depleted() -> Dictionary:
	if run_lifecycle_service == null:
		return {"ok": false, "reason": "missing_run_lifecycle", "error": "Run lifecycle service is not configured."}
	var result: Dictionary = run_lifecycle_service.resolve_lethal_hp(
		player.resources,
		inventory,
		player.combat_state,
		player.get_combat_id()
	)
	if not result.ok:
		push_error(result.error)
		return result
	if String(result.get("state", "")) != "death_pending":
		return result
	var replacement := _replace_confirmed_dead_run()
	if not replacement.ok:
		push_error(replacement.error)
	return replacement

func _replace_confirmed_dead_run() -> Dictionary:
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
		var preserved_activation := _activate_run_state(preserved_run)
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
		FRESH_RUN_SEED
	)
	var save_result: Dictionary = save_store.save_run(fresh_run)
	if not save_result.ok:
		return save_result
	_show_the_end_and_return_to_start()
	return {
		"ok": true,
		"state": "fresh_run",
		"invalidated_lifecycle_epoch": int(confirmed.invalidated_lifecycle_epoch),
		"lifecycle_epoch": fresh_run.lifecycle_epoch
	}

func _show_the_end_and_return_to_start() -> void:
	if _death_transition_active:
		return
	_death_transition_active = true
	MainSceneOverlays.show_ending(self)
	await get_tree().create_timer(THE_END_DURATION_SECONDS).timeout
	get_tree().change_scene_to_file(START_SCREEN_SCENE_PATH)

func _activate_run_state(state: RunState) -> Dictionary:
	run_state = state
	var services_result := _configure_run_services(catalog)
	if not services_result.ok:
		return services_result
	var combat_lifecycle_result := _configure_combat_lifecycle()
	if not combat_lifecycle_result.ok:
		return combat_lifecycle_result
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		return world_result
	return {"ok": true}

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

func _prepare_runtime_state_aliases_for_biome(biome_id: String) -> void:
	if run_state == null or biome_id.is_empty():
		return
	_migrate_legacy_runtime_aliases(biome_id)
	run_state.acquisitions = _dictionary_value(run_state.biome_acquisitions.get(biome_id, {}))
	run_state.map_discovery = _dictionary_value(run_state.map_discovery_by_biome.get(biome_id, {}))

func _store_current_biome_runtime_aliases(biome_id := "") -> void:
	if run_state == null:
		return
	var target_biome_id := biome_id
	if target_biome_id.is_empty():
		target_biome_id = _current_runtime_biome_id()
	if target_biome_id.is_empty():
		return
	run_state.biome_acquisitions[target_biome_id] = run_state.acquisitions.duplicate(true)
	run_state.map_discovery_by_biome[target_biome_id] = run_state.map_discovery.duplicate(true)

func _migrate_legacy_runtime_aliases(biome_id: String) -> void:
	if run_state == null:
		return
	if biome_id.is_empty():
		return
	if not run_state.acquisitions.is_empty() and run_state.biome_acquisitions.is_empty():
		run_state.biome_acquisitions[biome_id] = run_state.acquisitions.duplicate(true)
	if not run_state.map_discovery.is_empty() and run_state.map_discovery_by_biome.is_empty():
		run_state.map_discovery_by_biome[biome_id] = run_state.map_discovery.duplicate(true)

func _current_runtime_biome_id() -> String:
	if run_state == null:
		return ""
	var world_biome_id := String(generated_world.get("biome_id", "")) if typeof(generated_world) == TYPE_DICTIONARY else ""
	return world_biome_id if not world_biome_id.is_empty() else String(run_state.current_biome_id)

func _restore_run_state_from_snapshot(snapshot: Dictionary) -> void:
	if run_state == null:
		run_state = RunState.new()
	var restored: RunState = RunState.from_dictionary(snapshot)
	for field in restored.to_dictionary().keys():
		run_state.set(String(field), restored.get(String(field)))

func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func world_cell_from_world_position(world_position: Vector2) -> Vector2i:
	var tile_size := _runtime_tile_size()
	var local_position := world_position - _runtime_world_origin()
	return Vector2i(int(floor(local_position.x / tile_size)), int(floor(local_position.y / tile_size)))

func world_position_from_viewport_position(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * viewport_position

func world_position_for_cell_center(cell: Vector2i) -> Vector2:
	var tile_size := _runtime_tile_size()
	return _runtime_world_origin() + Vector2(
		cell.x * tile_size + tile_size * 0.5,
		cell.y * tile_size + tile_size * 0.5
	)

func _pointer_movement_command() -> GameCommand:
	if player == null:
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	return _pointer_route_controller.movement_command(
		player.global_position,
		POINTER_MOVE_STOP_DISTANCE_PIXELS,
		Callable(self, "world_position_for_cell_center"),
		Callable(self, "_complete_pending_pointer_interaction_from_pointer_route")
	)
func _clear_pointer_movement() -> void:
	_pointer_route_controller.clear()
func _complete_pending_pointer_interaction_from_pointer_route(target_id: String, target_cell: Vector2i) -> void:
	if target_id.is_empty() or (not _is_available_acquisition_target(target_id) and not _is_landmark_target(target_id)):
		_dungeon_debug("이동 완료 후 대상 무효: target=%s" % target_id)
		return
	if player == null or not _player_can_interact_with_target(world_cell_from_world_position(player.global_position), target_id, target_cell):
		_dungeon_debug("이동 완료했지만 상호작용 거리 불충족: player_cell=%s target=%s target_cell=%s" % [world_cell_from_world_position(player.global_position) if player != null else "nil", target_id, target_cell])
		return
	_dungeon_debug("입구 도착, 상호작용 실행: target=%s cell=%s" % [target_id, target_cell])
	if _is_dungeon_resource_target(target_id):
		_gather_dungeon_ore(target_id, target_cell)
	elif _is_landmark_target(target_id):
		submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))
	else:
		submit_interaction_at_world_cell(target_cell)
func _cells_are_adjacent(first: Vector2i, second: Vector2i) -> bool:
	return _spatial_resolver.cells_are_adjacent(first, second)
func _nearest_walkable_adjacent_cell(target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	return _spatial_resolver.nearest_walkable_adjacent_cell(world_data, target_cell, player_cell)
func _nearest_walkable_adjacent_cell_for_target(target_id: String, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	return _spatial_resolver.nearest_walkable_adjacent_cell_for_target(world_data, target_id, target_cell, player_cell)
func _runtime_tile_size() -> float:
	if world_data != null:
		return float(world_data.tile_size)
	var renderer_input: Dictionary = generated_world.get("renderer_input", {})
	return float(int(renderer_input.get("tile_size", RuntimeConstants.float_value("world.tile_size_pixels"))))

func _runtime_world_origin() -> Vector2:
	if world_visuals != null:
		return world_visuals.global_position
	var renderer_input: Dictionary = generated_world.get("renderer_input", {})
	if not renderer_input.is_empty():
		return _centered_world_origin(renderer_input)
	return Vector2.ZERO

func _interaction_candidate_cells(origin_cell: Vector2i, direction := Vector2i.ZERO) -> Array:
	return _spatial_resolver.interaction_candidate_cells(origin_cell, _resolved_grid_direction(direction))
func _pointer_candidate_cells(clicked_cell: Vector2i) -> Array:
	return _spatial_resolver.pointer_candidate_cells(clicked_cell)
func _resolved_grid_direction(direction: Vector2i) -> Vector2i:
	if direction != Vector2i.ZERO:
		return Vector2i(clampi(direction.x, -1, 1), clampi(direction.y, -1, 1))
	if player != null and player.get("movement_state") != null:
		match player.movement_state.facing:
			PlayerMovementState.Facing.DOWN:
				return Vector2i.DOWN
			PlayerMovementState.Facing.LEFT:
				return Vector2i.LEFT
			PlayerMovementState.Facing.RIGHT:
				return Vector2i.RIGHT
			PlayerMovementState.Facing.UP:
				return Vector2i.UP
	return Vector2i.DOWN

func _interaction_target_id_for_cell(cell: Vector2i) -> String:
	return _spatial_resolver.interaction_target_id_for_cell(world_data, _in_dungeon_map, cell, Callable(self, "_is_available_acquisition_target"))
func _player_can_interact_with_target(player_cell: Vector2i, target_id: String, target_cell: Vector2i) -> bool:
	return _spatial_resolver.player_can_interact_with_target(world_data, _in_dungeon_map, player_cell, target_id, target_cell)
func _target_footprint_cells(target_id: String, fallback_cell: Vector2i) -> Array:
	return _spatial_resolver.target_footprint_cells(world_data, target_id, fallback_cell)
func _dungeon_interaction_target_near_cell(origin_cell: Vector2i) -> Dictionary:
	return _spatial_resolver.dungeon_interaction_target_near_cell(world_data, _in_dungeon_map, origin_cell, _resolved_grid_direction(Vector2i.ZERO))
func _is_landmark_target(target_id: String) -> bool:
	return _spatial_resolver.is_landmark_target(_in_dungeon_map, target_id)
func _is_core_dungeon_target(target_id: String) -> bool:
	return _spatial_resolver.is_core_dungeon_target(target_id)
func _handle_landmark_interaction(target_id: String) -> bool:
	if _in_dungeon_map and target_id == "dungeon_entry":
		if dungeon_runtime == null:
			return false
		var lifecycle := String(dungeon_runtime.to_projection().get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE))
		if lifecycle == DungeonInstanceState.STATE_ACTIVE and _combat_targets().is_empty() and _dungeon_boss_combat_available():
			var clear_result: Dictionary = dungeon_runtime.complete_dungeon({"objective_complete": true, "resolution_type": "combat", "choice_key": "dungeon_boss_defeated", "run_flag": "dungeon_boss_defeated", "reward_item_ids": [], "progression_unlock_ids": [String(run_state.current_biome_id)]})
			if not clear_result.ok:
				return false
			lifecycle = DungeonInstanceState.STATE_COMPLETED
		if lifecycle != DungeonInstanceState.STATE_COMPLETED:
			return false
		if not dungeon_runtime.begin_return().ok or not dungeon_runtime.finish_return().ok:
			return false
		_return_from_dungeon_map()
		save_current_run()
		_configure_game_hud()
		if game_hud != null:
			game_hud.show_command_feedback("던전에서 귀환")
			game_hud.show_status_event({
				"type": "dungeon_exited",
				"ok": true,
				"dungeon_id": String(dungeon_runtime.to_projection().get("dungeon_id", "")),
				"event_id": "return:%s" % target_id
			})
		return true
	if _is_core_dungeon_target(target_id):
		_dungeon_debug("던전 랜드마크 상호작용: %s" % target_id)
		if run_state != null and run_state.completed_dungeon_ids.has(String(run_state.current_biome_id)):
			if game_hud != null:
				game_hud.show_command_feedback("유적 수리 완료 · 이동은 텔레포트를 이용하세요")
			return true
		return _handle_complete_dungeon_command(GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"entry_only": true}))
	if target_id.begins_with("%s_" % WorldData.LANDMARK_BOSS_ANCHOR):
		_dungeon_debug("보스 앵커 상호작용: %s" % target_id)
		if run_state != null and run_state.completed_dungeon_ids.has(String(run_state.current_biome_id)):
			if game_hud != null:
				game_hud.show_command_feedback("이미 정리한 보스 흔적입니다")
			return true
		return _handle_complete_dungeon_command(GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"entry_only": true, "target_id": target_id}))
	if target_id.begins_with("%s_" % WorldData.LANDMARK_RUIN):
		var current_biome_id := String(run_state.current_biome_id) if run_state != null else ""
		var dungeon_cleared := run_state != null and run_state.completed_dungeon_ids.has(current_biome_id)
		if dungeon_cleared:
			if game_hud != null:
				game_hud.show_ruin_travel_menu()
			return true
		if game_hud != null:
			game_hud.show_command_feedback("유적 연결은 던전 클리어 후 이용할 수 있습니다")
		return true
	if target_id.begins_with("%s_" % WorldData.LANDMARK_TELEPORT_ZONE):
		var biome_id := String(run_state.current_biome_id) if run_state != null else ""
		var progression := _ensure_biome_progression_state()
		if not progression.ok:
			return false
		if dungeon_runtime != null and _in_dungeon_map and _combat_targets().is_empty() and _dungeon_boss_combat_available():
			var clear_result: Dictionary = dungeon_runtime.complete_dungeon({"objective_complete": true, "resolution_type": "combat", "choice_key": "dungeon_boss_defeated", "run_flag": "dungeon_boss_defeated", "reward_item_ids": [], "progression_unlock_ids": [biome_id]})
			if clear_result.ok:
				_dungeon_debug("유적 접근 전 미기록 던전 클리어 보정 완료")
		var teleport_state: String = String(run_state.teleport_states.get(biome_id, "")) if run_state != null else biome_progression_state.teleport_state_for(biome_id)
		if teleport_state != BiomeProgressionState.TELEPORT_REPAIRED:
			return _handle_biome_progression_command(GameCommand.new(GameCommand.Type.REPAIR_TELEPORT, Vector2i.ZERO, -1, {"biome_id": biome_id}))
		if game_hud != null:
			game_hud.show_teleport_travel_menu()
		return true
	return false

func _travel_to_biome(biome_id: String, travel_mode: String = "teleport") -> bool:
	if run_state == null or biome_id.is_empty():
		return false
	var current_id := String(run_state.current_biome_id)
	var progression := _ensure_biome_progression_state()
	if not progression.ok or biome_id == current_id:
		return false
	var can_travel := false
	if travel_mode == "ruin":
		can_travel = run_state.completed_dungeon_ids.has(biome_id)
	else:
		can_travel = _is_connected_biome(current_id, biome_id)
	if not can_travel:
		if game_hud != null:
			game_hud.show_command_feedback("텔레포트 연결 조건을 만족하지 않았습니다")
		return false
	var rollback_snapshot := run_state.to_dictionary()
	var rollback_generated_world := generated_world.duplicate(true)
	_store_current_biome_runtime_aliases(current_id)
	run_state.current_biome_id = biome_id
	if travel_mode != "ruin":
		run_state.teleport_states[biome_id] = BiomeProgressionState.TELEPORT_BROKEN
	biome_progression_state = null
	_create_loading_overlay()
	_set_loading_status("%s 지역으로 이동하는 중…" % _loading_biome_label())
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		_restore_run_state_from_snapshot(rollback_snapshot)
		generated_world = rollback_generated_world.duplicate(true)
		biome_progression_state = null
		var rollback_world_result := _configure_world_for_current_run()
		if not rollback_world_result.ok:
			push_error(String(rollback_world_result.get("error", "Failed to restore previous biome world after travel failure.")))
		_clear_loading_overlay()
		return false
	_clear_loading_overlay()
	save_current_run()
	if game_hud != null:
		game_hud.show_status_event({
			"type": "biome_transition",
			"ok": true,
			"biome_id": biome_id,
			"event_id": "%s:%s" % [travel_mode, biome_id]
		})
	return true

func _is_connected_biome(from_id: String, to_id: String) -> bool:
	if biome_progression_state == null:
		return false
	var ordered: Array = biome_progression_state.to_projection().get("biome_order", [])
	var from_index := ordered.find(from_id)
	var to_index := ordered.find(to_id)
	if from_index < 0 or to_index < 0 or absi(from_index - to_index) != 1:
		return false
	var current_teleport_repaired := String(run_state.teleport_states.get(from_id, "")) == BiomeProgressionState.TELEPORT_REPAIRED
	if not current_teleport_repaired:
		return false
	# The repaired current gate opens the next adjacent biome. A destination
	# may still be marked undiscovered until the player first arrives there.
	if to_index > from_index:
		return to_index == from_index + 1
	return run_state.completed_dungeon_ids.has(to_id) or String(run_state.teleport_states.get(to_id, "")) != "undiscovered"

func _is_available_acquisition_target(target_id: String) -> bool:
	if acquisition_service == null or target_id.is_empty():
		return false
	var gatherable: Dictionary = acquisition_service.gatherable_for(target_id)
	if not gatherable.is_empty():
		return not bool(gatherable.get("depleted", false))
	return not acquisition_service.pickup_for(target_id).is_empty()

func _handle_tea_command(command: GameCommand) -> bool:
	return _player_item_actions.start_tea(command, tea_service, player.get("resources") if player != null else null)

func is_tea_drink_active() -> bool:
	return _player_item_actions.is_tea_drink_active()

func tick_tea_runtime(delta_seconds: float) -> Dictionary:
	return _player_item_actions.tick_tea(delta_seconds, tea_service, player.get("resources") if player != null else null)

func is_consumable_use_active() -> bool:
	return _player_item_actions.is_consumable_use_active(consumable_service)

func tick_consumable_runtime(delta_seconds: float) -> Dictionary:
	return _player_item_actions.tick_consumable(delta_seconds, consumable_service, inventory, player.get("resources") if player != null else null)

func _interrupt_consumable_use(reason := "hit") -> Dictionary:
	return _player_item_actions.interrupt_consumable(consumable_service, reason)

func _handle_consumable_command(command: GameCommand) -> bool:
	if consumable_service == null or inventory == null or player == null or player.resources == null:
		return false
	var item_id := _consumable_item_id_for_command(command)
	if item_id.is_empty():
		return false
	var start: Dictionary = _start_consumable_use(item_id, {"command_slot": command.slot, "source": "quickslot"})
	if game_hud != null:
		game_hud.show_command_feedback(
			"소모품 사용 중: %s" % item_id
			if start.ok
			else "소모품 실패: %s" % String(start.get("reason", "unknown"))
		)
	return bool(start.ok)

func _start_consumable_use(item_id: String, context := {}) -> Dictionary:
	return _player_item_actions.start_consumable(item_id, context, consumable_service, inventory)

func _consumable_item_id_for_command(command: GameCommand) -> String:
	return _player_item_actions.consumable_item_id_for_command(command, consumable_service, inventory)

func _handle_sleep_command() -> bool:
	if time_state == null or player == null or player.resources == null:
		return false
	var facility_result := _sleep_facility_interaction_at_player()
	if not facility_result.ok:
		if game_hud != null:
			game_hud.show_command_feedback(_sleep_facility_failure_message(String(facility_result.get("reason", "sleep_facility_unavailable"))))
		return false
	var result: Dictionary = time_state.sleep_until_morning(player.resources)
	if game_hud != null:
		game_hud.show_command_feedback("수면 완료: HP +%d / 心 +%d" % [
			int(result.get("hp_healed", 0)),
			int(result.get("kokoro_restored", 0))
		])
	save_current_run()
	_configure_game_hud()
	return true

func _sleep_facility_interaction_at_player() -> Dictionary:
	if facility_placement_service == null or world_data == null:
		return {"ok": false, "reason": "missing_facility_capability"}
	return facility_placement_service.facility_interaction_at(world_data, _player_world_cell(), "sleep")

func _sleep_facility_failure_message(reason: String) -> String:
	match reason:
		"interaction_tile_blocked":
			return "수면 불가: 시설 앞이 막혀 있습니다."
		"facility_interaction_out_of_position":
			return "수면 불가: 시설 정면에서만 가능합니다."
		"interaction_tile_out_of_bounds":
			return "수면 불가: 시설 정면 타일이 맵 밖입니다."
		_:
			return "수면 불가: 잘 수 있는 시설이 필요합니다."

func _handle_tea_brewing_command(command: GameCommand) -> bool:
	if tea_brewing_command_runtime == null:
		return false
	var result: Dictionary = tea_brewing_command_runtime.handle_command(command)
	if game_hud != null:
		game_hud.show_command_feedback(
			"차 우리기 완료"
			if result.ok and command.type == GameCommand.Type.BREW_TEA
			else "차 우리기 갱신"
			if result.ok
			else "차 우리기 실패: %s" % String(result.get("reason", "unknown"))
		)
	if not result.ok:
		return false
	_sync_run_runtime_state()
	if game_hud != null:
		game_hud.show_tea_brewing_menu()
	return true

func _handle_meta_codex_command(command: GameCommand) -> bool:
	if meta_codex_command_runtime == null:
		return false
	var result: Dictionary = meta_codex_command_runtime.handle_command(command)
	if game_hud != null:
		game_hud.show_command_feedback("도감 갱신" if result.ok else "도감 실패: %s" % String(result.get("reason", "unknown")))
	if not result.ok:
		return false
	if game_hud != null:
		game_hud.show_meta_codex_menu()
	return true

func _handle_craft_recipe_command(command: GameCommand) -> bool:
	if crafting_service == null or inventory == null:
		return false
	var recipe_id := String(command.payload.get("recipe_id", ""))
	if recipe_id.is_empty():
		return false
	var result: Dictionary = _craft_recipe_or_begin_facility_placement(recipe_id)
	if game_hud != null:
		if bool(result.get("placement_pending", false)):
			game_hud.show_command_feedback("설치할 타일을 선택하세요. (플레이어 기준 2칸 이내)")
		else:
			game_hud.show_command_feedback(
				"제작 완료: %s" % result.get("result_item_id", recipe_id)
				if result.ok
				else "제작 불가: %s" % String(result.get("reason", "unknown"))
			)
	if result.ok and not bool(result.get("placement_pending", false)):
		_sync_run_runtime_state()
		save_current_run()
		_configure_game_hud()
		if game_hud != null:
			game_hud.show_status_event({
				"type": "craft_completed",
				"ok": true,
				"result_item_id": String(result.get("result_item_id", "")),
				"quantity": int(result.get("result_quantity", 0)),
				"event_id": recipe_id
			})
	return bool(result.ok)

func _craft_recipe_or_begin_facility_placement(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = crafting_service.recipe_for(recipe_id)
	var result_item_id := String(recipe.get("result_item_id", ""))
	if not crafting_service.is_facility_item(result_item_id):
		return crafting_service.craft(recipe_id, inventory, _crafting_context())
	if _in_dungeon_map:
		return {"ok": false, "reason": "facility_installation_requires_overworld"}
	if facility_placement_service == null or world_data == null or player == null:
		return {"ok": false, "reason": "facility_placement_unavailable"}
	var result := _facility_placement_session.begin_or_craft_recipe(
		recipe_id, crafting_service, inventory, _crafting_context(),
		facility_placement_service, world_data, _player_world_cell(),
		_in_dungeon_map, _player_facility_metadata(result_item_id)
	)
	if not result.ok:
		return result
	_clear_pointer_movement()
	_clear_facility_placement_preview()
	if game_hud != null:
		game_hud.hide_menu()
		game_hud.show_facility_placement_controls()
	var initial_origin: Vector2i = result.get("initial_origin", Vector2i(-1, -1))
	if initial_origin.x >= 0:
		_select_pending_facility_at(initial_origin)
	result.erase("initial_origin")
	return result

func has_pending_facility_placement() -> bool:
	return _facility_placement_session.has_pending()

func _select_pending_facility_at(origin: Vector2i) -> void:
	var validation := _facility_placement_session.select_origin(origin, facility_placement_service, world_data, _player_world_cell())
	_update_facility_placement_preview(validation)
	if game_hud != null:
		game_hud.update_facility_placement_controls(
			bool(validation.get("ok", false)),
			"설치 가능" if bool(validation.get("ok", false)) else _facility_placement_reason(String(validation.get("reason", "invalid_placement")))
		)

func _rotate_pending_facility() -> bool:
	var result := _facility_placement_session.rotate(facility_placement_service, world_data, _player_world_cell())
	if not bool(result.get("ok", false)):
		return false
	if _pending_facility_origin.x >= 0:
		_update_facility_placement_preview(result)
		if game_hud != null:
			game_hud.update_facility_placement_controls(
				bool(result.get("ok", false)),
				"설치 가능" if bool(result.get("ok", false)) else _facility_placement_reason(String(result.get("reason", "invalid_placement")))
			)
	elif game_hud != null:
		game_hud.update_facility_placement_controls(true, "방향 %d°" % (_pending_facility_rotation * 90))
	return true

func _confirm_pending_facility() -> bool:
	if not has_pending_facility_placement() or _pending_facility_origin.x < 0 or _pending_facility_result.is_empty():
		return false
	if not bool(_pending_facility_result.get("ok", false)):
		_select_pending_facility_at(_pending_facility_origin)
		return false
	var placed := _place_pending_facility(_pending_facility_result)
	return bool(placed.get("ok", false))

func _place_pending_facility(placement_result: Dictionary) -> Dictionary:
	var result := _facility_placement_session.place_selected(crafting_service, inventory, _crafting_context(), facility_placement_service, world_data, placement_result)
	if not bool(result.get("ok", false)):
		return _facility_placement_failed(String(result.get("reason", "invalid_placement")))
	_record_placed_facility(result.placement)
	_sync_runtime_world_render()
	_facility_placement_session.clear()
	_clear_facility_placement_preview()
	if game_hud != null:
		game_hud.hide_facility_placement_controls()
	_sync_run_runtime_state()
	save_current_run()
	_configure_game_hud()
	if game_hud != null:
		game_hud.show_command_feedback("제작·설치 완료: %s" % String(result.get("facility_item_id", "")))
	_advance_time_for_turn()
	_play_feedback_beep()
	_queue_enemy_turn_after_player_action()
	return result

func _facility_placement_failed(reason: String) -> Dictionary:
	var result := _facility_placement_session.placement_failed(reason)
	if game_hud != null:
		game_hud.update_facility_placement_controls(false, _facility_placement_reason(reason))
	return result

func _facility_placement_reason(reason: String) -> String:
	return FacilityPlacementSession.reason_message(reason)

func _cancel_pending_facility_placement() -> bool:
	var result := _facility_placement_session.cancel()
	if not bool(result.get("ok", false)):
		return false
	_clear_facility_placement_preview()
	if game_hud != null:
		game_hud.hide_facility_placement_controls()
		game_hud.show_command_feedback("시설 설치를 취소했습니다.")
	return true

func _update_facility_placement_preview(validation: Dictionary) -> void:
	if world_visuals == null or _pending_facility_origin.x < 0:
		return
	if _facility_placement_preview == null:
		_facility_placement_preview = FacilityPlacementPreview.new()
		_facility_placement_preview.z_index = 50
		world_visuals.add_child(_facility_placement_preview)
	var footprint := _facility_footprint_for_pending_facility()
	if validation.has("footprint_size"):
		footprint = Vector2i(int(validation.footprint_size.x), int(validation.footprint_size.y))
	_facility_placement_preview.configure(
		_pending_facility_origin,
		footprint,
		_runtime_tile_size(),
		bool(validation.get("ok", false)),
		_facility_preview_texture(),
		_pending_facility_rotation
	)

func _facility_preview_texture() -> Texture2D:
	if not _preview_asset_catalog_ready:
		var manifest_result: Dictionary = _preview_asset_catalog.load_manifest()
		if not bool(manifest_result.get("ok", false)):
			return null
		_preview_asset_catalog_ready = true
	var metadata: Dictionary = _pending_facility_placement.get("metadata", {})
	return _preview_asset_catalog.load_texture_reference(String(metadata.get("source_id", "")))

func _content_image_asset_id(dataset: String, content_id: String) -> String:
	if not _preview_asset_catalog_ready:
		var manifest_result: Dictionary = _preview_asset_catalog.load_manifest()
		if not bool(manifest_result.get("ok", false)):
			return ""
		_preview_asset_catalog_ready = true
	if not _preview_content_image_map_ready:
		var map_result: Dictionary = _preview_asset_catalog.load_content_image_map()
		if not bool(map_result.get("ok", false)):
			return ""
		_preview_content_image_map_ready = true
	return _preview_asset_catalog.content_asset_id(dataset, content_id)

func _clear_facility_placement_preview() -> void:
	if _facility_placement_preview != null:
		_facility_placement_preview.clear()

func _facility_footprint_for_pending_facility() -> Vector2i:
	return _facility_placement_session.footprint_for_pending_facility(facility_placement_service)

func _player_facility_metadata(facility_item_id: String) -> Dictionary:
	return _facility_placement_session.player_facility_metadata(
		facility_item_id,
		facility_placement_service,
		_content_image_asset_id("items", facility_item_id)
	)

func _record_placed_facility(placed: Dictionary) -> void:
	if run_state == null:
		run_state = RunState.new()
	_facility_placement_session.record_placed_facility(run_state, generated_world, placed)

func _handle_inventory_command(command: GameCommand) -> bool:
	if inventory_command_runtime == null:
		return false
	var result: Dictionary = inventory_command_runtime.handle_command(command)
	var started_consumable := false
	if result.ok and command.type == GameCommand.Type.USE_INVENTORY_SLOT and result.has("use_intent"):
		var intent: Dictionary = result.get("use_intent", {})
		var start_result: Dictionary = _start_consumable_use(String(intent.get("item_id", "")), {
			"inventory_slot_index": int(intent.get("inventory_slot_index", command.slot)),
			"command_slot": command.slot,
			"source": "inventory"
		})
		if not start_result.ok:
			result = start_result
		else:
			started_consumable = true
	if game_hud != null:
		game_hud.show_command_feedback(
			"인벤토리 갱신"
			if result.ok
			else "인벤토리 명령 실패: %s" % String(result.get("reason", "unknown"))
		)
	if not result.ok:
		return false
	if not started_consumable:
		_sync_run_runtime_state()
		if game_hud != null:
			game_hud.show_inventory_menu()
		save_current_run()
	return true

func _handle_complete_dungeon_command(command: GameCommand) -> bool:
	_dungeon_debug("던전 입장 명령 시작")
	var runtime_result := _ensure_playable_dungeon_runtime()
	_dungeon_debug("런타임 준비 결과: ok=%s reason=%s" % [runtime_result.get("ok", false), runtime_result.get("reason", "")])
	if not runtime_result.ok:
		_dungeon_debug("던전 런타임 준비 실패: %s" % runtime_result)
		return false
	var previous_projection: Dictionary = dungeon_runtime.to_projection()
	var entered_result := _ensure_current_dungeon_entered()
	_dungeon_debug("입장 시도 결과: ok=%s reason=%s in_dungeon=%s" % [entered_result.get("ok", false), entered_result.get("reason", ""), _in_dungeon_map])
	if not entered_result.ok and String(entered_result.get("reason", "")) != "dungeon_already_active":
		_dungeon_debug("던전 입장 실패: %s" % entered_result)
		return false
	# Runtime persistence and the rendered map can briefly diverge (for
	# example after returning from a dungeon). Rehydrate the active instance
	# before acknowledging the interaction so a successful entry is visible.
	if _dungeon_runtime_is_active() and not _in_dungeon_map:
		_dungeon_debug("활성 던전 화면 복원: runtime=active map=false")
		_restore_dungeon_map_from_runtime()
	if bool(command.payload.get("entry_only", false)):
		save_current_run()
		_configure_game_hud()
		if game_hud != null:
			game_hud.show_status_event({
				"type": "dungeon_entered",
				"ok": true,
				"dungeon_id": String(dungeon_runtime.to_projection().get("dungeon_id", "")),
				"event_id": "entry:%s" % String(run_state.current_biome_id)
			})
		_dungeon_debug("입구 상호작용은 입장만 처리: in_dungeon=%s" % _in_dungeon_map)
		return true
	if String(previous_projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED] \
			and not _dungeon_completion_objective_met(command.payload):
		_dungeon_debug("입장만 처리(완료 조건 미충족)")
		save_current_run()
		_configure_game_hud()
		if game_hud != null:
			game_hud.show_command_feedback("던전 입장")
			game_hud.show_status_event({
				"type": "dungeon_entered",
				"ok": true,
				"dungeon_id": String(dungeon_runtime.to_projection().get("dungeon_id", "")),
				"event_id": "entry:%s" % String(run_state.current_biome_id)
			})
		return true
	var payload: Dictionary = command.payload.duplicate(true)
	if String(payload.get("resolution_type", "")).is_empty():
		payload["resolution_type"] = "combat"
	if String(payload.get("choice_key", "")).is_empty():
		payload["choice_key"] = "dev17_minimal_clear"
	if String(payload.get("run_flag", "")).is_empty():
		payload["run_flag"] = "dev17_common_dungeon_clear"
	if not payload.has("reward_item_ids"):
		payload["reward_item_ids"] = []
	if not payload.has("progression_unlock_ids"):
		payload["progression_unlock_ids"] = [String(run_state.current_biome_id)]
	_sync_dungeon_runtime_save_state()
	var completed: Dictionary = dungeon_runtime.complete_dungeon(payload)
	if not completed.ok:
		return false
	dungeon_runtime.begin_return()
	dungeon_runtime.finish_return()
	_return_from_dungeon_map()
	save_current_run()
	_configure_game_hud()
	return true

func _handle_biome_progression_command(command: GameCommand) -> bool:
	var progression_result := _ensure_biome_progression_state()
	if not progression_result.ok:
		return false
	if not command.payload.has("biome_id") and run_state != null:
		command.payload["biome_id"] = String(run_state.current_biome_id)
	_dungeon_debug("바이옴 진행 상태: biome=%s completed=%s teleport=%s" % [
		String(command.payload.get("biome_id", "")),
		str(run_state.completed_dungeon_ids if run_state != null else []),
		str(run_state.teleport_states if run_state != null else {})
	])
	var rollback_snapshot := run_state.to_dictionary() if run_state != null else {}
	var rollback_generated_world := generated_world.duplicate(true)
	var previous_biome_id := String(run_state.current_biome_id) if run_state != null else ""
	if command.type == GameCommand.Type.ADVANCE_BIOME:
		_store_current_biome_runtime_aliases(previous_biome_id)
	var result: Dictionary = biome_progression_state.apply_command(command)
	if not result.ok:
		_dungeon_debug("바이옴 진행 명령 실패: type=%s biome=%s reason=%s" % [command.type, String(command.payload.get("biome_id", "")), String(result.get("reason", "unknown"))])
		if game_hud != null and game_hud.has_method("show_command_feedback"):
			game_hud.show_command_feedback("수리 불가: %s" % String(result.get("reason", "unknown")))
		return false
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		if command.type == GameCommand.Type.ADVANCE_BIOME and not rollback_snapshot.is_empty():
			_restore_run_state_from_snapshot(rollback_snapshot)
			generated_world = rollback_generated_world.duplicate(true)
			biome_progression_state = null
			var rollback_world_result := _configure_world_for_current_run()
			if not rollback_world_result.ok:
				push_error(String(rollback_world_result.get("error", "Failed to restore previous biome world after transition failure.")))
		return false
	save_current_run()
	if game_hud != null and command.type == GameCommand.Type.ADVANCE_BIOME:
		game_hud.show_status_event({
			"type": "biome_transition",
			"ok": true,
			"biome_id": String(run_state.current_biome_id),
			"event_id": "advance:%s" % String(run_state.current_biome_id)
		})
	return true

func inventory_read_model() -> Dictionary:
	if inventory_command_runtime == null:
		return {"ok": false, "reason": "missing_inventory_command_runtime", "error": "Inventory command runtime is not configured."}
	var model: Dictionary = inventory_command_runtime.read_model()
	model["ok"] = true
	return model

func map_read_model(options := {}) -> Dictionary:
	if map_read_model_builder == null:
		return {"ok": false, "reason": "missing_map_read_model_builder", "error": "Map read model builder is not configured."}
	if world_data == null:
		return {"ok": false, "reason": "missing_world_data", "error": "Map read model requires current world data."}
	if run_state == null:
		run_state = RunState.new()
	return map_read_model_builder.build(world_data, run_state, _player_world_cell(), options)

func _selected_inventory_slot_index() -> int:
	if inventory_command_runtime == null:
		return -1
	return int(inventory_command_runtime.read_model().get("selected_slot_index", -1))

func _sync_run_runtime_state() -> void:
	if run_state == null:
		run_state = RunState.new()
	var result: Dictionary = run_runtime_state_binder.snapshot_to_run_state(run_state, _run_runtime_state_entries())
	if not result.ok:
		push_error(result.error)

func tea_brewing_read_model() -> Dictionary:
	if tea_brewing_command_runtime == null:
		return {"ok": false, "reason": "missing_tea_brewing_command_runtime", "error": "Tea brewing command runtime is not configured."}
	var model: Dictionary = tea_brewing_command_runtime.read_model()
	model["ok"] = true
	return model

func _run_runtime_state_entries() -> Array:
	return [
		{"field": "inventory", "runtime": inventory},
		{"field": "equipment", "runtime": equipment},
		{"field": "tea", "runtime": tea_service},
		{"field": "consumables", "runtime": consumable_service, "clear_when_empty_key": "active_action"},
		{"field": "time", "runtime": time_state},
		{"field": "acquisitions", "runtime": acquisition_service, "active": not _in_dungeon_map},
		{"field": "memory_tea_cutscene", "runtime": memory_tea_cutscene_runtime}
	]

func meta_codex_read_model() -> Dictionary:
	if meta_codex_command_runtime == null:
		return {"ok": false, "reason": "missing_meta_codex_runtime", "error": "Meta codex runtime is not configured."}
	var model: Dictionary = meta_codex_command_runtime.read_model()
	model["ok"] = true
	return model

func _current_run_state_snapshot() -> Dictionary:
	return run_state.to_dictionary() if run_state != null else {}

func _current_meta_state_snapshot() -> Dictionary:
	var loaded: Dictionary = save_store.load_meta() if save_store != null else {}
	if bool(loaded.get("ok", false)):
		return loaded.meta_state.to_dictionary()
	return {}

func _tea_brewing_context() -> Dictionary:
	var context := _crafting_context()
	context["has_brewing_location"] = _has_brewing_location(context)
	return context

func _has_brewing_location(context: Dictionary) -> bool:
	var facility_ids: Array = context.get("available_facility_item_ids", [])
	var explicit_ids: Array = context.get("brewing_location_ids", [])
	return not facility_ids.is_empty() or not explicit_ids.is_empty()

func _player_world_cell() -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	return world_cell_from_world_position(player.global_position)

func _record_current_map_discovery() -> void:
	if map_read_model_builder == null or world_data == null:
		return
	if run_state == null:
		run_state = RunState.new()
	var current_cell := _player_world_cell()
	if not world_data.contains(current_cell):
		return
	run_state.map_discovery = MapReadModelBuilder.discover_cells(run_state.map_discovery, current_cell)
	_store_current_biome_runtime_aliases()

func _crafting_context() -> Dictionary:
	return {
		"available_facility_item_ids": _available_facility_item_ids(),
		"unlocked_biome_ids": _unlocked_biome_ids(),
		"current_biome_id": String(generated_world.get("biome_id", ""))
	}

func _available_facility_item_ids() -> Array:
	if player == null:
		return []
	return _facility_placement_session.available_facility_item_ids(
		crafting_service,
		facility_placement_service,
		world_data,
		run_state,
		generated_world,
		_player_world_cell()
	)

func _restore_placed_facilities_for_current_biome() -> Dictionary:
	return _facility_placement_session.restore_placed_facilities_for_current_biome(
		facility_placement_service,
		world_data,
		run_state,
		generated_world
	)

func _unlocked_biome_ids() -> Array:
	var ids: Array = []
	if _start_mode == START_MODE_CHEAT and catalog != null and catalog.has_method("get_definitions"):
		for definition in catalog.get_definitions("biomes"):
			var cheat_id := String(definition.get("id", ""))
			if not cheat_id.is_empty() and not ids.has(cheat_id):
				ids.append(cheat_id)
		return ids
	if run_state != null:
		for biome_id in run_state.crafting_unlocks:
			var id := String(biome_id)
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
		# The biome the player is currently in is already reached for this run.
		# Include it immediately so recipes for facilities available in the
		# current region are shown instead of being filtered out as locked.
		var current_id := String(run_state.current_biome_id)
		if not current_id.is_empty() and not ids.has(current_id):
			ids.append(current_id)
	return ids

func _on_tea_drink_completed(result: Dictionary) -> void:
	if equipment == null:
		return
	var accounting_result: Dictionary = equipment.record_tea_ware_use_completion(result, inventory)
	if not accounting_result.ok:
		push_error(accounting_result.error)
	if memory_tea_cutscene_runtime != null:
		var memory_result: Dictionary = narrative_session.start_memory_tea_cutscene(memory_tea_cutscene_runtime, result, run_state)
		if not memory_result.ok:
			push_error(memory_result.error)

func complete_memory_tea_cutscene() -> Dictionary:
	return narrative_session.complete_memory_tea_cutscene(memory_tea_cutscene_runtime, run_state)

func skip_memory_tea_cutscene() -> Dictionary:
	return narrative_session.skip_memory_tea_cutscene(memory_tea_cutscene_runtime, run_state)

func _render_generated_world(world: Dictionary) -> void:
	WorldPresentation.hide_prototype_visuals(self)
	if not _in_dungeon_map and world_data != null:
		var migrated := _ensure_saved_world_has_teleport_landmark()
		world["world_data"] = world_data.to_dictionary()
		world["renderer_input"] = WorldRendererProjection.new().project(world["world_data"], biome_progression_state.to_projection() if biome_progression_state != null else {})
		if migrated:
			save_current_run()
	var renderer_input: Dictionary = world.get("renderer_input", {})
	WorldPresentation.apply_teleport_states(renderer_input, run_state)
	var origin := _centered_world_origin(renderer_input)
	world_render_result = WorldSceneRenderer.new().render(
		world_visuals,
		renderer_input,
		_owner_sprite_sources(world),
		origin
	)
	if not world_render_result.ok:
		push_error(world_render_result.error)
	if player != null and player.has_method("configure_grid_navigation"):
		var saved_cell: Dictionary = run_state.player_cell if run_state != null else {}
		var spawn_cell := _entry_spawn_cell(world)
		if not saved_cell.is_empty():
			var candidate := Vector2i(int(saved_cell.get("x", spawn_cell.x)), int(saved_cell.get("y", spawn_cell.y)))
			if world_data != null and world_data.is_walkable(candidate):
				spawn_cell = candidate
		player.global_position = world_position_for_cell_center(spawn_cell)
		player.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
	_configure_runtime_camera()
	if combat_dummy != null and combat_dummy.has_method("configure_grid_navigation"):
		combat_dummy.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
	_restore_overworld_enemy_state()

func _sync_runtime_world_render() -> void:
	if world_visuals == null or world_data == null or world_render_result.is_empty():
		return
	var world_snapshot: Dictionary = world_data.to_dictionary()
	var renderer_input: Dictionary = WorldRendererProjection.new().project(world_snapshot)
	WorldPresentation.apply_teleport_states(renderer_input, run_state)
	generated_world["world_data"] = world_snapshot
	generated_world["renderer_input"] = renderer_input
	var origin := _centered_world_origin(renderer_input)
	world_render_result = WorldSceneRenderer.new().render(
		world_visuals,
		renderer_input,
		_owner_sprite_sources(generated_world),
		origin
	)
	if not world_render_result.ok:
		push_error(world_render_result.error)
	_configure_runtime_camera()
	if player != null and player.has_method("configure_grid_navigation"):
		player.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
	if combat_dummy != null and combat_dummy.has_method("configure_grid_navigation"):
		combat_dummy.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())

func _sync_dungeon_runtime_save_state() -> void:
	if not _in_dungeon_map or dungeon_runtime == null or world_data == null or player == null:
		return
	var enemy_states := {}
	for enemy in _dungeon_enemy_nodes:
		if not is_instance_valid(enemy):
			continue
		var cell := _combat_target_cell(enemy)
		var owner_id := String(enemy.name)
		enemy_states[owner_id] = {
			"cell": {"x": cell.x, "y": cell.y},
			"hp": int(enemy.current_hp()) if enemy.has_method("current_hp") else 0,
			"visible": enemy.visible
		}
		_sync_dungeon_enemy_reservation(owner_id, cell, enemy.visible)
	var acquisition_snapshot: Dictionary = acquisition_service.to_snapshot() if acquisition_service != null else {}
	dungeon_runtime.sync_active_world_state(world_data, _player_world_cell(), enemy_states, acquisition_snapshot)

func _sync_dungeon_enemy_reservation(owner_id: String, cell: Vector2i, active: bool) -> void:
	var existing: Dictionary = world_data.get_reservation(owner_id)
	if not existing.is_empty():
		var existing_origin := _vector_from_dictionary(existing.get("origin", {}))
		if existing_origin == cell and active:
			return
		world_data.release_footprint(owner_id)
	if active and world_data.contains(cell) and world_data.is_walkable(cell):
		world_data.reserve_entity(owner_id, cell, Vector2i.ONE, false, {"role": "dungeon_enemy"})

func _combat_target_cell(enemy) -> Vector2i:
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("current_grid_cell"):
		return enemy.current_grid_cell()
	if enemy is Node2D:
		return world_cell_from_world_position(enemy.global_position)
	return Vector2i.ZERO

func _configure_runtime_camera() -> void:
	WorldPresentation.configure_camera(player, world_data, _runtime_world_origin(), _runtime_tile_size())
	if player != null and world_data != null and player.get_node_or_null("Camera2D") != null:
		_update_dungeon_sign_visibility()

func _update_dungeon_sign_visibility() -> void:
	if player != null:
		WorldPresentation.update_interaction_prompts(world_visuals, world_cell_from_world_position(player.global_position), _runtime_tile_size())

func _entry_spawn_cell(world: Dictionary) -> Vector2i:
	return WorldPresentation.entry_spawn_cell(world)

func _on_hud_mobile_command_issued(command) -> void:
	submit_mobile_action_command(command)

func _configure_game_hud() -> void:
	_configure_world_tone_overlay()
	if game_hud == null:
		return
	_connect_hud_commands()
	var hud_callback := Callable(self, "_on_hud_mobile_command_issued")
	if game_hud.has_signal("mobile_command_issued") and not game_hud.is_connected("mobile_command_issued", hud_callback):
		game_hud.connect("mobile_command_issued", hud_callback)
	game_hud.configure(player, generated_world, world_render_result, {
		"catalog": catalog,
		"inventory": inventory,
		"inventory_command_runtime": inventory_command_runtime,
		"map_read_model_builder": map_read_model_builder,
		"world_data": world_data,
		"combat_target": combat_dummy,
		"run_state": run_state,
		"tea_service": tea_service,
		"tea_brewing_command_runtime": tea_brewing_command_runtime,
		"meta_codex_command_runtime": meta_codex_command_runtime,
		"crafting_service": crafting_service,
		"crafting_context": _crafting_context(),
		"biome_progression_state": biome_progression_state,
		"cheat_mode": _start_mode == START_MODE_CHEAT,
		"time_state": time_state,
		"world_origin": _runtime_world_origin(),
		"biome_map_previews": _biome_map_previews
	})
	_maybe_show_run_start_event()

func _configure_world_tone_overlay() -> void:
	if world_tone_overlay != null and world_tone_overlay.has_method("configure"):
		world_tone_overlay.configure(time_state)

func first_run_prologue_read_model(meta_state = null) -> Dictionary:
	if run_state == null:
		run_state = RunState.new()
	var meta = meta_state if meta_state != null else _current_meta_state_snapshot()
	return narrative_session.first_run_prologue_read_model(narrative_runtime, run_state, meta, _force_first_run_prologue)

func start_run_event_read_model(meta_state = null) -> Dictionary:
	if run_state == null:
		run_state = RunState.new()
	var meta = meta_state if meta_state != null else _current_meta_state_snapshot()
	return narrative_session.start_run_event_read_model(narrative_runtime, run_start_event_selector, run_state, meta, _force_first_run_prologue)

func _maybe_show_run_start_event() -> Dictionary:
	if game_hud == null or narrative_runtime == null:
		return {"ok": false, "reason": "missing_presentation", "error": "Run-start presentation is not ready."}
	var model_result := start_run_event_read_model()
	if not model_result.ok:
		if game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
		return model_result
	_set_active_narrative_from_read_model(model_result.read_model)
	game_hud.show_narrative_dialogue(model_result.read_model)
	return {"ok": true, "read_model": model_result.read_model}

func _handle_narrative_option_command(command: GameCommand) -> bool:
	var event_id := String(command.payload.get("event_id", narrative_session.active_event_id))
	var result: Dictionary = narrative_session.select_option(command, narrative_runtime, run_state, _current_meta_state_snapshot())
	if not bool(result.get("handled", false)):
		return false
	if bool(result.get("complete", false)):
		var was_boss_precombat := _dungeon_precombat_dialogue_is_active(event_id)
		if was_boss_precombat:
			var boss_start_result: Dictionary = dungeon_runtime.complete_boss_precombat_dialogue(event_id)
			if not boss_start_result.ok:
				_dungeon_debug("보스 전 대화 완료 처리 실패: %s" % boss_start_result)
				return false
			var boss_cell := _dungeon_boss_cell()
			if boss_cell != Vector2i(-1, -1):
				_activate_dungeon_enemy(boss_cell)
		narrative_session.reset()
		if game_hud != null and game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
	else:
		var read_model: Dictionary = result.get("read_model", {})
		narrative_session.active_event_id = String(read_model.get("event_id", event_id))
		narrative_session.active_node_id = String(read_model.get("node_id", ""))
		if game_hud != null and game_hud.has_method("show_narrative_dialogue"):
			game_hud.show_narrative_dialogue(read_model)
	save_current_run()
	return true

func _set_active_narrative_from_read_model(read_model: Dictionary) -> void:
	narrative_session.begin_read_model(read_model)

func _configure_audio_feedback() -> void:
	if _sfx_router != null:
		return
	_sfx_router = SfxEventRouter.new()
	_sfx_router.name = "SfxEventRouter"
	add_child(_sfx_router)

func _play_feedback_beep() -> void:
	_play_sfx_event(SfxEventRouter.EVENT_UI_SELECT)

func _play_sfx_event(event_id: String, payload := {}, dedupe_key := "") -> Dictionary:
	if _sfx_router == null:
		_configure_audio_feedback()
	if _sfx_router == null:
		return {"ok": false, "reason": "missing_sfx_router", "event_id": event_id}
	var before_count := _sfx_router.played_events.size()
	var result: Dictionary = _sfx_router.play_event(event_id, payload, dedupe_key)
	if _sfx_router.played_events.size() > before_count:
		feedback_beep_count += 1
	return result

func _centered_world_origin(renderer_input: Dictionary) -> Vector2:
	return WorldPresentation.centered_world_origin(renderer_input)

func _owner_sprite_sources(world: Dictionary) -> Dictionary:
	return WorldPresentation.owner_sprite_sources(world)

func _acquisition_definitions() -> AcquisitionDefinitionBuilder:
	return AcquisitionDefinitionBuilder.new(catalog, inventory, world_data, String(generated_world.get("biome_id", "")))
