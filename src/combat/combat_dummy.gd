extends CharacterBody2D
class_name CombatDummy

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const TILE_SIZE_PIXELS := 32.0
const HIT_FLASH_SECONDS := 0.16
const HIT_FLASH_COLOR := Color(1.0, 0.26, 0.18, 1.0)

signal damaged(event: Dictionary, applied_damage: int)
signal defeated()
signal monster_defeated(event: Dictionary)
signal defeat_event(event: Dictionary)
signal drop_requested(event: Dictionary)
signal grid_step_started(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_blocked(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_finished(cell: Vector2i)

@export var monster_id := "road_bandit"
@export var sprite_asset_id := "wasteland_daimyo_front_idle"
@export var automatic_attacks := true
@export_range(1.0, 128.0, 1.0) var attack_range_pixels := 40.0

var combatant
var target
var attack_period_seconds := 0.0
var hit_invulnerability_seconds := 0.0
var _attack_cooldown_remaining := 0.0
var _attack_sequence := 0
var _pending_knockback := Vector2.ZERO
var _hit_effect_remaining := 0.0
var _grid_target_position := Vector2.ZERO
var _grid_source_position := Vector2.ZERO
var _grid_source_cell := Vector2i.ZERO
var _grid_step_direction := Vector2.ZERO
var _grid_moving := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var body: Polygon2D = $Body
@onready var headband: Polygon2D = $Headband
@onready var health_fill: Polygon2D = $HealthFill

func _ready() -> void:
	_apply_sprite()

func configure_combat(catalog, attack_target = null, config = null) -> Dictionary:
	var result: Dictionary = MonsterSpawnFactory.new(catalog).spawn(monster_id, {"combat_id": "%s_%d" % [monster_id, get_instance_id()]})
	if not result.ok:
		return result
	combatant = result.monster
	combatant.defeated.connect(_on_monster_defeated)
	combatant.drop_requested.connect(_on_monster_drop_requested)
	attack_period_seconds = combatant.attack_period_seconds
	if config == null:
		return {"ok": false, "error": "Combat config is required for dummy hit invulnerability"}
	hit_invulnerability_seconds = config.hit_invulnerability_seconds
	_attack_cooldown_remaining = attack_period_seconds
	target = attack_target
	_update_health_bar()
	return {"ok": true}

func has_runtime_sprite() -> bool:
	return sprite != null and sprite.texture != null

func _physics_process(delta: float) -> void:
	_update_hit_effect(delta)
	if _pending_knockback != Vector2.ZERO:
		move_and_collide(_pending_knockback)
		_pending_knockback = Vector2.ZERO
	if not automatic_attacks or combatant == null or target == null:
		return
	if _grid_moving:
		_advance_grid_step(delta)
		return
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if _attack_cooldown_remaining <= 0.0 and global_position.distance_to(target.global_position) <= attack_range_pixels:
		attack_target(target, hit_invulnerability_seconds)
		_attack_cooldown_remaining = attack_period_seconds
	elif global_position.distance_to(target.global_position) > attack_range_pixels:
		_start_grid_step_toward(target.global_position)

func get_combat_id() -> String:
	return combatant.get_combat_id() if combatant != null else ""

func apply_damage_event(event: Dictionary) -> int:
	if combatant == null:
		return 0
	var applied: int = combatant.apply_damage_event(event)
	if applied > 0:
		var knockback_tiles := maxf(float(event.get("knockback_tiles", 0.0)), 0.0)
		var direction = event.get("direction", Vector2.ZERO)
		if knockback_tiles > 0.0 and direction is Vector2 and direction != Vector2.ZERO:
			_pending_knockback = direction.normalized() * knockback_tiles * TILE_SIZE_PIXELS
		_start_hit_effect()
		damaged.emit(event, applied)
		_update_health_bar()
	return applied

func attack_target(attack_target, hit_invulnerability_seconds := 0.0) -> int:
	if combatant == null or attack_target == null or not attack_target.has_method("apply_damage_event"):
		return 0
	_attack_sequence += 1
	return int(attack_target.apply_damage_event({
		"type": "damage",
		"source_id": get_combat_id(),
		"target_id": attack_target.get_combat_id() if attack_target.has_method("get_combat_id") else "",
		"swing_id": "%s_attack_%d" % [get_combat_id(), _attack_sequence],
		"damage": combatant.attack,
		"hit_invulnerability_seconds": maxf(hit_invulnerability_seconds, 0.0)
	}))

func current_hp() -> int:
	return combatant.hp if combatant != null else 0

func received_hit_count() -> int:
	return combatant.received_damage_events.size() if combatant != null else 0

func _update_health_bar() -> void:
	if health_fill == null or combatant == null:
		return
	var ratio := float(combatant.hp) / float(combatant.hp_max)
	health_fill.scale.x = ratio
	health_fill.position.x = -7.0 + 7.0 * ratio

func _apply_sprite() -> void:
	if sprite == null or sprite_asset_id.is_empty():
		return
	var asset_catalog := AssetCatalog.new()
	var manifest_result := asset_catalog.load_manifest()
	if not manifest_result.ok:
		push_warning("Combat dummy sprite manifest failed: %s" % manifest_result.get("error", "unknown error"))
		return
	var texture := asset_catalog.load_texture(sprite_asset_id)
	if texture == null:
		push_warning("Combat dummy sprite missing: %s" % sprite_asset_id)
		return
	sprite.texture = texture
	sprite.z_index = 1
	_hide_placeholder_shapes()

func _hide_placeholder_shapes() -> void:
	if body != null:
		body.visible = false
	if headband != null:
		headband.visible = false

func _start_hit_effect() -> void:
	_hit_effect_remaining = HIT_FLASH_SECONDS
	if sprite != null:
		sprite.modulate = HIT_FLASH_COLOR
		sprite.scale = Vector2(1.18, 1.18)
	if body != null:
		body.color = HIT_FLASH_COLOR

func _update_hit_effect(delta: float) -> void:
	if _hit_effect_remaining <= 0.0:
		return
	_hit_effect_remaining = maxf(0.0, _hit_effect_remaining - maxf(delta, 0.0))
	if _hit_effect_remaining > 0.0:
		var pulse := 1.0 + 0.18 * (_hit_effect_remaining / HIT_FLASH_SECONDS)
		if sprite != null:
			sprite.modulate = HIT_FLASH_COLOR
			sprite.scale = Vector2(pulse, pulse)
		return
	if sprite != null:
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE
	if body != null:
		body.color = Color(0.45, 0.23, 0.19, 1)

func _start_grid_step_toward(target_position: Vector2) -> bool:
	var from_cell := _grid_cell_for_position(global_position)
	var target_cell := _grid_cell_for_position(target_position)
	var direction := _cardinal_direction(target_cell - from_cell)
	if direction == Vector2i.ZERO:
		return false
	var to_cell := from_cell + direction
	_grid_source_cell = from_cell
	_grid_source_position = _grid_position_for_cell_center(from_cell)
	_grid_target_position = _grid_position_for_cell_center(to_cell)
	_grid_step_direction = Vector2(direction)
	_grid_moving = true
	grid_step_started.emit(from_cell, to_cell)
	return true

func _advance_grid_step(delta: float) -> void:
	var speed_pixels := maxf(float(combatant.movement_speed) * TILE_SIZE_PIXELS, TILE_SIZE_PIXELS) if combatant != null else TILE_SIZE_PIXELS
	var remaining := _grid_target_position - global_position
	var distance := remaining.length()
	if distance <= 0.01:
		_finish_grid_step()
		return
	var motion := _grid_step_direction * minf(speed_pixels * maxf(delta, 0.0), distance)
	var collision := move_and_collide(motion)
	if collision != null:
		global_position = _grid_source_position
		_grid_moving = false
		grid_step_blocked.emit(_grid_source_cell, _grid_cell_for_position(_grid_target_position))
		return
	if global_position.distance_to(_grid_target_position) <= 0.5:
		global_position = _grid_target_position
		_finish_grid_step()

func _finish_grid_step() -> void:
	_grid_moving = false
	grid_step_finished.emit(_grid_cell_for_position(global_position))

func _grid_cell_for_position(world_position: Vector2) -> Vector2i:
	return Vector2i(int(round(world_position.x / TILE_SIZE_PIXELS)), int(round(world_position.y / TILE_SIZE_PIXELS)))

func _grid_position_for_cell_center(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) * TILE_SIZE_PIXELS, float(cell.y) * TILE_SIZE_PIXELS)

func _cardinal_direction(offset: Vector2i) -> Vector2i:
	if absi(offset.x) >= absi(offset.y) and offset.x != 0:
		return Vector2i(signi(offset.x), 0)
	if offset.y != 0:
		return Vector2i(0, signi(offset.y))
	return Vector2i.ZERO

func _on_monster_defeated(event: Dictionary) -> void:
	defeated.emit()
	monster_defeated.emit(event)
	defeat_event.emit(event)

func _on_monster_drop_requested(event: Dictionary) -> void:
	drop_requested.emit(event)
