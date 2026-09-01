extends "res://src/enemy/behavior/monster_behavior_strategy.gd"

func decide(observation: Dictionary) -> Dictionary:
	if bool(observation.get("in_attack_range", false)):
		return {"action": "attack", "state": "rare_action", "attack_kind": "rare"}
	return {"action": "approach", "state": "pursue", "reason": "approach"}
