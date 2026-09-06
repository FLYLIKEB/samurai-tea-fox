extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const RUN_PATH := "user://dungeon_input_regression_run.save.json"
const META_PATH := "user://dungeon_input_regression_meta.save.json"

class DropSource:
	extends Node2D
	signal drop_requested(event: Dictionary)
	var monster_id := "fixture_drop_source"
	var automatic_attacks := false
	var collision_layer := 0
	var collision_mask := 0

	func current_hp() -> int:
		return 1

class MovementPlayer:
	extends Node2D
	var combat_config := {"hit_invulnerability_seconds": 0.1}
	var movement_state := PlayerMovementState.new()
	var submitted_commands := []

	func submit_command(command) -> bool:
		submitted_commands.append(command)
		return true

class GridProbePlayer:
	extends MovementPlayer
	var configured_world_data = null
	var configured_origin := Vector2.ZERO
	var configured_tile_size := 0.0
	var grid_step_active := false

	func configure_grid_navigation(next_world_data = null, next_origin := Vector2.ZERO, next_tile_size := -1.0) -> void:
		var binding_changed: bool = configured_world_data != next_world_data or configured_origin != next_origin or not is_equal_approx(configured_tile_size, next_tile_size)
		configured_world_data = next_world_data
		configured_origin = next_origin
		configured_tile_size = next_tile_size
		if binding_changed:
			grid_step_active = false

	func is_grid_step_active() -> bool:
		return grid_step_active

	func submit_command(command) -> bool:
		if not command is GameCommand:
			return false
		if command.type != GameCommand.Type.MOVE:
			return true
		var from_cell: Vector2i = _cell_for(global_position)
		var to_cell: Vector2i = from_cell + command.direction
		if configured_world_data != null and configured_world_data.has_method("is_walkable") and not configured_world_data.is_walkable(to_cell):
			grid_step_active = false
			return false
		grid_step_active = command.direction != Vector2i.ZERO
		return true

	func _cell_for(world_position: Vector2) -> Vector2i:
		var tile_size := maxf(configured_tile_size, 1.0)
		var local_position := world_position - configured_origin
		return Vector2i(int(floor(local_position.x / tile_size)), int(floor(local_position.y / tile_size)))

