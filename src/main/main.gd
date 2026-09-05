extends Node2D

const PlayerItemActions = preload("res://src/main/player_item_actions.gd")
const ActionCommandResultEffects = preload("res://src/main/action_command_result_effects.gd")
const DungeonCommandCoordinator = preload("res://src/main/dungeon_command_coordinator.gd")
const GameProgressionCoordinator = preload("res://src/main/game_progression_coordinator.gd")
const FacilityBiomeCoordinator = preload("res://src/main/facility_biome_coordinator.gd")
const FacilityPreviewPresenter = preload("res://src/main/facility_preview_presenter.gd")
const HudPresentationCoordinator = preload("res://src/main/hud_presentation_coordinator.gd")
const MainCommandCoordinator = preload("res://src/main/main_command_coordinator.gd")
const MainInputCoordinator = preload("res://src/main/main_input_coordinator.gd")
const PlayerRuntimeCoordinator = preload("res://src/main/player_runtime_coordinator.gd")
const RunBootstrapCoordinator = preload("res://src/main/run_bootstrap_coordinator.gd")

const RunServiceFactory = preload("res://src/main/run_service_factory.gd")
const RunStateSnapshotCoordinator = preload("res://src/main/run_state_snapshot_coordinator.gd")

const WorldPresentation = preload("res://src/main/world_presentation.gd")

const CheatStartConfigurator = preload("res://src/main/cheat_start_configurator.gd")
const AcquisitionDefinitionBuilder = preload("res://src/main/acquisition_definition_builder.gd")

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const RunRuntimeStateBinder = preload("res://src/save/run_runtime_state_binder.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const FacilityPlacementSession = preload("res://src/main/facility_placement_session.gd")
const FacilityPlacementPreview = preload("res://src/presentation/facility_placement_preview.gd")
const MainSceneOverlays = preload("res://src/main/main_scene_overlays.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")
const DungeonDefinitionResolver = preload("res://src/main/dungeon_definition_resolver.gd")
const DungeonCombatantSession = preload("res://src/main/dungeon_combatant_session.gd")
const DungeonSceneCoordinator = preload("res://src/main/dungeon_scene_coordinator.gd")
const DungeonLayoutBuilder = preload("res://src/main/dungeon_layout_builder.gd")
const NarrativeSession = preload("res://src/main/narrative_session.gd")
const PointerRouteController = preload("res://src/main/pointer_route_controller.gd")
const SpatialInteractionResolver = preload("res://src/main/spatial_interaction_resolver.gd")
const WorldInteractionCoordinator = preload("res://src/main/world_interaction_coordinator.gd")

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
var run_state_snapshot_coordinator := RunStateSnapshotCoordinator.new()
var dungeon_definition_resolver := DungeonDefinitionResolver.new()
var game_progression_coordinator := GameProgressionCoordinator.new()
var dungeon_combatant_session := DungeonCombatantSession.new()
var _dungeon_scene_coordinator := DungeonSceneCoordinator.new()
var dungeon_layout_builder := DungeonLayoutBuilder.new()
var narrative_session := NarrativeSession.new()
var biome_progression_state
var save_store = SaveStore.new()
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
var _biome_map_previews: Dictionary = {}
var world_render_result: Dictionary = {}
var _overworld_generated_world: Dictionary:
	get:
		return dungeon_combatant_session.overworld_generated_world
	set(value):
		dungeon_combatant_session.overworld_generated_world = value
var _overworld_world_data_snapshot: Dictionary:
	get:
		return dungeon_combatant_session.overworld_world_data_snapshot
	set(value):
		dungeon_combatant_session.overworld_world_data_snapshot = value
var _overworld_player_cell := Vector2i.ZERO:
	get:
		return dungeon_combatant_session.overworld_player_cell
	set(value):
		dungeon_combatant_session.overworld_player_cell = value
var _overworld_combat_dummy_cell := Vector2i.ZERO:
	get:
		return dungeon_combatant_session.overworld_combat_dummy_cell
	set(value):
		dungeon_combatant_session.overworld_combat_dummy_cell = value
var _overworld_combat_dummy:
	get:
		return dungeon_combatant_session.overworld_combat_dummy
	set(value):
		dungeon_combatant_session.overworld_combat_dummy = value
var _overworld_combat_dummy_state: Dictionary:
	get:
		return dungeon_combatant_session.overworld_combat_dummy_state
	set(value):
		dungeon_combatant_session.overworld_combat_dummy_state = value
var _in_dungeon_map := false
var _dungeon_resources: Array = []
var _dungeon_enemy_nodes: Array:
	get:
		return dungeon_combatant_session.enemy_nodes
	set(value):
		dungeon_combatant_session.enemy_nodes = value
var _desktop_adapter := DesktopCommandAdapter.new()
var _command_dispatcher := CommandDispatcher.new()
var _action_command_result_effects := ActionCommandResultEffects.new(
	Callable(self, "_sync_run_runtime_state"),
	Callable(self, "_advance_time_for_turn"),
	Callable(self, "_play_feedback_beep"),
	Callable(self, "_queue_enemy_turn_after_player_action"),
	Callable(self, "_play_sfx_event")
)
var _main_command_coordinator
var _main_input_coordinator := MainInputCoordinator.new()
var _facility_biome_coordinator
var _hud_presentation_coordinator
var _player_runtime_coordinator
var _run_bootstrap_coordinator
var _dungeon_command_coordinator := DungeonCommandCoordinator.new(
	Callable(self, "_dungeon_debug"),
	Callable(self, "_ensure_playable_dungeon_runtime"),
	Callable(self, "_ensure_current_dungeon_entered"),
	Callable(self, "_dungeon_runtime_is_active"),
	Callable(self, "_restore_dungeon_map_from_runtime"),
	Callable(self, "_dungeon_completion_objective_met"),
	Callable(self, "_sync_dungeon_runtime_save_state"),
	Callable(self, "_return_from_dungeon_map"),
	Callable(self, "save_current_run"),
	Callable(self, "_configure_game_hud")
)
var _movement_selector := MovementCommandSelector.new()
var _pointer_route_controller := PointerRouteController.new()
var _spatial_resolver := SpatialInteractionResolver.new()
var _world_interaction_coordinator := WorldInteractionCoordinator.new()
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
var _facility_preview_presenter := FacilityPreviewPresenter.new()
var _facility_placement_preview: FacilityPlacementPreview:
	get:
		return _facility_preview_presenter.preview
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
	await _run_bootstrap().ready(self)

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
	return _run_bootstrap().configure_combat_lifecycle(self)

func _connect_player_feedback_signals() -> void:
	_run_bootstrap().connect_player_feedback_signals(self)

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
	return _run_bootstrap().configure_world_for_current_run()

func _generate_world_for_biome(generator: WorldGenerator, biome_definition: Dictionary, projection: Dictionary) -> Dictionary:
	return _run_bootstrap()._generate_world_for_biome(generator, biome_definition, projection)

func _world_generation_options(projection: Dictionary) -> Dictionary:
	return _run_bootstrap()._world_generation_options(projection)

func _configure_overworld_combat_from_spawn_pool() -> Dictionary:
	return _run_bootstrap().configure_overworld_combat_from_spawn_pool()

func _physics_process(_delta: float) -> void:
	_main_input_coordinator.process_frame(self, _delta)

func _unhandled_input(event) -> void:
	if _main_input_coordinator.handle_unhandled_input(self, event):
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
	return _world_interaction_coordinator.submit_pointer_interaction(self, world_position)

func _try_dungeon_interaction_from_input() -> bool:
	return _world_interaction_coordinator.try_dungeon_interaction_from_input(self)

func _pointer_enemy_clicked(world_position: Vector2) -> bool:
	return _world_interaction_coordinator.pointer_enemy_clicked(self, world_position)

func _try_landmark_interaction_from_input() -> bool:
	return _world_interaction_coordinator.try_landmark_interaction_from_input(self)

func _activate_dungeon_enemy(cell: Vector2i) -> void:
	_world_interaction_coordinator.activate_dungeon_enemy(self, cell)

func submit_pointer_movement(world_position: Vector2) -> bool:
	return _world_interaction_coordinator.submit_pointer_movement(self, world_position)

func submit_player_interaction(direction := Vector2i.ZERO) -> bool:
	return _world_interaction_coordinator.submit_player_interaction(self, direction)

func submit_interaction_at_world_cell(cell: Vector2i) -> bool:
	var target_id := _interaction_target_id_for_cell(cell)
	if target_id.is_empty():
		return false
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))

