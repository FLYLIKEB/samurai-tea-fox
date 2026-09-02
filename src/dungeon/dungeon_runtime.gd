extends RefCounted
class_name DungeonRuntime

signal dungeon_cleared(clear_event: Dictionary)

const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const RunState = preload("res://src/save/run_state.gd")

const CLEAR_EVENT_TYPE := "dungeon_cleared"

var _run_state: RunState
var _progression_state
var _completion_resolver: Callable
var _reward_hook: Callable
var _instance: DungeonInstanceState

func configure(run_state, progression_state, completion_resolver: Callable, reward_hook := Callable()) -> Dictionary:
	if not run_state is RunState:
		return _fail("invalid_run_state", "Dungeon runtime requires a RunState.")
	if progression_state == null \
		or not progression_state.has_method("complete_dungeon") \
		or not progression_state.has_method("current_biome_id"):
		return _fail("invalid_progression_state", "Dungeon runtime requires a biome progression boundary.")
	if not completion_resolver.is_valid():
		return _fail("invalid_completion_resolver", "Dungeon runtime requires a completion resolver.")
	_run_state = run_state
	_progression_state = progression_state
	_completion_resolver = completion_resolver
	_reward_hook = reward_hook
	_instance = null
	if not _run_state.dungeon_runtime_state.is_empty():
		_instance = DungeonInstanceState.from_dictionary(_run_state.dungeon_runtime_state)
		var hydration := _validate_hydrated_instance()
		if not hydration.ok:
			_instance = null
			return hydration
	return {"ok": true, "projection": to_projection()}

func enter_dungeon(instance_id: String, dungeon_definition: Dictionary, layout, return_context: Dictionary) -> Dictionary:
	if _instance != null and _instance.lifecycle_state != DungeonInstanceState.STATE_RETURNED:
		return _fail("dungeon_already_active", "Another dungeon lifecycle is already active.")
	var dungeon_id := String(dungeon_definition.get("id", ""))
	var biome_id := String(dungeon_definition.get("biome_id", ""))
	if instance_id.is_empty() or dungeon_id.is_empty() or biome_id.is_empty():
		return _fail("missing_stable_id", "Dungeon entry requires instance, dungeon, and biome stable ids.")
	if _run_state.completed_runtime_dungeon_ids.has(dungeon_id):
		return _fail("duplicate_dungeon_completion", "Canonical dungeon completion was already recorded.")
	if biome_id != String(_progression_state.current_biome_id()):
		return _fail("invalid_biome", "Dungeon must belong to the current progression biome.")
	var world_snapshot := _world_snapshot(layout)
	if world_snapshot.is_empty():
		return _fail("invalid_world_data", "Dungeon entry requires injected WorldData or a fixed layout dictionary.")
	if not _valid_return_context(return_context, biome_id):
		return _fail("invalid_return_context", "Return context requires biome_id and world identity.")

	_instance = DungeonInstanceState.new()
	_instance.lifecycle_state = DungeonInstanceState.STATE_ENTERING
	_instance.instance_id = instance_id
	_instance.dungeon_id = dungeon_id
	_instance.biome_id = biome_id
	_instance.world_data = world_snapshot
	_instance.return_context = return_context.duplicate(true)
	_instance.lifecycle_state = DungeonInstanceState.STATE_ACTIVE
	_persist()
	return {"ok": true, "projection": to_projection()}

func complete_dungeon(completion_payload: Dictionary) -> Dictionary:
	var transition := _require_state(DungeonInstanceState.STATE_ACTIVE, "invalid_completion_transition")
	if not transition.ok:
		return transition
	var resolution = _completion_resolver.call(completion_payload.duplicate(true), to_projection())
	if not _resolver_passed(resolution):
		return _fail("completion_condition_not_met", "Dungeon completion resolver rejected the payload.")

	var clear_event := _build_clear_event(completion_payload)
	var reward_result := {"ok": true}
	if _reward_hook.is_valid():
		var hook_value = _reward_hook.call(clear_event.duplicate(true))
		reward_result = _normalize_hook_result(hook_value)
		if not bool(reward_result.get("ok", false)):
			return _fail("reward_hook_rejected", String(reward_result.get("error", "Dungeon reward hook rejected completion.")))

	var progression_result: Dictionary = _progression_state.complete_dungeon(_instance.biome_id)
	if not progression_result.ok:
		return _fail(String(progression_result.get("reason", "progression_rejected")), String(progression_result.get("error", "Biome progression rejected dungeon completion.")))

	_instance.lifecycle_state = DungeonInstanceState.STATE_COMPLETED
	_instance.completion_payload = completion_payload.duplicate(true)
	_instance.clear_event = clear_event.duplicate(true)
	_instance.clear_event_emitted = true
	if not _run_state.completed_runtime_dungeon_ids.has(_instance.dungeon_id):
		_run_state.completed_runtime_dungeon_ids.append(_instance.dungeon_id)
	if _reward_hook.is_valid():
		_instance.reward_hook_invoked = true
		_instance.reward_claimed = true
	_persist()
	dungeon_cleared.emit(_instance.clear_event.duplicate(true))
	return {
		"ok": true,
		"clear_event": _instance.clear_event.duplicate(true),
		"reward_result": reward_result,
		"projection": to_projection()
	}