func run(asserts) -> void:
	_cleanup()
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "dungeon input catalog loads")
	_assert_visible_house_accepts_e_before_attack(asserts, catalog)
	_assert_visible_house_click_queues_entry(asserts, catalog)
	_assert_dungeon_combatants_do_not_cross_world_boundary(asserts, catalog)
	_assert_dungeon_entry_rebinds_map_and_movement_context(asserts, catalog)
	_assert_boss_precombat_dialogue_blocks_combat_until_completion(asserts, catalog)
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
	asserts.false_value(dungeon_terrain.has("projection_source_id"), "entered dungeon data stays semantic-only")
	asserts.false_value(dungeon_terrain.has("render_id"), "entered dungeon data does not store renderer ids")
	asserts.equal(dungeon_terrain.atlas_coords, {"x": 0, "y": 1}, "dungeon boundary selects an explicit wall tile")
	var projected_terrain: Dictionary = runtime.main.generated_world.renderer_input.layers[1].cells[0]
	asserts.equal(projected_terrain.source_id, Main.DUNGEON_TILESET_SOURCE_ID, "entered dungeon projection uses the dedicated mossy dojo tileset")
	asserts.equal(projected_terrain.atlas_coords, {"x": 0, "y": 1}, "entered dungeon projection preserves atlas presentation data")
	asserts.equal(runtime.main._dungeon_resources.size(), 18, "dungeon has the generated resource-node set")
	asserts.true_value(not runtime.main.acquisition_service.gatherable_for("dungeon_iron_ore_0").is_empty(), "dungeon ore is registered as gatherable")
	var ore_cell := Vector2i(4, 3)
	runtime.main.player.global_position = runtime.main.world_position_for_cell_center(ore_cell + Vector2i.LEFT)
	runtime.main.time_state = null
	var ore_before: int = runtime.main.inventory.get_total_quantity("iron_ore")
	var missing_tool_result: Dictionary = runtime.main.acquisition_service.gather("dungeon_iron_ore_0")
	asserts.false_value(missing_tool_result.ok, "dungeon ore rejects mining without stone pickaxe")
	asserts.equal(String(missing_tool_result.get("reason", "")), "missing_required_tool", "dungeon ore reports missing pickaxe")
	asserts.equal(runtime.main.inventory.get_total_quantity("iron_ore"), ore_before, "failed dungeon mining grants no ore")
	asserts.true_value(runtime.main.inventory.add_item("stone_pickaxe", 1).ok, "dungeon fixture stocks stone pickaxe")
	asserts.true_value(runtime.main._try_dungeon_interaction_from_input(), "dungeon ore E interaction succeeds")
	asserts.equal(runtime.main.inventory.get_total_quantity("iron_ore"), ore_before + 1, "dungeon ore is added to inventory")
	asserts.equal(runtime.main.inventory.get_total_quantity("stone_pickaxe"), 1, "dungeon ore mining does not consume pickaxe")
	var clear_result: Dictionary = runtime.main.dungeon_runtime.complete_dungeon({"objective_complete": true, "resolution_type": "combat", "choice_key": "test_clear", "run_flag": "test_clear", "reward_item_ids": [], "progression_unlock_ids": [String(runtime.main.run_state.current_biome_id)]})
	asserts.true_value(clear_result.ok, "fixture can mark the active dungeon complete before exit")
	runtime.main.player.global_position = runtime.main.world_position_for_cell_center(Vector2i(1, 1))
	asserts.true_value(runtime.main._try_dungeon_interaction_from_input(), "E on the completed dungeon entry returns to the overworld")
	asserts.false_value(runtime.main._in_dungeon_map, "completed dungeon E exit leaves dungeon mode")
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
	main.generated_world["monster_spawn_pool"] = {"entries": [
		{"id": "pool_wild_dog", "monster_id": "wild_dog"},
		{"id": "pool_road_bandit", "monster_id": "road_bandit"}
	]}
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
	var first_regular_enemy := dungeon_enemies[0] as CombatDummy
	var second_regular_enemy := dungeon_enemies[1] as CombatDummy
	asserts.true_value(first_regular_enemy != null, "dungeon first regular enemy is a combat dummy")
	asserts.true_value(second_regular_enemy != null, "dungeon second regular enemy is a combat dummy")
	if first_regular_enemy != null:
		asserts.equal(first_regular_enemy.monster_id, "wild_dog", "dungeon first regular enemy comes from the generated spawn pool")
		asserts.equal(first_regular_enemy.sprite_asset_id, "monster_wild_dog_front_idle", "dungeon first regular enemy sprite follows its monster content image")
	if second_regular_enemy != null:
		asserts.equal(second_regular_enemy.monster_id, "road_bandit", "dungeon second regular enemy comes from the generated spawn pool")
		asserts.equal(second_regular_enemy.sprite_asset_id, "monster_road_bandit_front_idle", "dungeon second regular enemy sprite follows its monster content image")
	if first_regular_enemy != null:
		asserts.true_value("dungeon_enemy_0" in main.world_data.get_occupants(Vector2i(7, 2)), "dungeon enemy reservation remains on its world cell")
		asserts.equal(main._world_interaction_coordinator.dungeon_enemy_cell_near(main, Vector2i(6, 2)), Vector2i(7, 2), "adjacent dungeon enemy cell can be resolved from world data")
		main.player.global_position = main.world_position_for_cell_center(Vector2i(6, 2))
		asserts.true_value(main._try_dungeon_interaction_from_input(), "E attacks an adjacent dungeon enemy")
		asserts.equal(player.submitted_commands.back().type, GameCommand.Type.ATTACK, "adjacent dungeon enemy routes through the shared attack command")
		asserts.equal(player.submitted_commands.back().direction, Vector2i.RIGHT, "adjacent dungeon enemy attack faces the target")
		player.submitted_commands.clear()
		main._dungeon_resources.append({"id": "dungeon_iron_ore_pointer_fixture", "position": {"x": 7, "y": 3}})
		asserts.true_value(main.submit_pointer_interaction(first_regular_enemy.global_position), "pointer attacks a dungeon enemy even when ore is nearby")
		asserts.equal(player.submitted_commands.back().type, GameCommand.Type.ATTACK, "pointer enemy selection wins over nearby ore acquisition")
		first_regular_enemy.global_position = main.world_position_for_cell_center(Vector2i(5, 2))
		main._sync_dungeon_enemy_reservation("dungeon_enemy_0", Vector2i(5, 2), true)
		main.player.global_position = main.world_position_for_cell_center(Vector2i(3, 2))
		player.movement_state.face(Vector2i.RIGHT)
		asserts.true_value(main.inventory.add_item("stone_pickaxe", 1).ok, "blocked mining fixture stocks a stone pickaxe")
		var stone_before: int = main.inventory.get_total_quantity("stone")
		var side_ore_before: Dictionary = main.acquisition_service.gatherable_for("dungeon_iron_ore_3").duplicate(true)
		asserts.true_value(main._try_dungeon_interaction_from_input(), "E mines the blocking stone before a farther enemy")
		asserts.equal(main.inventory.get_total_quantity("stone"), stone_before + 1, "blocking dungeon stone is added to inventory")
		asserts.equal(main.acquisition_service.gatherable_for("dungeon_iron_ore_3").get("depleted", false), side_ore_before.get("depleted", false), "side ore is not selected ahead of the blocking stone")
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