func submit_action_command(command) -> bool:
	return _main_command_router().submit_action_command(command)

func _main_command_router() -> MainCommandCoordinator:
	if _main_command_coordinator == null:
		_main_command_coordinator = MainCommandCoordinator.new(_main_command_ports(), _command_dispatcher, _action_command_result_effects)
	return _main_command_coordinator

func _hud_presentation() -> HudPresentationCoordinator:
	if _hud_presentation_coordinator == null:
		_hud_presentation_coordinator = HudPresentationCoordinator.new(_hud_presentation_ports())
	return _hud_presentation_coordinator

func _ensure_run_state() -> RunState:
	if run_state == null:
		run_state = RunState.new()
	return run_state

func _facility_biome_router() -> FacilityBiomeCoordinator:
	if _facility_biome_coordinator == null:
		_facility_biome_coordinator = FacilityBiomeCoordinator.new(_facility_placement_session, _facility_biome_ports())
	return _facility_biome_coordinator

func _player_runtime() -> PlayerRuntimeCoordinator:
	if _player_runtime_coordinator == null:
		_player_runtime_coordinator = PlayerRuntimeCoordinator.new(
			_player_runtime_ports(),
			_player_item_actions,
			narrative_session,
			run_state_snapshot_coordinator
		)
	return _player_runtime_coordinator

func _hud_presentation_ports() -> HudPresentationCoordinator.Ports:
	var ports := HudPresentationCoordinator.Ports.new()
	ports.get_scene_root = func(): return self
	ports.get_player = func(): return player
	ports.get_combat_target = func(): return combat_dummy
	ports.get_world_visuals = func(): return world_visuals
	ports.get_world_tone_overlay = func(): return world_tone_overlay
	ports.get_game_hud = func(): return game_hud
	ports.get_catalog = func(): return catalog
	ports.get_inventory = func(): return inventory
	ports.get_inventory_command_runtime = func(): return inventory_command_runtime
	ports.get_map_read_model_builder = func(): return map_read_model_builder
	ports.get_world_data = func(): return world_data
	ports.set_world_data = func(value): world_data = value
	ports.get_generated_world = func(): return generated_world
	ports.set_generated_world = func(value): generated_world = value
	ports.get_world_render_result = func(): return world_render_result
	ports.set_world_render_result = func(value): world_render_result = value
	ports.get_run_state = func(): return run_state
	ports.ensure_run_state = Callable(self, "_ensure_run_state")
	ports.get_tea_service = func(): return tea_service
	ports.get_tea_brewing_command_runtime = func(): return tea_brewing_command_runtime
	ports.get_meta_codex_command_runtime = func(): return meta_codex_command_runtime
	ports.get_crafting_service = func(): return crafting_service
	ports.get_crafting_context = Callable(self, "_crafting_context")
	ports.get_biome_progression_state = func(): return biome_progression_state
	ports.get_cheat_mode = func(): return _start_mode == START_MODE_CHEAT
	ports.get_time_state = func(): return time_state
	ports.get_biome_map_previews = func(): return _biome_map_previews
	ports.runtime_world_origin = Callable(self, "_runtime_world_origin")
	ports.runtime_tile_size = Callable(self, "_runtime_tile_size")
	ports.world_position_for_cell_center = Callable(self, "world_position_for_cell_center")
	ports.world_cell_from_world_position = Callable(self, "world_cell_from_world_position")
	ports.ensure_saved_world_has_teleport_landmark = Callable(self, "_ensure_saved_world_has_teleport_landmark")
	ports.save_current_run = Callable(self, "save_current_run")
	ports.restore_overworld_enemy_state = Callable(self, "_restore_overworld_enemy_state")
	ports.connect_hud_commands = Callable(self, "_connect_hud_commands")
	ports.submit_mobile_action_command = Callable(self, "submit_mobile_action_command")
	ports.current_meta_state_snapshot = Callable(self, "_current_meta_state_snapshot")
	ports.get_narrative_session = func(): return narrative_session
	ports.get_narrative_runtime = func(): return narrative_runtime
	ports.get_run_start_event_selector = func(): return run_start_event_selector
	ports.get_force_first_run_prologue = func(): return _force_first_run_prologue
	ports.dungeon_precombat_dialogue_is_active = Callable(self, "_dungeon_precombat_dialogue_is_active")
	ports.get_dungeon_runtime = func(): return dungeon_runtime
	ports.dungeon_boss_cell = Callable(self, "_dungeon_boss_cell")
	ports.activate_dungeon_enemy = Callable(self, "_activate_dungeon_enemy")
	ports.dungeon_debug = Callable(self, "_dungeon_debug")
	ports.get_sfx_router = func(): return _sfx_router
	ports.set_sfx_router = func(value): _sfx_router = value
	ports.increment_feedback_beep_count = func(): feedback_beep_count += 1
	ports.add_child = func(child): add_child(child)
	ports.push_error = func(message): push_error(message)
	ports.is_in_dungeon_map = func(): return _in_dungeon_map
	return ports

