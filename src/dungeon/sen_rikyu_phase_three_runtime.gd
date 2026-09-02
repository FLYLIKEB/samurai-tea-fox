extends RefCounted
class_name SenRikyuPhaseThreeRuntime

const FinalRoomStateBuilder = preload("res://src/meta/final_room_state_builder.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")

const EVENT_ID := "sen_rikyu_phase_3_final_victory"
const PHASE_2_BOSS_ID := "sen_rikyu_phase_2"
const PHASE_2_DUNGEON_ID := "final_tea_room"
const PHASE_2_ID := "sen_rikyu_phase_2"
const PHASE_3_ID := "sen_rikyu_phase_3"
const ICHIGO_ICHIE_USED_FLAG := "sen_rikyu_phase3_ichigoichie_used"
const STATE_IDLE := "idle"
const STATE_ACTIVE := "active"
const STATE_RESOLVED := "resolved"

signal ability_pool_built(event: Dictionary)
signal final_victory(event: Dictionary)

var data_version := ""
var final_room_state_builder: FinalRoomStateBuilder
var event_definition := {}
var lifecycle_state := STATE_IDLE
var selected_ability_id := ""
var victory_event := {}

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Sen Rikyu Phase 3 requires catalog data.")
	var event: Dictionary = catalog.find_by_id("events", EVENT_ID)
	if event.is_empty():
		return _fail("missing_phase_three_event", "Missing Sen Rikyu Phase 3 final victory event.")
	var builder_result: Dictionary = FinalRoomStateBuilder.from_catalog(catalog)
	if not builder_result.ok:
		return builder_result
	var runtime: SenRikyuPhaseThreeRuntime = load("res://src/dungeon/sen_rikyu_phase_three_runtime.gd").new()
	runtime.data_version = String(catalog.get("data_version")) if catalog.has_method("get") else ""
	runtime.final_room_state_builder = builder_result.builder
	runtime.event_definition = event.duplicate(true)
	return {"ok": true, "runtime": runtime}

func start(phase_two_transition, run_state) -> Dictionary:
	if lifecycle_state != STATE_IDLE:
		return _fail("phase_three_already_started", "Sen Rikyu Phase 3 can only start once.")
	var validation := _validate_phase_two_transition(phase_two_transition)
	if not validation.ok:
		return validation
	lifecycle_state = STATE_ACTIVE
	var pool := build_ability_pool(run_state)
	if not pool.ok:
		return pool
	return {"ok": true, "ability_pool": pool.ability_pool, "support_hooks": pool.support_hooks, "absence_hooks": pool.absence_hooks, "projection": to_projection(run_state)}

func build_ability_pool(run_state) -> Dictionary:
	var snapshot := _snapshot(run_state)
	var final_room: Dictionary = final_room_state_builder.build(run_state).state if final_room_state_builder != null else {}
	var abilities := []
	var blocked := []
	var used := _array_value(snapshot.get("narrative_flags", [])).has(ICHIGO_ICHIE_USED_FLAG)
	var base := _ability("ichigo_ichie_final_cut", "一期一会의 마지막 베기", ["phase_3"], true)
	if used:
		base["available"] = false
		base["blocked_reason"] = "ichigo_ichie_already_used"
		blocked.append(base)
	else:
		abilities.append(base)
	if _has_any(snapshot, "choice_history", ["daimyo_relinquish_tea"]) or _has_any(snapshot, "narrative_flags", ["daimyo_relinquished_tea"]):
		abilities.append(_ability("daimyo_mercy_reflection", "권력을 내려놓게 한 차의 여운", ["choice", "daimyo"], false))
	if _has_any(snapshot, "discovered_records", ["memory_tea"]) or not _dictionary_value(snapshot.get("memory_tea_cutscene", {})).is_empty():
		abilities.append(_ability("memory_tea_echo", "기억차의 메아리", ["memory_tea"], false))
	if not _array_value(_dictionary_value(snapshot.get("core_tea_ware_collection", {})).get("collected_ids", [])).is_empty():
		abilities.append(_ability("core_tea_ware_resonance", "명물 다기의 울림", ["core_tea_ware"], false))
	abilities.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.id) < String(right.id)
	)
	var support_hooks := _support_hooks(final_room)
	var absence_hooks := _absence_hooks(final_room)
	var event := {"event_type": "sen_rikyu_phase_three_pool_built", "ability_ids": abilities.map(func(item): return item.id), "blocked_ability_ids": blocked.map(func(item): return item.id), "support_hooks": support_hooks, "absence_hooks": absence_hooks}
	ability_pool_built.emit(event.duplicate(true))
	return {"ok": true, "ability_pool": abilities, "blocked_abilities": blocked, "support_hooks": support_hooks, "absence_hooks": absence_hooks, "event": event}

