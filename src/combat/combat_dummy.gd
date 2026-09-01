extends CharacterBody2D
class_name CombatDummy

const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const TILE_SIZE_PIXELS := 32.0

signal damaged(event: Dictionary, applied_damage: int)
signal defeated()
signal monster_defeated(event: Dictionary)
signal defeat_event(event: Dictionary)
signal drop_requested(event: Dictionary)

@export var monster_id := "road_bandit"
@export var automatic_attacks := true
@export_range(1.0, 128.0, 1.0) var attack_range_pixels := 40.0

var combatant
var target
var attack_period_seconds := 0.0
var hit_invulnerability_seconds := 0.0
var _attack_cooldown_remaining := 0.0
var _attack_sequence := 0
var _pending_knockback := Vector2.ZERO

@onready var health_fill: Polygon2D = $HealthFill

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

func _physics_process(delta: float) -> void:
	if _pending_knockback != Vector2.ZERO:
		move_and_collide(_pending_knockback)
		_pending_knockback = Vector2.ZERO
	if not automatic_attacks or combatant == null or target == null:
		return
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if _attack_cooldown_remaining <= 0.0 and global_position.distance_to(target.global_position) <= attack_range_pixels:
		attack_target(target, hit_invulnerability_seconds)
		_attack_cooldown_remaining = attack_period_seconds

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

func _on_monster_defeated(event: Dictionary) -> void:
	defeated.emit()
	monster_defeated.emit(event)
	defeat_event.emit(event)

func _on_monster_drop_requested(event: Dictionary) -> void:
	drop_requested.emit(event)