func _facility_biome_ports() -> FacilityBiomeCoordinator.Ports:
	var ports := FacilityBiomeCoordinator.Ports.new()
	ports.is_in_dungeon_map = func(): return _in_dungeon_map
	ports.get_dungeon_runtime = func(): return dungeon_runtime
	ports.combat_targets = Callable(self, "_combat_targets")
	ports.dungeon_boss_combat_available = Callable(self, "_dungeon_boss_combat_available")
	ports.return_from_dungeon_map = Callable(self, "_return_from_dungeon_map")
	ports.save_current_run = Callable(self, "save_current_run")
	ports.configure_game_hud = Callable(self, "_configure_game_hud")
	ports.get_game_hud = func(): return game_hud
	ports.get_run_state = func(): return run_state
	ports.set_run_state = func(value): run_state = value
	ports.is_core_dungeon_target = Callable(self, "_is_core_dungeon_target")
	ports.handle_complete_dungeon_command = Callable(self, "_handle_complete_dungeon_command")
	ports.ensure_biome_progression_state = Callable(self, "_ensure_biome_progression_state")
	ports.get_biome_progression_state = func(): return biome_progression_state
	ports.set_biome_progression_state = func(value): biome_progression_state = value
	ports.get_generated_world = func(): return generated_world
	ports.set_generated_world = func(value): generated_world = value
	ports.store_current_biome_runtime_aliases = Callable(self, "_store_current_biome_runtime_aliases")
	ports.restore_run_state_from_snapshot = Callable(self, "_restore_run_state_from_snapshot")
	ports.configure_world_for_current_run = Callable(self, "_configure_world_for_current_run")
	ports.create_loading_overlay = Callable(self, "_create_loading_overlay")
	ports.set_loading_status = Callable(self, "_set_loading_status")
	ports.clear_loading_overlay = Callable(self, "_clear_loading_overlay")
	ports.loading_biome_label = Callable(self, "_loading_biome_label")
	ports.debug = Callable(self, "_dungeon_debug")
	ports.get_crafting_service = func(): return crafting_service
	ports.get_inventory = func(): return inventory
	ports.get_facility_placement_service = func(): return facility_placement_service
	ports.get_world_data = func(): return world_data
	ports.get_player = func(): return player
	ports.player_world_cell = Callable(self, "_player_world_cell")
	ports.player_facility_metadata = Callable(self, "_player_facility_metadata")
	ports.crafting_context = Callable(self, "_crafting_context")
	ports.clear_pointer_movement = Callable(self, "_clear_pointer_movement")
	ports.clear_facility_placement_preview = Callable(self, "_clear_facility_placement_preview")
	ports.update_facility_placement_preview = Callable(self, "_update_facility_placement_preview")
	ports.sync_runtime_world_render = Callable(self, "_sync_runtime_world_render")
	ports.sync_run_runtime_state = Callable(self, "_sync_run_runtime_state")
	ports.advance_time_for_turn = Callable(self, "_advance_time_for_turn")
	ports.play_feedback_beep = Callable(self, "_play_feedback_beep")
	ports.queue_enemy_turn_after_player_action = Callable(self, "_queue_enemy_turn_after_player_action")
	ports.content_image_asset_id = Callable(self, "_content_image_asset_id")
	ports.get_start_mode = func(): return _start_mode
	ports.get_catalog = func(): return catalog
	return ports

func _main_command_ports() -> MainCommandCoordinator.Ports:
	var ports := MainCommandCoordinator.Ports.new()
	ports.is_boss_action_locked = Callable(self, "_dungeon_boss_action_locked")
	ports.handle_narrative_option_command = Callable(self, "_handle_narrative_option_command")
	ports.submit_player_interaction = Callable(self, "submit_player_interaction")
	ports.is_landmark_target = Callable(self, "_is_landmark_target")
	ports.handle_landmark_interaction = Callable(self, "_handle_landmark_interaction")
	ports.is_repair_interaction_target = Callable(self, "_is_repair_interaction_target")
	ports.handle_repair_interaction_command = Callable(self, "_handle_repair_interaction_command")
	ports.get_acquisition_service = func(): return acquisition_service
	ports.handle_tea_command = Callable(self, "_handle_tea_command")
	ports.handle_consumable_command = Callable(self, "_handle_consumable_command")
	ports.handle_sleep_command = Callable(self, "_handle_sleep_command")
	ports.handle_complete_dungeon_command = Callable(self, "_handle_complete_dungeon_command")
	ports.handle_biome_progression_command = Callable(self, "_handle_biome_progression_command")
	ports.travel_to_biome = Callable(self, "_travel_to_biome")
	ports.rotate_pending_facility = Callable(self, "_rotate_pending_facility")
	ports.confirm_pending_facility = Callable(self, "_confirm_pending_facility")
	ports.cancel_pending_facility_placement = Callable(self, "_cancel_pending_facility_placement")
	ports.get_game_hud = func(): return game_hud
	ports.configure_game_hud = Callable(self, "_configure_game_hud")
	ports.handle_tea_brewing_command = Callable(self, "_handle_tea_brewing_command")
	ports.handle_meta_codex_command = Callable(self, "_handle_meta_codex_command")
	ports.handle_craft_recipe_command = Callable(self, "_handle_craft_recipe_command")
	ports.has_pending_facility_placement = Callable(self, "has_pending_facility_placement")
	ports.handle_inventory_command = Callable(self, "_handle_inventory_command")
	ports.sen_rikyu_phase_two_accepts_command = Callable(self, "_sen_rikyu_phase_two_accepts_command")
	ports.handle_sen_rikyu_phase_two_action = Callable(self, "_handle_sen_rikyu_phase_two_action")
	ports.get_player = func(): return player
	ports.sync_runtime_state = Callable(self, "_sync_run_runtime_state")
	ports.advance_time_for_turn = Callable(self, "_advance_time_for_turn")
	ports.play_feedback_beep = Callable(self, "_play_feedback_beep")
	ports.queue_enemy_turn = Callable(self, "_queue_enemy_turn_after_player_action")
	ports.play_sfx_event = Callable(self, "_play_sfx_event")
	return ports

