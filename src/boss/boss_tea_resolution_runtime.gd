extends RefCounted
class_name BossTeaResolutionRuntime

const BossDefinition = preload("res://src/boss/boss_definition.gd")
const NarrativeConditionResolver = preload("res://src/narrative/narrative_condition_resolver.gd")

const STATE_IDLE := "idle"
const STATE_ACTIVE := "active"
const STATE_COMBAT_STARTED := "combat_started"
const STATE_RESOLVED := "resolved"

const COMMAND_DRINK_TEA := "drink_tea"
const COMMAND_REFUSE := "refuse"
const COMMAND_ATTACK_FIRST := "attack_first"
const COMMANDS := [COMMAND_DRINK_TEA, COMMAND_REFUSE, COMMAND_ATTACK_FIRST]

const OUTCOME_PEACEFUL_TEA_CEREMONY := "peaceful_tea_ceremony"
const OUTCOME_MIXED := "mixed"
const OUTCOME_COMBAT_STARTED := "combat_started"
const OUTCOME_COMBAT := OUTCOME_COMBAT_STARTED

const EVENT_PRE_BOSS_CHOICE := "boss_pre_boss_choice"
const EVENT_PRE_BOSS_COMBAT_STARTED := "boss_pre_boss_combat_started"

const DEFAULT_EXCLUSIVE_GROUP_SUFFIX := "_boss_resolution"

signal pre_boss_choice_selected(event: Dictionary)
signal peaceful_condition_evaluated(event: Dictionary)
signal resolution_committed(event: Dictionary)

var _definition: BossDefinition
var _tea_service
var _choice_runtime
var _resolution_hook: Callable
var _memory_hook: Callable
var _weakness_hook: Callable
var _dialogue_hook: Callable
var _condition_resolver := NarrativeConditionResolver.new()
var _state := {
	"lifecycle_state": STATE_IDLE,
	"pre_boss_id": "",
	"boss_id": "",
	"dungeon_id": "",
	"selected_command": "",
	"resolution_event": {}
}

func configure(
	definition,
	tea_service,
	resolution_hook: Callable,
	choice_runtime = null,
	memory_hook := Callable(),
	weakness_hook := Callable(),
	dialogue_hook := Callable()
) -> Dictionary:
	if not definition is BossDefinition:
		return _fail("invalid_boss_definition", "Boss tea resolution requires a BossDefinition.")
	if tea_service == null \
		or not tea_service.has_method("has_prepared_tea") \
		or not tea_service.has_method("get_prepared_tea") \
		or not tea_service.has_method("start_drinking") \
		or not tea_service.has_method("complete_drinking") \
		or not tea_service.has_method("to_snapshot") \
		or not tea_service.has_method("load_snapshot") \
		or not tea_service.has_method("prepare_drink_commit") \
		or not tea_service.has_method("publish_drink_commit"):
		return _fail("invalid_tea_service", "Boss tea resolution requires the tea service public boundary.")
	if not resolution_hook.is_valid():
		return _fail("invalid_resolution_hook", "Boss tea resolution requires a boss resolution hook.")
	if choice_runtime != null \
			and (not choice_runtime.has_method("can_apply") \
			or not choice_runtime.has_method("apply_choice") \
			or not choice_runtime.has_method("definition_for")):
		return _fail("invalid_choice_runtime", "Boss tea resolution requires the choice runtime public boundary.")
	_definition = definition
	_tea_service = tea_service
	_choice_runtime = choice_runtime
	_resolution_hook = resolution_hook
	_memory_hook = memory_hook
	_weakness_hook = weakness_hook
	_dialogue_hook = dialogue_hook
	_state = _empty_state()
	return {"ok": true, "projection": to_projection()}

func start(pre_boss_id: String) -> Dictionary:
	if _definition == null:
		return _fail("not_configured", "Boss tea resolution is not configured.")
	if _state.lifecycle_state != STATE_IDLE:
		return _fail("pre_boss_already_started", "Pre-boss tea resolution can only start once.")
	if not _is_stable_id(pre_boss_id):
		return _fail("invalid_pre_boss_id", "Pre-boss tea resolution requires a valid stable id.")
	_state.pre_boss_id = pre_boss_id
	_state.boss_id = _definition.id
	_state.dungeon_id = _definition.dungeon_id
	_state.lifecycle_state = STATE_ACTIVE
	return {"ok": true, "projection": to_projection()}

