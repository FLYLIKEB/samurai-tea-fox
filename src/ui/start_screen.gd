extends Control

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const GAMEPLAY_SCENE_PATH := "res://src/main/main.tscn"
const BACKGROUND_ASSET_ID := "clean_warm_teahouse_interior"
const LOGO_ASSET_ID := "muchau_title_plaque"
const DIVIDER_ASSET_ID := "divider_under_brand"
const START_MODE_META := "muchau_start_mode"
const START_MODE_NEW := "new"
const START_MODE_RESUME := "resume"
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)

@onready var start_button: Button = %StartButton
@onready var continue_button: Button = %ContinueButton
@onready var background: TextureRect = $Background
@onready var logo: TextureRect = $Content/Logo
@onready var divider: TextureRect = $Content/Divider

var _is_starting := false
var _asset_catalog := AssetCatalog.new()
var _save_store := SaveStore.new()

func _ready() -> void:
	_apply_default_window_size()
	_apply_manifest_textures()
	_update_continue_button()
	start_button.grab_focus()

func _apply_default_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_start_game(START_MODE_NEW)

func _on_start_button_pressed() -> void:
	_start_game(START_MODE_NEW)

func _on_continue_button_pressed() -> void:
	_start_game(START_MODE_RESUME)

func _start_game(start_mode := START_MODE_RESUME) -> void:
	if _is_starting:
		return
	_is_starting = true
	start_button.disabled = true
	continue_button.disabled = true
	get_tree().root.set_meta(START_MODE_META, start_mode)

	var change_error := get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)
	if change_error == OK:
		return

	get_tree().root.remove_meta(START_MODE_META)
	_is_starting = false
	start_button.disabled = false
	_update_continue_button()
	push_error("Could not start gameplay scene: %s" % error_string(change_error))

func _apply_manifest_textures() -> void:
	var load_result: Dictionary = _asset_catalog.load_manifest()
	if not load_result.ok:
		push_error(load_result.error)
		return
	background.texture = _asset_catalog.load_texture(BACKGROUND_ASSET_ID)
	logo.texture = _asset_catalog.load_texture(LOGO_ASSET_ID)
	divider.texture = _asset_catalog.load_texture(DIVIDER_ASSET_ID)

func _update_continue_button() -> void:
	var can_continue := bool(_save_store.load_run().get("ok", false))
	continue_button.disabled = not can_continue
