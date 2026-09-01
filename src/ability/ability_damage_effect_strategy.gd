extends "res://src/ability/ability_effect_strategy.gd"
class_name AbilityDamageEffectStrategy

func execute(definition, context: Dictionary) -> Dictionary:
	var targets: Array = context.get("targets", [])
	if targets.is_empty():
		return {"ok": false, "reason": "missing_targets", "ability_id": definition.id}

	var events: Array = []
	var applied_damage := 0
	for target in targets:
		var target_id := _target_id(target)
		if target_id == "":
			return {"ok": false, "reason": "missing_target_id", "ability_id": definition.id}
		var event := {
			"type": "ability_damage",
			"source_id": String(context.get("source_id", "")),
			"target_id": target_id,
			"ability_id": definition.id,
			"damage": definition.base_damage,
			"range_tiles": definition.range_tiles,
			"direction": context.get("direction", Vector2.ZERO),
			"status_effect": definition.status_effect
		}
		events.append(event)
		if target != null and typeof(target) != TYPE_DICTIONARY and target.has_method("apply_damage_event"):
			applied_damage += int(target.apply_damage_event(event))
		else:
			applied_damage += int(event.damage)

	return {
		"ok": true,
		"effect_type": "damage",
		"ability_id": definition.id,
		"events": events,
		"applied_damage": applied_damage
	}

func _target_id(target) -> String:
	if typeof(target) == TYPE_DICTIONARY:
		return String(target.get("combat_id", target.get("id", "")))
	if target != null and target.has_method("get_combat_id"):
		return String(target.get_combat_id())
	return ""