func handle_command(command_id: String, payload := {}, run_state = null, context := {}) -> Dictionary:
	var active := _require_active()
	if not active.ok:
		return active
	if not COMMANDS.has(command_id):
		return _fail("invalid_pre_boss_command", "Unknown pre-boss command: %s" % command_id)
	if command_id == COMMAND_DRINK_TEA:
		return _handle_drink_tea(_dictionary_value(payload), run_state, _dictionary_value(context))
	return _handle_combat_branch(command_id, _dictionary_value(payload), _dictionary_value(context))

func to_projection() -> Dictionary:
	var projection := _state.duplicate(true)
	projection["read_only"] = true
	projection["phase"] = "pre_boss"
	projection["combat_started"] = _state.lifecycle_state == STATE_COMBAT_STARTED
	projection["final_resolution_committed"] = _state.lifecycle_state == STATE_RESOLVED
	projection["boss_resolution_pending"] = _state.lifecycle_state in [STATE_ACTIVE, STATE_COMBAT_STARTED]
	return projection

func _handle_drink_tea(payload: Dictionary, run_state, context: Dictionary) -> Dictionary:
	var config := _tea_resolution_config()
	if not _definition.supports_resolution("peaceful"):
		return _fail("unsupported_resolution", "Boss definition does not support peaceful tea resolution.")
	var slot_index := int(payload.get("slot", -1))
	if not _tea_service.has_prepared_tea(slot_index):
		return _fail("missing_prepared_tea", "A prepared tea slot is required before the boss.")
	var prepared: Dictionary = _tea_service.get_prepared_tea(slot_index)
	var tea_allowed := _prepared_tea_allowed(prepared, config)
	if not tea_allowed.ok:
		return tea_allowed

	var condition_result := _peaceful_conditions_pass(prepared, config, run_state, context)
	var evaluation_event := _build_hook_event(COMMAND_DRINK_TEA, prepared, OUTCOME_PEACEFUL_TEA_CEREMONY)
	evaluation_event["event_type"] = "boss_peaceful_condition_evaluated"
	evaluation_event["signal_phase"] = "preflight"
	evaluation_event["passed"] = bool(condition_result.get("passed", false))
	if not condition_result.ok:
		return condition_result
	peaceful_condition_evaluated.emit(evaluation_event.duplicate(true))
	if not condition_result.passed:
		_state.selected_command = COMMAND_DRINK_TEA
		_state.lifecycle_state = STATE_COMBAT_STARTED
		var mixed_event := _build_hook_event(COMMAND_DRINK_TEA, prepared, OUTCOME_MIXED)
		_call_non_blocking_hooks(mixed_event)
		pre_boss_choice_selected.emit(mixed_event.duplicate(true))
		return {
			"ok": true,
			"outcome_type": OUTCOME_MIXED,
			"consumed": false,
			"combat_started": true,
			"event": mixed_event,
			"projection": to_projection()
		}

	var choice_result := _choice_metadata(config, payload)
	if not choice_result.ok:
		return choice_result
	var availability := _choice_available(choice_result.choice_id, run_state, config, context)
	if not availability.ok:
		return availability

	var resources = payload.get("resources", context.get("resources", null))
	var snapshots := _capture_transaction_snapshots(run_state, resources)
	if not snapshots.ok:
		return snapshots
	var signal_state := _block_transaction_signals(resources)
	var action_result: Dictionary = _tea_service.start_drinking(slot_index, {
		"pre_boss_id": _state.pre_boss_id,
		"boss_id": _definition.id,
		"dungeon_id": _definition.dungeon_id,
		"command": COMMAND_DRINK_TEA
	})
	if not action_result.ok:
		return _rollback_failure(action_result, snapshots, run_state, resources, signal_state)

	var consume_result: Dictionary = _tea_service.complete_drinking(action_result.action, resources)
	if not consume_result.ok:
		return _rollback_failure(consume_result, snapshots, run_state, resources, signal_state)
	var apply_result := _apply_choice(choice_result.choice_id, run_state, config, context)
	if not apply_result.ok:
		return _rollback_failure(apply_result, snapshots, run_state, resources, signal_state)
	var committed_tea_snapshot = _tea_service.to_snapshot()
	var tea_commit: Dictionary = _tea_service.prepare_drink_commit(
		action_result.action,
		consume_result,
		committed_tea_snapshot
	)
	if not tea_commit.ok:
		return _rollback_failure(tea_commit, snapshots, run_state, resources, signal_state)
	var resource_snapshot := _dictionary_value(snapshots.get("resources", {}))
	var committed_resource_snapshot := _current_resource_snapshot(resources, resource_snapshot)
	var resource_commit := _prepare_resource_commit(resources, resource_snapshot, committed_resource_snapshot)
	if not resource_commit.ok:
		return _rollback_failure(resource_commit, snapshots, run_state, resources, signal_state)

	var resolution_input := _build_resolution_input(
		COMMAND_DRINK_TEA,
		prepared,
		OUTCOME_PEACEFUL_TEA_CEREMONY,
		choice_result
	)
	var resolution_result := _normalize_hook_result(_resolution_hook.call(resolution_input.duplicate(true)))
	if not bool(resolution_result.get("ok", false)):
		var resolution_failure := _fail(String(resolution_result.get("reason", "resolution_hook_rejected")), String(resolution_result.get("error", "Boss resolution hook rejected peaceful tea completion.")))
		return _rollback_failure(resolution_failure, snapshots, run_state, resources, signal_state)

	_state.selected_command = COMMAND_DRINK_TEA
	_state.lifecycle_state = STATE_RESOLVED
	_state.resolution_event = _dictionary_value(resolution_result.get("event", resolution_input))
	_restore_signal_blocking(signal_state, resources)
	_tea_service.publish_drink_commit(_dictionary_value(tea_commit.get("token", {})))
	_publish_resource_commit(resources, resource_commit)
	var hook_event := _build_hook_event(COMMAND_DRINK_TEA, prepared, OUTCOME_PEACEFUL_TEA_CEREMONY)
	hook_event["signal_phase"] = "committed"
	_call_non_blocking_hooks(hook_event)
	pre_boss_choice_selected.emit(hook_event.duplicate(true))
	var committed := {
		"event_type": "boss_tea_resolution_committed",
		"pre_boss_id": _state.pre_boss_id,
		"boss_id": _definition.id,
		"dungeon_id": _definition.dungeon_id,
		"command": COMMAND_DRINK_TEA,
		"outcome_type": OUTCOME_PEACEFUL_TEA_CEREMONY,
		"tea_id": String(prepared.get("tea_id", "")),
		"choice_id": choice_result.choice_id,
		"choice_key": choice_result.choice_key
	}
	resolution_committed.emit(committed.duplicate(true))
	return {
		"ok": true,
		"outcome_type": OUTCOME_PEACEFUL_TEA_CEREMONY,
		"consumed": bool(consume_result.get("consumed", false)),
		"tea_result": consume_result,
		"choice_result": apply_result,
		"resolution_result": resolution_result,
		"event": _state.resolution_event.duplicate(true),
		"projection": to_projection()
	}

