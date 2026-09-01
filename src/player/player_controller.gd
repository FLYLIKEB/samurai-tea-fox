extends CharacterBody2D
class_name PlayerController

const GameCommand = preload("res://src/core/commands/game_command.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")

@export_range(1.0, 512.0, 1.0) var movement_speed_pixels_per_second := 96.0

@onready var sprite: Sprite2D = $Sprite2D

var movement_state := PlayerMovementState.new()
var _movement_command = GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)

func _ready() -> void:
	_update_sprite_frame()

func _physics_process(_delta: float) -> void:
	apply_movement_command(_movement_command)
	move_and_slide()

func submit_command(command) -> bool:
	if not _is_movement_command(command):
		return false
	_movement_command = command
	return true

func apply_movement_command(command) -> bool:
	if not _is_movement_command(command):
		return false

	velocity = movement_state.resolve(command.direction) * movement_speed_pixels_per_second
	_update_sprite_frame()
	return true

func _is_movement_command(command) -> bool:
	return command is GameCommand and command.type == GameCommand.Type.MOVE

func _update_sprite_frame() -> void:
	if sprite != null:
		sprite.frame = movement_state.facing
