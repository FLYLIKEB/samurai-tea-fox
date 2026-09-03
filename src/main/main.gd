extends Node2D

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CoreTeaWareCollection = preload("res://src/dungeon/core_tea_ware_collection.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const FinalRoomStateBuilder = preload("res://src/meta/final_room_state_builder.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const MovementCommandSelector = preload("res://src/core/commands/movement_command_selector.gd")
const MemoryTeaCutsceneRuntime = preload("res://src/narrative/memory_tea_cutscene_runtime.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const TeaBrewingCommandRuntime = preload("res://src/tea/tea_brewing_command_runtime.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")
const MetaCodexCommandRuntime = preload("res://src/meta/meta_codex_command_runtime.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const RunState = preload("res://src/save/run_state.gd")
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
const CraftingService = preload("res://src/crafting/crafting_service.gd")
const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")
const AcquisitionEffect = preload("res://src/presentation/acquisition_effect.gd")

const DEFAULT_RUN_SEED := 11037
const FRESH_RUN_SEED := 0
const POINTER_MOVE_STOP_DISTANCE_PIXELS := 4.0
const FEEDBACK_BEEP_MIX_RATE := 22050.0
const FEEDBACK_BEEP_SECONDS := 0.045
const FEEDBACK_BEEP_FREQUENCY := 880.0
const TIME_SECONDS_PER_TURN := 1.0
const FIRST_RUN_PROLOGUE_EVENT_ID := "first_run_prologue"
const START_MODE_META := "muchau_start_mode"
const START_MODE_NEW := "new"
const START_MODE_RESUME := "resume"
const TREE_HARVEST_TOOL_ITEM_ID := "stone_axe"
const TREE_HARVEST_DEFINITION_PREFIX := "terrain_tree_wood"
const DUNGEON_DEBUG_LOGGING := true
const LARGE_HOUSE_DUNGEON_OWNER_IDS := [
	"large_fenced_house",
	"large_house_fence_nw",
	"large_house_fence_ne",
	"large_house_fence_sw",
	"large_house_fence_se",
	"large_house_fence_n",
	"large_house_fence_s",
	"large_house_fence_w",
	"large_house_fence_e"
]

@onready var player = $Player
@onready var combat_dummy = $CombatDummy
@onready var world_visuals: Node2D = $WorldVisuals
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
var ending_route_runtime
var acquisition_service
var dungeon_runtime
var run_lifecycle_service
var biome_progression_state
var save_store = SaveStore.new()
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
var world_render_result: Dictionary = {}
var _overworld_generated_world: Dictionary = {}
var _overworld_world_data_snapshot: Dictionary = {}
var _overworld_player_cell := Vector2i.ZERO
var _overworld_combat_dummy_cell := Vector2i.ZERO
var _in_dungeon_map := false
var _dungeon_resources: Array = []
var _desktop_adapter := DesktopCommandAdapter.new()
var _movement_selector := MovementCommandSelector.new()
var _has_pointer_move_target := false
var _pointer_move_target_world := Vector2.ZERO
var _pointer_move_route: Array = []
var _pending_pointer_interaction_target_id := ""
var _pending_pointer_interaction_cell := Vector2i.ZERO
var _pending_facility_placement: Dictionary = {}
var _feedback_player: AudioStreamPlayer
var _feedback_playback: AudioStreamGeneratorPlayback
var feedback_beep_count := 0
var _enemy_turn_queued := false
var _active_narrative_event_id := ""
var _active_narrative_node_id := ""
var _start_mode := START_MODE_RESUME
var _force_first_run_prologue := false

func _ready() -> void:
	_configure_audio_feedback()
	_consume_start_mode()
	catalog = DataCatalog.new()
	var result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
		return
	var loaded_run := load_or_create_run_state()
	if not loaded_run.ok:
		push_error(loaded_run.error)
		return
	var runtime_result := _configure_run_services(catalog)
	if not runtime_result.ok:
		push_error(runtime_result.error)
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
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		push_error(world_result.error)
	else:
		_maybe_show_first_run_prologue()

func _configure_combat_lifecycle() -> Dictionary:
	var player_combat_result: Dictionary = player.configure_combat(catalog)
	if not player_combat_result.ok:
		return player_combat_result
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
		player.configure_ability_context(self, time_state, self)
		var ability_result := _equip_default_playable_ability()
		if not ability_result.ok:
			return ability_result
	if combat_dummy.has_signal("defeat_event") and not combat_dummy.is_connected("defeat_event", Callable(self, "_on_combat_dummy_defeated")):
		combat_dummy.connect("defeat_event", Callable(self, "_on_combat_dummy_defeated"))
	if player.has_signal("grid_step_finished") and not player.is_connected("grid_step_finished", Callable(self, "_on_player_grid_step_finished")):
		player.connect("grid_step_finished", Callable(self, "_on_player_grid_step_finished"))
	return {"ok": true}

func _connect_player_feedback_signals() -> void:
	for signal_name in [&"attack_started", &"ability_cast", &"dodge_started", &"grid_step_started"]:
		if player.has_signal(signal_name) and not player.is_connected(signal_name, Callable(self, "_on_player_activity_feedback")):
			player.connect(signal_name, Callable(self, "_on_player_activity_feedback"))

func _on_player_activity_feedback(_a = null, _b = null, _c = null) -> void:
	_play_feedback_beep()

func _on_player_grid_step_finished(_cell: Vector2i) -> void:
	_advance_time_for_turn()
	_queue_enemy_turn_after_player_action()

func _configure_world_for_current_run() -> Dictionary:
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		return progression_result
	biome_progression_state = progression_result.progression_state
	var projection: Dictionary = biome_progression_state.to_projection()
	var current_biome_id := String(projection.get("current_biome_id", ""))
	var current_biome: Dictionary = catalog.find_by_id("biomes", current_biome_id)
	if current_biome.is_empty():
		return {"ok": false, "reason": "missing_current_biome", "error": "No current biome data loaded for %s." % current_biome_id}
	generated_world = generator.generate(run_state.seed, catalog.data_version, current_biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), {"progression_projection": projection})
	if not generated_world.get("ok", false):
		return {"ok": false, "reason": "world_generation_failed", "error": String(generated_world.get("failure_reason", "World generation failed."))}
	var acquisition_result := _configure_acquisition_for_generated_world()
	if not acquisition_result.ok:
		return acquisition_result
	var drop_connection := _connect_acquisition_combat_source(combat_dummy)
	if not drop_connection.ok:
		return drop_connection
	_render_generated_world(generated_world)
	if _dungeon_runtime_is_active():
		_restore_dungeon_map_from_runtime()
	_record_current_map_discovery()
	_configure_game_hud()
	return {"ok": true}

func _physics_process(_delta: float) -> void:
	if player != null and player.ability_runtime != null:
		player.ability_runtime.tick(_delta)
	_record_current_map_discovery()
	var desktop_command = _desktop_adapter.poll_movement_command()
	player.submit_command(movement_command_for_current_inputs(desktop_command))
	var dungeon_interaction_handled := false
	if Input.is_action_just_pressed("attack"):
		_dungeon_debug("E/attack 입력 감지: player_cell=%s in_dungeon=%s" % [world_cell_from_world_position(player.global_position) if player != null else "nil", _in_dungeon_map])
		dungeon_interaction_handled = _try_dungeon_interaction_from_input()
		_dungeon_debug("E/attack 처리 결과: dungeon_handled=%s in_dungeon=%s" % [dungeon_interaction_handled, _in_dungeon_map])
		if not dungeon_interaction_handled:
			submit_desktop_action_command("attack", desktop_command.direction)
	if Input.is_action_just_pressed("dodge"):
		submit_desktop_action_command("dodge", desktop_command.direction)
	if Input.is_action_just_pressed("drink_tea"):
		submit_desktop_action_command("drink_tea")
	if Input.is_action_just_pressed("sleep"):
		submit_desktop_action_command("sleep")
	if Input.is_action_just_pressed("open_tea_brewing"):
		submit_desktop_action_command("open_tea_brewing")
	if _is_hud_menu_open("tea_brewing"):
		if Input.is_action_just_pressed("tea_brew_previous_leaf"):
			submit_desktop_action_command("tea_brew_previous_leaf")
		if Input.is_action_just_pressed("tea_brew_next_leaf"):
			submit_desktop_action_command("tea_brew_next_leaf")
		if Input.is_action_just_pressed("tea_brew_previous_vessel"):
			submit_desktop_action_command("tea_brew_previous_vessel")
		if Input.is_action_just_pressed("tea_brew_next_vessel"):
			submit_desktop_action_command("tea_brew_next_vessel")
		if Input.is_action_just_pressed("tea_brew_previous_slot"):
			submit_desktop_action_command("tea_brew_previous_slot")
		if Input.is_action_just_pressed("tea_brew_next_slot"):
			submit_desktop_action_command("tea_brew_next_slot")
		if Input.is_action_just_pressed("brew_tea"):
			submit_desktop_action_command("brew_tea")
	if Input.is_action_just_pressed("use_consumable"):
		submit_desktop_action_command("use_consumable")
	if Input.is_action_just_pressed("cast_ability"):
		submit_desktop_action_command("cast_ability", desktop_command.direction)
	if Input.is_action_just_pressed("interact") and not dungeon_interaction_handled:
		submit_desktop_action_command("interact", desktop_command.direction)
	if Input.is_action_just_pressed("open_inventory"):
		submit_desktop_action_command("open_inventory")
	if Input.is_action_just_pressed("open_meta_codex"):
		submit_desktop_action_command("open_meta_codex")
	if _is_hud_menu_open("inventory"):
		if Input.is_action_just_pressed("inventory_next"):
			submit_desktop_action_command("inventory_next")
		if Input.is_action_just_pressed("inventory_previous"):
			submit_desktop_action_command("inventory_previous")
		if Input.is_action_just_pressed("inventory_sort"):
			submit_desktop_action_command("inventory_sort")
		if Input.is_action_just_pressed("inventory_use_selected"):
			submit_desktop_action_command("inventory_use_selected", Vector2i.ZERO, _selected_inventory_slot_index())
		if Input.is_action_just_pressed("inventory_equip_selected"):
			submit_desktop_action_command("inventory_equip_selected", Vector2i.ZERO, _selected_inventory_slot_index())
		if Input.is_action_just_pressed("inventory_filter_all"):
			submit_desktop_action_command("inventory_filter_all")
		if Input.is_action_just_pressed("inventory_filter_consumable"):
			submit_desktop_action_command("inventory_filter_consumable")
		if Input.is_action_just_pressed("inventory_filter_equipment"):
			submit_desktop_action_command("inventory_filter_equipment")
	if _is_hud_menu_open("meta_codex"):
		if Input.is_action_just_pressed("meta_codex_next"):
			submit_desktop_action_command("meta_codex_next")
		if Input.is_action_just_pressed("meta_codex_previous"):
			submit_desktop_action_command("meta_codex_previous")
	if Input.is_action_just_pressed("open_crafting"):
		submit_desktop_action_command("open_crafting")
	if Input.is_action_just_pressed("open_facilities"):
		submit_desktop_action_command("open_facilities")
	if Input.is_action_just_pressed("open_map"):
		submit_desktop_action_command("open_map")

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
		_play_feedback_beep()
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
		_place_pending_facility_at(world_cell_from_world_position(world_position))
		return true
	_dungeon_debug("클릭 상호작용: world=%s cell=%s" % [world_position, world_cell_from_world_position(world_position)])
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
	var landmark := _landmark_target_near_world_position(player.global_position, _runtime_tile_size() * 2.5)
	if landmark.is_empty():
		landmark = _large_house_target_near_world_position(player.global_position, _runtime_tile_size() * 3.5)
	if landmark.is_empty():
		_dungeon_debug("E 대상 없음: origin_cell=%s" % origin_cell)
		return false
	_dungeon_debug("E 거리 대상 발견: %s" % landmark)
	return submit_interaction_at_world_cell(landmark.cell)

func _pointer_enemy_clicked(world_position: Vector2) -> bool:
	if combat_dummy == null \
			or not combat_dummy.visible \
			or not combat_dummy.has_method("current_hp") \
			or int(combat_dummy.current_hp()) <= 0:
		return false
	var hit_radius := maxf(_runtime_tile_size() * 0.5, 16.0)
	return combat_dummy.global_position.distance_to(world_position) <= hit_radius

func _queue_pointer_acquisition(target_id: String, target_cell: Vector2i) -> bool:
	if player == null:
		return submit_interaction_at_world_cell(target_cell)
	var player_cell := world_cell_from_world_position(player.global_position)
	if _cells_are_adjacent(player_cell, target_cell):
		return submit_interaction_at_world_cell(target_cell)
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
		return submit_interaction_at_world_cell(target_cell)
	var approach_cell := _nearest_walkable_adjacent_cell_for_target(target_id, target_cell, player_cell)
	if approach_cell == target_cell:
		return false
	_begin_pointer_move_route(player_cell, approach_cell, target_id, target_cell)
	if not _has_pointer_move_target:
		return false
	return true

func _begin_pointer_move_route(from_cell: Vector2i, destination_cell: Vector2i, target_id: String, target_cell: Vector2i) -> void:
	var route := _find_walkable_route(from_cell, destination_cell, target_id)
	if route.is_empty():
		_dungeon_debug("이동 경로 생성 실패: from=%s destination=%s target=%s" % [from_cell, destination_cell, target_id])
		_clear_pointer_movement()
		return
	_dungeon_debug("이동 경로 생성: %s -> %s, steps=%d, target=%s" % [from_cell, destination_cell, route.size(), target_id])
	_pointer_move_route = route
	_pointer_move_target_world = world_position_for_cell_center(Vector2i(route[0]))
	_has_pointer_move_target = true
	_pending_pointer_interaction_target_id = target_id
	_pending_pointer_interaction_cell = target_cell
	_movement_selector.submit_mobile_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))