func _handle_combat_branch(command_id: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	_state.selected_command = command_id
	_state.lifecycle_state = STATE_COMBAT_STARTED
	var event := _build_hook_event(command_id, {}, OUTCOME_COMBAT_STARTED)
	event["reason"] = String(payload.get("reason", command_id))
	_call_non_blocking_hooks(event, context)
	pre_boss_choice_selected.emit(event.duplicate(true))
	return {
		"ok": true,
		"outcome_type": OUTCOME_COMBAT_STARTED,
		"consumed": false,
		"combat_started": true,
		"event": event,
		"projection": to_projection()
	}

func _tea_resolution_config() -> Dictionary:
	return _dictionary_value(_definition.data_snapshot.get("tea_resolution", {}))

func _prepared_tea_allowed(prepared: Dictionary, config: Dictionary) -> Dictionary:
	var required_ids := _array_value(config.get("required_tea_ids", []))
	if required_ids.is_empty():
		return {"ok": true}
	var tea_id := String(prepared.get("tea_id", ""))
	if required_ids.has(tea_id):
		return {"ok": true}
	return _fail("prepared_tea_not_allowed", "Prepared tea does not satisfy the boss tea definition.")

func _peaceful_conditions_pass(prepared: Dictionary, config: Dictionary, run_state, context: Dictionary) -> Dictionary:
	var conditions := _array_value(config.get("peaceful_conditions", []))
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY:
			return _fail("invalid_peaceful_condition", "Boss peaceful condition must be an object.")
		var condition_type := String(condition.get("type", ""))
		if condition_type == "prepared_tea":
			if String(condition.get("id", "")) != String(prepared.get("tea_id", "")):
				return {"ok": true, "passed": false}
			continue
		var resolved := _condition_resolver.resolve(condition, _run_query(run_state, prepared, context), {})
		if not resolved.ok:
			return resolved
		if not resolved.passed:
			return {"ok": true, "passed": false}
	return {"ok": true, "passed": true}

func _choice_metadata(config: Dictionary, payload: Dictionary) -> Dictionary:
	var choice_id := String(config.get("choice_id", ""))
	if choice_id.is_empty():
		return _fail("missing_peaceful_choice", "Peaceful tea resolution requires a stable choice id.")
	if payload.has("choice_id") and String(payload.get("choice_id", "")) != choice_id:
		return _fail("peaceful_choice_mismatch", "Command choice id must match the configured boss tea choice.")
	var definition := _choice_definition(choice_id)
	if definition.is_empty():
		return _fail("missing_choice", "Peaceful tea resolution choice is not defined: %s" % choice_id)
	var choice_key := String(definition.get("choice_key", config.get("choice_key", "")))
	var run_flag := String(definition.get("run_flag", config.get("run_flag", "")))
	if choice_key.is_empty() or run_flag.is_empty():
		return _fail("invalid_choice_definition", "Peaceful tea choice must provide choice_key and run_flag.")
	return {
		"ok": true,
		"choice_id": choice_id,
		"choice_key": choice_key,
		"run_flag": run_flag
	}

func _choice_definition(choice_id: String) -> Dictionary:
	if _choice_runtime == null:
		var choices: Dictionary = _dictionary_value(_definition.data_snapshot.get("choice_definitions", {}))
		return _dictionary_value(choices.get(choice_id, {}))
	return _dictionary_value(_choice_runtime.definition_for(choice_id))

func _choice_available(choice_id: String, run_state, config: Dictionary, context: Dictionary) -> Dictionary:
	if _choice_runtime == null:
		return {"ok": true}
	return _choice_runtime.can_apply(choice_id, run_state, _choice_context(config, context))

func _apply_choice(choice_id: String, run_state, config: Dictionary, context: Dictionary) -> Dictionary:
	if _choice_runtime == null:
		return {"ok": true, "choice_id": choice_id}
	return _choice_runtime.apply_choice(choice_id, run_state, _choice_context(config, context))

func _choice_context(config: Dictionary, context: Dictionary) -> Dictionary:
	var choice_context := _dictionary_value(context.get("choice_context", {}))
	if not choice_context.has("exclusive_group"):
		choice_context["exclusive_group"] = String(config.get("exclusive_group", "%s%s" % [_definition.id, DEFAULT_EXCLUSIVE_GROUP_SUFFIX]))
	if not choice_context.has("target_id"):
		choice_context["target_id"] = _definition.id
	return choice_context

func _build_resolution_input(command_id: String, prepared: Dictionary, outcome_type: String, choice_result: Dictionary) -> Dictionary:
	var hook_keys := _hook_keys_for_outcome(outcome_type)
	return {
		"type": "peaceful",
		"choice_key": String(choice_result.choice_key),
		"run_flag": String(choice_result.run_flag),
		"pre_boss_command": command_id,
		"tea_resolution_outcome": outcome_type,
		"tea_id": String(prepared.get("tea_id", "")),
		"prepared_tea_id": String(prepared.get("prepared_id", "")),
		"memory_hook_keys": hook_keys.memory_hook_keys,
		"weakness_hook_keys": hook_keys.weakness_hook_keys,
		"dialogue_hook_keys": hook_keys.dialogue_hook_keys
	}

func _build_hook_event(command_id: String, prepared: Dictionary, outcome_type: String) -> Dictionary:
	var hook_keys := _hook_keys_for_outcome(outcome_type)
	var starts_combat := outcome_type in [OUTCOME_MIXED, OUTCOME_COMBAT_STARTED]
	return {
		"event_type": EVENT_PRE_BOSS_COMBAT_STARTED if starts_combat else EVENT_PRE_BOSS_CHOICE,
		"pre_boss_id": _state.pre_boss_id,
		"boss_id": _definition.id,
		"dungeon_id": _definition.dungeon_id,
		"phase": "pre_boss",
		"command": command_id,
		"outcome_type": outcome_type,
		"combat_started": starts_combat,
		"final_resolution": false,
		"boss_resolution_pending": starts_combat,
		"requires_boss_victory": starts_combat,
		"tea_id": String(prepared.get("tea_id", "")),
		"prepared_tea_id": String(prepared.get("prepared_id", "")),
		"memory_hook_keys": hook_keys.memory_hook_keys,
		"weakness_hook_keys": hook_keys.weakness_hook_keys,
		"dialogue_hook_keys": hook_keys.dialogue_hook_keys
	}

func _hook_keys_for_outcome(outcome_type: String) -> Dictionary:
	var config := _tea_resolution_config()
	var hooks := _dictionary_value(config.get("hooks", {}))
	var common := _dictionary_value(hooks.get("common", {}))
	var outcome := _dictionary_value(hooks.get(outcome_type, {}))
	return {
		"memory_hook_keys": _array_value(common.get("memory", [])) + _array_value(outcome.get("memory", [])),
		"weakness_hook_keys": _array_value(common.get("weakness", [])) + _array_value(outcome.get("weakness", [])),
		"dialogue_hook_keys": _array_value(common.get("dialogue", [])) + _array_value(outcome.get("dialogue", []))
	}

func _call_non_blocking_hooks(event: Dictionary, context := {}) -> Dictionary:
	var results := {
		"memory": _call_optional_hook(_memory_hook, event),
		"weakness": _call_optional_hook(_weakness_hook, event),
		"dialogue": _call_optional_hook(_dialogue_hook, event)
	}
	if typeof(context) == TYPE_DICTIONARY and context.has("hook_results"):
		context["hook_results"] = results.duplicate(true)
	return {"ok": true, "hook_results": results}

func _call_optional_hook(hook: Callable, event: Dictionary) -> Dictionary:
	if not hook.is_valid():
		return {"ok": true, "skipped": true}
	return _normalize_hook_result(hook.call(event.duplicate(true)))

func _run_query(run_state, prepared: Dictionary, context: Dictionary) -> Dictionary:
	var data: Dictionary = {}
	if run_state is Dictionary:
		data = run_state
	elif run_state != null and run_state.has_method("to_dictionary"):
		data = run_state.to_dictionary()
	return {
		"current_biome_id": String(data.get("current_biome_id", context.get("current_biome_id", ""))),
		"inventory": data.get("inventory", {}),
		"flags": data.get("narrative_flags", []),
		"prepared_tea": prepared.duplicate(true),
		"tea_id": String(prepared.get("tea_id", "")),
		"boss_id": _definition.id,
		"dungeon_id": _definition.dungeon_id
	}

func _capture_transaction_snapshots(run_state, resources) -> Dictionary:
	var tea_snapshot = _tea_service.to_snapshot()
	if typeof(tea_snapshot) != TYPE_DICTIONARY:
		return _fail("invalid_tea_snapshot", "Tea service transaction snapshot must be a dictionary.")
	var run_snapshot := _snapshot_run_state(run_state)
	if not run_snapshot.ok:
		return run_snapshot
	var resource_snapshot := _snapshot_resources(resources)
	if not resource_snapshot.ok:
		return resource_snapshot
	return {
		"ok": true,
		"tea": tea_snapshot.duplicate(true),
		"run": run_snapshot,
		"resources": resource_snapshot
	}

func _snapshot_run_state(run_state) -> Dictionary:
	if run_state == null:
		return {"ok": true, "kind": "none", "value": {}}
	if run_state is Dictionary:
		return {"ok": true, "kind": "dictionary", "value": run_state.duplicate(true)}
	if run_state.has_method("to_dictionary"):
		var snapshot = run_state.to_dictionary()
		if typeof(snapshot) == TYPE_DICTIONARY:
			return {"ok": true, "kind": "object", "value": snapshot.duplicate(true)}
	return _fail("invalid_run_state_snapshot", "Peaceful resolution requires snapshot-capable run state.")

func _rollback_failure(failure: Dictionary, snapshots: Dictionary, run_state, resources, signal_state: Dictionary) -> Dictionary:
	var tea_restore: Dictionary = _tea_service.load_snapshot(_dictionary_value(snapshots.get("tea", {})))
	var run_restore := _restore_run_state(run_state, _dictionary_value(snapshots.get("run", {})))
	var resource_restore := _restore_resources(resources, _dictionary_value(snapshots.get("resources", {})))
	_restore_signal_blocking(signal_state, resources)
	if not tea_restore.ok or not run_restore.ok or not resource_restore.ok:
		return {
			"ok": false,
			"reason": "boss_tea_rollback_failed",
			"error": "Boss tea resolution failed and its transaction snapshot could not be fully restored.",
			"cause": failure.duplicate(true),
			"tea_restore": tea_restore,
			"run_restore": run_restore,
			"resource_restore": resource_restore
		}
	var restored := failure.duplicate(true)
	restored["rolled_back"] = true
	return restored

func _restore_run_state(run_state, snapshot: Dictionary) -> Dictionary:
	var kind := String(snapshot.get("kind", ""))
	var value := _dictionary_value(snapshot.get("value", {}))
	if kind == "none":
		return {"ok": true}
	if kind == "dictionary" and run_state is Dictionary:
		run_state.clear()
		for field in value:
			run_state[field] = _duplicate_value(value[field])
		return {"ok": true}
	if kind == "object" and run_state != null:
		for field in value:
			run_state.set(field, _duplicate_value(value[field]))
		return {"ok": true}
	return _fail("invalid_run_state_restore", "Run state transaction snapshot does not match its target.")

func _snapshot_resources(resources) -> Dictionary:
	if resources == null:
		return {"ok": true, "kind": "none", "value": {}}
	if resources is Dictionary:
		return {"ok": true, "kind": "dictionary", "value": resources.duplicate(true)}
	if resources.has_method("to_snapshot") and resources.has_method("load_snapshot"):
		var snapshot = resources.to_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			return {"ok": true, "kind": "snapshot_object", "value": snapshot.duplicate(true)}
	if resources.has_method("to_dictionary") \
		and resources.has_method("heal_hp") \
		and resources.has_method("apply_damage") \
		and resources.has_method("recover_ki") \
		and resources.has_method("spend_ki") \
		and resources.has_method("restore_kokoro") \
		and resources.has_method("reduce_kokoro") \
		and resources.has_method("prepare_snapshot_delta") \
		and resources.has_method("publish_snapshot_delta"):
		var fields = resources.to_dictionary()
		if typeof(fields) == TYPE_DICTIONARY and _valid_resource_fields(fields):
			return {"ok": true, "kind": "player_resources", "value": fields.duplicate(true)}
	return _fail("invalid_resources_snapshot", "Tea resources must expose a restorable public snapshot boundary.")

func _restore_resources(resources, snapshot: Dictionary) -> Dictionary:
	var kind := String(snapshot.get("kind", ""))
	var value := _dictionary_value(snapshot.get("value", {}))
	if kind == "none":
		return {"ok": true}
	if kind == "dictionary" and resources is Dictionary:
		resources.clear()
		for field in value:
			resources[field] = _duplicate_value(value[field])
		return {"ok": true}
	if kind == "snapshot_object" and resources != null and resources.has_method("load_snapshot"):
		return _normalize_hook_result(resources.load_snapshot(value.duplicate(true)))
	if kind == "player_resources" and resources != null:
		return _restore_player_resources(resources, value)
	return _fail("invalid_resources_restore", "Resource transaction snapshot does not match its target.")

func _restore_player_resources(resources, target: Dictionary) -> Dictionary:
	var current = resources.to_dictionary()
	if typeof(current) != TYPE_DICTIONARY or not _valid_resource_fields(current):
		return _fail("invalid_resources_restore", "Player resources no longer expose their public field snapshot.")
	for maximum_field in ["hp_max", "ki_max", "kokoro_max", "kokoro_low_threshold"]:
		if int(current.get(maximum_field, -1)) != int(target.get(maximum_field, -2)):
			return _fail("resource_bounds_changed", "Player resource bounds changed during boss tea resolution.")
	_restore_resource_value(resources, "hp", int(current.hp), int(target.hp), "heal_hp", "apply_damage")
	_restore_resource_value(resources, "ki", int(current.ki), int(target.ki), "recover_ki", "spend_ki")
	_restore_resource_value(resources, "kokoro", int(current.kokoro), int(target.kokoro), "restore_kokoro", "reduce_kokoro")
	var restored = resources.to_dictionary()
	if typeof(restored) != TYPE_DICTIONARY or restored != target:
		return _fail("resources_restore_mismatch", "Player resources did not restore to the exact transaction snapshot.")
	return {"ok": true}

func _restore_resource_value(resources, _field: String, current: int, target: int, increase_method: String, decrease_method: String) -> void:
	if current < target:
		resources.call(increase_method, target - current)
	elif current > target:
		resources.call(decrease_method, current - target)

func _valid_resource_fields(value: Dictionary) -> bool:
	for field in ["hp", "hp_max", "ki", "ki_max", "kokoro", "kokoro_max", "kokoro_low_threshold"]:
		if typeof(value.get(field)) != TYPE_INT:
			return false
	return true

func _block_transaction_signals(resources) -> Dictionary:
	var state := {
		"tea_was_blocked": _tea_service.is_blocking_signals(),
		"resources_blocked": false,
		"resources_were_blocked": false
	}
	_tea_service.set_block_signals(true)
	if resources != null \
			and not resources is Dictionary \
			and resources.has_method("is_blocking_signals") \
			and resources.has_method("set_block_signals"):
		state.resources_blocked = true
		state.resources_were_blocked = resources.is_blocking_signals()
		resources.set_block_signals(true)
	return state

func _restore_signal_blocking(signal_state: Dictionary, resources) -> void:
	_tea_service.set_block_signals(bool(signal_state.get("tea_was_blocked", false)))
	if bool(signal_state.get("resources_blocked", false)) and resources != null and not resources is Dictionary:
		resources.set_block_signals(bool(signal_state.get("resources_were_blocked", false)))

func _current_resource_snapshot(resources, transaction_snapshot: Dictionary) -> Dictionary:
	var kind := String(transaction_snapshot.get("kind", ""))
	if kind == "dictionary" and resources is Dictionary:
		return resources.duplicate(true)
	if kind == "snapshot_object" and resources != null:
		var snapshot = resources.to_snapshot()
		return snapshot.duplicate(true) if typeof(snapshot) == TYPE_DICTIONARY else {}
	if kind == "player_resources" and resources != null:
		var snapshot = resources.to_dictionary()
		return snapshot.duplicate(true) if typeof(snapshot) == TYPE_DICTIONARY else {}
	return {}

func _prepare_resource_commit(resources, transaction_snapshot: Dictionary, committed_snapshot: Dictionary) -> Dictionary:
	var kind := String(transaction_snapshot.get("kind", ""))
	if kind in ["none", "dictionary", "snapshot_object"]:
		return {"ok": true, "skipped": true}
	if kind == "player_resources" and resources != null:
		return _normalize_hook_result(resources.prepare_snapshot_delta(
			_dictionary_value(transaction_snapshot.get("value", {})),
			committed_snapshot
		))
	return _fail("invalid_resource_commit", "Resource commit token could not be prepared.")

func _publish_resource_commit(resources, resource_commit: Dictionary) -> void:
	if bool(resource_commit.get("skipped", false)):
		return
	resources.publish_snapshot_delta(_dictionary_value(resource_commit.get("token", {})))

func _require_active() -> Dictionary:
	if _state.lifecycle_state != STATE_ACTIVE:
		return _fail("pre_boss_resolution_not_active", "Pre-boss resolution command requires an active state.")
	return {"ok": true}

func _empty_state() -> Dictionary:
	return {
		"lifecycle_state": STATE_IDLE,
		"pre_boss_id": "",
		"boss_id": "",
		"dungeon_id": "",
		"selected_command": "",
		"resolution_event": {}
	}

func _normalize_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": bool(result)}
	return {"ok": true, "value": result}

func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func _duplicate_value(value):
	return value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value

func _is_stable_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	return pattern.search(value) != null

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
