extends RefCounted
class_name BossEncounterRuntime

signal phase_changed(event: Dictionary)
signal pattern_scheduled(event: Dictionary)
signal summons_requested(event: Dictionary)
signal encounter_resolved(event: Dictionary)

const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterState = preload("res://src/boss/boss_encounter_state.gd")
const BossPatternScheduler = preload("res://src/boss/boss_pattern_scheduler.gd")

const EVENT_PATTERN := "boss_pattern_scheduled"
const EVENT_SUMMON := "boss_summons_requested"
const EVENT_RESOLVED := "boss_encounter_resolved"

var _definition: BossDefinition
var _state := BossEncounterState.new()
var _scheduler
var _summon_hook: Callable
var _resolution_hook: Callable

func configure(definition, scheduler = null, summon_hook := Callable(), resolution_hook := Callable()) -> Dictionary:
	if not definition is BossDefinition:
		return _fail("invalid_boss_definition", "Boss encounter requires a BossDefinition.")
	var selected_scheduler = scheduler if scheduler != null else BossPatternScheduler.new()
	if not selected_scheduler.has_method("select_pattern"):
		return _fail("invalid_pattern_scheduler", "Boss encounter requires a pattern scheduler boundary.")
	_definition = definition
	_scheduler = selected_scheduler
	_summon_hook = summon_hook
	_resolution_hook = resolution_hook
	_state = BossEncounterState.new()
	return {"ok": true, "projection": to_projection()}

func start(encounter_id: String, dungeon_id: String) -> Dictionary:
	if _definition == null:
		return _fail("not_configured", "Boss encounter is not configured.")
	if _state.lifecycle_state != BossEncounterState.STATE_IDLE:
		return _fail("encounter_already_started", "Boss encounter can only start once.")
	if encounter_id.is_empty() or dungeon_id != _definition.dungeon_id:
		return _fail("invalid_encounter_identity", "Boss encounter requires matching stable encounter and dungeon ids.")
	_state.encounter_id = encounter_id
	_state.boss_id = _definition.id
	_state.dungeon_id = dungeon_id
	_state.lifecycle_state = BossEncounterState.STATE_ACTIVE
	_state.current_hp = _definition.max_hp
	_state.max_hp = _definition.max_hp
	return {"ok": true, "projection": to_projection()}

func update_health(current_hp: int) -> Dictionary:
	var active := _require_active()
	if not active.ok:
		return active
	if current_hp < 0 or current_hp > _state.max_hp:
		return _fail("invalid_boss_health", "Boss health must stay within encounter bounds.")
	_state.current_hp = current_hp
	var next_phase := _definition.phase_index_for_health(current_hp)
	if next_phase != _state.phase_index:
		var previous_phase := _state.phase_index
		_state.phase_index = next_phase
		_state.pattern_cursor = 0
		_state.pattern_cooldown_remaining = 0.0
		var event := {
			"event_type": "boss_phase_changed",
			"encounter_id": _state.encounter_id,
			"boss_id": _state.boss_id,
			"from_phase_id": String(_definition.phases[previous_phase].id),
			"phase_id": String(_definition.phases[next_phase].id),
			"phase_index": next_phase
		}
		phase_changed.emit(event.duplicate(true))
		return {"ok": true, "phase_changed": true, "event": event, "projection": to_projection()}
	return {"ok": true, "phase_changed": false, "projection": to_projection()}

