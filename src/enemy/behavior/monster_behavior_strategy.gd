extends RefCounted
class_name MonsterBehaviorStrategy

func decide(observation: Dictionary) -> Dictionary:
	return {"action": "idle", "state": "idle", "reason": "no_strategy"}

func reset() -> void:
	pass
