extends Control

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")

const GAMEPLAY_SCENE_PATH := "res://src/main/main.tscn"
const BACKGROUND_ASSET_ID := "clean_warm_teahouse_interior"
const LOGO_ASSET_ID := "muchau_title_plaque"
const DIVIDER_ASSET_ID := "divider_under_brand"

@onready var start_button: Button = %StartButton
@onready var background: TextureRect = $Background
@onready var logo: TextureRect = $Content/Logo
@onready var divider: TextureRect = $Content/Divider

var _is_starting := false
var _asset_catalog := AssetCatalog.new()

func _ready() -> void:
	_apply_manifest_textures()
	start_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_start_game()

func _on_start_button_pressed() -> void:
	_start_game()

func _start_game() -> void:
	if _is_starting:
		return
	_is_starting = true
	start_button.disabled = true

	var change_error := get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)
	if change_error == OK:
		return

	_is_starting = false
	start_button.disabled = false
	push_error("Could not start gameplay scene: %s" % error_string(change_error))

func _apply_manifest_textures() -> void:
	var load_result: Dictionary = _asset_catalog.load_manifest()
	if not load_result.ok:
		push_error(load_result.error)
		return
	background.texture = _asset_catalog.load_texture(BACKGROUND_ASSET_ID)
	logo.texture = _asset_catalog.load_texture(LOGO_ASSET_ID)
	divider.texture = _asset_catalog.load_texture(DIVIDER_ASSET_ID)