func _find_walkable_route(from_cell: Vector2i, destination_cell: Vector2i, target_id: String) -> Array:
	if from_cell == destination_cell:
		return [destination_cell]
	if world_data == null:
		return []
	var blocked := {}
	for cell in _target_footprint_cells(target_id, destination_cell):
		blocked[_cell_key(cell)] = true
	blocked.erase(_cell_key(destination_cell))
	var queue: Array = [from_cell]
	var previous := {_cell_key(from_cell): ""}
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for offset in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var next: Vector2i = current + offset
			var key := _cell_key(next)
			if previous.has(key) or blocked.has(key):
				continue
			if not world_data.contains(next) or not world_data.is_walkable(next):
				continue
			previous[key] = _cell_key(current)
			queue.append(next)
			if next == destination_cell:
				var route: Array = []
				var cursor := key
				while cursor != _cell_key(from_cell):
					var parts := cursor.split(",")
					route.push_front(Vector2i(int(parts[0]), int(parts[1])))
					cursor = String(previous[cursor])
				return route
	return []

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
	_pointer_move_target_world = world_position_for_cell_center(target_cell)
	_has_pointer_move_target = true
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
			return submit_interaction_at_world_cell(nearby_landmark.cell)
	return false

func _landmark_target_near_world_position(world_position: Vector2, max_distance := -1.0) -> Dictionary:
	if world_data == null:
		return {}
	var tile_size := _runtime_tile_size()
	var distance_limit := tile_size * 1.6 if max_distance < 0.0 else max_distance
	for landmark in world_data.get_required_landmarks():
		var kind := String(landmark.get("kind", landmark.get("type", "")))
		if kind != WorldData.LANDMARK_CORE_DUNGEON:
			continue
		var cell := _vector_from_dictionary(landmark.get("position", {}))
		var center := world_position_for_cell_center(cell) + Vector2(tile_size * 0.5, tile_size * 0.5)
		if world_position.distance_to(center) <= distance_limit:
			return {"target_id": String(landmark.get("id", "")), "cell": cell}
	return {}

func _large_house_target_near_world_position(world_position: Vector2, max_distance := -1.0) -> Dictionary:
	var house: Dictionary = generated_world.get("large_house", {})
	if house.is_empty():
		return {}
	var origin := _vector_from_dictionary(house.get("position", {}))
	var tile_size := _runtime_tile_size()
	var center := _runtime_world_origin() + Vector2((origin.x + 1.0) * tile_size, (origin.y + 1.0) * tile_size)
	var distance_limit := tile_size * 2.0 if max_distance < 0.0 else max_distance
	if world_position.distance_to(center) <= distance_limit:
		return {"target_id": WorldGenerator.LARGE_HOUSE_ID, "cell": origin}
	return {}

func submit_interaction_at_world_cell(cell: Vector2i) -> bool:
	var target_id := _interaction_target_id_for_cell(cell)
	if target_id.is_empty():
		return false
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))

