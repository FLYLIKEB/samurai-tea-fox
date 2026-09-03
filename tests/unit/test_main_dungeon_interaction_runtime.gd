extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const RUN_PATH := "user://dungeon_input_regression_run.save.json"
const META_PATH := "user://dungeon_input_regression_meta.save.json"

class DropSource:
	extends Node2D
	signal drop_requested(event: Dictionary)

class MovementPlayer:
	extends Node2D

func run(asserts) -> void:
	_cleanup()
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "dungeon input catalog loads")
	_assert_visible_house_accepts_e_before_attack(asserts, catalog)
	_assert_visible_house_click_queues_entry(asserts, catalog)
	_cleanup()

func _assert_visible_house_accepts_e_before_attack(asserts, catalog: DataCatalog) -> void:
	var runtime := _configured_runtime(catalog)
	asserts.true_value(runtime.result.ok, "E dungeon fixture configures")
	if not runtime.result.ok:
		_free_runtime(runtime)
		return
	var house_origin := _large_house_origin(runtime.main)
	var approach_cell := _nearest_walkable_adjacent_cell_to_compound(runtime.main, house_origin)
	asserts.true_value(approach_cell != Vector2i(-1, -1), "visible dungeon house has a walkable adjacent E cell")
	runtime.main.player.global_position = runtime.main.world_position_for_cell_center(approach_cell)
	asserts.true_value(runtime.main._try_dungeon_interaction_from_input(), "E attack path enters from the visible dungeon house approach cell")
	asserts.true_value(runtime.main._in_dungeon_map, "E switches to the dungeon map instead of attacking")
	_free_runtime(runtime)

func _assert_visible_house_click_queues_entry(asserts, catalog: DataCatalog) -> void:
	var runtime := _configured_runtime(catalog)
	asserts.true_value(runtime.result.ok, "click dungeon fixture configures")
	if not runtime.result.ok:
		_free_runtime(runtime)
		return
	var house_origin := _large_house_origin(runtime.main)
	var approach_cell := _nearest_walkable_adjacent_cell_to_compound(runtime.main, house_origin)
	asserts.true_value(approach_cell != Vector2i(-1, -1), "visible dungeon house has a walkable adjacent click cell")
	runtime.main.player.global_position = runtime.main.world_position_for_cell_center(approach_cell + Vector2i.LEFT * 3)
	asserts.true_value(runtime.main.submit_pointer_interaction(runtime.main.world_position_for_cell_center(house_origin)), "clicking the visible dungeon house queues dungeon entry movement")
	while runtime.main._has_pointer_move_target:
		runtime.main.player.global_position = runtime.main._pointer_move_target_world
		runtime.main.movement_command_for_current_inputs(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	asserts.true_value(runtime.main._in_dungeon_map, "arriving from a visible dungeon house click switches to the dungeon map")
	_free_runtime(runtime)

func _configured_runtime(catalog: DataCatalog) -> Dictionary:
	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = RunState.new()
	runtime.run_state.seed = Main.DEFAULT_RUN_SEED
	runtime.world_visuals = Node2D.new()
	runtime.player = MovementPlayer.new()
	runtime.combat_dummy = DropSource.new()
	runtime.save_store = SaveStore.new(RUN_PATH, META_PATH)
	var services: Dictionary = runtime._configure_run_services(catalog)
	if not services.ok:
		return {"main": runtime, "result": services}
	var world_result: Dictionary = runtime._configure_world_for_current_run()
	return {"main": runtime, "result": world_result}

func _large_house_origin(main: Main) -> Vector2i:
	return main._vector_from_dictionary(main.generated_world.get("large_house", {}).get("position", {}))

func _nearest_walkable_adjacent_cell_to_compound(main: Main, house_origin: Vector2i) -> Vector2i:
	var cells: Array = main._target_footprint_cells(WorldGenerator.LARGE_HOUSE_ID, house_origin)
	var cell_lookup := {}
	for cell in cells:
		cell_lookup[main._cell_key(cell)] = true
	for cell in cells:
		for offset in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var candidate: Vector2i = cell + offset
			if cell_lookup.has(main._cell_key(candidate)):
				continue
			if main.world_data.contains(candidate) and main.world_data.is_walkable(candidate):
				return candidate
	return Vector2i(-1, -1)

func _free_runtime(runtime: Dictionary) -> void:
	var main: Main = runtime.main
	if main.player != null:
		main.player.free()
	if main.combat_dummy != null:
		main.combat_dummy.free()
	if main.world_visuals != null:
		main.world_visuals.free()
	main.free()

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", META_PATH, META_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
