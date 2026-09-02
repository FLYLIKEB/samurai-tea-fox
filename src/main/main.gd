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
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const TeaBrewingCommandRuntime = preload("res://src/tea/tea_brewing_command_runtime.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const MetaCodexCommandRuntime = preload("res://src/meta/meta_codex_command_runtime.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")
const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const CraftingService = preload("res://src/crafting/crafting_service.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")

const DEFAULT_RUN_SEED := 11037
const FRESH_RUN_SEED := 0
const POINTER_MOVE_STOP_DISTANCE_PIXELS := 4.0
const FEEDBACK_BEEP_MIX_RATE := 22050.0
const FEEDBACK_BEEP_SECONDS := 0.045
const FEEDBACK_BEEP_FREQUENCY := 880.0

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
var consumable_service
var core_tea_ware_collection
var final_room_state_builder
var sen_rikyu_phase_one_runtime
var sen_rikyu_phase_two_runtime
var sen_rikyu_phase_three_runtime
var memory_tea_cutscene_runtime
var ending_route_runtime
var acquisition_service
var dungeon_runtime
var run_lifecycle_service
var save_store = SaveStore.new()
var run_state: RunState
var world_data
var generated_world: Dictionary = {}
var world_render_result: Dictionary = {}
var _desktop_adapter := DesktopCommandAdapter.new()
var _movement_selector := MovementCommandSelector.new()
var _has_pointer_move_target := false
var _pointer_move_target_world := Vector2.ZERO
var _feedback_player: AudioStreamPlayer
var _feedback_playback: AudioStreamGeneratorPlayback
var feedback_beep_count := 0

func _ready() -> void:
	_configure_audio_feedback()
	catalog = DataCatalog.new()
	var result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not result.ok:
		push_error(result.error)
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

func _configure_combat_lifecycle() -> Dictionary:
	var player_combat_result: Dictionary = player.configure_combat(catalog)
	if not player_combat_result.ok:
		return player_combat_result
	_connect_player_feedback_signals()
	var lifecycle_result: Dictionary = RunLifecycleService.from_catalog(catalog)
	if not lifecycle_result.ok:
		return lifecycle_result
	run_lifecycle_service = lifecycle_result.run_lifecycle_service
	player.resources.hp_depleted.connect(_on_player_hp_depleted)
	var dummy_combat_result: Dictionary = combat_dummy.configure_combat(catalog, player, player.combat_config)
	if not dummy_combat_result.ok:
		return dummy_combat_result
	return {"ok": true}

func _connect_player_feedback_signals() -> void:
	for signal_name in [&"attack_started", &"ability_cast", &"dodge_started", &"grid_step_started"]:
		if player.has_signal(signal_name) and not player.is_connected(signal_name, Callable(self, "_on_player_activity_feedback")):
			player.connect(signal_name, Callable(self, "_on_player_activity_feedback"))

func _on_player_activity_feedback(_a = null, _b = null, _c = null) -> void:
	_play_feedback_beep()

func _configure_world_for_current_run() -> Dictionary:
	var generator := WorldGenerator.new()
	var progression_result := BiomeProgressionState.from_catalog(catalog, run_state)
	if not progression_result.ok:
		return progression_result
	var projection: Dictionary = progression_result.progression_state.to_projection()
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
	_record_current_map_discovery()
	_configure_game_hud()
	return {"ok": true}

func _physics_process(_delta: float) -> void:
	_record_current_map_discovery()
	var desktop_command = _desktop_adapter.poll_movement_command()
	player.submit_command(movement_command_for_current_inputs(desktop_command))
	if Input.is_action_just_pressed("attack"):
		submit_desktop_action_command("attack", desktop_command.direction)
	if Input.is_action_just_pressed("dodge"):
		submit_desktop_action_command("dodge", desktop_command.direction)
	if Input.is_action_just_pressed("drink_tea"):
		submit_desktop_action_command("drink_tea")
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
	if Input.is_action_just_pressed("interact"):
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
	var clicked_cell := world_cell_from_world_position(world_position)
	for cell in _pointer_candidate_cells(clicked_cell):
		if submit_interaction_at_world_cell(cell):
			return true
	return false

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
	return false

func submit_interaction_at_world_cell(cell: Vector2i) -> bool:
	var target_id := _interaction_target_id_for_cell(cell)
	if target_id.is_empty():
		return false
	return submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": target_id}))

func submit_action_command(command) -> bool:
	if not command is GameCommand:
		return false
	match command.type:
		GameCommand.Type.INTERACT:
			var target_id := String(command.payload.get("target_id", ""))
			if target_id.is_empty():
				return submit_player_interaction(command.direction)
			var accepted: bool = acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.DRINK_TEA:
			var accepted: bool = _handle_tea_command(command)
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
			var accepted: bool = game_hud != null and game_hud.show_crafting_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.OPEN_FACILITIES:
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
			var accepted: bool = game_hud != null and game_hud.hide_menu()
			if accepted:
				_play_feedback_beep()
			return accepted
		GameCommand.Type.CRAFT_RECIPE:
			var accepted: bool = _handle_craft_recipe_command(command)
			if accepted:
				_play_feedback_beep()
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
					_play_feedback_beep()
				return accepted
			return player != null and player.submit_command(command)

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
	run_state = state
	if inventory != null:
		run_state.inventory = inventory.to_snapshot()
	if equipment != null:
		run_state.equipment = equipment.to_snapshot()
	if tea_service != null:
		run_state.tea = tea_service.to_snapshot()
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
	return run_state.to_dictionary()

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
	var crafting_result: Dictionary = CraftingService.from_catalog(loaded_catalog)
	if not crafting_result.ok:
		return crafting_result
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
	if run_state != null and not run_state.tea.is_empty():
		var tea_load_result: Dictionary = tea_service.load_snapshot(run_state.tea)
		if not tea_load_result.ok:
			return tea_load_result
	crafting_service = crafting_result.crafting_service
	consumable_service = consumable_result.consumable_service if consumable_result.ok else null
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
	acquisition_service = AcquisitionService.new()
	var definitions := _confirmed_generated_resource_definitions(generated_world.get("resource_nodes", []))
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
	if not saved_acquisitions.is_empty():
		var loaded: Dictionary = acquisition_service.load_snapshot(saved_acquisitions)
		if not loaded.ok:
			return loaded
	acquisition_service.changed.connect(_on_acquisition_changed)
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

func _on_combat_drop_requested(event: Dictionary) -> void:
	if acquisition_service == null:
		return
	var normalized := event.duplicate(true)
	if not normalized.has("position") and combat_dummy != null:
		normalized.position = {
			"x": int(round(combat_dummy.global_position.x / 32.0)),
			"y": int(round(combat_dummy.global_position.y / 32.0))
		}
	var result: Dictionary = acquisition_service.process_drop_request(normalized)
	if not result.ok:
		push_error(result.error)

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
		_clear_pointer_movement()
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
	return [
		clicked_cell,
		clicked_cell + Vector2i.RIGHT,
		clicked_cell + Vector2i.LEFT,
		clicked_cell + Vector2i.DOWN,
		clicked_cell + Vector2i.UP,
		clicked_cell + Vector2i(1, 1),
		clicked_cell + Vector2i(1, -1),
		clicked_cell + Vector2i(-1, 1),
		clicked_cell + Vector2i(-1, -1)
	]

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
	for target_id_value in world_data.get_interactables(cell):
		var target_id := String(target_id_value)
		if _is_available_acquisition_target(target_id):
			return target_id
	return ""

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
	return bool(completed.ok)

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
	var result: Dictionary = crafting_service.craft(recipe_id, inventory, _crafting_context())
	if game_hud != null:
		game_hud.show_command_feedback(
			"제작 완료: %s" % result.get("result_item_id", recipe_id)
			if result.ok
			else "제작 불가: %s" % String(result.get("reason", "unknown"))
		)
	if result.ok:
		_sync_inventory_runtime_state()
	return bool(result.ok)

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
		"unlocked_biome_ids": _unlocked_biome_ids()
	}

