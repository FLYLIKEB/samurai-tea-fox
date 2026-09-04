extends RefCounted
class_name AbilityRuntime

const AbilityDefinition = preload("res://src/ability/ability_definition.gd")
const AbilityDamageEffectStrategy = preload("res://src/ability/ability_damage_effect_strategy.gd")
const AbilityMovementEffectStrategy = preload("res://src/ability/ability_movement_effect_strategy.gd")

const ABILITY_EQUIP_SLOTS_ID := "ability_equip_slots"

signal ability_equipped(slot: int, ability_id: String)
signal ability_cast(result: Dictionary)

var definitions: Dictionary = {}
var equip_slots: Array[String] = []
var cooldown_remaining: Dictionary = {}
var _strategies: Dictionary = {}

func _init(initial_definitions := {}, equip_slot_count := 0) -> void:
	definitions = initial_definitions.duplicate()
	equip_slots.resize(maxi(int(equip_slot_count), 0))
	for index in equip_slots.size():
		equip_slots[index] = ""
	_register_default_strategies()

static func from_catalog(catalog) -> Dictionary:
	var slot_value := _required_balance_value(catalog, ABILITY_EQUIP_SLOTS_ID)
	if not slot_value.ok:
		return slot_value
	if float(slot_value.value) != floor(float(slot_value.value)) or int(slot_value.value) < 0:
		return {"ok": false, "error": "Ability equip slot count must be a non-negative integer"}

	var loaded_definitions := {}
	for item in catalog.get_definitions("abilities"):
		var definition_result: Dictionary = AbilityDefinition.from_dictionary(item)
		if not definition_result.ok:
			return definition_result
		var definition: AbilityDefinition = definition_result.definition
		loaded_definitions[definition.id] = definition

	return {
		"ok": true,
		"runtime": load("res://src/ability/ability_runtime.gd").new(loaded_definitions, int(slot_value.value))
	}

func equip(slot: int, ability_id: String, context := {}) -> Dictionary:
	if slot < 0 or slot >= equip_slots.size():
		return {"ok": false, "reason": "invalid_slot", "slot": slot}
	if not definitions.has(ability_id):
		return {"ok": false, "reason": "unknown_ability", "ability_id": ability_id}
	var definition: AbilityDefinition = definitions[ability_id]
	var tail_check := _tail_condition_result(definition, context)
	if not tail_check.ok:
		return tail_check
	equip_slots[slot] = ability_id
	ability_equipped.emit(slot, ability_id)
	return {"ok": true, "slot": slot, "ability_id": ability_id}

func can_cast(slot: int, context: Dictionary) -> Dictionary:
	var ability_result := _ability_for_slot(slot)
	if not ability_result.ok:
		return ability_result
	var definition: AbilityDefinition = ability_result.definition
	if not _strategies.has(definition.type):
		return {"ok": false, "reason": "unsupported_effect_type", "ability_id": definition.id, "effect_type": definition.type}

	var tail_check := _tail_condition_result(definition, context)
	if not tail_check.ok:
		return tail_check

	var resources = context.get("resources")
	if resources == null:
		return {"ok": false, "reason": "missing_resources", "ability_id": definition.id}
	if int(resources.kokoro) <= 0:
		return {"ok": false, "reason": "kokoro_depleted", "ability_id": definition.id}

	var remaining := float(cooldown_remaining.get(definition.id, 0.0))
	if remaining > 0.0:
		return {"ok": false, "reason": "ability_on_cooldown", "ability_id": definition.id, "cooldown_remaining": remaining}

	var final_cost := effective_ki_cost(definition, context)
	if int(resources.ki) < final_cost:
		return {"ok": false, "reason": "insufficient_ki", "ability_id": definition.id, "ki_cost": final_cost, "current_ki": int(resources.ki)}

	return {"ok": true, "definition": definition, "ki_cost": final_cost}

func cast(slot: int, context: Dictionary) -> Dictionary:
	var cast_check := can_cast(slot, context)
	if not cast_check.ok:
		return cast_check
	var definition: AbilityDefinition = cast_check.definition
	var resources = context.resources
	if not resources.spend_ki(int(cast_check.ki_cost)):
		return {"ok": false, "reason": "insufficient_ki", "ability_id": definition.id, "ki_cost": int(cast_check.ki_cost), "current_ki": int(resources.ki)}

	var strategy = _strategies[definition.type]
	var effect_result: Dictionary = strategy.execute(definition, context)
	if not effect_result.ok:
		resources.recover_ki(int(cast_check.ki_cost))
		return effect_result

	cooldown_remaining[definition.id] = definition.cooldown_seconds
	var tea_modifier := _consume_tea_cost_modifier(context)
	effect_result["ki_cost"] = int(cast_check.ki_cost)
	effect_result["tea_ki_cost_modifier_percent"] = tea_modifier
	effect_result["cooldown_seconds"] = definition.cooldown_seconds
	effect_result["range_tiles"] = definition.range_tiles
	ability_cast.emit(effect_result)
	return effect_result

