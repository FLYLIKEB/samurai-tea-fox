extends CharacterBody2D
class_name CombatDummy

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DirectionalWalkAnimator = preload("res://src/presentation/directional_walk_animator.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
static var TILE_SIZE_PIXELS := RuntimeConstants.float_value("world.tile_size_pixels")
static var HIT_FLASH_SECONDS := RuntimeConstants.float_value("combat.hit_flash_seconds")
const HIT_FLASH_COLOR := Color(1.0, 0.26, 0.18, 1.0)
const DAMAGE_POPUP_FONT := "res://assets/fonts/galmuri/Galmuri11.ttf"
const DAMAGE_POPUP_COLOR := Color(1.0, 0.10, 0.07, 1.0)
static var DAMAGE_POPUP_SECONDS := RuntimeConstants.float_value("combat.damage_popup_seconds")
static var DAMAGE_POPUP_RISE_PIXELS := RuntimeConstants.float_value("combat.damage_popup_rise_pixels")
static var GRID_STEP_TWEEN_SECONDS := RuntimeConstants.float_value("combat.grid_step_tween_seconds")
const DUMMY_CHARACTER_ID := ""
const IDLE_ASSET_IDS := {}

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
@export var sprite_asset_id := ""
@export var automatic_attacks := true
@export_range(1.0, 128.0, 1.0) var attack_range_pixels := RuntimeConstants.float_value("combat.attack_range_pixels")

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
var _grid_step_active := false
var _grid_step_tween: Tween
var _damage_popup: Label
var _damage_popup_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D
@onready var body: Polygon2D = $Body
@onready var headband: Polygon2D = $Headband
@onready var health_fill: Polygon2D = $HealthFill

func _ready() -> void:
	_ensure_damage_popup()
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

func configure_grid_navigation(world_data = null, world_origin := Vector2.ZERO, tile_size := -1.0) -> void:
	_grid_world_data = world_data
	_grid_world_origin = world_origin
	_grid_tile_size = maxf(TILE_SIZE_PIXELS if tile_size < 0.0 else tile_size, 1.0)
	_snap_to_grid_center()

func suspend_for_world_transition() -> Dictionary:
	var state := {
		"visible": visible,
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
		"automatic_attacks": automatic_attacks,
		"target": target
	}
	deactivate_runtime()
	return state

func restore_after_world_transition(state: Dictionary) -> void:
	_stop_runtime_motion()
	visible = bool(state.get("visible", true))
	collision_layer = int(state.get("collision_layer", 2))
	collision_mask = int(state.get("collision_mask", 1))
	automatic_attacks = bool(state.get("automatic_attacks", true))
	target = state.get("target", null)

func deactivate_runtime() -> void:
	_stop_runtime_motion()
	target = null
	automatic_attacks = false
	visible = false
	collision_layer = 0
	collision_mask = 0

func _stop_runtime_motion() -> void:
	velocity = Vector2.ZERO
	_pending_knockback = Vector2.ZERO
	if _grid_step_tween != null and _grid_step_tween.is_valid():
		_grid_step_tween.kill()
	_grid_step_tween = null
	_grid_step_active = false

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
		_show_damage_popup(applied)
		damaged.emit(event, applied)
		_update_health_bar()
	return applied

func _ensure_damage_popup() -> Label:
	if _damage_popup != null and is_instance_valid(_damage_popup):
		return _damage_popup
	_damage_popup = Label.new()
	_damage_popup.name = "DamagePopup"
	_damage_popup.position = Vector2(-20.0, -34.0)
	_damage_popup.size = Vector2(40.0, 16.0)
	_damage_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var popup_font := ResourceLoader.load(DAMAGE_POPUP_FONT) as Font
	if popup_font is FontFile:
		var font_file := popup_font as FontFile
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if popup_font != null:
		_damage_popup.add_theme_font_override("font", popup_font)
	_damage_popup.add_theme_font_size_override("font_size", 13)
	_damage_popup.add_theme_color_override("font_color", DAMAGE_POPUP_COLOR)
	_damage_popup.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.04, 1.0))
	_damage_popup.add_theme_color_override("font_shadow_color", Color(0.16, 0.02, 0.01, 0.95))
	_damage_popup.add_theme_constant_override("outline_size", 1)
	_damage_popup.add_theme_constant_override("shadow_offset_x", 2)
	_damage_popup.add_theme_constant_override("shadow_offset_y", 2)
	_damage_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_popup.z_index = 10
	_damage_popup.visible = false
	add_child(_damage_popup)
	return _damage_popup