func _available_facility_item_ids() -> Array:
	var ids: Array = []
	if crafting_service == null:
		return ids
	var name_to_id = crafting_service.get("item_name_to_id")
	if typeof(name_to_id) != TYPE_DICTIONARY:
		return ids
	for node in generated_world.get("facility_nodes", []):
		var term := String(node.get("facility_term", ""))
		if name_to_id.has(term) and not ids.has(String(name_to_id[term])):
			ids.append(String(name_to_id[term]))
	return ids

func _unlocked_biome_ids() -> Array:
	var ids := []
	var biome_id := String(generated_world.get("biome_id", ""))
	if not biome_id.is_empty():
		ids.append(biome_id)
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
		player.configure_grid_navigation(world_data, _runtime_world_origin(), _runtime_tile_size())

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
		"run_state": run_state,
		"tea_service": tea_service,
		"tea_brewing_command_runtime": tea_brewing_command_runtime,
		"meta_codex_command_runtime": meta_codex_command_runtime,
		"crafting_service": crafting_service,
		"crafting_context": _tea_brewing_context()
	})

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
		WorldData.LANDMARK_ENTRY: "res://assets/sprites/objects/structures/small_signpost_32x32.png",
		WorldData.LANDMARK_CORE_DUNGEON: "res://assets/sprites/objects/structures/dungeon_entry_small_32x32.png",
		WorldData.LANDMARK_TELEPORT_ZONE: "res://assets/sprites/objects/shrine-props/stone_pagoda_lantern_32x32.png",
		"wood": "res://assets/sprites/objects/nature/log_32x32.png",
		"stone": "res://assets/sprites/objects/natural-props/small_rock_32x32.png",
		"clay": "res://assets/sprites/objects/natural-props/mud_patch_32x32.png"
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
	return sources

func _hide_prototype_visuals() -> void:
	for child in get_children():
		if child is Polygon2D:
			child.visible = false
