extends Control

const GAMEPLAY_SCENE_PATH := "res://src/main/main.tscn"

@onready var start_button: Button = %StartButton

var _is_starting := false

func _ready() -> void:
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