func submit_action_command(command) -> bool:
	if not command is GameCommand:
		return false
	match command.type:
		GameCommand.Type.NARRATIVE_SELECT_OPTION:
			var narrative_accepted := _handle_narrative_option_command(command)
			if narrative_accepted:
				_play_feedback_beep()
			return narrative_accepted
		GameCommand.Type.INTERACT:
			var target_id := String(command.payload.get("target_id", ""))
			if target_id.is_empty():
				return submit_player_interaction(command.direction)
			if _is_landmark_target(target_id):
				var landmark_accepted := _handle_landmark_interaction(target_id)
				if landmark_accepted:
					_play_feedback_beep()
				return landmark_accepted
			var accepted: bool = acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
			if accepted:
				_advance_time_for_turn()
				_play_feedback_beep()
				_queue_enemy_turn_after_player_action()
			return accepted
		GameCommand.Type.DRINK_TEA:
			var accepted: bool = _handle_tea_command(command)
			if accepted:
				_advance_time_for_turn()
				_play_feedback_beep()
				_queue_enemy_turn_after_player_action()
			return accepted
		GameCommand.Type.USE_CONSUMABLE:
			var accepted: bool = _handle_consumable_command(command)
			if accepted:
				_advance_time_for_turn()
				_play_feedback_beep()
			return accepted
		GameCommand.Type.SLEEP:
			var accepted: bool = _handle_sleep_command()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.COMPLETE_DUNGEON:
			var accepted: bool = _handle_complete_dungeon_command(command)
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.REPAIR_TELEPORT, GameCommand.Type.ADVANCE_BIOME:
			var accepted: bool = _handle_biome_progression_command(command)
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_TEA_BREWING:
			var accepted: bool = game_hud != null and game_hud.show_tea_brewing_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.TEA_BREW_SELECT_LEAF, GameCommand.Type.TEA_BREW_SELECT_VESSEL, GameCommand.Type.TEA_BREW_SELECT_SLOT, GameCommand.Type.TEA_BREW_NAVIGATE, GameCommand.Type.BREW_TEA:
			var accepted: bool = _handle_tea_brewing_command(command)
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_META_CODEX:
			var accepted: bool = game_hud != null and game_hud.show_meta_codex_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.META_CODEX_SET_TAB, GameCommand.Type.META_CODEX_SET_FILTER, GameCommand.Type.META_CODEX_SELECT_DETAIL, GameCommand.Type.META_CODEX_NAVIGATE:
			var accepted: bool = _handle_meta_codex_command(command)
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_INVENTORY:
			var accepted: bool = game_hud != null and game_hud.show_inventory_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_CRAFTING:
			_configure_game_hud()
			var accepted: bool = game_hud != null and game_hud.show_crafting_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_FACILITIES:
			_configure_game_hud()
			var accepted: bool = game_hud != null and game_hud.show_facilities_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_MAP:
			var accepted: bool = game_hud != null and game_hud.show_map_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.HIDE_MENU:
			var placement_cancelled := _cancel_pending_facility_placement()
			var accepted: bool = (game_hud != null and game_hud.hide_menu()) or placement_cancelled
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.CRAFT_RECIPE:
			var accepted: bool = _handle_craft_recipe_command(command)
			if accepted and not has_pending_facility_placement():
				_advance_time_for_turn()
				_play_feedback_beep()
				_queue_enemy_turn_after_player_action()
			return accepted
		GameCommand.Type.INVENTORY_SET_FILTER, GameCommand.Type.INVENTORY_SORT, GameCommand.Type.INVENTORY_SELECT_SLOT, GameCommand.Type.INVENTORY_NAVIGATE, GameCommand.Type.EQUIP_INVENTORY_SLOT, GameCommand.Type.UNEQUIP_SLOT, GameCommand.Type.USE_INVENTORY_SLOT:
			var accepted: bool = _handle_inventory_command(command)
			if accepted:
				_play_feedback_beep()
			return accepted
		_:
			if _sen_rikyu_phase_two_accepts_command(command):
				var accepted: bool = _handle_sen_rikyu_phase_two_action(command)
				if accepted:
					_advance_time_for_turn()
					_play_feedback_beep()
					_queue_enemy_turn_after_player_action()
				return accepted
			var accepted: bool = player != null and player.submit_command(command)
			if accepted and _is_turn_advancing_player_action(command):
				_advance_time_for_turn()
				_queue_enemy_turn_after_player_action()
			return accepted

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
	var inventory_before: Dictionary = inventory.to_snapshot() if inventory != null else {}
	var equipment_before: Dictionary = equipment.to_snapshot() if equipment != null else {}
	var tea_before: Dictionary = tea_service.to_snapshot() if tea_service != null else {}
	var consumables_before: Dictionary = consumable_service.to_snapshot() if consumable_service != null else {}
	var acquisitions_before: Dictionary = acquisition_service.to_snapshot() if acquisition_service != null else {}
	if inventory != null and not state.inventory.is_empty():
		var inventory_result: Dictionary = inventory.load_snapshot(state.inventory)
		if not inventory_result.ok:
			return inventory_result
	if acquisition_service != null and not state.acquisitions.is_empty():
		var acquisition_result: Dictionary = acquisition_service.load_snapshot(state.acquisitions)
		if not acquisition_result.ok:
			if inventory != null and not inventory_before.is_empty():
				inventory.load_snapshot(inventory_before)
			if equipment != null and not equipment_before.is_empty():
				equipment.load_snapshot(equipment_before)
			if not acquisitions_before.is_empty():
				acquisition_service.load_snapshot(acquisitions_before)
			return acquisition_result
	if equipment != null and not state.equipment.is_empty():
		var equipment_result: Dictionary = equipment.load_snapshot(state.equipment)
		if not equipment_result.ok:
			if inventory != null and not inventory_before.is_empty():
				inventory.load_snapshot(inventory_before)
			return equipment_result
	if tea_service != null and not state.tea.is_empty():
		var tea_load_result: Dictionary = tea_service.load_snapshot(state.tea)
		if not tea_load_result.ok:
			if inventory != null and not inventory_before.is_empty():
				inventory.load_snapshot(inventory_before)
			if equipment != null and not equipment_before.is_empty():
				equipment.load_snapshot(equipment_before)
			if not tea_before.is_empty():
				tea_service.load_snapshot(tea_before)
			return tea_load_result
	if consumable_service != null and not state.consumables.is_empty():
		var consumable_load_result: Dictionary = consumable_service.load_snapshot(state.consumables)
		if not consumable_load_result.ok:
			if inventory != null and not inventory_before.is_empty():
				inventory.load_snapshot(inventory_before)
			if equipment != null and not equipment_before.is_empty():
				equipment.load_snapshot(equipment_before)
			if not tea_before.is_empty():
				tea_service.load_snapshot(tea_before)
			if not consumables_before.is_empty():
				consumable_service.load_snapshot(consumables_before)
			if not acquisitions_before.is_empty():
				acquisition_service.load_snapshot(acquisitions_before)
			return consumable_load_result
	run_state = state
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if equipment != null:
		run_state.equipment = equipment.to_snapshot()
	if tea_service != null:
		run_state.tea = tea_service.to_snapshot()
	if consumable_service != null:
		_sync_consumable_runtime_state()
	if time_state != null:
		run_state.time = time_state.to_snapshot()
	if acquisition_service != null:
		run_state.acquisitions = acquisition_service.to_snapshot()
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
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if acquisition_service != null:
		run_state.acquisitions = acquisition_service.to_snapshot()
	if memory_tea_cutscene_runtime != null:
		run_state.memory_tea_cutscene = memory_tea_cutscene_runtime.to_snapshot()
	if tea_service != null:
		run_state.tea = tea_service.to_snapshot()
	if consumable_service != null:
		_sync_consumable_runtime_state()
	if time_state != null:
		run_state.time = time_state.to_snapshot()
	return run_state.to_dictionary()

func load_or_create_run_state() -> Dictionary:
	if run_state != null:
		return {"ok": true, "state": "provided", "run_state": run_state}
	if _start_mode == START_MODE_NEW:
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
	_force_first_run_prologue = _start_mode == START_MODE_NEW

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

func save_current_run() -> Dictionary:
	if save_store == null:
		return {"ok": false, "reason": "missing_save_store", "error": "Save store is not configured."}
	return save_store.save_run(snapshot_run_state())

func _catalog_declares_time_balance(loaded_catalog) -> bool:
	if loaded_catalog == null or not loaded_catalog.has_method("find_by_id"):
		return false
	for id in [
		TimeConfig.DAY_DURATION_ID,
		TimeConfig.DUSK_DURATION_ID,
		TimeConfig.NIGHT_DURATION_ID,
		TimeConfig.LATE_NIGHT_DURATION_ID,
		TimeConfig.DUSK_KOKORO_DECAY_ID,
		TimeConfig.NIGHT_KOKORO_DECAY_ID,
		TimeConfig.LATE_NIGHT_KOKORO_DECAY_ID,
		TimeConfig.LOW_KOKORO_ABILITY_COST_INCREASE_ID,
		TimeConfig.SLEEP_HEAL_RATIO_ID
	]:
		if not loaded_catalog.find_by_id("balance", id).is_empty():
			return true
	return false

func _configure_run_services(loaded_catalog) -> Dictionary:
	var inventory_result: Dictionary = InventoryModel.from_catalog(loaded_catalog)
	if not inventory_result.ok:
		return inventory_result
	var equipment_result: Dictionary = EquipmentModel.from_catalog(loaded_catalog)
	if not equipment_result.ok:
		return equipment_result
	var tea_result: Dictionary = TeaService.from_catalog(loaded_catalog)
	if not tea_result.ok:
		return tea_result
	var time_config_result: Dictionary = TimeConfig.from_catalog(loaded_catalog)
	if not time_config_result.ok and _catalog_declares_time_balance(loaded_catalog):
		return time_config_result
	var crafting_result: Dictionary = CraftingService.from_catalog(loaded_catalog)
	if not crafting_result.ok:
		return crafting_result
	var facility_placement_result: Dictionary = FacilityPlacementService.from_catalog(loaded_catalog)
	if not facility_placement_result.ok:
		return facility_placement_result
	var consumable_result: Dictionary = ConsumableService.from_catalog(loaded_catalog)
	if not consumable_result.ok and String(consumable_result.get("reason", "")) not in ["missing_balance", "missing_consumable_definitions"]:
		return consumable_result
	var core_tea_ware_result: Dictionary = CoreTeaWareCollection.from_catalog(loaded_catalog)
	if not core_tea_ware_result.ok:
		return core_tea_ware_result
	var final_room_result: Dictionary = FinalRoomStateBuilder.from_catalog(loaded_catalog)
	if not final_room_result.ok:
		return final_room_result
	inventory = inventory_result.inventory
	if run_state != null and not run_state.inventory.is_empty():
		var inventory_load_result: Dictionary = inventory.load_snapshot(run_state.inventory)
		if not inventory_load_result.ok:
			return inventory_load_result
	equipment = equipment_result.equipment
	if run_state != null and not run_state.equipment.is_empty():
		var equipment_load_result: Dictionary = equipment.load_snapshot(run_state.equipment)
		if not equipment_load_result.ok:
			return equipment_load_result
	tea_service = tea_result.tea_service
	time_state = TimeState.new(time_config_result.config) if time_config_result.ok else null
	if time_state != null and run_state != null and not run_state.time.is_empty():
		var time_load_result: Dictionary = time_state.load_snapshot(run_state.time)
		if not time_load_result.ok:
			return time_load_result
	if run_state != null and not run_state.tea.is_empty():
		var tea_load_result: Dictionary = tea_service.load_snapshot(run_state.tea)
		if not tea_load_result.ok:
			return tea_load_result
	crafting_service = crafting_result.crafting_service
	facility_placement_service = facility_placement_result.facility_placement_service
	consumable_service = consumable_result.consumable_service if consumable_result.ok else null
	if consumable_service != null and run_state != null and not run_state.consumables.is_empty():
		var consumable_load_result: Dictionary = consumable_service.load_snapshot(run_state.consumables)
		if not consumable_load_result.ok:
			return consumable_load_result
	core_tea_ware_collection = core_tea_ware_result.collection
	final_room_state_builder = final_room_result.builder
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
	if run_state != null and not run_state.memory_tea_cutscene.is_empty():
		var memory_load_result: Dictionary = memory_tea_cutscene_runtime.load_snapshot(run_state.memory_tea_cutscene)
		if not memory_load_result.ok:
			return memory_load_result
	narrative_runtime = NarrativeRuntime.new()
	var narrative_result: Dictionary = narrative_runtime.from_catalog(loaded_catalog)
	if not narrative_result.ok:
		return narrative_result
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
				"direction": Vector2(command.direction).normalized() if command.direction != Vector2i.ZERO else Vector2.RIGHT
			}
			return bool(sen_rikyu_phase_two_runtime.cast_player_ability(player.ability_runtime, command.slot, context).ok)
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
	if combat_dummy != null \
			and combat_dummy.has_method("current_hp") \
			and int(combat_dummy.current_hp()) > 0 \
			and _ability_target_is_in_range(source, definition, direction, combat_dummy):
		return [combat_dummy]
	return []

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
	return combat_dummy != null and combat_dummy.has_method("current_hp") and int(combat_dummy.current_hp()) <= 0

