extends "res://src/ability/ability_effect_strategy.gd"
class_name AbilityMovementEffectStrategy

func execute(definition, context: Dictionary) -> Dictionary:
	var direction = context.get("direction", Vector2.ZERO)
	if direction is Vector2i:
		direction = Vector2(direction)
	if not direction is Vector2:
		return {"ok": false, "reason": "invalid_direction", "ability_id": definition.id}
	var normalized: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	return {
		"ok": true,
		"effect_type": "movement",
		"ability_id": definition.id,
		"distance_tiles": definition.range_tiles,
		"direction": normalized
	}