func _player_runtime_ports() -> PlayerRuntimeCoordinator.Ports:
	var ports := PlayerRuntimeCoordinator.Ports.new()
	ports.get_player = func(): return player
	ports.get_inventory = func(): return inventory
	ports.get_equipment = func(): return equipment
	ports.get_game_hud = func(): return game_hud
	ports.get_tea_service = func(): return tea_service
	ports.get_consumable_service = func(): return consumable_service
	ports.get_time_state = func(): return time_state
	ports.get_facility_placement_service = func(): return facility_placement_service
	ports.get_world_data = func(): return world_data
	ports.get_run_state = func(): return run_state
	ports.set_run_state = func(value): run_state = value
	ports.get_save_store = func(): return save_store
	ports.get_inventory_command_runtime = func(): return inventory_command_runtime
	ports.get_tea_brewing_command_runtime = func(): return tea_brewing_command_runtime
	ports.get_meta_codex_command_runtime = func(): return meta_codex_command_runtime
	ports.get_map_read_model_builder = func(): return map_read_model_builder
	ports.get_memory_tea_cutscene_runtime = func(): return memory_tea_cutscene_runtime
	ports.get_generated_world = func(): return generated_world
	ports.get_run_runtime_state_binder = func(): return run_runtime_state_binder
	ports.get_acquisition_service = func(): return acquisition_service
	ports.get_in_dungeon_map = func(): return _in_dungeon_map
	ports.world_cell_from_world_position = Callable(self, "world_cell_from_world_position")
	ports.save_current_run = Callable(self, "save_current_run")
	ports.configure_game_hud = Callable(self, "_configure_game_hud")
	ports.start_consumable_use = Callable(self, "_start_consumable_use")
	ports.sync_runtime_state = Callable(self, "_sync_run_runtime_state")
	ports.store_current_biome_runtime_aliases = Callable(self, "_store_current_biome_runtime_aliases")
	ports.available_facility_item_ids = Callable(self, "_available_facility_item_ids")
	ports.unlocked_biome_ids = Callable(self, "_unlocked_biome_ids")
	return ports

func _run_bootstrap() -> RunBootstrapCoordinator:
	if _run_bootstrap_coordinator == null:
		_run_bootstrap_coordinator = RunBootstrapCoordinator.new(_run_bootstrap_ports(), FRESH_RUN_SEED)
	return _run_bootstrap_coordinator

func _run_bootstrap_ports() -> RunBootstrapCoordinator.Ports:
	var ports := RunBootstrapCoordinator.Ports.new()
	ports.get_catalog = func(): return catalog
	ports.get_run_state = func(): return run_state
	ports.set_run_state = func(value): run_state = value
	ports.get_save_store = func(): return save_store
	ports.get_run_runtime_state_binder = func(): return run_runtime_state_binder
	ports.set_run_runtime_state_binder = func(value): run_runtime_state_binder = value
	ports.runtime_state_entries = Callable(self, "_run_runtime_state_entries")
	ports.ensure_playable_dungeon_runtime = Callable(self, "_ensure_playable_dungeon_runtime")
	ports.prepare_runtime_state_aliases_for_biome = Callable(self, "_prepare_runtime_state_aliases_for_biome")
	ports.configure_acquisition_for_generated_world = Callable(self, "_configure_acquisition_for_generated_world")
	ports.ensure_saved_world_has_teleport_landmark = Callable(self, "_ensure_saved_world_has_teleport_landmark")
	ports.connect_acquisition_combat_source = Callable(self, "_connect_acquisition_combat_source")
	ports.render_generated_world = Callable(self, "_render_generated_world")
	ports.dungeon_runtime_is_active = Callable(self, "_dungeon_runtime_is_active")
	ports.restore_dungeon_map_from_runtime = Callable(self, "_restore_dungeon_map_from_runtime")
	ports.record_current_map_discovery = Callable(self, "_record_current_map_discovery")
	ports.configure_game_hud = Callable(self, "_configure_game_hud")
	ports.get_repair_interaction_service = func(): return repair_interaction_service
	ports.get_time_state = func(): return time_state
	ports.get_combat_dummy = func(): return combat_dummy
	ports.get_player = func(): return player
	ports.get_generated_world = func(): return generated_world
	ports.set_generated_world = func(value): generated_world = value
	ports.set_biome_map_previews = func(value): _biome_map_previews = value
	ports.set_biome_progression_state = func(value): biome_progression_state = value
	ports.set_inventory = func(value): inventory = value
	ports.set_equipment = func(value): equipment = value
	ports.set_tea_service = func(value): tea_service = value
	ports.set_time_state = func(value): time_state = value
	ports.set_crafting_service = func(value): crafting_service = value
	ports.set_facility_placement_service = func(value): facility_placement_service = value
	ports.set_repair_interaction_service = func(value): repair_interaction_service = value
	ports.set_consumable_service = func(value): consumable_service = value
	ports.set_core_tea_ware_collection = func(value): core_tea_ware_collection = value
	ports.set_final_room_state_builder = func(value): final_room_state_builder = value
	ports.set_sen_rikyu_phase_one_runtime = func(value): sen_rikyu_phase_one_runtime = value
	ports.set_sen_rikyu_phase_two_runtime = func(value): sen_rikyu_phase_two_runtime = value
	ports.set_sen_rikyu_phase_three_runtime = func(value): sen_rikyu_phase_three_runtime = value
	ports.set_ending_route_runtime = func(value): ending_route_runtime = value
	ports.set_inventory_command_runtime = func(value): inventory_command_runtime = value
	ports.set_map_read_model_builder = func(value): map_read_model_builder = value
	ports.set_tea_brewing_command_runtime = func(value): tea_brewing_command_runtime = value
	ports.set_meta_codex_command_runtime = func(value): meta_codex_command_runtime = value
	ports.set_memory_tea_cutscene_runtime = func(value): memory_tea_cutscene_runtime = value
	ports.set_narrative_runtime = func(value): narrative_runtime = value
	ports.set_run_start_event_selector = func(value): run_start_event_selector = value
	ports.clear_active_tea_drink_action = func(): _player_item_actions.active_tea_drink_action = {}
	ports.tea_brewing_context = Callable(self, "_tea_brewing_context")
	ports.current_run_state_snapshot = Callable(self, "_current_run_state_snapshot")
	ports.current_meta_state_snapshot = Callable(self, "_current_meta_state_snapshot")
	ports.on_tea_drink_completed = Callable(self, "_on_tea_drink_completed")
	ports.get_run_lifecycle_service = func(): return run_lifecycle_service
	ports.get_inventory = func(): return inventory
	ports.activate_run_state = Callable(self, "_activate_run_state")
	ports.show_the_end_and_return_to_start = Callable(self, "_show_the_end_and_return_to_start")
	ports.push_error = func(message): push_error(message)
	return ports