func _ensure_current_dungeon_entered() -> Dictionary:
	var projection: Dictionary = dungeon_runtime.to_projection() if dungeon_runtime != null else {}
	var lifecycle := String(projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE))
	if lifecycle == DungeonInstanceState.STATE_ACTIVE:
		return {"ok": true, "state": "already_active"}
	if lifecycle not in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED]:
		return {"ok": false, "reason": "dungeon_lifecycle_busy", "error": "Dungeon lifecycle is not ready for a new entry."}
	var definition := _current_biome_dungeon_definition()
	if definition.is_empty():
		_dungeon_debug("현재 바이옴 던전 정의 없음: biome=%s" % (run_state.current_biome_id if run_state != null else "nil"))
		return {"ok": false, "reason": "missing_current_dungeon", "error": "No dungeon definition exists for the current biome."}
	var biome_id := String(run_state.current_biome_id)
	definition["biome_id"] = biome_id
	var layout := WorldData.new(12, 9, "terrain_plains_grass_ground_01", true)
	layout.add_required_landmark(WorldData.LANDMARK_ENTRY, "dungeon_entry", Vector2i(1, 1), {"dungeon_id": String(definition.id)})
	_dungeon_resources.clear()
	for y in range(layout.height):
		for x in range(layout.width):
			layout.set_terrain(Vector2i(x, y), "dungeon_grass", true, "terrain_plains_grass_ground_02")
	for index in range(6):
		var resource_cell := Vector2i(4 + (index % 3) * 2, 3 + (index / 3) * 3)
		var resource_id := "dungeon_iron_ore_%d" % index
		var reservation := layout.reserve_entity(resource_id, resource_cell, Vector2i.ONE, true, {"source_id": "asset_assets_sprites_objects_mining_iron_ore_32x32_png"})
		if reservation.ok:
			_dungeon_resources.append({"id": resource_id, "resource_id": "iron_ore", "position": {"x": resource_cell.x, "y": resource_cell.y}, "source_id": "asset_assets_sprites_objects_mining_iron_ore_32x32_png"})
	for enemy in [{"id": "dungeon_enemy_0", "cell": Vector2i(7, 2)}, {"id": "dungeon_enemy_1", "cell": Vector2i(9, 5)}, {"id": "dungeon_enemy_2", "cell": Vector2i(5, 7)}, {"id": "dungeon_boss", "cell": Vector2i(10, 7)}]:
		layout.reserve_entity(String(enemy.id), enemy.cell, Vector2i.ONE, false, {"source_id": "asset_assets_sprites_characters_bosses_chr_6_yokai_tea_master_yokai_tea_master_front_32x32_png" if enemy.id == "dungeon_boss" else "monster_foxfire_front_idle", "role": "boss" if enemy.id == "dungeon_boss" else "dungeon_enemy"})
	var enter_result: Dictionary = dungeon_runtime.enter_dungeon(
		"%s_%d" % [String(definition.id), run_state.seed],
		definition,
		layout,
		{"biome_id": biome_id, "world_seed": run_state.seed}
	)
	if enter_result.ok:
		_enter_dungeon_map(layout, definition)
	else:
		_dungeon_debug("dungeon_runtime.enter_dungeon 실패: %s" % enter_result)
	return enter_result

func _dungeon_runtime_is_active() -> bool:
	return dungeon_runtime != null and String(dungeon_runtime.to_projection().get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) == DungeonInstanceState.STATE_ACTIVE

func _dungeon_debug(message: String) -> void:
	if DUNGEON_DEBUG_LOGGING:
		print("[DungeonDebug] %s" % message)