func tick(delta_seconds: float) -> void:
	var delta := maxf(delta_seconds, 0.0)
	for ability_id in cooldown_remaining.keys():
		var remaining := maxf(0.0, float(cooldown_remaining[ability_id]) - delta)
		if remaining <= 0.0:
			cooldown_remaining.erase(ability_id)
		else:
			cooldown_remaining[ability_id] = remaining

func effective_ki_cost(definition, context: Dictionary) -> int:
	var multiplier := 1.0
	var time_state = context.get("time_state")
	if time_state != null and time_state.has_method("ability_cost_multiplier_for"):
		multiplier = float(time_state.ability_cost_multiplier_for(context.get("resources")))
	var tea_effect_query = context.get("tea_effect_query")
	if tea_effect_query != null and tea_effect_query.has_method("next_ability_ki_cost_multiplier"):
		multiplier *= maxf(0.0, float(tea_effect_query.next_ability_ki_cost_multiplier()))
	return int(ceil(definition.ki_cost * multiplier))

func _consume_tea_cost_modifier(context: Dictionary) -> float:
	var tea_effect_query = context.get("tea_effect_query")
	if tea_effect_query == null or not tea_effect_query.has_method("consume_next_ability_ki_cost_modifier"):
		return 0.0
	return float(tea_effect_query.consume_next_ability_ki_cost_modifier())

func definition_for_slot(slot: int) -> Dictionary:
	return _ability_for_slot(slot)

func ability_candidates(context := {}) -> Dictionary:
	var ids := []
	var candidates := []
	var sorted_ids := definitions.keys()
	sorted_ids.sort()
	for ability_id in sorted_ids:
		var definition: AbilityDefinition = definitions[ability_id]
		var tail_check := _tail_condition_result(definition, context)
		if tail_check.ok:
			ids.append(definition.id)
			candidates.append(definition.to_dictionary())
		elif String(tail_check.get("reason", "")) != "tail_requirement_not_met":
			return tail_check
	return {"ok": true, "ability_ids": ids, "definitions": candidates}

func equipped_ability_id(slot: int) -> String:
	if slot < 0 or slot >= equip_slots.size():
		return ""
	return equip_slots[slot]

func _register_default_strategies() -> void:
	_strategies["공격"] = AbilityDamageEffectStrategy.new()
	_strategies["이동"] = AbilityMovementEffectStrategy.new()

func _ability_for_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= equip_slots.size():
		return {"ok": false, "reason": "invalid_slot", "slot": slot}
	var ability_id := equip_slots[slot]
	if ability_id == "":
		return {"ok": false, "reason": "empty_slot", "slot": slot}
	if not definitions.has(ability_id):
		return {"ok": false, "reason": "unknown_ability", "ability_id": ability_id}
	return {"ok": true, "definition": definitions[ability_id]}

func _tail_condition_result(definition, context: Dictionary) -> Dictionary:
	var tail_query = context.get("tail_query")
	if tail_query != null and tail_query.has_method("can_use_ability"):
		if bool(tail_query.can_use_ability(definition.id, definition.tail_requirement)):
			return {"ok": true}
		return {
			"ok": false,
			"reason": "tail_requirement_not_met",
			"ability_id": definition.id,
			"tail_requirement": definition.tail_requirement
		}
	if context.has("tail_count"):
		if int(context.tail_count) >= definition.tail_requirement:
			return {"ok": true}
		return {
			"ok": false,
			"reason": "tail_requirement_not_met",
			"ability_id": definition.id,
			"tail_requirement": definition.tail_requirement,
			"tail_count": int(context.tail_count)
		}
	return {"ok": false, "reason": "missing_tail_query", "ability_id": definition.id}

static func _required_balance_value(catalog, id: String) -> Dictionary:
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return {"ok": false, "error": "Missing required ability balance value: %s" % id}
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "Ability balance value must be numeric: %s" % id}
	var numeric_value := float(value)
	if not is_finite(numeric_value):
		return {"ok": false, "error": "Ability balance value must be finite: %s" % id}
	return {"ok": true, "value": numeric_value}