func _show_damage_popup(applied_damage: int) -> void:
	if applied_damage <= 0:
		return
	var popup := _ensure_damage_popup()
	if _damage_popup_tween != null and _damage_popup_tween.is_valid():
		_damage_popup_tween.kill()
	popup.text = "-%d" % applied_damage
	popup.position = Vector2(-20.0, -34.0)
	popup.modulate = Color.WHITE
	popup.visible = true
	if not is_inside_tree():
		return
	_damage_popup_tween = create_tween().set_parallel(true)
	_damage_popup_tween.tween_property(popup, "position:y", popup.position.y - DAMAGE_POPUP_RISE_PIXELS, DAMAGE_POPUP_SECONDS)
	_damage_popup_tween.tween_property(popup, "modulate:a", 0.0, DAMAGE_POPUP_SECONDS).set_delay(0.25)
	_damage_popup_tween.chain().tween_callback(func(): popup.visible = false)

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

func is_grid_step_active() -> bool:
	return _grid_step_active

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
	if sprite == null:
		return
	var asset_catalog := AssetCatalog.new()
	var manifest_result := asset_catalog.load_manifest()
	if not manifest_result.ok:
		push_warning("Combat dummy sprite manifest failed: %s" % manifest_result.get("error", "unknown error"))
		return
	var resolved_sprite_asset_id := _resolve_sprite_asset_id(asset_catalog)
	if resolved_sprite_asset_id.is_empty():
		push_warning("Combat dummy sprite missing: %s (monster=%s)" % [sprite_asset_id, monster_id])
		return
	var texture := asset_catalog.load_texture(resolved_sprite_asset_id)
	if texture == null:
		push_warning("Combat dummy sprite missing: %s" % resolved_sprite_asset_id)
		return
	sprite.texture = texture
	sprite.z_index = 1
	# Overworld enemies can override with explicit sprite ids; otherwise this uses
	# the monster-specific "monster_<id>_front_idle" sprite if present.
	# Do not configure the boss-character directional animator here: its fallback
	# character mapping would replace the selected monster texture with a king NPC.
	_walk_animator_ready = false
	_hide_placeholder_shapes()

func _resolve_sprite_asset_id(asset_catalog: AssetCatalog) -> String:
	if not sprite_asset_id.is_empty():
		if sprite_asset_id != "monster_foxfire_front_idle" and asset_catalog.has(sprite_asset_id):
			return sprite_asset_id

	var monster_sprite_asset_id := "monster_%s_front_idle" % monster_id
	if asset_catalog.has(monster_sprite_asset_id):
		return monster_sprite_asset_id

	if not sprite_asset_id.is_empty() and asset_catalog.has(sprite_asset_id):
		return sprite_asset_id
	return ""

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
	# Probe the full step without moving the body; visual movement is performed by
	# the tween below so the enemy never snaps to the destination first.
	var collision := move_and_collide(_grid_target_position - _grid_source_position, true)
	if collision != null:
		global_position = _grid_source_position
		_update_walk_animation(direction, false)
		grid_step_blocked.emit(_grid_source_cell, _grid_cell_for_position(_grid_target_position))
		return false
	_update_walk_animation(direction, true)
	_grid_step_active = true
	if _grid_step_tween != null and _grid_step_tween.is_valid():
		_grid_step_tween.kill()
	_grid_step_tween = create_tween()
	_grid_step_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_grid_step_tween.tween_property(self, "global_position", _grid_target_position, GRID_STEP_TWEEN_SECONDS)
	_grid_step_tween.tween_callback(_finish_grid_step_tween)
	return true

func _finish_grid_step_tween() -> void:
	_grid_step_active = false
	_update_walk_animation(
		Vector2i(int(round(_grid_step_direction.x)), int(round(_grid_step_direction.y))),
		false,
	)
	grid_step_finished.emit(_grid_cell_for_position(global_position))

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
