extends "res://src/enemy/behavior/monster_behavior_strategy.gd"

func decide(observation: Dictionary) -> Dictionary:
	if bool(observation.get("too_close", false)):
		return {"action": "retreat", "state": "reposition", "reason": "keep_range"}
	if bool(observation.get("in_attack_range", false)):
		return {"action": "attack", "state": "attack", "attack_kind": "ranged"}
	return {"action": "approach", "state": "pursue", "reason": "approach"}