func movement_command_for_current_inputs(desktop_command) -> GameCommand:
	if desktop_command is GameCommand and desktop_command.type == GameCommand.Type.MOVE and desktop_command.direction != Vector2i.ZERO:
		_clear_pointer_movement()
		return desktop_command
	var pointer_command: GameCommand = _pointer_movement_command()
	if pointer_command.direction != Vector2i.ZERO:
		return pointer_command
	return _movement_selector.select(desktop_command)

func restore_run_state(state) -> Dictionary:
	var restore_result: Dictionary = run_state_snapshot_coordinator.restore_run_state(state, run_runtime_state_binder, _run_runtime_state_entries())
	if not restore_result.ok:
		return restore_result
	run_state = restore_result.run_state
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
	var snapshot_result: Dictionary = run_state_snapshot_coordinator.snapshot_run_state(
		run_state,
		run_runtime_state_binder,
		_run_runtime_state_entries(),
		{
			"player_resources": player.get("resources") if player != null else null,
			"in_dungeon_map": _in_dungeon_map,
			"player_cell": _player_world_cell() if player != null and not _in_dungeon_map else Vector2i.ZERO,
			"overworld_enemy_state": _snapshot_overworld_enemy_state() if not _in_dungeon_map and combat_dummy != null and is_instance_valid(combat_dummy) else {},
			"sync_dungeon_runtime_save_state": Callable(self, "_sync_dungeon_runtime_save_state") if player != null and _in_dungeon_map else Callable(),
			"generated_world": generated_world
		}
	)
	if not snapshot_result.ok:
		push_error(snapshot_result.error)
	else:
		run_state = snapshot_result.run_state
	return run_state.to_dictionary()

func load_or_create_run_state() -> Dictionary:
	var result: Dictionary = run_state_snapshot_coordinator.load_or_create_run_state(
		run_state,
		_start_mode,
		save_store,
		catalog,
		DEFAULT_RUN_SEED
	)
	if result.ok:
		run_state = result.run_state
	return result

func _consume_start_mode() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root == null or not root.has_meta(START_MODE_META):
		return
	_start_mode = String(root.get_meta(START_MODE_META, START_MODE_RESUME))
	root.remove_meta(START_MODE_META)
	_force_first_run_prologue = _start_mode in [START_MODE_NEW, START_MODE_CHEAT]

func _apply_cheat_start_inventory() -> Dictionary:
	if _start_mode != START_MODE_CHEAT:
		return {"ok": true, "applied": false}
	return CheatStartConfigurator.new(catalog, inventory, equipment, run_state).apply(_sync_run_runtime_state)

func _normalize_cheat_progression_state() -> void:
	if _start_mode == START_MODE_CHEAT:
		CheatStartConfigurator.new(catalog, inventory, equipment, run_state).normalize_cheat_progression_state()

func save_current_run() -> Dictionary:
	return _run_bootstrap().save_current_run(Callable(self, "snapshot_run_state"))

func _catalog_declares_time_balance(loaded_catalog) -> bool:
	return RunServiceFactory.catalog_declares_time_balance(loaded_catalog)

func _configure_run_services(loaded_catalog) -> Dictionary:
	return _run_bootstrap().configure_run_services(loaded_catalog)

func final_room_gate_query() -> Dictionary:
	return game_progression_coordinator.final_room_gate_query(self)

func final_room_state_read_model() -> Dictionary:
	return game_progression_coordinator.final_room_state_read_model(self)

func start_sen_rikyu_phase_one(meta_state = null) -> Dictionary:
	return game_progression_coordinator.start_sen_rikyu_phase_one(self, meta_state)

func handle_sen_rikyu_phase_one_command(command_id: String, payload := {}, meta_state = null, resources = null) -> Dictionary:
	return game_progression_coordinator.handle_sen_rikyu_phase_one_command(self, command_id, payload, meta_state, resources)

func start_sen_rikyu_phase_two(phase_one_transition_command) -> Dictionary:
	return game_progression_coordinator.start_sen_rikyu_phase_two(self, phase_one_transition_command)

func start_sen_rikyu_phase_three(phase_two_transition) -> Dictionary:
	return game_progression_coordinator.start_sen_rikyu_phase_three(self, phase_two_transition)

func complete_sen_rikyu_phase_three(ability_id: String) -> Dictionary:
	return game_progression_coordinator.complete_sen_rikyu_phase_three(self, ability_id)

func ending_read_model() -> Dictionary:
	return game_progression_coordinator.ending_read_model(self)

func record_ending_to_meta(meta_state, read_model := {}) -> Dictionary:
	return game_progression_coordinator.record_ending_to_meta(self, meta_state, read_model)

func request_new_run_after_credits(read_model: Dictionary) -> Dictionary:
	return game_progression_coordinator.request_new_run_after_credits(self, read_model)

func _sen_rikyu_phase_two_accepts_command(command) -> bool:
	return game_progression_coordinator.sen_rikyu_phase_two_accepts_command(self, command)

