extends CharacterBody2D
class_name CombatDummy

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DirectionalWalkAnimator = preload("res://src/presentation/directional_walk_animator.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const TILE_SIZE_PIXELS := 32.0
const HIT_FLASH_SECONDS := 0.16
const HIT_FLASH_COLOR := Color(1.0, 0.26, 0.18, 1.0)
const DUMMY_CHARACTER_ID := "CHR-2"
const IDLE_ASSET_IDS := {
	"south": "wasteland_daimyo_front_idle",
	"west": "asset_assets_sprites_characters_bosses_chr_2_wasteland_daimyo_wasteland_daimyo_left_32x32_png",
	"east": "asset_assets_sprites_characters_bosses_chr_2_wasteland_daimyo_wasteland_daimyo_right_32x32_png",
	"north": "asset_assets_sprites_characters_bosses_chr_2_wasteland_daimyo_wasteland_daimyo_back_32x32_png"
}

signal damaged(event: Dictionary, applied_damage: int)
signal defeated()
signal monster_defeated(event: Dictionary)
signal defeat_event(event: Dictionary)
signal drop_requested(event: Dictionary)
signal grid_step_started(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_blocked(from_cell: Vector2i, to_cell: Vector2i)
signal grid_step_finished(cell: Vector2i)
signal turn_finished(result: Dictionary)

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
var _grid_world_data = null
var _grid_world_origin := Vector2.ZERO
var _grid_tile_size := TILE_SIZE_PIXELS
var walk_animator := DirectionalWalkAnimator.new()
var _walk_animator_ready := false

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

func configure_grid_navigation(world_data = null, world_origin := Vector2.ZERO, tile_size := TILE_SIZE_PIXELS) -> void:
	_grid_world_data = world_data
	_grid_world_origin = world_origin
	_grid_tile_size = maxf(tile_size, 1.0)
	_snap_to_grid_center()

func has_runtime_sprite() -> bool:
	return sprite != null and sprite.texture != null

func _physics_process(delta: float) -> void:
	_update_hit_effect(delta)
	if combatant == null or target == null:
		return

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
			_apply_grid_knockback(direction.normalized(), int(round(knockback_tiles)))
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

func take_turn(turn_target = null) -> Dictionary:
	if combatant == null or combatant.is_defeated():
		var defeated_result := {"ok": false, "reason": "defeated"}
		turn_finished.emit(defeated_result.duplicate(true))
		return defeated_result
	var resolved_target = turn_target if turn_target != null else target
	if resolved_target == null:
		_snap_to_grid_center()
		var waiting_result := {"ok": true, "action": "wait", "cell": _grid_cell_for_position(global_position)}
		turn_finished.emit(waiting_result.duplicate(true))
		return waiting_result
	target = resolved_target
	_snap_to_grid_center()
	if global_position.distance_to(resolved_target.global_position) <= attack_range_pixels:
		var applied := attack_target(resolved_target, hit_invulnerability_seconds)
		var attack_result := {"ok": true, "action": "attack", "applied_damage": applied, "cell": _grid_cell_for_position(global_position)}
		turn_finished.emit(attack_result.duplicate(true))
		return attack_result
	var moved := _move_one_grid_cell_toward(resolved_target.global_position)
	var move_result := {
		"ok": true,
		"action": "move" if moved else "wait",
		"cell": _grid_cell_for_position(global_position)
	}
	turn_finished.emit(move_result.duplicate(true))
	return move_result

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
	var animation_result := walk_animator.configure_for_character(sprite, asset_catalog, DUMMY_CHARACTER_ID, IDLE_ASSET_IDS)
	if animation_result.ok:
		_walk_animator_ready = true
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

func _move_one_grid_cell_toward(target_position: Vector2) -> bool:
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
	grid_step_started.emit(from_cell, to_cell)
	var collision := move_and_collide(_grid_target_position - _grid_source_position)
	if collision != null:
		global_position = _grid_source_position
		_update_walk_animation(direction, false)
		grid_step_blocked.emit(_grid_source_cell, _grid_cell_for_position(_grid_target_position))
		return false
	_update_walk_animation(direction, true)
	global_position = _grid_target_position
	_update_walk_animation(direction, false)
	grid_step_finished.emit(_grid_cell_for_position(global_position))
	return true

func _apply_grid_knockback(direction: Vector2, tile_count: int) -> bool:
	if tile_count <= 0:
		_snap_to_grid_center()
		return false
	_snap_to_grid_center()
	var from_cell := _grid_cell_for_position(global_position)
	var step := _cardinal_direction(Vector2i(int(round(direction.x)), int(round(direction.y))))
	if step == Vector2i.ZERO:
		return false
	var to_cell := from_cell + step * tile_count
	var source_position := _grid_position_for_cell_center(from_cell)
	var target_position := _grid_position_for_cell_center(to_cell)
	var collision := move_and_collide(target_position - source_position)
	if collision != null:
		global_position = source_position
		return false
	global_position = target_position
	return true

func _snap_to_grid_center() -> void:
	global_position = _grid_position_for_cell_center(_grid_cell_for_position(global_position))

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

func _cardinal_direction(offset: Vector2i) -> Vector2i:
	if absi(offset.x) >= absi(offset.y) and offset.x != 0:
		return Vector2i(signi(offset.x), 0)
	if offset.y != 0:
		return Vector2i(0, signi(offset.y))
	return Vector2i.ZERO

func _update_walk_animation(direction: Vector2i, moving: bool) -> void:
	if not _walk_animator_ready:
		return
	walk_animator.update(1.0 / 8.0, _direction_name(direction), moving)

func _direction_name(direction: Vector2i) -> String:
	if direction == Vector2i.UP:
		return "north"
	if direction == Vector2i.LEFT:
		return "west"
	if direction == Vector2i.RIGHT:
		return "east"
	return "south"

func _on_monster_defeated(event: Dictionary) -> void:
	defeated.emit()
	monster_defeated.emit(event)
	defeat_event.emit(event)

func _on_monster_drop_requested(event: Dictionary) -> void:
	drop_requested.emit(event)
