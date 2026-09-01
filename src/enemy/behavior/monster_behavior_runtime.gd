extends RefCounted
class_name MonsterBehaviorRuntime

const STRATEGY_SCRIPTS := {
	"근접": preload("res://src/enemy/behavior/melee_behavior_strategy.gd"),
	"돌진": preload("res://src/enemy/behavior/charge_behavior_strategy.gd"),
	"원거리": preload("res://src/enemy/behavior/ranged_behavior_strategy.gd"),
	"방해": preload("res://src/enemy/behavior/disruptor_behavior_strategy.gd"),
	"희귀": preload("res://src/enemy/behavior/rare_behavior_strategy.gd")
}

var actor_id: String
var behavior_type: String
var target_id := ""
var state := "idle"
var attack: int
var attack_period_seconds: float
var movement_speed: float

var _strategy
var _attack_cooldown_remaining := 0.0
var _stagger_remaining := 0.0

func _init(definition, initial_actor_id: String) -> void:
	actor_id = initial_actor_id
	behavior_type = definition.behavior_type
	attack = definition.attack
	attack_period_seconds = definition.attack_period_seconds
	movement_speed = definition.movement_speed
	_strategy = STRATEGY_SCRIPTS[behavior_type].new()

func tick(delta_seconds: float, observation: Dictionary, world_data) -> Dictionary:
	var elapsed := maxf(delta_seconds, 0.0)
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - elapsed, 0.0)
	_stagger_remaining = maxf(_stagger_remaining - elapsed, 0.0)
	if _stagger_remaining > 0.0:
		state = "staggered"
		return _idle("staggered")

	if not bool(observation.get("detected", false)):
		target_id = ""
		state = "idle"
		_strategy.reset()
		return _idle("target_lost")

	target_id = String(observation.get("target_id", ""))
	if target_id == "":
		state = "idle"
		_strategy.reset()
		return _idle("target_lost")

	var decision: Dictionary = _strategy.decide(observation)
	state = String(decision.get("state", "idle"))
	match String(decision.get("action", "idle")):
		"attack":
			return _attack_command(String(decision.get("attack_kind", "melee")))
		"approach":
			return _navigation_command(observation, world_data, false, String(decision.get("reason", "approach")))
		"retreat":
			return _navigation_command(observation, world_data, true, String(decision.get("reason", "keep_range")))
		"wait":
			return _idle(String(decision.get("reason", "waiting")))
		_:
			return _idle(String(decision.get("reason", "idle")))

func interrupt_for_stagger(duration_seconds: float) -> void:
	_stagger_remaining = maxf(_stagger_remaining, maxf(duration_seconds, 0.0))
	_strategy.reset()

func on_staggered(event: Dictionary, _applied_stagger: float) -> void:
	interrupt_for_stagger(float(event.get("stagger_duration_seconds", 0.0)))

func to_dictionary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"behavior_type": behavior_type,
		"target_id": target_id,
		"state": state,
		"attack_cooldown_remaining": _attack_cooldown_remaining,
		"stagger_remaining": _stagger_remaining
	}

func _attack_command(attack_kind: String) -> Dictionary:
	if _attack_cooldown_remaining > 0.0:
		state = "cooldown"
		return _idle("attack_cooldown")
	_attack_cooldown_remaining = attack_period_seconds
	return {
		"type": "attack",
		"actor_id": actor_id,
		"target_id": target_id,
		"damage": attack,
		"attack_kind": attack_kind
	}

func _navigation_command(observation: Dictionary, world_data, retreat: bool, reason: String) -> Dictionary:
	var from_cell: Vector2i = observation.get("self_cell", Vector2i.ZERO)
	var target_cell: Vector2i = observation.get("target_cell", from_cell)
	var direction := _cardinal_direction(target_cell - from_cell)
	if retreat:
		direction = -direction
	var to_cell := from_cell + direction
	if direction == Vector2i.ZERO or world_data == null or not world_data.is_walkable(to_cell):
		state = "idle"
		return _idle("blocked")
	return {
		"type": "navigate",
		"actor_id": actor_id,
		"target_id": target_id,
		"from_cell": from_cell,
		"to_cell": to_cell,
		"direction": direction,
		"speed": movement_speed,
		"reason": reason
	}

func _cardinal_direction(offset: Vector2i) -> Vector2i:
	if absi(offset.x) >= absi(offset.y) and offset.x != 0:
		return Vector2i(signi(offset.x), 0)
	if offset.y != 0:
		return Vector2i(0, signi(offset.y))
	return Vector2i.ZERO

func _idle(reason: String) -> Dictionary:
	return {"type": "idle", "actor_id": actor_id, "target_id": target_id, "reason": reason}
