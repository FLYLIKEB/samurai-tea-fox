extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const Main = preload("res://src/main/main.gd")
const PlayerController = preload("res://src/player/player_controller.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const TimeState = preload("res://src/time/time_state.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")

const RUN_PATH := "user://dev17_vertical_slice_run.save.json"
const META_PATH := "user://dev17_vertical_slice_meta.save.json"

class PartialTimeCatalog:
	extends RefCounted

	func find_by_id(dataset: String, id: String) -> Dictionary:
		if dataset == "balance" and id == "dusk_phase_duration_seconds":
			return {"id": id, "value": 120}
		return {}

func run(asserts) -> void:
	_cleanup()
	asserts.true_value(Main.new()._catalog_declares_time_balance(PartialTimeCatalog.new()), "Main detects partially declared time balance without the day sentinel")
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "vertical slice catalog loads")
	var runtime := _configured_runtime(catalog, RunState.new())
	asserts.true_value(runtime.result.ok, "vertical slice main runtime configures")
	if not runtime.result.ok:
		runtime.main.free()
		_cleanup()
		return
	var main: Main = runtime.main
	asserts.equal(main.generated_world.biome_id, "common_region", "vertical slice starts in the common biome")
	asserts.true_value(main.world_render_result.ok, "common biome world renders for playable runtime")
	asserts.true_value(main.game_hud.narrative_dialogue_visible(), "first launch shows the first-run prologue dialogue")
	var prologue_model: Dictionary = main.first_run_prologue_read_model({"run_count": 0, "dialogue_memory_flags": [], "unlocked_meta_flags": []})
	asserts.true_value(prologue_model.ok, "first-run prologue has a read model before completion")
	if prologue_model.ok:
		asserts.equal(prologue_model.read_model.speaker_id, "CHR-1", "first-run prologue starts as father dialogue")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.NARRATIVE_SELECT_OPTION, Vector2i.ZERO, -1, {
		"event_id": "first_run_prologue",
		"node_id": "father_farewell",
		"option_id": "accept_farewell"
	})), "first-run prologue advances from father farewell")
	asserts.true_value(main.game_hud.narrative_dialogue_visible(), "first-run prologue remains visible after the first advance")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.NARRATIVE_SELECT_OPTION, Vector2i.ZERO, -1, {
		"event_id": "first_run_prologue",
		"node_id": "muchau_question",
		"option_id": "cross_sea"
	})), "first-run prologue advances through Muchau's question")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.NARRATIVE_SELECT_OPTION, Vector2i.ZERO, -1, {
		"event_id": "first_run_prologue",
		"node_id": "border_cup",
		"option_id": "begin_road"
	})), "first-run prologue completes at the Hongguk border cup")
	asserts.false_value(main.game_hud.narrative_dialogue_visible(), "first-run prologue closes after completion")
	asserts.equal(int(main.run_state.narrative_event_counts.get("first_run_prologue", 0)), 1, "first-run prologue completion is recorded in run state")
	asserts.true_value(main.run_state.narrative_flags.has("first_run_prologue_completed"), "first-run prologue applies its completion run flag")
	asserts.false_value(main.first_run_prologue_read_model({"run_count": 0, "dialogue_memory_flags": [], "unlocked_meta_flags": []}).ok, "completed first-run prologue cannot reopen in the same run")
	var repeat_runtime := _configured_runtime(catalog, RunState.new(), {"run_count": 1})
	asserts.true_value(repeat_runtime.result.ok, "repeat-run fixture configures")
	if repeat_runtime.result.ok:
		asserts.false_value(repeat_runtime.main.game_hud.narrative_dialogue_visible(), "repeat-run meta state does not auto-open the first-run prologue")
		asserts.equal(repeat_runtime.main.first_run_prologue_read_model({"run_count": 1}).reason, "not_first_run", "repeat-run meta state rejects first-run prologue")
	asserts.equal(main.player.ability_runtime.equipped_ability_id(0), "ember", "first-tail playable ability is equipped by default")
	main.player.global_position = main.world_position_for_cell_center(Vector2i(1, 1))
	main.combat_dummy.global_position = main.world_position_for_cell_center(Vector2i(3, 1))

	var first_resource: Dictionary = main.generated_world.resource_nodes[0]
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": first_resource.id})), "slice gathers a generated common resource")
	asserts.true_value(main.inventory.get_total_quantity(String(first_resource.resource_id)) > 0, "gathered resource enters inventory")

	asserts.true_value(main.inventory.add_item("tea_11", 1).ok, "slice can stock a confirmed conditional tea leaf")
	asserts.true_value(main.inventory.add_item("humble_clay_bowl", 1).ok, "slice can stock the minimal tea vessel")
	asserts.true_value(main.tea_service.brew("tea_11", "humble_clay_bowl", main.inventory, 0, {"has_brewing_location": true}).ok, "slice prepares tea in a quickslot")
	main.player.resources.apply_damage(30)
	var hp_after_damage: int = main.player.resources.hp
	main.player.resources.spend_ki(20)
	var ki_before_tea: int = main.player.resources.ki
	asserts.true_value(main.submit_desktop_action_command("drink_tea", Vector2i.ZERO, 0), "slice starts prepared tea through Main")
	asserts.true_value(main.is_tea_drink_active(), "tea remains active for its data-driven drinking time")
	asserts.equal(main.player.resources.ki, ki_before_tea, "tea effect waits until drinking completes")
	main.tick_tea_runtime(1.9)
	asserts.equal(main.player.resources.ki, ki_before_tea, "tea does not complete before its exported duration")
	main.tick_tea_runtime(0.1)
	asserts.false_value(main.is_tea_drink_active(), "tea completes at its exported duration")
	asserts.equal(main.player.resources.hp, hp_after_damage, "tea does not heal HP")
	asserts.true_value(main.player.resources.ki > ki_before_tea, "tea restores ki")

	var ki_before_ability: int = main.player.resources.ki
	asserts.true_value(main.submit_desktop_action_command("cast_ability", Vector2i.RIGHT, 0), "slice casts the default ability through Main")
	asserts.equal(ki_before_ability - main.player.resources.ki, 13, "tea sustain modifier reduces the next ability ki cost once")
	asserts.equal(main.run_state.tea.next_ability_ki_cost_modifier_percent, 0.0, "successful ability use clears the persisted one-shot tea modifier")
	asserts.true_value(main.combat_dummy.current_hp() < main.combat_dummy.combatant.hp_max, "ability damages the common combat target")

	main.time_state.tick(300.0 + 120.0 + 1.0, main.player.resources)
	main.player.resources.reduce_kokoro(20)
	main.player.resources.apply_damage(10)
	asserts.true_value(main.submit_desktop_action_command("sleep"), "slice sleeps through Main")
	asserts.equal(main.time_state.phase, TimeState.DAY, "sleep returns time to morning")
	asserts.equal(main.player.resources.kokoro, main.player.resources.kokoro_max, "sleep restores 心")

	asserts.true_value(main.submit_desktop_action_command("complete_dungeon"), "slice enters the minimal common dungeon through Main")
	asserts.equal(main.run_state.completed_dungeon_ids, [], "dungeon entry alone does not complete biome progression")
	asserts.true_value(main._in_dungeon_map, "dungeon entry switches the active world to dungeon mode")
	asserts.equal(main.world_data.width, 12, "dungeon map uses the dedicated dungeon width")
	asserts.equal(main.world_data.height, 9, "dungeon map uses the dedicated dungeon height")
	asserts.equal(main.world_cell_from_world_position(main.player.global_position), Vector2i(1, 1), "player spawns at the dungeon entrance")
	for _attempt in range(10):
		if main.combat_dummy.current_hp() <= 0:
			break
		main.player.ability_runtime.tick(10.0)
		main.player.resources.recover_ki(main.player.resources.ki_max)
		asserts.true_value(main.submit_desktop_action_command("cast_ability", Vector2i.RIGHT, 0), "slice continues combat until the dungeon objective is clear")
	asserts.true_value(main.combat_dummy.current_hp() <= 0, "combat objective is defeated before dungeon completion")
	asserts.true_value(main.submit_desktop_action_command("complete_dungeon"), "slice completes the minimal common dungeon after combat objective clear")
	asserts.false_value(main._in_dungeon_map, "dungeon completion returns to the overworld map")
	asserts.equal(main.run_state.completed_dungeon_ids, ["common_region"], "dungeon completion updates biome progression")
	asserts.equal(main.run_state.teleport_states.common_region, BiomeProgressionState.TELEPORT_REPAIRABLE, "dungeon completion makes teleport repairable")
	asserts.true_value(main.submit_desktop_action_command("repair_teleport"), "slice repairs the common teleport through Main")
	asserts.equal(main.run_state.teleport_states.common_region, BiomeProgressionState.TELEPORT_REPAIRED, "teleport repair is recorded")
	asserts.equal(main.run_state.crafting_unlocks, ["common_region"], "teleport repair unlocks common crafting for the current run")

	asserts.true_value(main.inventory.add_item("cloth", 2).ok, "slice stocks existing cloth material for the exported bandage recipe")
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "bandage"})), "slice crafts a bandage through stable recipe ID")
	main.player.resources.apply_damage(40)
	var hp_before_bandage: int = main.player.resources.hp
	asserts.true_value(main.submit_mobile_action_command(GameCommand.new(GameCommand.Type.USE_CONSUMABLE)), "slice uses a bandage through Main quick consumable command")
	asserts.true_value(main.player.resources.hp > hp_before_bandage, "bandage heals HP")
	asserts.equal(main.inventory.get_total_quantity("bandage"), 0, "bandage use consumes the crafted item")
	main.time_state.tick(300.0 + 120.0 + 1.0, main.player.resources)
	asserts.equal(main.time_state.phase, TimeState.NIGHT, "slice can persist from night after daytime progress")

	asserts.true_value(main.save_current_run().ok, "slice can persist an interruptible run")
	var restored := _configured_runtime(catalog, null)
	asserts.true_value(restored.result.ok, "slice relaunch loads the persisted run: %s" % String(restored.result.get("error", restored.result.get("reason", ""))))
	if not restored.result.ok:
		main.free()
		runtime.player.free()
		runtime.dummy.free()
		runtime.world_root.free()
		runtime.hud.free()
		restored.main.free()
		restored.player.free()
		restored.dummy.free()
		restored.world_root.free()
		restored.hud.free()
		_cleanup()
		return
	asserts.equal(restored.main.run_state.teleport_states.common_region, BiomeProgressionState.TELEPORT_REPAIRED, "relaunch preserves repaired common teleport")
	asserts.true_value(restored.main.run_state.acquisitions.gatherables[0].depleted, "relaunch preserves gathered resource depletion")
	asserts.equal(restored.main.time_state.phase, TimeState.NIGHT, "relaunch preserves runtime time phase")

	asserts.true_value(restored.main.inventory.add_item("item_29", 1).ok, "slice can stock the data-defined resurrection item")
	restored.main.player.resources.apply_damage(999)
	asserts.true_value(restored.main.player.resources.hp > 0, "lethal damage consumes resurrection before run reset")
	asserts.equal(restored.main.inventory.get_total_quantity("item_29"), 0, "resurrection item is consumed")
	restored.main.player.resources.apply_damage(999)
	asserts.equal(restored.main.run_state.lifecycle_epoch, 1, "death without resurrection activates a fresh run epoch")
	asserts.equal(restored.main.run_state.inventory, {}, "fresh run clears run inventory growth")
	asserts.equal(restored.main.run_state.completed_dungeon_ids, [], "fresh run clears dungeon progression")

	main.free()
	runtime.player.free()
	runtime.dummy.free()
	runtime.world_root.free()
	runtime.hud.free()
	restored.main.free()
	restored.player.free()
	restored.dummy.free()
	restored.world_root.free()
	restored.hud.free()
	repeat_runtime.main.free()
	repeat_runtime.player.free()
	repeat_runtime.dummy.free()
	repeat_runtime.world_root.free()
	repeat_runtime.hud.free()
	_cleanup()

