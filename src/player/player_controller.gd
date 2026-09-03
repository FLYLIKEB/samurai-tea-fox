extends CharacterBody2D
class_name PlayerController

const GameCommand = preload("res://src/core/commands/game_command.gd")
const PlayerMovementState = preload("res://src/player/player_movement_state.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const AbilityRuntime = preload("res://src/ability/ability_runtime.gd")
const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DirectionalWalkAnimator = preload("res://src/presentation/directional_walk_animator.gd")

const TILE_SIZE_PIXELS := 32.0
const PLAYER_COMBAT_ID := "player"
const PLAYER_CHARACTER_ID := "CHR-8"
const IDLE_ASSET_IDS := {
	"south": "fox_samurai_front_idle",
	"west": "fox_samurai_left_idle",
	"east": "fox_samurai_right_idle",
	"north": "fox_samurai_back_idle"
}

signal attack_started(swing: Dictionary)
signal ability_cast(result: Dictionary)
signal damage_received(event: Dictionary, applied_damage: int)
signal dodge_started(direction: Vector2, distance_pixels: float)
signal grid_step_started(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_blocked(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_finished(cell: Vector2i)

@export_range(1.0, 512.0, 1.0) var movement_speed_pixels_per_second := 96.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var movement_state := PlayerMovementState.new()
var resources
var combat_config
var combat_state
var ability_runtime
var ability_tail_query
var ability_time_state
var ability_target_query
var asset_catalog := AssetCatalog.new()
var walk_animator := DirectionalWalkAnimator.new()
var _current_sprite_asset_id := ""
var _walk_animator_ready := false
var _movement_command = GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO)
var _pending_swing: Dictionary = {}
var _attack_query_pending := false
var _dodge_direction := Vector2.ZERO
var _dodge_time_remaining := 0.0
var _dodge_speed_pixels_per_second := 0.0
var grid_movement_enabled := true
var _grid_target_position := Vector2.ZERO
var _grid_source_position := Vector2.ZERO
var _grid_source_cell := Vector2i.ZERO
var _grid_step_direction := Vector2.ZERO
var _grid_moving := false
var _grid_world_data = null
var _grid_world_origin := Vector2.ZERO
var _grid_tile_size := TILE_SIZE_PIXELS

func _ready() -> void:
	var asset_result := asset_catalog.load_manifest()
	if not asset_result.ok:
		push_error(asset_result.error)
	else:
		var animation_result := walk_animator.configure_for_character(
			sprite,
			asset_catalog,
			PLAYER_CHARACTER_ID,
			IDLE_ASSET_IDS
		)
		if animation_result.ok:
			_walk_animator_ready = true
			_current_sprite_asset_id = walk_animator.current_asset_id()
		else:
			push_error(animation_result.error)
	if not _walk_animator_ready:
		_update_sprite_frame()

func _physics_process(delta: float) -> void:
	if combat_state != null:
		combat_state.tick(delta)
	if ability_runtime != null:
		ability_runtime.tick(delta)
	var is_dodging := _dodge_time_remaining > 0.0
	if is_dodging:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
		velocity = _dodge_direction * _dodge_speed_pixels_per_second
	elif grid_movement_enabled:
		if not _grid_moving:
			apply_movement_command(_movement_command)
		_advance_grid_step(delta)
	else:
		apply_movement_command(_movement_command)
	_update_sprite_animation(delta, not is_dodging)
	if is_dodging or not grid_movement_enabled:
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
	var ability_result: Dictionary = AbilityRuntime.from_catalog(catalog)
	if not ability_result.ok:
		return ability_result
	ability_runtime = ability_result.runtime
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
		GameCommand.Type.CAST_ABILITY:
			return _cast_ability(command.slot, command.direction)
		_:
			return false

func apply_movement_command(command) -> bool:
	if not _is_movement_command(command):
		return false

	if grid_movement_enabled:
		return _start_grid_step(command.direction)

	velocity = movement_state.resolve(command.direction) * movement_speed_pixels_per_second
	_update_sprite_animation(0.0)
	return true

func configure_grid_navigation(world_data = null, world_origin := Vector2.ZERO, tile_size := TILE_SIZE_PIXELS) -> void:
	_grid_world_data = world_data
	_grid_world_origin = world_origin
	_grid_tile_size = maxf(tile_size, 1.0)
	var current_cell := _grid_cell_for_position(global_position)
	if _grid_cell_is_walkable(current_cell):
		global_position = _grid_position_for_cell_center(current_cell)

func is_grid_step_active() -> bool:
	return _grid_moving

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

func configure_ability_context(tail_query = null, time_state = null, target_query = null) -> void:
	ability_tail_query = tail_query
	ability_time_state = time_state
	ability_target_query = target_query

func equip_ability(slot: int, ability_id: String, tail_query = null) -> Dictionary:
	if ability_runtime == null:
		return {"ok": false, "reason": "missing_ability_runtime"}
	if tail_query != null:
		ability_tail_query = tail_query
	return ability_runtime.equip(slot, ability_id, {"tail_query": ability_tail_query})

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
	if _walk_animator_ready:
		walk_animator.play_attack(_animation_direction_for_vector(attack_direction))
		_current_sprite_asset_id = walk_animator.current_asset_id()
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
	_grid_moving = false
	var dodge: Dictionary = combat_state.start_dodge()
	if not dodge.ok:
		return false
	_dodge_direction = _resolved_action_direction(direction)
	_dodge_time_remaining = float(dodge.invulnerability_seconds)
	var distance_pixels := float(dodge.distance_tiles) * TILE_SIZE_PIXELS
	_dodge_speed_pixels_per_second = distance_pixels / maxf(_dodge_time_remaining, 0.001)
	dodge_started.emit(_dodge_direction, distance_pixels)
	return true

func _start_grid_step(direction: Vector2i) -> bool:
	var resolved := movement_state.resolve(direction)
	if resolved == Vector2.ZERO:
		velocity = Vector2.ZERO
		return true
	var step := Vector2i(int(resolved.x), int(resolved.y))
	var from_cell := _grid_cell_for_position(global_position)
	var to_cell := from_cell + step
	if not _grid_cell_is_walkable(to_cell):
		velocity = Vector2.ZERO
		grid_step_blocked.emit(from_cell, to_cell)
		return false
	_grid_source_cell = from_cell
	_grid_source_position = _grid_position_for_cell_center(from_cell)
	_grid_target_position = _grid_position_for_cell_center(to_cell)
	_grid_step_direction = Vector2(step)
	_grid_moving = true
	velocity = _grid_step_direction * movement_speed_pixels_per_second
	grid_step_started.emit(from_cell, to_cell)
	return true

func _advance_grid_step(delta: float) -> void:
	if not _grid_moving:
		velocity = Vector2.ZERO
		return
	var remaining := _grid_target_position - global_position
	var distance := remaining.length()
	if distance <= 0.01:
		_finish_grid_step()
		return
	var motion := _grid_step_direction * minf(movement_speed_pixels_per_second * maxf(delta, 0.0), distance)
	var collision := move_and_collide(motion)
	if collision != null:
		global_position = _grid_source_position
		_grid_moving = false
		velocity = Vector2.ZERO
		grid_step_blocked.emit(_grid_source_cell, _grid_cell_for_position(_grid_target_position))
		return
	if global_position.distance_to(_grid_target_position) <= 0.5:
		global_position = _grid_target_position
		_finish_grid_step()
	else:
		velocity = _grid_step_direction * movement_speed_pixels_per_second

func _finish_grid_step() -> void:
	_grid_moving = false
	velocity = Vector2.ZERO
	grid_step_finished.emit(_grid_cell_for_position(global_position))

func _grid_cell_for_position(world_position: Vector2) -> Vector2i:
	var local_position := world_position - _grid_world_origin
	if _grid_world_data == null:
		return Vector2i(int(round(local_position.x / _grid_tile_size)), int(round(local_position.y / _grid_tile_size)))
	return Vector2i(int(floor(local_position.x / _grid_tile_size)), int(floor(local_position.y / _grid_tile_size)))

func _grid_position_for_cell_center(cell: Vector2i) -> Vector2:
	if _grid_world_data == null:
		return _grid_world_origin + Vector2(float(cell.x) * _grid_tile_size, float(cell.y) * _grid_tile_size)
	return _grid_world_origin + Vector2(
		float(cell.x) * _grid_tile_size + _grid_tile_size * 0.5,
		float(cell.y) * _grid_tile_size + _grid_tile_size * 0.5
	)

func _grid_cell_is_walkable(cell: Vector2i) -> bool:
	if _grid_world_data == null:
		return true
	if _grid_world_data.has_method("contains") and not _grid_world_data.contains(cell):
		return false
	if _grid_world_data.has_method("is_walkable"):
		return bool(_grid_world_data.is_walkable(cell))
	return true

func _cast_ability(slot: int, direction: Vector2i) -> bool:
	if ability_runtime == null or resources == null:
		return false
	var action_direction := _resolved_action_direction(direction)
	var context := {
		"source_id": PLAYER_COMBAT_ID,
		"resources": resources,
		"tail_query": ability_tail_query,
		"time_state": ability_time_state,
		"direction": action_direction
	}
	var definition_result: Dictionary = ability_runtime.definition_for_slot(slot)
	if definition_result.ok and ability_target_query != null and ability_target_query.has_method("targets_for_ability"):
		context["targets"] = ability_target_query.targets_for_ability(self, definition_result.definition, action_direction)
	var result: Dictionary = ability_runtime.cast(slot, context)
	if not result.ok:
		return false
	ability_cast.emit(result)
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
		var sprite_asset_id := _sprite_asset_id_for_facing()
		if sprite_asset_id == _current_sprite_asset_id:
			return
		var texture := asset_catalog.load_texture(sprite_asset_id)
		if texture != null:
			sprite.hframes = 1
			sprite.vframes = 1
			sprite.frame = 0
			sprite.texture = texture
			_current_sprite_asset_id = sprite_asset_id

func _update_sprite_animation(delta: float, allow_walk := true) -> void:
	if not _walk_animator_ready:
		_update_sprite_frame()
		return
	walk_animator.update(
		delta,
		_animation_direction_for_facing(),
		allow_walk and not velocity.is_zero_approx()
	)
	_current_sprite_asset_id = walk_animator.current_asset_id()

func _animation_direction_for_facing() -> String:
	match movement_state.facing:
		PlayerMovementState.Facing.UP:
			return "north"
		PlayerMovementState.Facing.LEFT:
			return "west"
		PlayerMovementState.Facing.RIGHT:
			return "east"
		_:
			return "south"

func _animation_direction_for_vector(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "east" if direction.x > 0.0 else "west"
	if direction.y < 0.0:
		return "north"
	return "south"

func _sprite_asset_id_for_facing() -> String:
	match movement_state.facing:
		PlayerMovementState.Facing.UP:
			return "fox_samurai_back_idle"
		PlayerMovementState.Facing.LEFT:
			return "fox_samurai_left_idle"
		PlayerMovementState.Facing.RIGHT:
			return "fox_samurai_right_idle"
		_:
			return "fox_samurai_front_idle"
