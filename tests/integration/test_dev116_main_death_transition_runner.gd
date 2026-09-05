extends SceneTree

const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const Main = preload("res://src/main/main.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const PlayerController = preload("res://src/player/player_controller.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const LIFECYCLE_DIRECTORY := "user://dev116_main_death_transition"
const RUN_PATH := LIFECYCLE_DIRECTORY + "/run.json"
const META_PATH := LIFECYCLE_DIRECTORY + "/meta.json"
const START_SCREEN_SCENE_PATH := "res://scenes/ui/start_screen.tscn"
const PLAYER_SCENE_PATH := "res://scenes/actors/player.tscn"

class TreeAttachedMain:
	extends Main

	func _ready() -> void:
		pass

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_cleanup()
	var original_end_duration: float = Main.THE_END_DURATION_SECONDS
	Main.THE_END_DURATION_SECONDS = 0.01

	var runtime := _configured_tree_runtime()
	if not runtime.result.ok:
		failures.append("death transition fixture configures: %s" % String(runtime.result.get("error", runtime.result.get("reason", ""))))
		Main.THE_END_DURATION_SECONDS = original_end_duration
		_cleanup()
		finish()
		return

	var main: Main = runtime.main
	var player: PlayerController = runtime.player
	var store := SaveStore.new(RUN_PATH, META_PATH)
	main.save_store = store
	main.run_state.lifecycle_epoch = 0
	main.run_state.seed = 701
	main.inventory.add_item("wood", 1)
	main.run_state.inventory = main.inventory.to_snapshot()
	if not store.save_run(main.run_state).ok:
		failures.append("death transition fixture persists old run")
	var meta := MetaState.new()
	meta.run_count = 9
	if not store.save_meta(meta).ok:
		failures.append("death transition fixture persists meta")
	var meta_before := FileAccess.get_file_as_string(META_PATH)

	player.resources.apply_damage(player.resources.hp_max)
	if not main._death_transition_active:
		failures.append("lethal damage starts the death transition")

	await _wait_for_start_screen()

	var loaded := SaveStore.new(RUN_PATH, META_PATH).load_run()
	if not loaded.ok:
		failures.append("death transition persists a fresh run save: %s" % String(loaded.get("reason", "")))
	elif loaded.state.lifecycle_epoch != 1 or loaded.state.seed != 0:
		failures.append("death transition fresh save advances epoch and resets seed")
	if FileAccess.get_file_as_string(META_PATH) != meta_before:
		failures.append("death transition preserves meta save bytes")
	var marker = JSON.parse_string(FileAccess.get_file_as_string(RUN_PATH + ".invalidated.json"))
	if typeof(marker) != TYPE_DICTIONARY or int(marker.get("invalidated_lifecycle_epoch", -1)) != 0:
		failures.append("death transition writes the invalidated old epoch marker")

	var start_screen := current_scene
	if start_screen == null or start_screen.scene_file_path != START_SCREEN_SCENE_PATH:
		failures.append("death transition returns to the start screen after the timer")

	Main.THE_END_DURATION_SECONDS = original_end_duration
	main.queue_free()
	_cleanup()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("DEV-116 main death transition integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _wait_for_start_screen() -> void:
	var deadline_msec := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline_msec:
		if current_scene != null and current_scene.scene_file_path == START_SCREEN_SCENE_PATH:
			return
		await process_frame

func _configured_tree_runtime() -> Dictionary:
	var catalog := DataCatalog.new()
	var load_result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not load_result.ok:
		return {"result": load_result}
	var main := TreeAttachedMain.new()
	main.name = "Main"
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	player.name = "Player"
	var dummy := _new_combat_dummy()
	dummy.name = "CombatDummy"
	var world_root := Node2D.new()
	world_root.name = "WorldVisuals"
	var tone_overlay := CanvasLayer.new()
	tone_overlay.name = "WorldToneOverlay"
	var hud := GameHud.new()
	hud.name = "GameHud"
	dummy.automatic_attacks = false
	main.add_child(world_root)
	main.add_child(player)
	main.add_child(dummy)
	main.add_child(tone_overlay)
	main.add_child(hud)
	main.catalog = catalog
	main.player = player
	main.combat_dummy = dummy
	main.world_visuals = world_root
	main.game_hud = hud
	main.save_store = SaveStore.new(RUN_PATH, META_PATH)
	main.run_state = RunState.new()
	main.run_state.data_version = catalog.data_version
	main.run_state.seed = Main.DEFAULT_RUN_SEED
	root.add_child(main)
	var services: Dictionary = main._configure_run_services(catalog)
	if not services.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": services}
	var combat: Dictionary = main._configure_combat_lifecycle()
	if not combat.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": combat}
	var world: Dictionary = main._configure_world_for_current_run()
	return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": world}

func _new_combat_dummy() -> CombatDummy:
	var dummy := CombatDummy.new()
	dummy.add_child(Sprite2D.new())
	dummy.get_child(0).name = "Sprite2D"
	var body := Polygon2D.new()
	body.name = "Body"
	dummy.add_child(body)
	var headband := Polygon2D.new()
	headband.name = "Headband"
	dummy.add_child(headband)
	var background := Polygon2D.new()
	background.name = "HealthBackground"
	dummy.add_child(background)
	var fill := Polygon2D.new()
	fill.name = "HealthFill"
	dummy.add_child(fill)
	return dummy

func _cleanup() -> void:
	for path in [
		RUN_PATH,
		RUN_PATH + ".tmp",
		RUN_PATH + ".invalidated.json",
		RUN_PATH + ".invalidated.json.tmp",
		META_PATH,
		META_PATH + ".tmp"
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := ProjectSettings.globalize_path(LIFECYCLE_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
