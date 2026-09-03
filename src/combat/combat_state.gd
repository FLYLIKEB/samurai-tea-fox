extends RefCounted
class_name CombatState

const CombatConfig = preload("res://src/combat/combat_config.gd")

const HIT_INVULNERABLE_REASON := "target_invulnerable"
const DUPLICATE_TARGET_REASON := "duplicate_target"

var config: CombatConfig
var combo_hit: int = 0
var swing_sequence: int = 0
var attack_cooldown_remaining: float = 0.0
var dodge_cooldown_remaining: float = 0.0
var dodge_invulnerability_remaining: float = 0.0

var _active_swings: Dictionary = {}
var _hit_invulnerability_remaining: Dictionary = {}

func _init(initial_config: CombatConfig) -> void:
	config = initial_config

func start_basic_attack(attacker_id: String, current_ki: float) -> Dictionary:
	if attack_cooldown_remaining > 0.0:
		return {"ok": false, "reason": "attack_on_cooldown", "cooldown_remaining": attack_cooldown_remaining}
	# Basic attacks are input-driven: every E press starts the next swing
	# immediately. Weapon speed remains exposed for animation/balance data, but
	# no longer throttles discrete player commands.
	attack_cooldown_remaining = 0.0
	combo_hit = (combo_hit % config.basic_attack_combo_hits) + 1
	swing_sequence += 1
	var swing_id := "basic_%d" % swing_sequence
	var is_finisher := combo_hit == config.basic_attack_combo_hits
	_active_swings[swing_id] = {}
	return {
		"ok": true,
		"swing_id": swing_id,
		"attacker_id": attacker_id,
		"weapon_id": config.weapon_id,
		"combo_hit": combo_hit,
		"combo_hits": config.basic_attack_combo_hits,
		"is_finisher": is_finisher,
		"damage": config.damage_for_ki(current_ki),
		"range_tiles": config.weapon_range_tiles,
		"attack_speed": config.weapon_attack_speed,
		"knockback_tiles": config.finisher_knockback_tiles if is_finisher else 0.0
	}

func apply_swing_hit(swing: Dictionary, target, hit_invulnerability_seconds := 0.0) -> Dictionary:
	var swing_id := String(swing.get("swing_id", ""))
	if swing_id == "" or not _active_swings.has(swing_id):
		return {"ok": false, "reason": "unknown_swing"}

	var target_id := _target_id(target)
	if target_id == "":
		return {"ok": false, "reason": "missing_target_id"}

	var hit_targets: Dictionary = _active_swings[swing_id]
	if hit_targets.has(target_id):
		return {"ok": false, "reason": DUPLICATE_TARGET_REASON, "target_id": target_id}
	if is_hit_invulnerable(target_id):
		return {"ok": false, "reason": HIT_INVULNERABLE_REASON, "target_id": target_id}

	hit_targets[target_id] = true
	var event := damage_event_payload(swing, target_id)
	var applied := _apply_damage_event(target, event)
	if hit_invulnerability_seconds > 0.0:
		set_hit_invulnerable(target_id, hit_invulnerability_seconds)
	return {"ok": true, "event": event, "applied_damage": applied}

func damage_event_payload(swing: Dictionary, target_id: String) -> Dictionary:
	return {
		"type": "damage",
		"source_id": String(swing.get("attacker_id", "")),
		"target_id": target_id,
		"weapon_id": String(swing.get("weapon_id", config.weapon_id)),
		"swing_id": String(swing.get("swing_id", "")),
		"combo_hit": int(swing.get("combo_hit", 0)),
		"combo_hits": int(swing.get("combo_hits", config.basic_attack_combo_hits)),
		"is_finisher": bool(swing.get("is_finisher", false)),
		"damage": int(swing.get("damage", 0)),
		"knockback_tiles": float(swing.get("knockback_tiles", 0.0)),
		"range_tiles": float(swing.get("range_tiles", config.weapon_range_tiles)),
		"attack_speed": float(swing.get("attack_speed", config.weapon_attack_speed)),
		"direction": swing.get("direction", Vector2.ZERO)
	}

func finish_swing(swing: Dictionary) -> void:
	_active_swings.erase(String(swing.get("swing_id", "")))

func set_hit_invulnerable(target_id: String, seconds: float) -> void:
	if seconds <= 0.0:
		_hit_invulnerability_remaining.erase(target_id)
		return
	_hit_invulnerability_remaining[target_id] = seconds

func is_hit_invulnerable(target_id: String) -> bool:
	return float(_hit_invulnerability_remaining.get(target_id, 0.0)) > 0.0

func start_dodge() -> Dictionary:
	if dodge_cooldown_remaining > 0.0:
		return {
			"ok": false,
			"reason": "dodge_on_cooldown",
			"cooldown_remaining": dodge_cooldown_remaining,
			"invulnerable": is_dodge_invulnerable()
		}
	dodge_cooldown_remaining = config.dodge_cooldown_seconds
	dodge_invulnerability_remaining = config.dodge_invulnerability_seconds
	return {
		"ok": true,
		"distance_tiles": config.dodge_distance_tiles,
		"cooldown_seconds": config.dodge_cooldown_seconds,
		"invulnerability_seconds": config.dodge_invulnerability_seconds
	}

func is_dodge_ready() -> bool:
	return dodge_cooldown_remaining <= 0.0

func is_dodge_invulnerable() -> bool:
	return dodge_invulnerability_remaining > 0.0

func tick(delta_seconds: float) -> void:
	var delta := maxf(delta_seconds, 0.0)
	attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta)
	dodge_cooldown_remaining = maxf(0.0, dodge_cooldown_remaining - delta)
	dodge_invulnerability_remaining = maxf(0.0, dodge_invulnerability_remaining - delta)
	for target_id in _hit_invulnerability_remaining.keys():
		var remaining := maxf(0.0, float(_hit_invulnerability_remaining[target_id]) - delta)
		if remaining <= 0.0:
			_hit_invulnerability_remaining.erase(target_id)
		else:
			_hit_invulnerability_remaining[target_id] = remaining

func _target_id(target) -> String:
	if typeof(target) == TYPE_DICTIONARY:
		return String(target.get("combat_id", target.get("id", "")))
	if target != null and target.has_method("get_combat_id"):
		return String(target.get_combat_id())
	return ""

func _apply_damage_event(target, event: Dictionary) -> int:
	if target != null and typeof(target) != TYPE_DICTIONARY and target.has_method("apply_damage_event"):
		return int(target.apply_damage_event(event))
	return int(event.damage)
