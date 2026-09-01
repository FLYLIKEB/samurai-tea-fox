extends CharacterBody2D
class_name PlayerController

const GameCommand = preload("res://src/core/commands/game_command.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")

const TILE_SIZE_PIXELS := 32.0
const PLAYER_COMBAT_ID := "player"

signal attack_started(swing: Dictionary)
signal damage_received(event: Dictionary, applied_damage: int)
signal dodge_started(direction: Vector2, distance_pixels: float)

@export_range(1.0, 512.0, 1.0) var movement_speed_pixels_per_second := 96.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var movement_state := PlayerMovementState.new()
var resources
var combat_config
var combat_state
var _movement_command = GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
var _pending_swing: Dictionary = {}
var _attack_query_pending := false
var _dodge_direction := Vector2.ZERO
var _dodge_time_remaining := 0.0
var _dodge_speed_pixels_per_second := 0.0

func _ready() -> void:
	_update_sprite_frame()

func _physics_process(delta: float) -> void:
	if combat_state != null:
		combat_state.tick(delta)
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
		velocity = _dodge_direction * _dodge_speed_pixels_per_second
	else:
		apply_movement_command(_movement_command)
	move_and_slide()
	if _attack_query_pending:
		_attack_query_pending = false
		_resolve_pending_attack()

func configure_combat(catalog) -> Dictionary:
	var resource_result: Dictionary = PlayerResources.from_catalog(catalog)
	if not resource_result.ok:
		return resource_result
	var config_result: Dictionary = CombatConfig.from_catalog(catalog)
	if not config_result.ok:
		return config_result
	resources = resource_result.resources
	combat_config = config_result.config
	combat_state = CombatState.new(combat_config)
	return {"ok": true}

func submit_command(command) -> bool:
	if not command is GameCommand:
		return false
	match command.type:
		GameCommand.Type.MOVE:
			_movement_command = command
			return true
		GameCommand.Type.ATTACK:
			return _start_attack(command.direction)
		GameCommand.Type.DODGE:
			return _start_dodge(command.direction)
		_:
			return false

func apply_movement_command(command) -> bool:
	if not _is_movement_command(command):
		return false

	velocity = movement_state.resolve(command.direction) * movement_speed_pixels_per_second
	_update_sprite_frame()
	return true

func _is_movement_command(command) -> bool:
	return command is GameCommand and command.type == GameCommand.Type.MOVE

func get_combat_id() -> String:
	return PLAYER_COMBAT_ID

func apply_damage_event(event: Dictionary) -> int:
	if resources == null or combat_state == null:
		return 0
	if combat_state.is_dodge_invulnerable() or combat_state.is_hit_invulnerable(PLAYER_COMBAT_ID):
		return 0
	var applied: int = resources.apply_damage(maxi(int(event.get("damage", 0)), 0))
	var invulnerability_seconds := maxf(float(event.get("hit_invulnerability_seconds", 0.0)), 0.0)
	if applied > 0 and invulnerability_seconds > 0.0:
		combat_state.set_hit_invulnerable(PLAYER_COMBAT_ID, invulnerability_seconds)
	if applied > 0:
		damage_received.emit(event, applied)
	return applied

func receive_damage(amount: int, hit_invulnerability_seconds := 0.0) -> int:
	return apply_damage_event({
		"type": "damage",
		"source_id": "external",
		"target_id": PLAYER_COMBAT_ID,
		"damage": amount,
		"hit_invulnerability_seconds": hit_invulnerability_seconds
	})

func is_invulnerable() -> bool:
	return combat_state != null and (
		combat_state.is_dodge_invulnerable()
		or combat_state.is_hit_invulnerable(PLAYER_COMBAT_ID)
	)

func can_dodge() -> bool:
	return combat_state != null and combat_state.is_dodge_ready()

func _start_attack(direction: Vector2i) -> bool:
	if combat_state == null or resources == null or _attack_query_pending:
		return false
	var attack_direction := _resolved_action_direction(direction)
	_pending_swing = combat_state.start_basic_attack(PLAYER_COMBAT_ID, resources.ki)
	if not _pending_swing.ok:
		_pending_swing = {}
		return false
	_pending_swing["direction"] = attack_direction
	_position_attack_area(attack_direction, float(_pending_swing.range_tiles))
	_attack_query_pending = true
	attack_started.emit(_pending_swing)
	return true

func _resolve_pending_attack() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = attack_shape.shape
	query.transform = attack_area.global_transform
	query.collision_mask = attack_area.collision_mask
	query.exclude = [get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var body = result.collider
		if body == self or not body.has_method("get_combat_id") or not body.has_method("apply_damage_event"):
			continue
		combat_state.apply_swing_hit(_pending_swing, body, combat_config.hit_invulnerability_seconds)
	combat_state.finish_swing(_pending_swing)
	_pending_swing = {}

func _start_dodge(direction: Vector2i) -> bool:
	if combat_state == null:
		return false
	var dodge: Dictionary = combat_state.start_dodge()
	if not dodge.ok:
		return false
	_dodge_direction = _resolved_action_direction(direction)
	_dodge_time_remaining = float(dodge.invulnerability_seconds)
	var distance_pixels := float(dodge.distance_tiles) * TILE_SIZE_PIXELS
	_dodge_speed_pixels_per_second = distance_pixels / maxf(_dodge_time_remaining, 0.001)
	dodge_started.emit(_dodge_direction, distance_pixels)
	return true

func _resolved_action_direction(direction: Vector2i) -> Vector2:
	if direction != Vector2i.ZERO:
		return Vector2(direction).normalized()
	match movement_state.facing:
		PlayerMovementState.Facing.DOWN:
			return Vector2.DOWN
		PlayerMovementState.Facing.LEFT:
			return Vector2.LEFT
		PlayerMovementState.Facing.RIGHT:
			return Vector2.RIGHT
		_:
			return Vector2.UP

func _position_attack_area(direction: Vector2, range_tiles: float) -> void:
	var range_pixels := range_tiles * TILE_SIZE_PIXELS
	attack_area.position = direction * range_pixels * 0.5
	var rectangle := attack_shape.shape as RectangleShape2D
	if absf(direction.x) > absf(direction.y):
		rectangle.size = Vector2(range_pixels, TILE_SIZE_PIXELS * 0.75)
	else:
		rectangle.size = Vector2(TILE_SIZE_PIXELS * 0.75, range_pixels)

func _update_sprite_frame() -> void:
	if sprite != null:
		sprite.frame = movement_state.facing
