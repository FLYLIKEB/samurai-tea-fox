extends SceneTree

const START_SCREEN_PATH := "res://scenes/ui/start_screen.tscn"
const GAMEPLAY_SCENE_PATH := "res://src/main/main.tscn"
const BACKGROUND_ASSET_ID := "clean_warm_teahouse_interior"
const LOGO_ASSET_ID := "muchau_title_plaque"
const DIVIDER_ASSET_ID := "divider_under_brand"
const MetaState = preload("res://src/save/meta_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_cleanup()
	_write_existing_completed_run()
	var change_error := change_scene_to_file(START_SCREEN_PATH)
	if change_error != OK:
		failures.append("start screen scene loads")
		finish()
		return

	await process_frame
	await process_frame

	var start_screen := current_scene
	if start_screen == null or start_screen.scene_file_path != START_SCREEN_PATH:
		failures.append("start screen becomes the current scene")
		finish()
		return

	_assert_texture(start_screen, "Background", BACKGROUND_ASSET_ID, "promoted teahouse background")
	_assert_texture(start_screen, "Content/Logo", LOGO_ASSET_ID, "Muchau title plaque")
	_assert_texture(start_screen, "Content/Divider", DIVIDER_ASSET_ID, "brand divider")

	var start_button := start_screen.get_node_or_null("Content/StartButton") as Button
	if start_button == null:
		failures.append("start screen exposes a start button")
		finish()
		return
	if start_button.text != "처음부터 시작하기":
		failures.append("start button uses the Korean new-start label")
	if root.gui_get_focus_owner() != start_button:
		failures.append("start button receives initial keyboard focus")
	var continue_button := start_screen.get_node_or_null("Content/ContinueButton") as Button
	if continue_button == null:
		failures.append("start screen exposes a continue button")
		finish()
		return
	if continue_button.text != "이어하기":
		failures.append("continue button uses the Korean resume label")
	if continue_button.disabled:
		failures.append("continue button is enabled when a valid run save exists")

	var accept_event := InputEventAction.new()
	accept_event.action = "ui_accept"
	accept_event.pressed = true
	start_screen._unhandled_input(accept_event)

	await process_frame
	await process_frame
	await process_frame

	var gameplay_scene := current_scene
	if gameplay_scene == null or gameplay_scene.scene_file_path != GAMEPLAY_SCENE_PATH:
		failures.append("ui_accept enters the existing gameplay scene")
		finish()
		return
	if gameplay_scene.get_node_or_null("Player") == null:
		failures.append("gameplay scene initializes its player after the transition")
	if gameplay_scene.generated_world.is_empty():
		failures.append("gameplay scene completes its existing world initialization")
	if not gameplay_scene.game_hud.narrative_dialogue_visible():
		failures.append("new start opens the prologue dialogue even when an older completed run existed")
	if int(gameplay_scene.run_state.narrative_event_counts.get("first_run_prologue", 0)) != 0:
		failures.append("new start replaces the old completed run state before the prologue")

	finish()

func _write_existing_completed_run() -> void:
	var store := SaveStore.new()
	var run_state := RunState.new()
	run_state.lifecycle_epoch = 3
	run_state.seed = 9281
	run_state.narrative_event_counts = {"first_run_prologue": 1}
	run_state.narrative_flags = ["first_run_prologue_completed"]
	store.save_run(run_state)
	var meta_state := MetaState.new()
	meta_state.run_count = 4
	store.save_meta(meta_state)

func _assert_texture(scene: Node, node_path: String, expected_asset_id: String, label: String) -> void:
	var texture_rect := scene.get_node_or_null(node_path) as TextureRect
	if texture_rect == null or texture_rect.texture == null:
		failures.append("start screen reuses the %s" % label)
		return
	var expected_texture := current_scene._asset_catalog.load_texture(expected_asset_id) as Texture2D
	if expected_texture == null:
		failures.append("start screen manifest resolves the %s" % label)
		return
	if texture_rect.texture.get_width() != expected_texture.get_width() or texture_rect.texture.get_height() != expected_texture.get_height():
		failures.append("start screen reuses the %s at manifest dimensions" % label)

func finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("Start screen integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _cleanup() -> void:
	for path in [
		SaveStore.DEFAULT_RUN_PATH,
		SaveStore.DEFAULT_RUN_PATH + ".tmp",
		SaveStore.DEFAULT_RUN_PATH + ".invalidated.json",
		SaveStore.DEFAULT_RUN_PATH + ".invalidated.json.tmp",
		SaveStore.DEFAULT_META_PATH,
		SaveStore.DEFAULT_META_PATH + ".tmp"
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
