extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")

class FakePlayer:
	extends Node2D
	var resources := PlayerResources.new(100, 100, 100, 30)

	func submit_command(_command) -> bool:
		return false

class FakeHud:
	extends Node

	func show_command_feedback(_message: String) -> void:
		pass

	func show_inventory_menu() -> bool:
		return true

	func configure(_player, _world, _render_result, _context := {}) -> void:
		pass

	func show_narrative_dialogue(_read_model: Dictionary) -> bool:
		return true

class EnemyProbe:
	extends Node2D
	var monster_id := "enemy_probe"
	var automatic_attacks := true
	var collision_layer := 2
	var collision_mask := 1
	var turns := 0

	func current_hp() -> int:
		return 1

	func take_turn(_player) -> void:
		turns += 1

func run(asserts) -> void:
	_assert_quickslot_consumable_completes_on_tick(asserts)
	_assert_inventory_route_uses_same_consumable_lifecycle(asserts)
	_assert_active_consumable_action_saves_and_resumes(asserts)
	_assert_failed_duplicate_and_hit_paths_do_not_spend_turns(asserts)

func _assert_quickslot_consumable_completes_on_tick(asserts) -> void:
	var main := _configured_main("quickslot")
	var enemy := EnemyProbe.new()
	main.combat_dummy = enemy
	main.player.resources.apply_damage(40)
	asserts.true_value(main.inventory.add_item("bandage", 1).ok, "quickslot fixture stocks one bandage")

	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "quickslot consumable starts")
	asserts.false_value(main.consumable_service.to_snapshot().active_action.is_empty(), "quickslot start records active action")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "quickslot start does not consume")
	asserts.equal(main.player.resources.hp, 60, "quickslot start does not heal")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "quickslot start does not advance time")
	asserts.false_value(main._enemy_turn_queued, "quickslot start does not queue enemy turn")
	asserts.false_value(_saved_run(main).consumables.active_action.is_empty(), "quickslot start saves active action")

	var partial: Dictionary = main.tick_consumable_runtime(0.5)
	asserts.true_value(partial.ok, "quickslot partial tick succeeds")
	asserts.false_value(bool(partial.get("completed", false)), "partial tick does not complete")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "partial tick preserves quantity")
	asserts.equal(main.player.resources.hp, 60, "partial tick does not heal")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "partial tick does not advance time")
	asserts.equal(main.consumable_service.to_snapshot().active_action.elapsed_seconds, 0.5, "partial tick keeps elapsed use time in runtime")
	asserts.equal(_saved_run(main).consumables.active_action.elapsed_seconds, 0.0, "partial tick does not write every frame without an explicit save")
	asserts.true_value(main.save_current_run().ok, "explicit save during active use succeeds")
	asserts.equal(_saved_run(main).consumables.active_action.elapsed_seconds, 0.5, "explicit save captures current elapsed use time")

	var complete: Dictionary = main.tick_consumable_runtime(0.5)
	asserts.true_value(complete.ok, "quickslot completion tick succeeds")
	asserts.true_value(bool(complete.get("completed", false)), "quickslot completion reports completed use")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 0, "completion consumes exactly one bandage")
	asserts.equal(main.player.resources.hp, 85, "completion applies one clamped heal")
	asserts.equal(main.consumable_service.to_snapshot().active_action, {}, "completion clears active action")
	asserts.equal(main.time_state.phase_elapsed_seconds, 1.0, "completion advances time exactly once")
	asserts.true_value(main._enemy_turn_queued, "completion queues enemy turn")
	main._run_enemy_turn_after_player_action()
	main._run_enemy_turn_after_player_action()
	asserts.equal(enemy.turns, 1, "completion runs one enemy turn")
	_cleanup_main(main)

func _assert_inventory_route_uses_same_consumable_lifecycle(asserts) -> void:
	var main := _configured_main("inventory")
	main.player.resources.apply_damage(50)
	asserts.true_value(main.inventory.add_item("bandage", 1).ok, "inventory fixture stocks one bandage")
	var slot_index := _slot_for_item(main, "bandage")
	asserts.true_value(slot_index >= 0, "inventory route finds bandage slot")

	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, slot_index, {"slot_index": slot_index})), "inventory use starts consumable lifecycle")
	var active: Dictionary = main.consumable_service.to_snapshot().active_action
	asserts.equal(active.context.source, "inventory", "inventory route records serializable source")
	asserts.equal(active.context.inventory_slot_index, slot_index, "inventory route records source slot")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "inventory start does not consume")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "inventory start does not advance time")

	asserts.true_value(main.tick_consumable_runtime(1.0).completed, "inventory route completes through tick")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 0, "inventory route completion consumes exactly one")
	asserts.equal(main.player.resources.hp, 75, "inventory route completion heals once")
	asserts.equal(main.time_state.phase_elapsed_seconds, 1.0, "inventory route completion advances one turn")
	_cleanup_main(main)