func _handle_sen_rikyu_phase_two_action(command: GameCommand) -> bool:
	return game_progression_coordinator.handle_sen_rikyu_phase_two_action(self, command)

func record_boss_core_tea_ware_rewards(resolution_event: Dictionary) -> Dictionary:
	return game_progression_coordinator.record_boss_core_tea_ware_rewards(self, resolution_event)

func configure_dungeon_runtime(progression_state, completion_resolver: Callable, additional_reward_hook := Callable()) -> Dictionary:
	return game_progression_coordinator.configure_dungeon_runtime(self, progression_state, completion_resolver, additional_reward_hook)

func _equip_default_playable_ability() -> Dictionary:
	return game_progression_coordinator.equip_default_playable_ability(self)

func can_use_ability(_ability_id: String, tail_requirement: int) -> bool:
	if run_state == null:
		return int(tail_requirement) <= 1
	return int(run_state.tails) >= int(tail_requirement)

func targets_for_ability(source, definition, direction: Vector2) -> Array:
	return game_progression_coordinator.targets_for_ability(self, source, definition, direction)

func _combat_targets() -> Array:
	return dungeon_combatant_session.combat_targets(
		_in_dungeon_map,
		combat_dummy,
		DUNGEON_BOSS_OWNER_ID,
		_dungeon_boss_combat_available()
	)

func _dungeon_regular_combat_targets() -> Array:
	return dungeon_combatant_session.regular_combat_targets(_in_dungeon_map, DUNGEON_BOSS_OWNER_ID)

func _ability_target_is_in_range(source, definition, direction: Vector2, target) -> bool:
	return game_progression_coordinator.ability_target_is_in_range(source, definition, direction, target, _runtime_tile_size())

func _ensure_biome_progression_state() -> Dictionary:
	return game_progression_coordinator.ensure_biome_progression_state(self)

func _ensure_playable_dungeon_runtime() -> Dictionary:
	return game_progression_coordinator.ensure_playable_dungeon_runtime(self)

func _dungeon_completion_objective_met(payload: Dictionary) -> bool:
	if bool(payload.get("objective_complete", false)):
		return true
	return _in_dungeon_map and _combat_targets().is_empty() and _dungeon_boss_combat_available()

func _ensure_current_dungeon_entered() -> Dictionary:
	return _dungeon_scene_coordinator.ensure_current_dungeon_entered(self)

func _is_dungeon_resource_target(target_id: String) -> bool:
	return _dungeon_scene_coordinator.is_dungeon_resource_target(self, target_id)

func _is_mining_target(target_id: String) -> bool:
	return _dungeon_scene_coordinator.is_mining_target(self, target_id)

func _dungeon_runtime_is_active() -> bool:
	return _dungeon_scene_coordinator.dungeon_runtime_is_active(self)

func _dungeon_boss_combat_available() -> bool:
	return _dungeon_scene_coordinator.dungeon_boss_combat_available(self)

func _dungeon_boss_action_locked(command) -> bool:
	return _dungeon_scene_coordinator.dungeon_boss_action_locked(self, command)

func _dungeon_boss_node() -> Node2D:
	return _dungeon_scene_coordinator.dungeon_boss_node(self)

func _dungeon_boss_cell() -> Vector2i:
	return _dungeon_scene_coordinator.dungeon_boss_cell(self)

func _dungeon_precombat_dialogue_is_active(event_id: String) -> bool:
	return _dungeon_scene_coordinator.dungeon_precombat_dialogue_is_active(self, event_id)

func _restore_dungeon_boss_precombat_dialogue_if_needed() -> void:
	_dungeon_scene_coordinator.restore_dungeon_boss_precombat_dialogue_if_needed(self)

func _begin_dungeon_boss_precombat_dialogue() -> bool:
	return _dungeon_scene_coordinator.begin_dungeon_boss_precombat_dialogue(self)

func _dungeon_debug(message: String) -> void:
	_dungeon_scene_coordinator.dungeon_debug(self, message)

func _enter_dungeon_map(layout: WorldData, definition: Dictionary, is_new_entry := false) -> void:
	_dungeon_scene_coordinator.enter_dungeon_map(self, layout, definition, is_new_entry)

func _spawn_dungeon_combatants(allow_default_spawn := false) -> void:
	_dungeon_scene_coordinator.spawn_dungeon_combatants(self, allow_default_spawn)

func _dungeon_regular_monster_ids(count: int) -> Array:
	return _dungeon_scene_coordinator.dungeon_regular_monster_ids(self, count)

func _monster_sprite_asset_id(monster_id: String) -> String:
	return _dungeon_scene_coordinator.monster_sprite_asset_id(self, monster_id)

func _clear_dungeon_combatants(restore_overworld := true) -> void:
	_dungeon_scene_coordinator.clear_dungeon_combatants(self, restore_overworld)

func _on_dungeon_enemy_defeated(_event: Dictionary, enemy, owner_id: String) -> void:
	_dungeon_scene_coordinator.on_dungeon_enemy_defeated(self, _event, enemy, owner_id)

func _restore_dungeon_map_from_runtime() -> void:
	_dungeon_scene_coordinator.restore_dungeon_map_from_runtime(self)

func _return_from_dungeon_map() -> void:
	_dungeon_scene_coordinator.return_from_dungeon_map(self)

func _ensure_saved_world_has_teleport_landmark() -> bool:
	return _dungeon_scene_coordinator.ensure_saved_world_has_teleport_landmark(self)

func _current_biome_dungeon_definition() -> Dictionary:
	return _dungeon_scene_coordinator.current_biome_dungeon_definition(self)

func _current_biome_boss_definition(biome_id: String, dungeon_id: String) -> Dictionary:
	return _dungeon_scene_coordinator.current_biome_boss_definition(self, biome_id, dungeon_id)

func _pre_boss_dialogue_event_id_for(dungeon_definition: Dictionary, boss_definition := {}) -> String:
	return _dungeon_scene_coordinator.pre_boss_dialogue_event_id_for(self, dungeon_definition, boss_definition)

func _normalize_reward_hook_result(result) -> Dictionary:
	return DungeonSceneCoordinator.normalize_reward_hook_result(result)


func _configure_acquisition_for_generated_world() -> Dictionary:
	return _world_interaction_coordinator.configure_acquisition_for_generated_world(self)