func complete_with_ability(ability_id: String, run_state) -> Dictionary:
	if lifecycle_state != STATE_ACTIVE:
		return _fail("phase_three_not_active", "Sen Rikyu Phase 3 must be active before final victory.")
	var pool := build_ability_pool(run_state)
	if not pool.ok:
		return pool
	var selected := {}
	for ability in pool.ability_pool:
		if String(ability.id) == ability_id:
			selected = ability
			break
	if selected.is_empty():
		return _fail("phase_three_ability_unavailable", "Selected Sen Rikyu Phase 3 ability is not available for this run.")
	if bool(selected.ichigo_ichie):
		_append_unique(run_state, "narrative_flags", ICHIGO_ICHIE_USED_FLAG)
	_append_unique(run_state, "narrative_flags", "sen_rikyu_phase3_victory")
	_append_unique(run_state, "narrative_flags", "sen_rikyu_phase3_ability_%s" % ability_id)
	_increment_event_count(run_state, EVENT_ID)
	selected_ability_id = ability_id
	lifecycle_state = STATE_RESOLVED
	victory_event = {
		"event_type": "sen_rikyu_phase_three_final_victory",
		"event_id": EVENT_ID,
		"phase": PHASE_3_ID,
		"selected_ability_id": ability_id,
		"ability_tags": selected.tags.duplicate(true),
		"support_hooks": pool.support_hooks,
		"absence_hooks": pool.absence_hooks,
		"ending_renderer_required": false,
		"permanent_power_granted": false
	}
	final_victory.emit(victory_event.duplicate(true))
	return {"ok": true, "event": victory_event.duplicate(true), "projection": to_projection(run_state)}

func to_projection(run_state = null) -> Dictionary:
	return {"read_only": true, "phase": PHASE_3_ID, "lifecycle_state": lifecycle_state, "selected_ability_id": selected_ability_id, "victory_event": victory_event.duplicate(true), "ability_pool": build_ability_pool(run_state).get("ability_pool", []) if run_state != null and lifecycle_state != STATE_RESOLVED else []}

func _validate_phase_two_transition(transition) -> Dictionary:
	var payload_result := _transition_payload(transition)
	if not payload_result.ok:
		return payload_result
	var payload: Dictionary = payload_result.payload
	var result := _dictionary_value(payload.get("result", {}))
	if String(payload.get("phase", "")) != PHASE_2_ID or String(result.get("type", "")) != "start_phase" or String(result.get("id", "")) != PHASE_3_ID:
		return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires the Phase 2 victory transition.")
	if String(payload.get("boss_id", "")) != PHASE_2_BOSS_ID or String(payload.get("dungeon_id", "")) != PHASE_2_DUNGEON_ID:
		return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires the Sen Rikyu Phase 2 boss victory.")
	var resolution := _dictionary_value(payload.get("resolution_event", {}))
	if String(resolution.get("resolution_type", "")) != "combat" or String(resolution.get("boss_id", "")) != PHASE_2_BOSS_ID:
		return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires a Phase 2 combat victory resolution.")
	return {"ok": true}

func _transition_payload(transition) -> Dictionary:
	if transition is GameCommand:
		if transition.type != GameCommand.Type.NARRATIVE_RESULT:
			return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires a narrative transition command.")
		return {"ok": true, "payload": transition.payload.duplicate(true)}
	if typeof(transition) == TYPE_DICTIONARY:
		if transition.has("payload"):
			var type_value := int(transition.get("type", -1))
			if type_value != GameCommand.Type.NARRATIVE_RESULT:
				return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires a serialized narrative transition command.")
			return {"ok": true, "payload": _dictionary_value(transition.payload)}
		return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires the serialized Phase 2 transition command.")
	return _fail("invalid_phase_two_transition", "Sen Rikyu Phase 3 requires the Phase 2 transition command.")

func _support_hooks(final_room: Dictionary) -> Array:
	var hooks := []
	for character in _array_value(final_room.get("surviving_characters", [])):
		hooks.append({"type": "character_support", "target_id": String(character.target_id), "character_id": String(character.character_id), "hook_key": "support_%s" % String(character.target_id)})
	hooks.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.hook_key) < String(right.hook_key))
	return hooks

func _absence_hooks(final_room: Dictionary) -> Array:
	var hooks := []
	for relic in _array_value(final_room.get("relics", [])):
		hooks.append({"type": "character_absence", "target_id": String(relic.target_id), "character_id": String(relic.character_id), "hook_key": "absence_%s" % String(relic.target_id)})
	hooks.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.hook_key) < String(right.hook_key))
	return hooks

func _ability(id: String, label: String, tags: Array, ichigo_ichie: bool) -> Dictionary:
	return {"id": id, "label": label, "tags": tags.duplicate(true), "ichigo_ichie": ichigo_ichie, "available": true}

func _snapshot(state) -> Dictionary:
	if state == null:
		return {}
	if state is Dictionary:
		return state.duplicate(true)
	if state.has_method("to_dictionary"):
		return state.to_dictionary()
	return {}

func _append_unique(state, field: String, value: String) -> void:
	if state == null:
		return
	var values := _array_value(_snapshot(state).get(field, []))
	if not values.has(value):
		values.append(value)
	if state is Dictionary:
		state[field] = values
	elif state.has_method("set"):
		state.set(field, values)

func _increment_event_count(state, event_id: String) -> void:
	if state == null:
		return
	var counts := _dictionary_value(_snapshot(state).get("narrative_event_counts", {}))
	counts[event_id] = int(counts.get(event_id, 0)) + 1
	if state is Dictionary:
		state["narrative_event_counts"] = counts
	elif state.has_method("set"):
		state.set("narrative_event_counts", counts)

func _has_any(snapshot: Dictionary, field: String, ids: Array) -> bool:
	var values := _array_value(snapshot.get(field, []))
	for id in ids:
		if values.has(id):
			return true
	return false

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