func tick(delta_seconds: float) -> Dictionary:
	var active := _require_active()
	if not active.ok:
		return active
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		return _fail("invalid_delta", "Boss scheduler delta must be a finite non-negative number.")
	_state.pattern_cooldown_remaining = maxf(_state.pattern_cooldown_remaining - delta_seconds, 0.0)
	if _state.pattern_cooldown_remaining > 0.0:
		return {"ok": true, "scheduled": false, "projection": to_projection()}
	var phase: Dictionary = _definition.phases[_state.phase_index]
	var selection: Dictionary = _scheduler.select_pattern(phase, _state.pattern_cursor)
	if not bool(selection.get("ok", false)):
		return selection
	var pattern: Dictionary = selection.pattern.duplicate(true)
	var event := {
		"event_type": EVENT_PATTERN,
		"encounter_id": _state.encounter_id,
		"boss_id": _state.boss_id,
		"phase_id": String(phase.id),
		"pattern_id": String(pattern.id),
		"pattern": pattern.duplicate(true)
	}
	var summon_result := {"ok": true}
	var summon_ids: Array = pattern.get("summon_monster_ids", []).duplicate(true)
	if not summon_ids.is_empty():
		var summon_event := {
			"event_type": EVENT_SUMMON,
			"encounter_id": _state.encounter_id,
			"boss_id": _state.boss_id,
			"phase_id": String(phase.id),
			"pattern_id": String(pattern.id),
			"monster_ids": summon_ids
		}
		if _summon_hook.is_valid():
			summon_result = _normalize_hook_result(_summon_hook.call(summon_event.duplicate(true)))
			if not bool(summon_result.get("ok", false)):
				var failure := _fail("summon_hook_rejected", String(summon_result.get("error", "Boss summon hook rejected the request.")))
				failure["pattern_id"] = String(pattern.id)
				failure["summon_result"] = summon_result
				failure["projection"] = to_projection()
				return failure
		summons_requested.emit(summon_event.duplicate(true))
	_state.pattern_cursor = int(selection.next_cursor)
	_state.pattern_cooldown_remaining = float(pattern.interval_seconds)
	pattern_scheduled.emit(event.duplicate(true))
	return {"ok": true, "scheduled": true, "event": event, "summon_result": summon_result, "projection": to_projection()}

func handle_resolution(input: Dictionary) -> Dictionary:
	var active := _require_active()
	if not active.ok:
		return active
	var input_type := String(input.get("type", ""))
	if input_type == "abort":
		_state.lifecycle_state = BossEncounterState.STATE_ABORTED
		_state.resolution_event = _build_resolution_event("abort", input)
		encounter_resolved.emit(_state.resolution_event.duplicate(true))
		return {"ok": true, "event": _state.resolution_event.duplicate(true), "projection": to_projection()}
	var resolution_type := "combat" if input_type == "victory" else input_type
	if not _definition.supports_resolution(resolution_type):
		return _fail("unsupported_resolution", "Boss definition does not support this resolution.")
	if resolution_type == "combat" and _state.current_hp > 0:
		return _fail("victory_condition_not_met", "Combat victory requires zero boss health.")
	if resolution_type == "peaceful" and String(input.get("choice_key", "")).is_empty():
		return _fail("missing_peaceful_choice", "Peaceful resolution requires a stable choice key.")
	var event := _build_resolution_event(resolution_type, input)
	var completion_result := {"ok": true}
	if _resolution_hook.is_valid():
		completion_result = _normalize_hook_result(_resolution_hook.call(event.duplicate(true)))
		if not bool(completion_result.get("ok", false)):
			return _fail(String(completion_result.get("reason", "resolution_hook_rejected")), String(completion_result.get("error", "Boss resolution hook rejected completion.")))
	_state.lifecycle_state = BossEncounterState.STATE_RESOLVED
	_state.resolution_event = event.duplicate(true)
	encounter_resolved.emit(event.duplicate(true))
	return {"ok": true, "event": event, "completion_result": completion_result, "projection": to_projection()}

func to_projection() -> Dictionary:
	var projection := _state.to_dictionary()
	projection["read_only"] = true
	if _definition != null and _state.phase_index >= 0 and _state.phase_index < _definition.phases.size():
		projection["phase_id"] = String(_definition.phases[_state.phase_index].id)
	return projection

func _build_resolution_event(resolution_type: String, input: Dictionary) -> Dictionary:
	return {
		"event_type": EVENT_RESOLVED,
		"encounter_id": _state.encounter_id,
		"boss_id": _state.boss_id,
		"dungeon_id": _state.dungeon_id,
		"resolution_type": resolution_type,
		"choice_key": String(input.get("choice_key", "")),
		"run_flag": String(input.get("run_flag", "")),
		"reward_item_ids": _definition.reward_item_ids.duplicate(true),
		"progression_unlock_ids": _definition.progression_unlock_ids.duplicate(true)
	}

func _require_active() -> Dictionary:
	if _state.lifecycle_state != BossEncounterState.STATE_ACTIVE:
		return _fail("encounter_not_active", "Boss encounter input requires an active encounter.")
	return {"ok": true}

func _normalize_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": bool(result)}
	return {"ok": true, "value": result}

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
