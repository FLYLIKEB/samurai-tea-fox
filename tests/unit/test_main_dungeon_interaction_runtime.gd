extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const RUN_PATH := "user://dungeon_input_regression_run.save.json"
const META_PATH := "user://dungeon_input_regression_meta.save.json"

class DropSource:
	extends Node2D
	signal drop_requested(event: Dictionary)

class MovementPlayer:
	extends Node2D
	var combat_config := {"hit_invulnerability_seconds": 0.1}

func run(asserts) -> void:
	_cleanup()
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "dungeon input catalog loads")
	_assert_visible_house_accepts_e_before_attack(asserts, catalog)
	_assert_visible_house_click_queues_entry(asserts, catalog)
	_assert_dungeon_combatants_do_not_cross_world_boundary(asserts, catalog)
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
	var dungeon_snapshot: Dictionary = runtime.main.world_data.to_dictionary()
	var dungeon_terrain: Dictionary = dungeon_snapshot.cells[0].layers[WorldData.LAYER_TERRAIN]
	asserts.equal(dungeon_terrain.render_id, Main.DUNGEON_TILESET_SOURCE_ID, "entered dungeon uses the dedicated mossy dojo tileset")
	asserts.equal(dungeon_terrain.atlas_coords, {"x": 0, "y": 1}, "dungeon boundary selects an explicit wall tile")
	asserts.equal(runtime.main._dungeon_resources.size(), 44, "dungeon has the expanded resource-node set")
	asserts.true_value(not runtime.main.acquisition_service.gatherable_for("dungeon_iron_ore_0").is_empty(), "dungeon ore is registered as gatherable")
	var ore_cell := Vector2i(4, 3)
	runtime.main.player.global_position = runtime.main.world_position_for_cell_center(ore_cell + Vector2i.LEFT)
	runtime.main.time_state = null
	var ore_before: int = runtime.main.inventory.get_total_quantity("iron_ore")
	asserts.true_value(runtime.main._try_dungeon_interaction_from_input(), "dungeon ore E interaction succeeds")
	asserts.equal(runtime.main.inventory.get_total_quantity("iron_ore"), ore_before + 1, "dungeon ore is added to inventory")
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

func _assert_dungeon_combatants_do_not_cross_world_boundary(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	var player := MovementPlayer.new()
	var overworld_dummy := CombatDummy.new()
	main.catalog = catalog
	main.run_state = RunState.new()
	main.run_state.seed = Main.DEFAULT_RUN_SEED
	main.world_visuals = Node2D.new()
	main.player = player
	main.combat_dummy = overworld_dummy
	main.save_store = SaveStore.new(RUN_PATH, META_PATH)
	var services: Dictionary = main._configure_run_services(catalog)
	asserts.true_value(services.ok, "dungeon lifecycle fixture configures services")
	if not services.ok:
		_free_combat_runtime(main, player, overworld_dummy)
		return
	var combat: Dictionary = overworld_dummy.configure_combat(catalog, player, player.combat_config)
	asserts.true_value(combat.ok, "overworld monster configures before dungeon entry")
	var world: Dictionary = main._configure_world_for_current_run()
	asserts.true_value(world.ok, "dungeon lifecycle fixture configures overworld")
	if not combat.ok or not world.ok:
		_free_combat_runtime(main, player, overworld_dummy)
		return
	overworld_dummy.global_position = main.world_position_for_cell_center(Vector2i(3, 1))
	var original_combat_id: String = overworld_dummy.get_combat_id()
	var original_hp: int = overworld_dummy.current_hp()
	var original_monster_id: String = overworld_dummy.monster_id
	var original_sprite_id: String = overworld_dummy.sprite_asset_id
	var entered: Dictionary = main._ensure_playable_dungeon_runtime()
	if entered.ok:
		entered = main._ensure_current_dungeon_entered()
	asserts.true_value(entered.ok, "dungeon lifecycle fixture enters dungeon")
	asserts.true_value(main._in_dungeon_map, "dungeon lifecycle fixture switches maps")
	asserts.true_value(main.combat_dummy != overworld_dummy, "dungeon boss is a separate node from the overworld monster")
	asserts.false_value(overworld_dummy.visible, "overworld monster is suspended while inside the dungeon")
	var dungeon_enemies: Array = main._dungeon_enemy_nodes.duplicate()
	asserts.equal(dungeon_enemies.size(), 4, "dungeon owns four independent combatant nodes")
	main._enemy_turn_queued = true
	main._return_from_dungeon_map()
	asserts.false_value(main._in_dungeon_map, "direct dungeon exit returns to overworld mode")
	asserts.true_value(main.combat_dummy == overworld_dummy, "dungeon exit restores the original overworld monster")
	asserts.equal(overworld_dummy.get_combat_id(), original_combat_id, "overworld monster combat identity survives dungeon visit")
	asserts.equal(overworld_dummy.current_hp(), original_hp, "dungeon fight cannot replace overworld monster HP")
	asserts.equal(overworld_dummy.monster_id, original_monster_id, "dungeon fight cannot replace overworld monster definition")
	asserts.equal(overworld_dummy.sprite_asset_id, original_sprite_id, "dungeon fight cannot replace overworld monster sprite")
	asserts.true_value(overworld_dummy.visible, "overworld monster visibility is restored after exit")
	asserts.false_value(main._enemy_turn_queued, "enemy turn queued in dungeon is cancelled on exit")
	asserts.equal(main._dungeon_enemy_nodes, [], "dungeon exit clears active dungeon combatants")
	for dungeon_enemy in dungeon_enemies:
		if is_instance_valid(dungeon_enemy):
			asserts.false_value(dungeon_enemy.visible, "dungeon enemy is hidden before deferred deletion")
			asserts.equal(dungeon_enemy.target, null, "dungeon enemy loses its player target before deferred deletion")
	var restored_position: Vector2 = overworld_dummy.global_position
	main._run_enemy_turn_after_player_action()
	asserts.equal(overworld_dummy.global_position, restored_position, "cancelled dungeon turn cannot move a monster after map exit")
	_free_combat_runtime(main, player, overworld_dummy)

func _free_combat_runtime(main: Main, player: Node2D, overworld_dummy: CombatDummy) -> void:
	if main.world_visuals != null:
		main.world_visuals.free()
	if is_instance_valid(player):
		player.free()
	if is_instance_valid(overworld_dummy):
		overworld_dummy.free()
	main.free()

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