func _is_repair_interaction_target(target_id: String) -> bool:
	return _world_interaction_coordinator.is_repair_interaction_target(self, target_id)

func _handle_repair_interaction_command(command: GameCommand) -> Dictionary:
	return _world_interaction_coordinator.handle_repair_interaction_command(self, command)

func _node_kind_for_resource_context(item_id: String, biome_id: String) -> String:
	return _acquisition_definitions().node_kind_for_resource_context(item_id, biome_id)

func _generated_drop_definitions() -> Array:
	return _world_interaction_coordinator.generated_drop_definitions(self)

func _connect_acquisition_combat_source(source) -> Dictionary:
	return _world_interaction_coordinator.connect_acquisition_combat_source(self, source)

func _connect_combat_sfx_source(source) -> void:
	if source == null or not source.has_signal("damaged"):
		return
	var callback := Callable(self, "_on_combat_target_damaged")
	if not source.is_connected("damaged", callback):
		source.connect("damaged", callback)

func _on_combat_target_damaged(event: Dictionary, applied_damage: int) -> void:
	_play_sfx_event(SfxEventRouter.EVENT_COMBAT_HIT, {"event": event, "applied_damage": applied_damage}, String(event.get("swing_id", "combat_hit")))

func _on_acquisition_changed(snapshot: Dictionary) -> void:
	_world_interaction_coordinator.acquisition_changed(self, snapshot)

func _on_acquisition_completed(result: Dictionary) -> void:
	_world_interaction_coordinator.acquisition_completed(self, result)

func _on_combat_drop_requested(event: Dictionary, source = null) -> void:
	_world_interaction_coordinator.combat_drop_requested(self, event, source)

func _on_combat_dummy_defeated(_event: Dictionary) -> void:
	_world_interaction_coordinator.combat_dummy_defeated(self, _event)

func _snapshot_overworld_enemy_state() -> Dictionary:
	return _world_interaction_coordinator.snapshot_overworld_enemy_state(self)

func _restore_overworld_enemy_state() -> void:
	_world_interaction_coordinator.restore_overworld_enemy_state(self)

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
	return _run_bootstrap().on_player_hp_depleted()

func _replace_confirmed_dead_run() -> Dictionary:
	return _run_bootstrap().replace_confirmed_dead_run()

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
	return RunStateSnapshotCoordinator.vector_from_dictionary(data)

func _prepare_runtime_state_aliases_for_biome(biome_id: String) -> void:
	run_state_snapshot_coordinator.prepare_runtime_state_aliases_for_biome(run_state, biome_id)

func _store_current_biome_runtime_aliases(biome_id := "") -> void:
	var target_biome_id := biome_id
	if target_biome_id.is_empty():
		target_biome_id = _current_runtime_biome_id()
	run_state_snapshot_coordinator.store_current_biome_runtime_aliases(run_state, target_biome_id)

func _current_runtime_biome_id() -> String:
	return run_state_snapshot_coordinator.current_runtime_biome_id(run_state, generated_world)

func _restore_run_state_from_snapshot(snapshot: Dictionary) -> void:
	run_state = run_state_snapshot_coordinator.restore_run_state_from_snapshot(run_state, snapshot)

func _dictionary_value(value) -> Dictionary:
	return RunStateSnapshotCoordinator._dictionary_value(value)

func _cell_key(cell: Vector2i) -> String:
	return RunStateSnapshotCoordinator.cell_key(cell)

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
	return _world_interaction_coordinator.pointer_movement_command(self)

func _clear_pointer_movement() -> void:
	_world_interaction_coordinator.clear_pointer_movement(self)

func _complete_pending_pointer_interaction_from_pointer_route(target_id: String, target_cell: Vector2i) -> void:
	_world_interaction_coordinator.complete_pending_pointer_interaction_from_pointer_route(self, target_id, target_cell)

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
	return _world_interaction_coordinator.interaction_target_id_for_cell(self, cell)

func _target_footprint_cells(target_id: String, fallback_cell: Vector2i) -> Array:
	return _world_interaction_coordinator.target_footprint_cells(self, target_id, fallback_cell)

func _is_landmark_target(target_id: String) -> bool:
	return _world_interaction_coordinator.is_landmark_target(self, target_id)

func _is_core_dungeon_target(target_id: String) -> bool:
	return _world_interaction_coordinator.is_core_dungeon_target(self, target_id)
func _handle_landmark_interaction(target_id: String) -> bool:
	return _facility_biome_router().handle_landmark_interaction(target_id)

func _travel_to_biome(biome_id: String, travel_mode: String = "teleport") -> bool:
	return _facility_biome_router().travel_to_biome(biome_id, travel_mode)

func _is_connected_biome(from_id: String, to_id: String) -> bool:
	return _facility_biome_router().is_connected_biome(from_id, to_id)

func _is_available_acquisition_target(target_id: String) -> bool:
	return _world_interaction_coordinator.is_available_acquisition_target(self, target_id)

func _handle_tea_command(command: GameCommand) -> bool:
	return _player_runtime().handle_tea_command(command)

func is_tea_drink_active() -> bool:
	return _player_runtime().is_tea_drink_active()

func tick_tea_runtime(delta_seconds: float) -> Dictionary:
	return _player_runtime().tick_tea_runtime(delta_seconds)

func is_consumable_use_active() -> bool:
	return _player_runtime().is_consumable_use_active()

func tick_consumable_runtime(delta_seconds: float) -> Dictionary:
	return _player_runtime().tick_consumable_runtime(delta_seconds)

func _interrupt_consumable_use(reason := "hit") -> Dictionary:
	return _player_runtime().interrupt_consumable_use(reason)

func _handle_consumable_command(command: GameCommand) -> bool:
	return _player_runtime().handle_consumable_command(command)

func _start_consumable_use(item_id: String, context := {}) -> Dictionary:
	return _player_runtime().start_consumable_use(item_id, context)

func _handle_sleep_command() -> bool:
	return _player_runtime().handle_sleep_command()

func _handle_tea_brewing_command(command: GameCommand) -> bool:
	return _player_runtime().handle_tea_brewing_command(command)

func _handle_meta_codex_command(command: GameCommand) -> bool:
	return _player_runtime().handle_meta_codex_command(command)