func complete_boss_encounter(resolution_event: Dictionary) -> Dictionary:
	if String(resolution_event.get("event_type", "")) != "boss_encounter_resolved":
		return _fail("invalid_boss_resolution", "Dungeon runtime requires the common boss resolution event.")
	if String(resolution_event.get("dungeon_id", "")) != String(to_projection().get("dungeon_id", "")):
		return _fail("invalid_boss_resolution", "Boss resolution must match the active dungeon.")
	var resolution_type := String(resolution_event.get("resolution_type", ""))
	if not ["combat", "peaceful"].has(resolution_type):
		return _fail("invalid_boss_resolution", "Only combat or peaceful boss outcomes clear a dungeon.")
	var completion_payload := resolution_event.duplicate(true)
	completion_payload["objective_complete"] = true
	return complete_dungeon(completion_payload)

func begin_return() -> Dictionary:
	var transition := _require_state(DungeonInstanceState.STATE_COMPLETED, "invalid_return_transition")
	if not transition.ok:
		return transition
	_instance.lifecycle_state = DungeonInstanceState.STATE_RETURNING
	_persist()
	return {"ok": true, "return_context": _instance.return_context.duplicate(true), "projection": to_projection()}

func finish_return() -> Dictionary:
	var transition := _require_state(DungeonInstanceState.STATE_RETURNING, "invalid_return_transition")
	if not transition.ok:
		return transition
	_instance.lifecycle_state = DungeonInstanceState.STATE_RETURNED
	_persist()
	return {"ok": true, "return_context": _instance.return_context.duplicate(true), "projection": to_projection()}

func to_projection() -> Dictionary:
	if _instance == null:
		return {"schema_version": 1, "read_only": true, "lifecycle_state": DungeonInstanceState.STATE_OUTSIDE}
	var projection := _instance.to_dictionary()
	projection["read_only"] = true
	return projection

func _build_clear_event(payload: Dictionary) -> Dictionary:
	return {
		"event_type": CLEAR_EVENT_TYPE,
		"dungeon_id": _instance.dungeon_id,
		"biome_id": _instance.biome_id,
		"source_instance_id": _instance.instance_id,
		"resolution_type": String(payload.get("resolution_type", "")),
		"choice_key": String(payload.get("choice_key", "")),
		"run_flag": String(payload.get("run_flag", "")),
		"reward_item_ids": _array_value(payload.get("reward_item_ids", [])),
		"progression_unlock_ids": _array_value(payload.get("progression_unlock_ids", []))
	}

func _world_snapshot(layout) -> Dictionary:
	if typeof(layout) == TYPE_DICTIONARY:
		return layout.duplicate(true)
	if layout != null and layout.has_method("to_dictionary"):
		var snapshot = layout.to_dictionary()
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot.duplicate(true)
	return {}

func _valid_return_context(context: Dictionary, expected_biome_id: String) -> bool:
	var return_biome_id := String(context.get("biome_id", ""))
	if return_biome_id.is_empty() or return_biome_id != expected_biome_id:
		return false
	if _valid_world_id(context.get("world_id")):
		return true
	return _valid_world_seed(context.get("world_seed"))

func _valid_world_id(value) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()

func _valid_world_seed(value) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_finite(float(value)) and float(value) == floor(float(value))
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()

func _validate_hydrated_instance() -> Dictionary:
	if _instance.instance_id.is_empty() or _instance.dungeon_id.is_empty() or _instance.biome_id.is_empty():
		return _fail("invalid_saved_dungeon_state", "Saved dungeon runtime is missing stable ids.")
	if not [
		DungeonInstanceState.STATE_ENTERING,
		DungeonInstanceState.STATE_ACTIVE,
		DungeonInstanceState.STATE_COMPLETED,
		DungeonInstanceState.STATE_RETURNING,
		DungeonInstanceState.STATE_RETURNED
	].has(_instance.lifecycle_state):
		return _fail("invalid_saved_dungeon_state", "Saved dungeon runtime has an unknown lifecycle state.")
	if _instance.world_data.is_empty() or not _valid_return_context(_instance.return_context, _instance.biome_id):
		return _fail("invalid_saved_dungeon_state", "Saved dungeon runtime has invalid world or return context.")
	if _instance.lifecycle_state != DungeonInstanceState.STATE_RETURNED \
		and _instance.biome_id != String(_progression_state.current_biome_id()):
		return _fail("invalid_saved_dungeon_state", "Saved dungeon runtime does not match the current progression biome.")
	return {"ok": true}

func _require_state(expected_state: String, reason: String) -> Dictionary:
	if _instance == null or _instance.lifecycle_state != expected_state:
		return _fail(reason, "Dungeon lifecycle transition is not legal from the current state.")
	return {"ok": true}

func _persist() -> void:
	_run_state.dungeon_runtime_state = _instance.to_dictionary() if _instance != null else {}

func _resolver_passed(result) -> bool:
	if typeof(result) == TYPE_BOOL:
		return bool(result)
	if typeof(result) == TYPE_DICTIONARY:
		return bool(result.get("ok", false))
	return false

func _normalize_hook_result(result) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		return result.duplicate(true)
	if typeof(result) == TYPE_BOOL:
		return {"ok": bool(result)}
	return {"ok": true, "value": result}

func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