func _enter_dungeon_map(layout: WorldData, definition: Dictionary) -> void:
	if _in_dungeon_map:
		return
	_overworld_generated_world = generated_world.duplicate(true)
	_overworld_world_data_snapshot = world_data.to_dictionary() if world_data != null else {}
	_overworld_player_cell = _player_world_cell()
	_overworld_combat_dummy_cell = world_cell_from_world_position(combat_dummy.global_position) if combat_dummy != null else Vector2i.ZERO
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
			dungeon_definitions.append({"id": String(node.id), "item_id": "iron_ore", "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT})
		acquisition_service.configure(inventory, world_data, dungeon_definitions, [])
	_render_generated_world(generated_world)
	player.global_position = world_position_for_cell_center(Vector2i(1, 1))
	if combat_dummy != null:
		combat_dummy.global_position = world_position_for_cell_center(Vector2i(3, 1))
	_configure_game_hud()

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
	generated_world = _overworld_generated_world
	world_data = WorldData.from_dictionary(_overworld_world_data_snapshot)
	_in_dungeon_map = false
	_configure_acquisition_for_generated_world()
	_render_generated_world(generated_world)
	player.global_position = world_position_for_cell_center(_overworld_player_cell)
	if combat_dummy != null:
		combat_dummy.global_position = world_position_for_cell_center(_overworld_combat_dummy_cell)
	_configure_game_hud()

func _current_biome_dungeon_definition() -> Dictionary:
	if catalog == null or run_state == null:
		return {}
	var current_biome_id := String(run_state.current_biome_id)
	for definition in catalog.get_definitions("dungeons"):
		var biome_ids: Array = definition.get("biome_ids", [])
		if biome_ids.has(current_biome_id):
			return definition.duplicate(true)
	return {
		"id": "%s_core_dungeon" % current_biome_id,
		"name": "%s 핵심 던전" % current_biome_id,
		"biome_ids": [current_biome_id],
		"phase_count": 1,
		"pattern_count": 1,
		"peaceful_resolution": false,
		"reward_item_ids": []
	}

func _normalize_reward_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": result, "reason": "additional_reward_hook_rejected", "error": "Additional dungeon reward hook rejected completion."}
	return {"ok": true, "value": result}

func _configure_acquisition_for_generated_world() -> Dictionary:
	if not generated_world.get("ok", false) or typeof(generated_world.get("world_data")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_generated_world", "error": "Acquisition requires a generated world snapshot."}
	var saved_acquisitions := run_state.acquisitions.duplicate(true) if run_state != null else {}
	world_data = WorldData.from_dictionary(generated_world.world_data)
	var facility_restore_result := _restore_placed_facilities_for_current_biome()
	if not facility_restore_result.ok:
		return facility_restore_result
	acquisition_service = AcquisitionService.new()
	var definitions := _confirmed_generated_resource_definitions(generated_world.get("resource_nodes", []))
	definitions.append_array(_terrain_tree_gatherable_definitions())
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
	var terrain_tree_result := _register_terrain_tree_gatherables(definition_ids)
	if not terrain_tree_result.ok:
		return terrain_tree_result
	if not saved_acquisitions.is_empty():
		var loaded: Dictionary = acquisition_service.load_snapshot(saved_acquisitions)
		if not loaded.ok:
			return loaded
		terrain_tree_result = _register_terrain_tree_gatherables(definition_ids)
		if not terrain_tree_result.ok:
			return terrain_tree_result
	acquisition_service.changed.connect(_on_acquisition_changed)
	acquisition_service.acquisition_completed.connect(_on_acquisition_completed)
	_on_acquisition_changed(acquisition_service.to_snapshot())
	return {"ok": true}

func _confirmed_generated_resource_definitions(resource_nodes: Array) -> Array:
	var definitions := []
	var seen := {}
	for node in resource_nodes:
		var resource_id := String(node.get("resource_id", ""))
		if resource_id.is_empty() or seen.has(resource_id) or inventory == null or not inventory.has_definition(resource_id):
			continue
		var item: Dictionary = catalog.find_by_id("items", resource_id)
		if String(item.get("status", "")) != "확정" or not _is_generated_resource_item_type(String(item.get("type", ""))):
			continue
		definitions.append({"id": resource_id, "item_id": resource_id, "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT})
		seen[resource_id] = true
	return definitions

func _is_generated_resource_item_type(item_type: String) -> bool:
	return item_type == "재료" or item_type == "향"

func _terrain_tree_gatherable_definitions() -> Array:
	var definitions: Array = []
	if world_data == null:
		return definitions
	var snapshot: Dictionary = world_data.to_dictionary()
	for cell in snapshot.get("cells", []):
		var tree_profile := _tree_harvest_profile_for_cell(cell)
		if tree_profile.is_empty():
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		definitions.append({
			"id": _terrain_tree_gatherable_id(position),
			"item_id": "wood",
			"quantity": 1,
			"policy": AcquisitionService.POLICY_DIRECT,
			"required_tool_item_id": TREE_HARVEST_TOOL_ITEM_ID,
			"depleted_terrain": tree_profile
		})
	return definitions

func _register_terrain_tree_gatherables(definition_ids: Dictionary) -> Dictionary:
	if world_data == null or acquisition_service == null:
		return {"ok": true}
	var snapshot: Dictionary = world_data.to_dictionary()
	for cell in snapshot.get("cells", []):
		if _tree_harvest_profile_for_cell(cell).is_empty():
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		var node_id := _terrain_tree_gatherable_id(position)
		if not definition_ids.has(node_id):
			continue
		if not acquisition_service.gatherable_for(node_id).is_empty():
			continue
		var registered: Dictionary = acquisition_service.register_gatherable(node_id, node_id, position)
		if not registered.ok:
			return registered
	return {"ok": true}

func _terrain_tree_gatherable_id(position: Vector2i) -> String:
	return "%s_%d_%d" % [TREE_HARVEST_DEFINITION_PREFIX, position.x, position.y]

func _tree_harvest_profile_for_cell(cell: Dictionary) -> Dictionary:
	var layers: Dictionary = cell.get("layers", {})
	var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
	var terrain_id := String(terrain.get("id", ""))
	match terrain_id:
		WorldGenerator.TERRAIN_FOREST:
			return {"id": WorldGenerator.TERRAIN_GRASS, "render_id": WorldGenerator.RENDER_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_MOUNTAIN_CONIFER:
			return {"id": WorldGenerator.TERRAIN_GRASS, "render_id": WorldGenerator.RENDER_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_WASTELAND_DEAD_TREE:
			return {"id": WorldGenerator.TERRAIN_GRASS, "render_id": WorldGenerator.RENDER_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_SNOWFIELD_PINE:
			return {"id": WorldGenerator.TERRAIN_GRASS, "render_id": WorldGenerator.RENDER_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_RAINFOREST_JUNGLE, WorldGenerator.TERRAIN_RAINFOREST_AGARWOOD:
			return {"id": WorldGenerator.TERRAIN_GRASS, "render_id": WorldGenerator.RENDER_GRASS, "walkable": true}
		_:
			return {}

func _generated_drop_definitions() -> Array:
	var grants_by_monster := {}
	for drop in catalog.get_definitions("drops"):
		var monster_id := String(drop.get("monster_id", ""))
		var target_id := String(drop.get("item_id", drop.get("tea_id", "")))
		if not grants_by_monster.has(monster_id):
			grants_by_monster[monster_id] = []
		grants_by_monster[monster_id].append({
			"drop_id": String(drop.get("id", "")),
			"item_id": target_id,
			"min_quantity": int(drop.get("min_quantity", 0)),
			"max_quantity": int(drop.get("max_quantity", 0)),
			"chance": float(drop.get("chance", 0.0)),
			"condition": String(drop.get("condition", "")),
			"policy": AcquisitionService.POLICY_DIRECT
		})
	var definitions := []
	var monster_ids: Array = grants_by_monster.keys()
	monster_ids.sort()
	for monster_id in monster_ids:
		definitions.append({"monster_id": monster_id, "grants": grants_by_monster[monster_id]})
	return definitions

func _connect_acquisition_combat_source(source) -> Dictionary:
	if source == null or not source.has_signal("drop_requested"):
		return {"ok": false, "reason": "invalid_drop_source", "error": "Combat source must expose drop_requested."}
	var callback := Callable(self, "_on_combat_drop_requested")
	if not source.is_connected("drop_requested", callback):
		source.connect("drop_requested", callback)
	return {"ok": true}

func _on_acquisition_changed(snapshot: Dictionary) -> void:
	if run_state != null:
		run_state.acquisitions = snapshot.duplicate(true)
	_sync_runtime_world_render()

func _on_acquisition_completed(result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not result.get("position", null) is Dictionary:
		return
	var item_id := String(result.get("item_id", ""))
	if item_id.is_empty():
		return
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

func _on_combat_drop_requested(event: Dictionary) -> void:
	if acquisition_service == null:
		return
	var normalized := event.duplicate(true)
	if not normalized.has("position") and combat_dummy != null:
		var drop_cell := world_cell_from_world_position(combat_dummy.global_position)
		normalized.position = {
			"x": drop_cell.x,
			"y": drop_cell.y
		}
	var result: Dictionary = acquisition_service.process_drop_request(normalized)
	if not result.ok:
		push_error(result.error)

func _on_combat_dummy_defeated(_event: Dictionary) -> void:
	if combat_dummy == null:
		return
	combat_dummy.visible = false
	combat_dummy.automatic_attacks = false
	combat_dummy.collision_layer = 0
	combat_dummy.collision_mask = 0

func _queue_enemy_turn_after_player_action() -> void:
	if _enemy_turn_queued:
		return
	_enemy_turn_queued = true
	call_deferred("_run_enemy_turn_after_player_action")

func _run_enemy_turn_after_player_action() -> void:
	if player != null and player.has_method("is_grid_step_active") and player.is_grid_step_active():
		var scene_tree := get_tree()
		if scene_tree == null:
			_enemy_turn_queued = false
			return
		scene_tree.process_frame.connect(Callable(self, "_run_enemy_turn_after_player_action"), CONNECT_ONE_SHOT)
		return
	if combat_dummy != null and combat_dummy.has_method("is_grid_step_active") and combat_dummy.is_grid_step_active():
		var scene_tree := get_tree()
		if scene_tree != null:
			scene_tree.process_frame.connect(Callable(self, "_run_enemy_turn_after_player_action"), CONNECT_ONE_SHOT)
		return
	_enemy_turn_queued = false
	if combat_dummy == null or player == null or not combat_dummy.visible:
		return
	if combat_dummy.has_method("take_turn"):
		combat_dummy.take_turn(player)

func _is_turn_advancing_player_action(command) -> bool:
	if not command is GameCommand:
		return false
	return [
		GameCommand.Type.ATTACK,
		GameCommand.Type.DODGE,
		GameCommand.Type.CAST_ABILITY,
		GameCommand.Type.USE_CONSUMABLE,
		GameCommand.Type.COMPLETE_DUNGEON,
		GameCommand.Type.REPAIR_TELEPORT,
		GameCommand.Type.ADVANCE_BIOME
	].has(command.type)

func _advance_time_for_turn() -> void:
	if time_state == null or player == null or player.resources == null:
		return
	time_state.tick(TIME_SECONDS_PER_TURN, player.resources)

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
	var activation_result := _activate_run_state(fresh_run)
	if not activation_result.ok:
		return activation_result
	return {
		"ok": true,
		"state": "fresh_run",
		"invalidated_lifecycle_epoch": int(confirmed.invalidated_lifecycle_epoch),
		"lifecycle_epoch": fresh_run.lifecycle_epoch
	}

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
	if not _has_pointer_move_target or player == null:
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	var delta: Vector2 = _pointer_move_target_world - player.global_position
	if delta.length() <= POINTER_MOVE_STOP_DISTANCE_PIXELS:
		if not _pointer_move_route.is_empty():
			_pointer_move_route.pop_front()
			if not _pointer_move_route.is_empty():
				_pointer_move_target_world = world_position_for_cell_center(Vector2i(_pointer_move_route[0]))
				return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
		_complete_pending_pointer_interaction()
		return GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
	var direction := Vector2i(
		0 if absf(delta.x) <= POINTER_MOVE_STOP_DISTANCE_PIXELS else int(signf(delta.x)),
		0 if absf(delta.y) <= POINTER_MOVE_STOP_DISTANCE_PIXELS else int(signf(delta.y))
	)
	if direction == Vector2i.ZERO:
		_clear_pointer_movement()
	return GameCommand.new(GameCommand.Type.MOVE, direction)

func _clear_pointer_movement() -> void:
	_has_pointer_move_target = false
	_pointer_move_target_world = Vector2.ZERO
	_pointer_move_route.clear()
	_pending_pointer_interaction_target_id = ""
	_pending_pointer_interaction_cell = Vector2i.ZERO

func _complete_pending_pointer_interaction() -> void:
	var target_id := _pending_pointer_interaction_target_id
	var target_cell := _pending_pointer_interaction_cell
	_clear_pointer_movement()
	if target_id.is_empty() or (not _is_available_acquisition_target(target_id) and not _is_landmark_target(target_id)):
		_dungeon_debug("이동 완료 후 대상 무효: target=%s" % target_id)
		return
	if player == null or not _player_can_interact_with_target(world_cell_from_world_position(player.global_position), target_id, target_cell):
		_dungeon_debug("이동 완료했지만 상호작용 거리 불충족: player_cell=%s target=%s target_cell=%s" % [world_cell_from_world_position(player.global_position) if player != null else "nil", target_id, target_cell])
		return
	_dungeon_debug("입구 도착, 상호작용 실행: target=%s cell=%s" % [target_id, target_cell])
	submit_interaction_at_world_cell(target_cell)

func _cells_are_adjacent(first: Vector2i, second: Vector2i) -> bool:
	var offset := second - first
	return absi(offset.x) + absi(offset.y) <= 1

func _nearest_walkable_adjacent_cell(target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	var best_cell := target_cell
	var best_distance := 1 << 30
	for offset in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		var candidate: Vector2i = target_cell + offset
		if world_data == null or not world_data.contains(candidate) or not world_data.is_walkable(candidate):
			continue
		if _is_landmark_footprint_cell(candidate):
			continue
		var distance := absi(candidate.x - player_cell.x) + absi(candidate.y - player_cell.y)
		if distance < best_distance:
			best_cell = candidate
			best_distance = distance
	return best_cell

func _nearest_walkable_adjacent_cell_for_target(target_id: String, target_cell: Vector2i, player_cell: Vector2i) -> Vector2i:
	var target_cells := _target_footprint_cells(target_id, target_cell)
	var target_cell_lookup := {}
	for footprint_cell in target_cells:
		target_cell_lookup[_cell_key(footprint_cell)] = true
	var best_cell := target_cell
	var best_distance := 1 << 30
	for footprint_cell in target_cells:
		for offset in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var candidate: Vector2i = footprint_cell + offset
			if target_cell_lookup.has(_cell_key(candidate)):
				continue
			if world_data == null or not world_data.contains(candidate) or not world_data.is_walkable(candidate):
				continue
			var distance := absi(candidate.x - player_cell.x) + absi(candidate.y - player_cell.y)
			if distance < best_distance:
				best_cell = candidate
				best_distance = distance
	return best_cell

func _runtime_tile_size() -> float:
	if world_data != null:
		return float(world_data.tile_size)
	var renderer_input: Dictionary = generated_world.get("renderer_input", {})
	return float(int(renderer_input.get("tile_size", 32)))

func _runtime_world_origin() -> Vector2:
	if world_visuals != null:
		return world_visuals.global_position
	var renderer_input: Dictionary = generated_world.get("renderer_input", {})
	if not renderer_input.is_empty():
		return _centered_world_origin(renderer_input)
	return Vector2.ZERO

func _interaction_candidate_cells(origin_cell: Vector2i, direction := Vector2i.ZERO) -> Array:
	var forward: Vector2i = _resolved_grid_direction(direction)
	var candidates := [origin_cell]
	if forward != Vector2i.ZERO:
		candidates.append(origin_cell + forward)
	for adjacent in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		var cell: Vector2i = origin_cell + adjacent
		if not candidates.has(cell):
			candidates.append(cell)
	return candidates

func _pointer_candidate_cells(clicked_cell: Vector2i) -> Array:
	var cells := [clicked_cell]
	for y in range(-2, 3):
		for x in range(-2, 3):
			if x == 0 and y == 0 or abs(x) + abs(y) > 2:
				continue
			cells.append(clicked_cell + Vector2i(x, y))
	return cells

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
	if world_data == null or not world_data.contains(cell):
		return ""
	var dungeon_reservation_id := _dungeon_reservation_target_id_for_cell(cell)
	if not dungeon_reservation_id.is_empty():
		return dungeon_reservation_id
	for target_id_value in world_data.get_interactables(cell):
		var target_id := String(target_id_value)
		if _is_landmark_target(target_id):
			return target_id
		if _is_available_acquisition_target(target_id):
			return target_id
	var landmark_id := _landmark_target_id_for_cell(cell)
	if not landmark_id.is_empty():
		return landmark_id
	return ""

func _player_can_interact_with_target(player_cell: Vector2i, target_id: String, target_cell: Vector2i) -> bool:
	for footprint_cell in _target_footprint_cells(target_id, target_cell):
		if _cells_are_adjacent(player_cell, footprint_cell):
			return true
	return false

func _target_footprint_cells(target_id: String, fallback_cell: Vector2i) -> Array:
	if _is_large_house_dungeon_target(target_id):
		var compound_cells := []
		for owner_id in LARGE_HOUSE_DUNGEON_OWNER_IDS:
			compound_cells.append_array(_reservation_cells_for_owner(owner_id))
		if not compound_cells.is_empty():
			return _unique_cells(compound_cells)
	return [fallback_cell]

func _reservation_cells_for_owner(owner_id: String) -> Array:
	if world_data == null:
		return []
	var reservation: Dictionary = world_data.get_reservation(owner_id)
	var cells := []
	for cell_value in reservation.get("cells", []):
		cells.append(_vector_from_dictionary(cell_value))
	return cells

func _unique_cells(cells: Array) -> Array:
	var seen := {}
	var unique := []
	for cell in cells:
		var key := _cell_key(cell)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(cell)
	return unique

func _dungeon_interaction_target_near_cell(origin_cell: Vector2i) -> Dictionary:
	for cell in _interaction_candidate_cells(origin_cell):
		var target_id := _dungeon_interaction_target_id_for_cell(cell)
		if not target_id.is_empty():
			return {"target_id": target_id, "cell": cell}
	for y in range(origin_cell.y - 2, origin_cell.y + 3):
		for x in range(origin_cell.x - 2, origin_cell.x + 3):
			if abs(x - origin_cell.x) + abs(y - origin_cell.y) > 2:
				continue
			var cell := Vector2i(x, y)
			var target_id := _dungeon_interaction_target_id_for_cell(cell)
			if not target_id.is_empty():
				return {"target_id": target_id, "cell": cell}
	return {}

func _dungeon_interaction_target_id_for_cell(cell: Vector2i) -> String:
	if world_data == null or not world_data.contains(cell):
		return ""
	var dungeon_reservation_id := _dungeon_reservation_target_id_for_cell(cell)
	if not dungeon_reservation_id.is_empty():
		return dungeon_reservation_id
	for target_id_value in world_data.get_interactables(cell):
		var target_id := String(target_id_value)
		if _is_core_dungeon_target(target_id):
			return target_id
	var landmark_id := _landmark_target_id_for_cell(cell)
	if _is_core_dungeon_target(landmark_id):
		return landmark_id
	return ""

func _dungeon_reservation_target_id_for_cell(cell: Vector2i) -> String:
	if world_data == null or not world_data.contains(cell):
		return ""
	for owner_id_value in world_data.get_occupants(cell):
		var owner_id := String(owner_id_value)
		if _is_core_dungeon_target(owner_id):
			return owner_id
	return ""

func _landmark_target_id_for_cell(cell: Vector2i) -> String:
	if world_data == null:
		return ""
	for landmark in world_data.get_required_landmarks():
		var origin := _vector_from_dictionary(landmark.get("position", {}))
		var size := Vector2i(2, 2) if String(landmark.get("kind", landmark.get("type", ""))) == WorldData.LANDMARK_CORE_DUNGEON else Vector2i.ONE
		if cell.x >= origin.x and cell.y >= origin.y and cell.x < origin.x + size.x and cell.y < origin.y + size.y:
			return String(landmark.get("id", ""))
	return ""

func _is_landmark_footprint_cell(cell: Vector2i) -> bool:
	return not _landmark_target_id_for_cell(cell).is_empty()

func _is_landmark_target(target_id: String) -> bool:
	return _is_core_dungeon_target(target_id) \
		or target_id.begins_with("%s_" % WorldData.LANDMARK_TELEPORT_ZONE)

func _is_core_dungeon_target(target_id: String) -> bool:
	return target_id.begins_with("%s_" % WorldData.LANDMARK_CORE_DUNGEON) \
		or _is_large_house_dungeon_target(target_id)

func _is_large_house_dungeon_target(target_id: String) -> bool:
	return target_id == WorldGenerator.LARGE_HOUSE_ID \
		or target_id.begins_with("large_house_fence_")

func _handle_landmark_interaction(target_id: String) -> bool:
	if _is_core_dungeon_target(target_id):
		_dungeon_debug("던전 랜드마크 상호작용: %s" % target_id)
		return _handle_complete_dungeon_command(GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"entry_only": true}))
	if target_id.begins_with("%s_" % WorldData.LANDMARK_TELEPORT_ZONE):
		var biome_id := String(run_state.current_biome_id) if run_state != null else ""
		var progression := _ensure_biome_progression_state()
		if not progression.ok:
			return false
		var teleport_state: String = biome_progression_state.teleport_state_for(biome_id)
		var command_type := GameCommand.Type.ADVANCE_BIOME if teleport_state == BiomeProgressionState.TELEPORT_REPAIRED else GameCommand.Type.REPAIR_TELEPORT
		return _handle_biome_progression_command(GameCommand.new(command_type, Vector2i.ZERO, -1, {"biome_id": biome_id}))
	return false

func _is_available_acquisition_target(target_id: String) -> bool:
	if acquisition_service == null or target_id.is_empty():
		return false
	var gatherable: Dictionary = acquisition_service.gatherable_for(target_id)
	if not gatherable.is_empty():
		return not bool(gatherable.get("depleted", false))
	return not acquisition_service.pickup_for(target_id).is_empty()

func _handle_tea_command(command: GameCommand) -> bool:
	if tea_service == null:
		return false
	var start_result: Dictionary = tea_service.start_drinking(maxi(command.slot, 0))
	if not start_result.ok:
		return false
	var resources = player.resources if player != null else null
	var completed: Dictionary = tea_service.complete_drinking(start_result.action, resources)
	_sync_tea_runtime_state()
	if completed.ok:
		save_current_run()
	return bool(completed.ok)

func _handle_consumable_command(command: GameCommand) -> bool:
	if consumable_service == null or inventory == null or player == null or player.resources == null:
		return false
	var item_id := _consumable_item_id_for_command(command)
	if item_id.is_empty():
		return false
	var start: Dictionary = consumable_service.start_use(item_id, inventory, {"command_slot": command.slot})
	if not start.ok:
		return false
	var completed: Dictionary = consumable_service.complete_use(inventory, player.resources)
	_sync_inventory_runtime_state()
	_sync_consumable_runtime_state()
	if game_hud != null:
		game_hud.show_command_feedback(
			"소모품 사용: %s" % item_id
			if completed.ok
			else "소모품 실패: %s" % String(completed.get("reason", "unknown"))
		)
	if not completed.ok:
		return false
	save_current_run()
	_configure_game_hud()
	return true

func _consumable_item_id_for_command(command: GameCommand) -> String:
	var requested := String(command.payload.get("item_id", ""))
	if not requested.is_empty():
		return requested if consumable_service.has_definition(requested) and inventory.get_total_quantity(requested) > 0 else ""
	var slots = inventory.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		return ""
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var item_id := String(slot.get("item_id", ""))
		if not item_id.is_empty() and int(slot.get("quantity", 0)) > 0 and consumable_service.has_definition(item_id):
			return item_id
	return ""

func _handle_sleep_command() -> bool:
	if time_state == null or player == null or player.resources == null:
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
	_sync_inventory_runtime_state()
	_sync_tea_runtime_state()
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
		_sync_inventory_runtime_state()
		save_current_run()
		_configure_game_hud()
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

	var crafting_context := _crafting_context()
	var availability: Dictionary = crafting_service.can_craft(recipe_id, inventory, crafting_context)
	if not availability.ok:
		return availability
	_pending_facility_placement = {
		"recipe_id": recipe_id,
		"facility_item_id": result_item_id,
		"metadata": _player_facility_metadata(result_item_id)
	}
	_clear_pointer_movement()
	return {
		"ok": true,
		"placement_pending": true,
		"recipe_id": recipe_id,
		"result_item_id": result_item_id
	}

func has_pending_facility_placement() -> bool:
	return not _pending_facility_placement.is_empty()

func _place_pending_facility_at(origin: Vector2i) -> Dictionary:
	if not has_pending_facility_placement():
		return {"ok": false, "reason": "no_pending_facility_placement"}
	var player_cell := _player_world_cell()
	var distance := absi(origin.x - player_cell.x) + absi(origin.y - player_cell.y)
	if distance == 0 or distance > FacilityPlacementService.DEFAULT_PLACEMENT_SEARCH_RADIUS:
		return _facility_placement_failed("placement_out_of_range")

	var recipe_id := String(_pending_facility_placement.get("recipe_id", ""))
	var facility_item_id := String(_pending_facility_placement.get("facility_item_id", ""))
	var crafting_context := _crafting_context()
	var availability: Dictionary = crafting_service.can_craft(recipe_id, inventory, crafting_context)
	if not availability.ok:
		return _facility_placement_failed(String(availability.get("reason", "craft_unavailable")))
	var placement_context := {
		"metadata": _pending_facility_placement.get("metadata", {}).duplicate(true)
	}
	var placed: Dictionary = facility_placement_service.place_facility(
		facility_item_id,
		world_data,
		origin,
		placement_context
	)
	if not placed.ok:
		return _facility_placement_failed(String(placed.get("reason", "invalid_placement")))

	var crafted: Dictionary = crafting_service.craft(recipe_id, inventory, crafting_context, {"store_result": false})
	if not crafted.ok:
		world_data.release_footprint(String(placed.owner_id))
		return _facility_placement_failed(String(crafted.get("reason", "craft_failed")))
	_record_placed_facility(placed)
	_sync_runtime_world_render()
	crafted["installed"] = true
	crafted["placement"] = placed.duplicate(true)
	_pending_facility_placement.clear()
	_sync_inventory_runtime_state()
	save_current_run()
	_configure_game_hud()
	if game_hud != null:
		game_hud.show_command_feedback("제작·설치 완료: %s" % facility_item_id)
	_advance_time_for_turn()
	_play_feedback_beep()
	_queue_enemy_turn_after_player_action()
	return crafted

func _facility_placement_failed(reason: String) -> Dictionary:
	if game_hud != null:
		game_hud.show_command_feedback("설치 불가: %s" % reason)
	return {"ok": false, "reason": reason, "placement_pending": true}

func _cancel_pending_facility_placement() -> bool:
	if not has_pending_facility_placement():
		return false
	_pending_facility_placement.clear()
	if game_hud != null:
		game_hud.show_command_feedback("시설 설치를 취소했습니다.")
	return true

func _player_facility_metadata(facility_item_id: String) -> Dictionary:
	var definition: Dictionary = facility_placement_service.facility_for(facility_item_id)
	var source_id := ""
	for key in ["source_id", "sprite_asset_id", "asset_id", "icon_asset_id", "icon"]:
		source_id = String(definition.get(key, ""))
		if not source_id.is_empty():
			break
	if source_id.is_empty():
		source_id = "asset_assets_sprites_objects_crafting_workbench_32x32_png"
	return {
		"facility_item_id": facility_item_id,
		"installed_by_player": true,
		"source_id": source_id
	}

func _record_placed_facility(placed: Dictionary) -> void:
	if run_state == null:
		run_state = RunState.new()
	var reservation: Dictionary = placed.get("reservation", {})
	var record := {
		"biome_id": String(generated_world.get("biome_id", run_state.current_biome_id)),
		"facility_item_id": String(placed.get("facility_item_id", "")),
		"owner_id": String(placed.get("owner_id", "")),
		"origin": placed.get("origin", {}).duplicate(true),
		"metadata": reservation.get("metadata", {}).duplicate(true)
	}
	for existing in run_state.placed_facilities:
		if String(existing.get("owner_id", "")) == String(record.owner_id):
			return
	run_state.placed_facilities.append(record)

func _handle_inventory_command(command: GameCommand) -> bool:
	if inventory_command_runtime == null:
		return false
	var result: Dictionary = inventory_command_runtime.handle_command(command)
	if game_hud != null:
		game_hud.show_command_feedback(
			"인벤토리 갱신"
			if result.ok
			else "인벤토리 명령 실패: %s" % String(result.get("reason", "unknown"))
		)
	if not result.ok:
		return false
	_sync_inventory_runtime_state()
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
	if bool(command.payload.get("entry_only", false)):
		save_current_run()
		_configure_game_hud()
		_dungeon_debug("입구 상호작용은 입장만 처리: in_dungeon=%s" % _in_dungeon_map)
		return true
	if String(previous_projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED] \
			and not _dungeon_completion_objective_met(command.payload):
		_dungeon_debug("입장만 처리(완료 조건 미충족)")
		save_current_run()
		_configure_game_hud()
		if game_hud != null:
			game_hud.show_command_feedback("던전 입장")
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
	var result: Dictionary = biome_progression_state.apply_command(command)
	if not result.ok:
		return false
	var world_result := _configure_world_for_current_run()
	if not world_result.ok:
		return false
	save_current_run()
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

func _sync_inventory_runtime_state() -> void:
	if run_state == null:
		run_state = RunState.new()
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if equipment != null:
		run_state.equipment = equipment.to_snapshot()

func _sync_tea_runtime_state() -> void:
	if run_state == null:
		run_state = RunState.new()
	if tea_service != null:
		run_state.tea = tea_service.to_snapshot()

func tea_brewing_read_model() -> Dictionary:
	if tea_brewing_command_runtime == null:
		return {"ok": false, "reason": "missing_tea_brewing_command_runtime", "error": "Tea brewing command runtime is not configured."}
	var model: Dictionary = tea_brewing_command_runtime.read_model()
	model["ok"] = true
	return model

func _sync_consumable_runtime_state() -> void:
	if run_state == null:
		run_state = RunState.new()
	if consumable_service != null:
		var snapshot: Dictionary = consumable_service.to_snapshot()
		var active_action: Dictionary = snapshot.get("active_action", {})
		run_state.consumables = snapshot if not active_action.is_empty() else {}

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

func _crafting_context() -> Dictionary:
	return {
		"available_facility_item_ids": _available_facility_item_ids(),
		"unlocked_biome_ids": _unlocked_biome_ids(),
		"current_biome_id": String(generated_world.get("biome_id", ""))
	}

func _available_facility_item_ids() -> Array:
	var ids: Array = []
	if crafting_service == null or player == null:
		return ids
	var player_cell := _player_world_cell()
	if facility_placement_service != null:
		for facility_item_id in facility_placement_service.facility_item_ids_near(world_data, player_cell):
			if not ids.has(String(facility_item_id)):
				ids.append(String(facility_item_id))
	var name_to_id = crafting_service.get("item_name_to_id")
	if typeof(name_to_id) != TYPE_DICTIONARY:
		return ids
	for node in generated_world.get("facility_nodes", []):
		var position := _vector_from_dictionary(node.get("position", {}))
		if absi(player_cell.x - position.x) + absi(player_cell.y - position.y) > FacilityPlacementService.DEFAULT_USE_DISTANCE:
			continue
		var term := String(node.get("facility_term", ""))
		if name_to_id.has(term) and not ids.has(String(name_to_id[term])):
			ids.append(String(name_to_id[term]))
	ids.sort()
	return ids

func _restore_placed_facilities_for_current_biome() -> Dictionary:
	if facility_placement_service == null or world_data == null or run_state == null:
		return {"ok": true, "restored": 0}
	var current_biome_id := String(generated_world.get("biome_id", run_state.current_biome_id))
	var restored := 0
	for record_value in run_state.placed_facilities:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		if String(record.get("biome_id", "")) != current_biome_id:
			continue
		var owner_id := String(record.get("owner_id", ""))
		if not owner_id.is_empty() and not world_data.get_reservation(owner_id).is_empty():
			continue
		var facility_item_id := String(record.get("facility_item_id", ""))
		var origin := _vector_from_dictionary(record.get("origin", {}))
		var placement: Dictionary = facility_placement_service.place_facility(facility_item_id, world_data, origin, {
			"owner_id": owner_id,
			"metadata": record.get("metadata", {}).duplicate(true)
		})
		if not placement.ok:
			return {
				"ok": false,
				"reason": "placed_facility_restore_failed",
				"facility_item_id": facility_item_id,
				"owner_id": owner_id,
				"cause": placement
			}
		restored += 1
	return {"ok": true, "restored": restored}

func _unlocked_biome_ids() -> Array:
	var ids: Array = []
	if run_state != null:
		for biome_id in run_state.crafting_unlocks:
			var id := String(biome_id)
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
	return ids

func _on_tea_drink_completed(result: Dictionary) -> void:
	if equipment == null:
		return
	var accounting_result: Dictionary = equipment.record_tea_ware_use_completion(result, inventory)
	if not accounting_result.ok:
		push_error(accounting_result.error)
	if memory_tea_cutscene_runtime != null:
		var memory_result: Dictionary = memory_tea_cutscene_runtime.start_from_drink_completion(result, run_state)
		if not memory_result.ok:
			push_error(memory_result.error)
		elif memory_result.started and run_state != null:
			run_state.memory_tea_cutscene = memory_tea_cutscene_runtime.to_snapshot()

func complete_memory_tea_cutscene() -> Dictionary:
	if memory_tea_cutscene_runtime == null:
		return {"ok": false, "reason": "missing_memory_cutscene_runtime", "error": "Memory tea cutscene runtime is not configured."}
	var result: Dictionary = memory_tea_cutscene_runtime.complete_current(run_state)
	if result.ok and run_state != null:
		run_state.memory_tea_cutscene = memory_tea_cutscene_runtime.to_snapshot()
	return result

func skip_memory_tea_cutscene() -> Dictionary:
	if memory_tea_cutscene_runtime == null:
		return {"ok": false, "reason": "missing_memory_cutscene_runtime", "error": "Memory tea cutscene runtime is not configured."}
	var result: Dictionary = memory_tea_cutscene_runtime.skip_current(run_state)
	if result.ok and run_state != null:
		run_state.memory_tea_cutscene = memory_tea_cutscene_runtime.to_snapshot()
	return result

func _render_generated_world(world: Dictionary) -> void:
	_hide_prototype_visuals()
	var renderer_input: Dictionary = world.get("renderer_input", {})
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
		player.global_position = world_position_for_cell_center(_entry_spawn_cell(world))
		player.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())
	_configure_runtime_camera()
	if combat_dummy != null and combat_dummy.has_method("configure_grid_navigation"):
		combat_dummy.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())

func _sync_runtime_world_render() -> void:
	if world_visuals == null or world_data == null or world_render_result.is_empty():
		return
	var world_snapshot: Dictionary = world_data.to_dictionary()
	var renderer_input: Dictionary = WorldRendererProjection.new().project(world_snapshot)
	var previous_renderer_input: Dictionary = generated_world.get("renderer_input", {})
	if previous_renderer_input.has("required_landmarks"):
		renderer_input["required_landmarks"] = previous_renderer_input.required_landmarks.duplicate(true)
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

func _configure_runtime_camera() -> void:
	if player == null or world_data == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var origin := _runtime_world_origin()
	var tile_size := _runtime_tile_size()
	camera.limit_left = int(floor(origin.x))
	camera.limit_top = int(floor(origin.y))
	camera.limit_right = int(ceil(origin.x + float(world_data.width) * tile_size))
	camera.limit_bottom = int(ceil(origin.y + float(world_data.height) * tile_size))
	camera.enabled = true

func _entry_spawn_cell(world: Dictionary) -> Vector2i:
	var landmarks: Array = world.get("required_landmarks", [])
	if landmarks.is_empty():
		landmarks = world.get("landmarks", [])
	if landmarks.is_empty():
		var renderer_input: Dictionary = world.get("renderer_input", {})
		landmarks = renderer_input.get("required_landmarks", [])
	for landmark in landmarks:
		if String(landmark.get("kind", landmark.get("type", ""))) != WorldData.LANDMARK_ENTRY:
			continue
		return _vector_from_dictionary(landmark.get("position", {}))
	return Vector2i.ZERO

func _on_hud_mobile_command_issued(command) -> void:
	submit_mobile_action_command(command)

func _configure_game_hud() -> void:
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
		"crafting_context": _tea_brewing_context(),
		"time_state": time_state,
		"world_origin": _runtime_world_origin()
	})
	_maybe_show_first_run_prologue()

func first_run_prologue_read_model(meta_state = null) -> Dictionary:
	if narrative_runtime == null:
		return {"ok": false, "reason": "missing_narrative_runtime", "error": "Narrative runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	var meta = meta_state if meta_state != null else _current_meta_state_snapshot()
	if not _force_first_run_prologue and int(meta.get("run_count", 0)) != 0:
		return {"ok": false, "reason": "not_first_run", "error": "First-run prologue only opens before any completed run."}
	return narrative_runtime.read_model_for_event(FIRST_RUN_PROLOGUE_EVENT_ID, run_state, meta)

func _maybe_show_first_run_prologue() -> Dictionary:
	if game_hud == null or narrative_runtime == null:
		return {"ok": false, "reason": "missing_presentation", "error": "Prologue presentation is not ready."}
	var model_result := first_run_prologue_read_model()
	if not model_result.ok:
		if game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
		return model_result
	_active_narrative_event_id = String(model_result.read_model.event_id)
	_active_narrative_node_id = String(model_result.read_model.node_id)
	game_hud.show_narrative_dialogue(model_result.read_model)
	return {"ok": true, "read_model": model_result.read_model}

func _handle_narrative_option_command(command: GameCommand) -> bool:
	if narrative_runtime == null or run_state == null:
		return false
	var event_id := String(command.payload.get("event_id", _active_narrative_event_id))
	var node_id := String(command.payload.get("node_id", _active_narrative_node_id))
	var option_id := String(command.payload.get("option_id", ""))
	if event_id.is_empty() or node_id.is_empty() or option_id.is_empty():
		return false
	var result: Dictionary = narrative_runtime.select_option(event_id, node_id, option_id, run_state, _current_meta_state_snapshot())
	if not result.ok:
		return false
	_apply_narrative_result_commands(result.get("commands", []))
	if bool(result.get("complete", false)):
		_active_narrative_event_id = ""
		_active_narrative_node_id = ""
		if game_hud != null and game_hud.has_method("hide_narrative_dialogue"):
			game_hud.hide_narrative_dialogue()
	else:
		var read_model: Dictionary = result.get("read_model", {})
		_active_narrative_event_id = String(read_model.get("event_id", event_id))
		_active_narrative_node_id = String(read_model.get("node_id", ""))
		if game_hud != null and game_hud.has_method("show_narrative_dialogue"):
			game_hud.show_narrative_dialogue(read_model)
	save_current_run()
	return true

func _apply_narrative_result_commands(commands: Array) -> void:
	if run_state == null:
		run_state = RunState.new()
	for command in commands:
		if not command is GameCommand or command.type != GameCommand.Type.NARRATIVE_RESULT:
			continue
		var result: Dictionary = command.payload.get("result", {})
		if String(result.get("type", "")) == NarrativeRuntime.RESULT_SET_RUN_FLAG:
			var flag_id := String(result.get("id", ""))
			if not flag_id.is_empty() and not run_state.narrative_flags.has(flag_id):
				run_state.narrative_flags.append(flag_id)

func _configure_audio_feedback() -> void:
	if _feedback_player != null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = FEEDBACK_BEEP_MIX_RATE
	stream.buffer_length = 0.08
	_feedback_player = AudioStreamPlayer.new()
	_feedback_player.name = "FeedbackAudio"
	_feedback_player.stream = stream
	add_child(_feedback_player)
	_feedback_player.play()
	_feedback_playback = _feedback_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _play_feedback_beep() -> void:
	feedback_beep_count += 1
	if _feedback_playback == null:
		return
	var frame_count := mini(int(FEEDBACK_BEEP_MIX_RATE * FEEDBACK_BEEP_SECONDS), _feedback_playback.get_frames_available())
	for index in range(frame_count):
		var t := float(index) / FEEDBACK_BEEP_MIX_RATE
		var envelope := 1.0 - (float(index) / maxf(float(frame_count), 1.0))
		var sample := sin(TAU * FEEDBACK_BEEP_FREQUENCY * t) * 0.12 * envelope
		_feedback_playback.push_frame(Vector2(sample, sample))

func _centered_world_origin(renderer_input: Dictionary) -> Vector2:
	var bounds: Dictionary = renderer_input.get("bounds", {})
	var tile_size := int(renderer_input.get("tile_size", 32))
	return Vector2(
		-float(int(bounds.get("width", 0)) * tile_size) * 0.5,
		-float(int(bounds.get("height", 0)) * tile_size) * 0.5
	)

func _owner_sprite_sources(world: Dictionary) -> Dictionary:
	var sources := {
		WorldData.LANDMARK_ENTRY: "small_signpost",
		WorldData.LANDMARK_CORE_DUNGEON: "asset_assets_sprites_objects_structures_warehouse_2x2_64x64_png",
		WorldData.LANDMARK_TELEPORT_ZONE: "stone_pagoda_lantern",
		"wood": "log_resource",
		"stone": "small_rock_resource",
		"clay": "mud_patch_resource"
	}
	for node in world.get("resource_nodes", []):
		var owner_id := String(node.get("id", ""))
		var resource_id := String(node.get("resource_id", ""))
		var source_id := String(node.get("source_id", ""))
		if owner_id != "" and not source_id.is_empty():
			sources[owner_id] = source_id
		elif owner_id != "" and sources.has(resource_id):
			sources[owner_id] = sources[resource_id]
	for node in world.get("facility_nodes", []):
		var owner_id := String(node.get("id", ""))
		var source_id := String(node.get("source_id", ""))
		if owner_id != "" and source_id != "":
			sources[owner_id] = source_id
	# Generated path fences (and other procedural entities) keep their sprite
	# reference in WorldData reservations rather than the high-level node lists.
	var snapshot: Dictionary = world.get("world_data", world)
	for reservation in snapshot.get("reservations", []):
		var reservation_id := String(reservation.get("owner_id", ""))
		var metadata: Dictionary = reservation.get("metadata", {})
		var reservation_source := String(metadata.get("source_id", ""))
		if not reservation_id.is_empty() and not reservation_source.is_empty():
			sources[reservation_id] = reservation_source
	return sources

func _hide_prototype_visuals() -> void:
	for child in get_children():
		if child is Polygon2D:
			child.visible = false
		if child is StaticBody2D:
			child.collision_layer = 0
			child.collision_mask = 0
			for descendant in child.find_children("*", "CollisionShape2D", true, false):
				(descendant as CollisionShape2D).disabled = true
