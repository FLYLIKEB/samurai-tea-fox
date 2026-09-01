extends "res://src/enemy/behavior/monster_behavior_strategy.gd"

var _winding_up := false

func decide(observation: Dictionary) -> Dictionary:
	if _winding_up:
		if bool(observation.get("windup_complete", false)):
			_winding_up = false
			return {"action": "approach", "state": "charge", "reason": "charge"}
		return {"action": "wait", "state": "windup", "reason": "charge_windup"}
	if bool(observation.get("charge_opportunity", false)):
		_winding_up = true
		return {"action": "wait", "state": "windup", "reason": "charge_windup"}
	if bool(observation.get("in_attack_range", false)):
		return {"action": "attack", "state": "attack", "attack_kind": "charge_melee"}
	return {"action": "approach", "state": "pursue", "reason": "approach"}

func reset() -> void:
	_winding_up = false