func _assert_active_consumable_action_saves_and_resumes(asserts) -> void:
	var paths := _save_paths("resume")
	_cleanup_paths(paths)
	var main := _configured_main("resume", paths, false)
	main.player.resources.apply_damage(40)
	asserts.true_value(main.inventory.add_item("bandage", 1).ok, "resume fixture stocks one bandage")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "resume fixture starts consumable")
	asserts.true_value(main.tick_consumable_runtime(0.25).ok, "resume fixture partially ticks active action")
	asserts.true_value(main.save_current_run().ok, "explicit active-use save records resume progress")
	var loaded: Dictionary = main.save_store.load_run()
	asserts.true_value(loaded.ok, "explicit SaveStore path reloads active consumable run")
	asserts.equal(loaded.state.consumables.active_action.elapsed_seconds, 0.25, "run save preserves active consumable elapsed time")

	var restored := _configured_main("resume-restored", paths, false)
	restored.player.resources.apply_damage(40)
	asserts.true_value(restored.restore_run_state(loaded.run_state).ok, "Main restores saved active consumable runtime")
	asserts.equal(restored.consumable_service.to_snapshot().active_action.elapsed_seconds, 0.25, "restored Main owns active consumable action")
	asserts.true_value(restored.tick_consumable_runtime(0.75).completed, "restored active action completes once")
	asserts.equal(restored.inventory.get_total_quantity("bandage"), 0, "restored completion consumes saved inventory item")
	asserts.equal(restored.time_state.phase_elapsed_seconds, 1.0, "restored completion charges one turn")
	_cleanup_main(main, false)
	_cleanup_main(restored, false)
	_cleanup_paths(paths)

func _assert_failed_duplicate_and_hit_paths_do_not_spend_turns(asserts) -> void:
	var main := _configured_main("failure")
	main.player.resources.apply_damage(30)
	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "missing_bandage"})), "missing consumable command is rejected")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "missing consumable does not advance time")
	asserts.false_value(main._enemy_turn_queued, "missing consumable does not queue enemy turn")

	asserts.true_value(main.inventory.add_item("bandage", 1).ok, "failure fixture stocks one bandage")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "first consumable start succeeds")
	asserts.false_value(main.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "duplicate consumable start is rejected")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "duplicate start preserves quantity")
	asserts.equal(main.player.resources.hp, 70, "duplicate start does not heal")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "duplicate start does not advance time")
	asserts.false_value(main._enemy_turn_queued, "duplicate start does not queue enemy turn")

	main._on_player_damage_feedback({"source_id": "test_hit"}, 5)
	asserts.equal(main.consumable_service.to_snapshot().active_action, {}, "hit interrupts active consumable action")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "hit interruption preserves quantity")
	asserts.equal(main.player.resources.hp, 70, "hit interruption does not heal")
	asserts.equal(main.time_state.phase_elapsed_seconds, 0.0, "hit interruption does not advance time")
	asserts.false_value(bool(main.tick_consumable_runtime(1.0).get("completed", false)), "interrupted use cannot complete later")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 1, "post-interrupt tick preserves quantity")
	_cleanup_main(main)

	var missing_after_start := _configured_main("missing-after-start")
	missing_after_start.player.resources.apply_damage(30)
	asserts.true_value(missing_after_start.inventory.add_item("bandage", 1).ok, "missing-after-start fixture stocks one bandage")
	asserts.true_value(missing_after_start.submit_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, -1, {"item_id": "bandage"})), "missing-after-start use begins")
	asserts.true_value(missing_after_start.inventory.remove_item("bandage", 1).ok, "external removal empties active consumable item")
	var missing_completion: Dictionary = missing_after_start.tick_consumable_runtime(1.0)
	asserts.false_value(missing_completion.ok, "missing item at completion fails")
	asserts.equal(missing_completion.reason, "missing_consumable", "missing item failure reason is preserved")
	asserts.true_value(bool(missing_completion.get("interrupted", false)), "missing item failure clears active action")
	asserts.equal(missing_after_start.consumable_service.to_snapshot().active_action, {}, "missing item failure does not leave permanent active action")
	asserts.equal(missing_after_start.player.resources.hp, 70, "missing item failure does not heal")
	asserts.equal(missing_after_start.time_state.phase_elapsed_seconds, 0.0, "missing item failure does not advance time")
	asserts.false_value(missing_after_start._enemy_turn_queued, "missing item failure does not queue enemy turn")
	_cleanup_main(missing_after_start)

func _configured_main(label: String, paths := {}, clean_paths := true) -> Main:
	var save_paths: Dictionary = paths if typeof(paths) == TYPE_DICTIONARY and not paths.is_empty() else _save_paths(label)
	if clean_paths:
		_cleanup_paths(save_paths)
	var catalog := DataCatalog.new()
	var main := Main.new()
	main.run_state = RunState.new()
	main.save_store = SaveStore.new(save_paths.run, save_paths.meta)
	main.player = FakePlayer.new()
	main.game_hud = FakeHud.new()
	assert(catalog.load_from_directory("res://data/generated").ok)
	assert(main._configure_run_services(catalog).ok)
	return main

func _saved_run(main: Main) -> Dictionary:
	var loaded: Dictionary = main.save_store.load_run()
	return loaded.state if loaded.ok else {}

func _slot_for_item(main: Main, item_id: String) -> int:
	for index in range(main.inventory.slot_count):
		if String(main.inventory.get_slot(index).get("item_id", "")) == item_id:
			return index
	return -1

func _save_paths(label: String) -> Dictionary:
	var base := "user://samurai-tea-fox-dev118/%s" % label
	return {
		"run": "%s.run.save.json" % base,
		"meta": "%s.meta.save.json" % base
	}

func _cleanup_main(main: Main, clean_paths := true) -> void:
	var paths := {"run": main.save_store.run_path, "meta": main.save_store.meta_path} if main.save_store != null else {}
	if main.game_hud != null:
		main.game_hud.free()
	if main.player != null:
		main.player.free()
	if main.combat_dummy != null and main.combat_dummy is Node:
		main.combat_dummy.free()
	main.free()
	if clean_paths:
		_cleanup_paths(paths)

func _cleanup_paths(paths: Dictionary) -> void:
	for path in [String(paths.get("run", "")), String(paths.get("meta", "")), "%s.invalidated.json" % String(paths.get("run", ""))]:
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
