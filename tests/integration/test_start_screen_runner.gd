extends SceneTree

const START_SCREEN_PATH := "res://scenes/ui/start_screen.tscn"
const GAMEPLAY_SCENE_PATH := "res://src/main/main.tscn"
const BACKGROUND_ASSET_ID := "clean_warm_teahouse_interior"
const LOGO_ASSET_ID := "muchau_title_plaque"
const DIVIDER_ASSET_ID := "divider_under_brand"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
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
	if start_button.text != "시작하기":
		failures.append("start button uses the Korean start label")
	if root.gui_get_focus_owner() != start_button:
		failures.append("start button receives initial keyboard focus")

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

	finish()

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
	if failures.is_empty():
		print("Start screen integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