func _assert_dungeon_entry_rebinds_map_and_movement_context(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	var player := GridProbePlayer.new()
	var overworld_dummy := CombatDummy.new()
	main.catalog = catalog
	main.run_state = RunState.new()
	main.run_state.seed = Main.DEFAULT_RUN_SEED
	main.world_visuals = Node2D.new()
	main.player = player
	main.combat_dummy = overworld_dummy
	main.save_store = SaveStore.new(RUN_PATH, META_PATH)
	asserts.true_value(main._configure_run_services(catalog).ok, "dungeon context fixture configures services")
	asserts.true_value(overworld_dummy.configure_combat(catalog, player, {"hit_invulnerability_seconds": 0.1}).ok, "dungeon context fixture configures dummy combat")
	asserts.true_value(main._configure_world_for_current_run().ok, "dungeon context fixture configures overworld")
	player.global_position = main.world_position_for_cell_center(Vector2i(1, 1))
	player.configure_grid_navigation(main.world_data, main._runtime_world_origin(), main._runtime_tile_size())
	player.grid_step_active = true
	asserts.true_value(player.is_grid_step_active(), "fixture has an active overworld grid step")
	main._has_pointer_move_target = true
	main._pointer_move_route = [Vector2i(2, 1), Vector2i(3, 1)]
	main._pointer_move_target_world = main.world_position_for_cell_center(Vector2i(2, 1))
	var entered := main._ensure_playable_dungeon_runtime()
	if entered.ok:
		entered = main._ensure_current_dungeon_entered()
	asserts.true_value(entered.ok, "dungeon context fixture enters dungeon")
	asserts.true_value(main._in_dungeon_map, "dungeon context fixture switches to dungeon")
	var map_model: Dictionary = main.map_read_model({"reveal_all": true})
	asserts.equal(map_model.bounds, {"width": 12, "height": 9}, "Main map read model uses dungeon bounds after entry")
	asserts.equal(_marker_type(map_model.markers, "dungeon_entry"), "landmark", "Main map read model uses dungeon entry marker")
	asserts.true_value(player.configured_world_data == main.world_data, "player grid navigation is bound to dungeon WorldData")
	asserts.false_value(main._has_pointer_move_target, "dungeon entry clears stale overworld pointer movement")
	asserts.false_value(player.is_grid_step_active(), "dungeon entry cancels stale overworld grid movement")
	asserts.false_value(player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.UP)), "dungeon navigation blocks the dungeon wall above entry")
	asserts.true_value(main.submit_pointer_movement(main.world_position_for_cell_center(Vector2i(1, 1))), "pointer movement accepts a dungeon walkable cell")
	asserts.false_value(main.submit_pointer_movement(main.world_position_for_cell_center(Vector2i(0, 0))), "pointer movement rejects a dungeon wall cell")
	var saved_dungeon_cell := _first_free_dungeon_cell(main)
	asserts.true_value(saved_dungeon_cell != Vector2i(1, 1), "dungeon context fixture finds a non-entry walkable save cell")
	main.player.global_position = main.world_position_for_cell_center(saved_dungeon_cell)
	asserts.true_value(main.save_current_run().ok, "active dungeon context saves through explicit test store")
	var loaded: Dictionary = main.save_store.load_run()
	asserts.true_value(loaded.ok, "active dungeon context reloads from explicit test store")
	if loaded.ok:
		asserts.equal(main._vector_from_dictionary(loaded.run_state.dungeon_runtime_state.get("player_cell", {})), saved_dungeon_cell, "active dungeon save stores the dungeon player cell")
		var resumed := Main.new()
		var resumed_player := GridProbePlayer.new()
		var resumed_dummy := CombatDummy.new()
		resumed.catalog = catalog
		resumed.run_state = loaded.run_state
		resumed.world_visuals = Node2D.new()
		resumed.player = resumed_player
		resumed.combat_dummy = resumed_dummy
		resumed.save_store = SaveStore.new(RUN_PATH, META_PATH)
		asserts.true_value(resumed._configure_run_services(catalog).ok, "resumed dungeon context services configure")
		asserts.true_value(resumed_dummy.configure_combat(catalog, resumed_player, {"hit_invulnerability_seconds": 0.1}).ok, "resumed dungeon context dummy configures")
		asserts.true_value(resumed._configure_world_for_current_run().ok, "resumed active dungeon restores world")
		asserts.true_value(resumed._in_dungeon_map, "resumed active dungeon stays in dungeon mode")
		var resumed_model: Dictionary = resumed.map_read_model({"reveal_all": true})
		asserts.equal(resumed_model.bounds, {"width": 12, "height": 9}, "resumed active dungeon map uses dungeon bounds")
		asserts.equal(resumed._vector_from_dictionary(resumed_model.player.position), saved_dungeon_cell, "resumed active dungeon map uses saved dungeon player cell")
		asserts.true_value(resumed_player.configured_world_data == resumed.world_data, "resumed player navigation is bound to dungeon WorldData")
		_free_combat_runtime(resumed, resumed_player, resumed_dummy)
	main._return_from_dungeon_map()
	asserts.false_value(main._in_dungeon_map, "dungeon context fixture returns to overworld")
	var returned_model: Dictionary = main.map_read_model({"reveal_all": true})
	asserts.true_value(int(returned_model.bounds.width) != 12 or int(returned_model.bounds.height) != 9, "return restores non-dungeon map bounds")
	asserts.true_value(player.configured_world_data == main.world_data, "player navigation rebinds to restored overworld WorldData")
	asserts.false_value(main._has_pointer_move_target, "dungeon return leaves no stale pointer movement")
	asserts.false_value(player.is_grid_step_active(), "dungeon return leaves no stale dungeon grid movement")
	_free_combat_runtime(main, player, overworld_dummy)

