extends RefCounted
class_name ChoiceRuntime

const ChoiceDefinition = preload("res://src/choice/choice_definition.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const NarrativeConditionResolver = preload("res://src/narrative/narrative_condition_resolver.gd")

var definitions: Dictionary = {}
var condition_resolver := NarrativeConditionResolver.new()

func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Catalog cannot provide choice definitions.")
	definitions.clear()
	for row in catalog.get_definitions("choices"):
		if typeof(row) != TYPE_DICTIONARY:
			return _fail("invalid_choice_definition", "Choice catalog contains a non-object row.")
		var result := register_definition(row)
		if not result.ok:
			return result
	return {"ok": true, "runtime": self}

func register_definition(row: Dictionary) -> Dictionary:
	var result := ChoiceDefinition.from_row(row)
	if not result.ok:
		return result
	var definition: Dictionary = result.definition
	if definitions.has(definition.id):
		return _fail("duplicate_choice_id", "Choice id '%s' is duplicated." % definition.id)
	definitions[definition.id] = definition
	return {"ok": true, "definition": definition}

func definition_for(choice_id: String) -> Dictionary:
	return definitions.get(choice_id, {})

func can_apply(choice_id: String, run_state, context := {}) -> Dictionary:
	if not definitions.has(choice_id):
		return _fail("missing_choice", "Choice '%s' is not defined." % choice_id)
	var state_result := _validate_run_state(run_state)
	if not state_result.ok:
		return state_result
	var history: Array = _state_field(run_state, "choice_history", [])
	if history.has(choice_id):
		return _fail("choice_already_applied", "Choice '%s' was already applied in this run." % choice_id)
	var group := String(context.get("exclusive_group", ""))
	var selections: Dictionary = _state_field(run_state, "choice_group_selections", {})
	if not group.is_empty() and selections.has(group):
		return _fail("choice_group_already_resolved", "Choice group '%s' was already resolved by '%s'." % [group, selections[group]])
	var definition: Dictionary = definitions[choice_id]
	if bool(definition.target_survives) and context.has("target_alive") and not bool(context.target_alive):
		return _fail("choice_target_unavailable", "Choice '%s' requires a living target." % choice_id)
	var query := {
		"current_biome_id": String(_state_field(run_state, "current_biome_id", "")),
		"inventory": _state_field(run_state, "inventory", {}),
		"flags": _state_field(run_state, "narrative_flags", [])
	}
	for condition in definition.conditions:
		if condition_resolver.requires_meta(condition):
			return _fail("choice_meta_condition_forbidden", "Choice '%s' cannot query meta state." % choice_id)
		var condition_result := condition_resolver.resolve(condition, query)
		if not condition_result.ok:
			return condition_result
		if not condition_result.passed:
			return _fail("choice_condition_failed", "Choice '%s' is not currently available." % choice_id)
	return {"ok": true}

func apply_choice(choice_id: String, run_state, context := {}) -> Dictionary:
	var availability := can_apply(choice_id, run_state, context)
	if not availability.ok:
		return availability
	var definition: Dictionary = definitions[choice_id]
	var history: Array = _state_field(run_state, "choice_history", []).duplicate()
	var flags: Array = _state_field(run_state, "narrative_flags", []).duplicate()
	var selections: Dictionary = _state_field(run_state, "choice_group_selections", {}).duplicate(true)
	var survival: Dictionary = _state_field(run_state, "target_survival", {}).duplicate(true)
	var marks: Array = _state_field(run_state, "philosophy_marks", []).duplicate()
	var effects: Array = _state_field(run_state, "final_room_effects", []).duplicate(true)
	history.append(choice_id)
	_append_unique(flags, String(definition.run_flag))
	var group := String(context.get("exclusive_group", ""))
	if not group.is_empty():
		selections[group] = choice_id
	var target_id := String(context.get("target_id", ""))
	if not target_id.is_empty():
		survival[target_id] = bool(definition.target_survives)
	for mark in definition.philosophy_marks:
		_append_unique(marks, String(mark))
	effects.append({"choice_id": choice_id, "effect": String(definition.final_room_effect)})
	_write_state_field(run_state, "choice_history", history)
	_write_state_field(run_state, "narrative_flags", flags)
	_write_state_field(run_state, "choice_group_selections", selections)
	_write_state_field(run_state, "target_survival", survival)
	_write_state_field(run_state, "philosophy_marks", marks)
	_write_state_field(run_state, "final_room_effects", effects)
	var meta_events: Array = []
	if bool(definition.meta_record):
		meta_events.append({
			"type": "choice_meta_record_requested",
			"choice_id": choice_id,
			"choice_key": String(definition.choice_key),
			"run_flag": String(definition.run_flag)
		})
	return {"ok": true, "choice": definition.duplicate(true), "meta_events": meta_events}

func apply_narrative_command(command, run_state, context := {}) -> Dictionary:
	if command == null or int(command.get("type")) != GameCommand.Type.NARRATIVE_RESULT:
		return _fail("invalid_choice_command", "Choice runtime only accepts narrative result commands.")
	var payload = command.get("payload")
	var result = payload.get("result", {}) if typeof(payload) == TYPE_DICTIONARY else {}
	if typeof(result) != TYPE_DICTIONARY or String(result.get("type", "")) != "apply_choice":
		return _fail("invalid_choice_command", "Narrative command does not contain an apply_choice result.")
	return apply_choice(String(result.get("id", "")), run_state, context)

func projection(run_state) -> Dictionary:
	return {
		"run_flags": _state_field(run_state, "narrative_flags", []).duplicate(),
		"target_survival": _state_field(run_state, "target_survival", {}).duplicate(true),
		"philosophy_marks": _state_field(run_state, "philosophy_marks", []).duplicate(),
		"final_room_effects": _state_field(run_state, "final_room_effects", []).duplicate(true)
	}

func _state_field(run_state, field: String, fallback):
	if run_state == null:
		return fallback
	if run_state is Dictionary:
		return run_state.get(field, fallback)
	var value = run_state.get(field) if run_state.has_method("get") else null
	return fallback if value == null else value

func _validate_run_state(run_state) -> Dictionary:
	if run_state == null:
		return _fail("invalid_choice_state", "Choice results require a writable run state.")
	if not (run_state is Dictionary) and not (run_state.has_method("get") and run_state.has_method("set")):
		return _fail("invalid_choice_state", "Choice results require a writable run state.")
	var array_fields := ["choice_history", "narrative_flags", "philosophy_marks", "final_room_effects"]
	var dictionary_fields := ["choice_group_selections", "target_survival"]
	for field in array_fields:
		var value = _state_field(run_state, field, [])
		if typeof(value) != TYPE_ARRAY:
			return _fail("invalid_choice_state", "Choice run state field '%s' must be an array." % field)
	for field in dictionary_fields:
		var value = _state_field(run_state, field, {})
		if typeof(value) != TYPE_DICTIONARY:
			return _fail("invalid_choice_state", "Choice run state field '%s' must be a dictionary." % field)
	return {"ok": true}

func _write_state_field(run_state, field: String, value) -> void:
	if run_state is Dictionary:
		run_state[field] = value
	elif run_state != null and run_state.has_method("set"):
		run_state.set(field, value)

func _append_unique(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