func _configured_runtime(catalog: DataCatalog, state, meta_snapshot := {}) -> Dictionary:
	var main := Main.new()
	var player := PlayerController.new()
	var dummy := CombatDummy.new()
	var world_root := Node2D.new()
	var hud := GameHud.new()
	dummy.automatic_attacks = false
	main.catalog = catalog
	main.player = player
	main.combat_dummy = dummy
	main.world_visuals = world_root
	main.game_hud = hud
	main.save_store = SaveStore.new(RUN_PATH, META_PATH)
	if not meta_snapshot.is_empty():
		main.save_store.save_meta(meta_snapshot)
	main.run_state = state
	var loaded_run: Dictionary = main.load_or_create_run_state()
	if not loaded_run.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": loaded_run}
	main.run_state.data_version = catalog.data_version
	if main.run_state.seed == 0:
		main.run_state.seed = Main.DEFAULT_RUN_SEED
	var services: Dictionary = main._configure_run_services(catalog)
	if not services.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": services}
	var combat: Dictionary = main._configure_combat_lifecycle()
	if not combat.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": combat}
	var world: Dictionary = main._configure_world_for_current_run()
	return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": world}

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", META_PATH, META_PATH + ".tmp", RUN_PATH + ".invalidated.json", RUN_PATH + ".invalidated.json.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