func _handle_craft_recipe_command(command: GameCommand) -> bool:
	return _facility_biome_router().handle_craft_recipe_command(command)

func has_pending_facility_placement() -> bool:
	return _facility_biome_router().has_pending_facility_placement()

func _select_pending_facility_at(origin: Vector2i) -> void:
	_facility_biome_router().select_pending_facility_at(origin)

func _rotate_pending_facility() -> bool:
	return _facility_biome_router().rotate_pending_facility()

func _confirm_pending_facility() -> bool:
	return _facility_biome_router().confirm_pending_facility()

func _cancel_pending_facility_placement() -> bool:
	return _facility_biome_router().cancel_pending_facility_placement()

func _update_facility_placement_preview(validation: Dictionary) -> void:
	_facility_preview_presenter.update(world_visuals, _pending_facility_origin, _pending_facility_placement, _pending_facility_rotation, validation, _runtime_tile_size(), _facility_footprint_for_pending_facility())

func _content_image_asset_id(dataset: String, content_id: String) -> String:
	return _facility_preview_presenter.content_image_asset_id(dataset, content_id)

func _clear_facility_placement_preview() -> void:
	_facility_preview_presenter.clear()

func _facility_footprint_for_pending_facility() -> Vector2i:
	return _facility_biome_router().facility_footprint_for_pending_facility()

func _player_facility_metadata(facility_item_id: String) -> Dictionary:
	return _facility_biome_router().player_facility_metadata(facility_item_id)

func _handle_inventory_command(command: GameCommand) -> bool:
	return _player_runtime().handle_inventory_command(command)

func _handle_complete_dungeon_command(command: GameCommand) -> bool:
	return _dungeon_command_coordinator.handle_complete_dungeon_command(command, dungeon_runtime, run_state, _in_dungeon_map, game_hud)

func _handle_biome_progression_command(command: GameCommand) -> bool:
	return _facility_biome_router().handle_biome_progression_command(command)

func inventory_read_model() -> Dictionary:
	return _player_runtime().inventory_read_model()

func map_read_model(options := {}) -> Dictionary:
	return _player_runtime().map_read_model(options)

func _selected_inventory_slot_index() -> int:
	return _player_runtime().selected_inventory_slot_index()

func _sync_run_runtime_state() -> void:
	var result: Dictionary = _player_runtime().sync_run_runtime_state()
	if not result.ok:
		push_error(result.error)

func tea_brewing_read_model() -> Dictionary:
	return _player_runtime().tea_brewing_read_model()

func _run_runtime_state_entries() -> Array:
	return _player_runtime().run_runtime_state_entries()

func meta_codex_read_model() -> Dictionary:
	return _player_runtime().meta_codex_read_model()

func _current_run_state_snapshot() -> Dictionary:
	return _player_runtime().current_run_state_snapshot()

func _current_meta_state_snapshot() -> Dictionary:
	return _player_runtime().current_meta_state_snapshot()

func _tea_brewing_context() -> Dictionary:
	return _player_runtime().tea_brewing_context()

func _player_world_cell() -> Vector2i:
	return _player_runtime().player_world_cell()

func _record_current_map_discovery() -> void:
	_player_runtime().record_current_map_discovery()

func _crafting_context() -> Dictionary:
	return _player_runtime().crafting_context()

func _available_facility_item_ids() -> Array:
	return _facility_biome_router().available_facility_item_ids()

func _restore_placed_facilities_for_current_biome() -> Dictionary:
	return _facility_biome_router().restore_placed_facilities_for_current_biome()

func _unlocked_biome_ids() -> Array:
	return _facility_biome_router().unlocked_biome_ids()

func _on_tea_drink_completed(result: Dictionary) -> void:
	_player_runtime().on_tea_drink_completed(result)

func complete_memory_tea_cutscene() -> Dictionary:
	return _player_runtime().complete_memory_tea_cutscene()

func skip_memory_tea_cutscene() -> Dictionary:
	return _player_runtime().skip_memory_tea_cutscene()

func _render_generated_world(world: Dictionary) -> void:
	_hud_presentation().render_generated_world(world)

func _sync_runtime_world_render() -> void:
	_hud_presentation().sync_runtime_world_render()

func _sync_dungeon_runtime_save_state() -> void:
	_dungeon_scene_coordinator.sync_runtime_save_state(self)

func _sync_dungeon_enemy_reservation(owner_id: String, cell: Vector2i, active: bool) -> void:
	_dungeon_scene_coordinator.sync_enemy_reservation(self, owner_id, cell, active)

func _combat_target_cell(enemy) -> Vector2i:
	return _dungeon_scene_coordinator.combat_target_cell(self, enemy)

func _update_dungeon_sign_visibility() -> void:
	_hud_presentation().update_dungeon_sign_visibility()

func _entry_spawn_cell(world: Dictionary) -> Vector2i:
	return WorldPresentation.entry_spawn_cell(world)

func _configure_game_hud() -> void:
	_hud_presentation().configure_game_hud()

func first_run_prologue_read_model(meta_state = null) -> Dictionary:
	return _hud_presentation().first_run_prologue_read_model(meta_state)

func start_run_event_read_model(meta_state = null) -> Dictionary:
	return _hud_presentation().start_run_event_read_model(meta_state)

func _maybe_show_run_start_event() -> Dictionary:
	return _hud_presentation().maybe_show_run_start_event()

func _handle_narrative_option_command(command: GameCommand) -> bool:
	return _hud_presentation().handle_narrative_option_command(command)

func _configure_audio_feedback() -> void:
	_hud_presentation().configure_audio_feedback()

func _play_feedback_beep() -> void:
	_hud_presentation().play_feedback_beep()

func _play_sfx_event(event_id: String, payload := {}, dedupe_key := "") -> Dictionary:
	return _hud_presentation().play_sfx_event(event_id, payload, dedupe_key)

func _centered_world_origin(renderer_input: Dictionary) -> Vector2:
	return _hud_presentation().centered_world_origin(renderer_input)

func _owner_sprite_sources(world: Dictionary) -> Dictionary:
	return _hud_presentation().owner_sprite_sources(world)

func _acquisition_definitions() -> AcquisitionDefinitionBuilder:
	return AcquisitionDefinitionBuilder.new(catalog, inventory, world_data, String(generated_world.get("biome_id", "")))
