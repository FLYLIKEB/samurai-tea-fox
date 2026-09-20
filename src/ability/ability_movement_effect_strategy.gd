extends "res://src/ability/ability_effect_strategy.gd"
class_name AbilityMovementEffectStrategy

func execute(definition, context: Dictionary) -> Dictionary:
	var direction = context.get("direction", Vector2.ZERO)
	if direction is Vector2i:
		direction = Vector2(direction)
	if not direction is Vector2:
		return {"ok": false, "reason": "invalid_direction", "ability_id": definition.id}
	var normalized: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	var result := {
		"ok": true,
		"effect_type": "movement",
		"ability_id": definition.id,
		"distance_tiles": definition.range_tiles,
		"direction": normalized
	}
	var movement_actor = context.get("movement_actor")
	if movement_actor != null and movement_actor.has_method("apply_ability_movement"):
		var movement_result: Dictionary = movement_actor.apply_ability_movement(normalized, definition.range_tiles)
		if not movement_result.ok:
			movement_result["ability_id"] = definition.id
			return movement_result
		result.merge(movement_result, true)
	return result