func _assert_boss_precombat_dialogue_blocks_combat_until_completion(asserts, catalog: DataCatalog) -> void:
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
	asserts.true_value(services.ok, "boss precombat fixture configures services")
	var combat: Dictionary = overworld_dummy.configure_combat(catalog, player, player.combat_config)
	asserts.true_value(combat.ok, "boss precombat fixture configures base combatant")
	if not services.ok or not combat.ok:
		_free_combat_runtime(main, player, overworld_dummy)
		return
	asserts.true_value(main._ensure_playable_dungeon_runtime().ok, "boss precombat fixture configures dungeon runtime")
	asserts.true_value(main._ensure_current_dungeon_entered().ok, "boss precombat fixture enters dungeon")
	asserts.equal(main.dungeon_runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_PENDING, "dungeon entry stores pre-boss dialogue pending state")
	asserts.equal(main.dungeon_runtime.to_projection().pre_boss_dialogue_event_id, "story_b01_03", "common-region boss uses the exported confrontation event")
	asserts.equal(main._combat_targets().size(), 3, "locked boss is excluded from combat targets while regular enemies remain")
	var boss: Node2D = main._dungeon_boss_node()
	asserts.true_value(boss != null, "boss node is present in dungeon map")
	if boss == null:
		_free_combat_runtime(main, player, overworld_dummy)
		return
	main.player.global_position = boss.global_position
	asserts.false_value(main._pointer_enemy_clicked(boss.global_position), "boss dialogue cannot start while regular dungeon enemies remain")
	for enemy in main._dungeon_enemy_nodes:
		if enemy.name != Main.DUNGEON_BOSS_OWNER_ID:
			enemy.visible = false
			main.world_data.release_footprint(String(enemy.name))
	asserts.equal(main._combat_targets().size(), 0, "all regular enemies defeated still does not expose boss before dialogue")
	asserts.true_value(main._pointer_enemy_clicked(boss.global_position), "boss click starts pre-combat dialogue after regular combat")
	asserts.equal(main.dungeon_runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE, "boss dialogue has its own persisted active state")
	asserts.equal(main._active_narrative_event_id, "story_b01_03", "main stores active pre-boss dialogue event for input")
	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)), "attack command is blocked during pre-boss dialogue")
	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.DODGE, Vector2i.RIGHT)), "dodge command is blocked during pre-boss dialogue")
	asserts.equal(boss.current_hp(), boss.combatant.hp_max, "blocked dialogue attack cannot damage the boss")
	asserts.true_value(main.submit_action_command(GameCommand.new(
		GameCommand.Type.NARRATIVE_SELECT_OPTION,
		Vector2i.ZERO,
		-1,
		{"event_id": "story_b01_03", "node_id": "dlg_b01_003", "option_id": "complete_dlg_b01_003"}
	)), "dialogue completion command is accepted")
	asserts.equal(main.dungeon_runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_COMBAT_ACTIVE, "dialogue completion unlocks boss combat")
	asserts.equal(main._combat_targets().size(), 1, "boss is the only combat target after pre-combat dialogue")
	main._on_dungeon_enemy_defeated({}, boss, Main.DUNGEON_BOSS_OWNER_ID)
	asserts.equal(main.dungeon_runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_COMPLETED, "boss defeat completes dungeon runtime")
	asserts.equal(main.run_state.completed_runtime_dungeon_ids, ["dungeon_4"], "boss defeat records runtime dungeon completion exactly once")
	main._on_dungeon_enemy_defeated({}, boss, Main.DUNGEON_BOSS_OWNER_ID)
	asserts.equal(main.run_state.completed_runtime_dungeon_ids, ["dungeon_4"], "duplicate boss defeat cannot duplicate dungeon completion")
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

func _first_free_dungeon_cell(main: Main) -> Vector2i:
	for y in range(1, main.world_data.height - 1):
		for x in range(1, main.world_data.width - 1):
			var cell := Vector2i(x, y)
			if cell != Vector2i(1, 1) and main.world_data.is_walkable(cell):
				return cell
	return Vector2i(1, 1)

func _marker_type(markers: Array, id: String) -> String:
	for marker in markers:
		if String(marker.get("id", "")) == id:
			return String(marker.get("marker_type", ""))
	return ""

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
