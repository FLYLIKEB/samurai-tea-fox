extends RefCounted
class_name SenRikyuPhaseTwoRuntime

const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const BossEncounterState = preload("res://src/boss/boss_encounter_state.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")

const BOSS_ID := "sen_rikyu_phase_2"
const DUNGEON_ID := "final_tea_room"
const ENCOUNTER_ID := "sen_rikyu_phase_2_encounter"
const PHASE_1_ID := "sen_rikyu_phase_1"
const PHASE_1_EVENT_ID := "sen_rikyu_phase_1_last_tea"
const PHASE_2_ID := "sen_rikyu_phase_2"
const PHASE_3_ID := "sen_rikyu_phase_3"
const PHASE_1_COMMANDS := ["share_last_tea", "refuse_last_tea"]
const ARENA_IDLE := "idle"
const ARENA_COMBAT := "combat"
const ARENA_PHASE_3_READY := "phase_3_ready"

signal arena_state_changed(event: Dictionary)
signal phase_three_transition_requested(command: Dictionary)

class BossCombatTarget:
	extends RefCounted
	var combat_id := ""
	var hp := 1
	var hp_max := 1
	var received_damage_events := []

	func _init(new_combat_id: String, new_hp: int) -> void:
		combat_id = new_combat_id
		hp_max = maxi(new_hp, 1)
		hp = hp_max

	func get_combat_id() -> String:
		return combat_id

	func apply_damage_event(event: Dictionary) -> int:
		var applied := mini(maxi(int(event.get("damage", 0)), 0), hp)
		hp -= applied
		received_damage_events.append(event.duplicate(true))
		return applied

var boss_definition: BossDefinition
var boss_runtime := BossEncounterRuntime.new()
var boss_target: BossCombatTarget
var data_version := ""
var arena_state := ARENA_IDLE
var phase_three_command := {}

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Sen Rikyu Phase 2 requires catalog boss data.")
	var definition_result: Dictionary = BossDefinition.from_catalog(catalog, BOSS_ID)
	if not definition_result.ok:
		return definition_result
	var runtime: SenRikyuPhaseTwoRuntime = load("res://src/dungeon/sen_rikyu_phase_two_runtime.gd").new()
	var configured := runtime.configure(definition_result.definition, String(catalog.get("data_version")) if catalog.has_method("get") else "")
	if not configured.ok:
		return configured
	return {"ok": true, "runtime": runtime}

func configure(definition, new_data_version := "") -> Dictionary:
	if not definition is BossDefinition:
		return _fail("invalid_boss_definition", "Sen Rikyu Phase 2 requires a BossDefinition.")
	if definition.id != BOSS_ID or definition.dungeon_id != DUNGEON_ID:
		return _fail("invalid_phase_two_definition", "Sen Rikyu Phase 2 requires the final tea room boss definition.")
	if not definition.supports_resolution("combat"):
		return _fail("missing_combat_resolution", "Sen Rikyu Phase 2 must use the common combat boss resolution.")
	boss_definition = definition
	data_version = new_data_version
	boss_runtime = BossEncounterRuntime.new()
	var boss_configured := boss_runtime.configure(boss_definition)
	if not boss_configured.ok:
		return boss_configured
	arena_state = ARENA_IDLE
	phase_three_command = {}
	boss_target = null
	return {"ok": true, "projection": to_projection()}

func start_from_phase_one(transition_command) -> Dictionary:
	var validation := _validate_phase_one_transition(transition_command)
	if not validation.ok:
		return validation
	if arena_state != ARENA_IDLE:
		return _fail("phase_two_already_started", "Sen Rikyu Phase 2 arena can only start once.")
	boss_target = BossCombatTarget.new(BOSS_ID, boss_definition.max_hp)
	var started := boss_runtime.start(ENCOUNTER_ID, DUNGEON_ID)
	if not started.ok:
		return started
	arena_state = ARENA_COMBAT
	var event := {"event_type": "sen_rikyu_phase_two_arena_started", "arena_state": arena_state, "boss_id": BOSS_ID, "dungeon_id": DUNGEON_ID, "combat_started": true}
	arena_state_changed.emit(event.duplicate(true))
	return {"ok": true, "event": event, "projection": to_projection()}

func tick(delta_seconds: float) -> Dictionary:
	if arena_state != ARENA_COMBAT:
		return _fail("phase_two_not_active", "Sen Rikyu Phase 2 tick requires an active combat arena.")
	return boss_runtime.tick(delta_seconds)

func handle_player_attack(player_combat_state: CombatState, current_ki: float) -> Dictionary:
	if arena_state != ARENA_COMBAT:
		return _fail("phase_two_not_active", "Sen Rikyu Phase 2 attack requires an active combat arena.")
	if player_combat_state == null:
		return _fail("missing_player_combat", "Sen Rikyu Phase 2 requires the player combat state.")
	var swing: Dictionary = player_combat_state.start_basic_attack("player", current_ki)
	if not swing.ok:
		return swing
	var hit: Dictionary = player_combat_state.apply_swing_hit(swing, boss_target, player_combat_state.config.hit_invulnerability_seconds)
	player_combat_state.finish_swing(swing)
	if not hit.ok:
		return hit
	return _after_boss_damage(hit.applied_damage, {"source": "sword", "damage_event": hit.event})

func handle_player_dodge(player_combat_state: CombatState) -> Dictionary:
	if arena_state != ARENA_COMBAT:
		return _fail("phase_two_not_active", "Sen Rikyu Phase 2 dodge requires an active combat arena.")
	if player_combat_state == null:
		return _fail("missing_player_combat", "Sen Rikyu Phase 2 requires the player combat state.")
	var dodge: Dictionary = player_combat_state.start_dodge()
	if not dodge.ok:
		return dodge
	return {"ok": true, "event": {"event_type": "sen_rikyu_phase_two_dodge", "invulnerable": true, "distance_tiles": float(dodge.distance_tiles)}, "projection": to_projection()}

func cast_player_ability(ability_runtime, slot: int, context := {}) -> Dictionary:
	if arena_state != ARENA_COMBAT:
		return _fail("phase_two_not_active", "Sen Rikyu Phase 2 ability requires an active combat arena.")
	if ability_runtime == null or not ability_runtime.has_method("cast"):
		return _fail("missing_ability_runtime", "Sen Rikyu Phase 2 requires the shared ability runtime.")
	var cast_context := _dictionary_value(context)
	cast_context["targets"] = [boss_target]
	if not cast_context.has("source_id"):
		cast_context["source_id"] = "player"
	var cast_result: Dictionary = ability_runtime.cast(slot, cast_context)
	if not cast_result.ok:
		return cast_result
	return _after_boss_damage(int(cast_result.get("applied_damage", 0)), {"source": "ability", "ability_result": cast_result})

func transition_to_phase_three() -> Dictionary:
	if arena_state == ARENA_PHASE_3_READY:
		return _fail("phase_three_already_requested", "Sen Rikyu Phase 3 transition can only be requested once.")
	if arena_state != ARENA_COMBAT:
		return _fail("phase_two_not_active", "Sen Rikyu Phase 3 transition requires active Phase 2 combat.")
	if boss_target == null or boss_target.hp > 0:
		return _fail("phase_three_condition_not_met", "Sen Rikyu Phase 3 requires Phase 2 combat victory.")
	return _commit_phase_three_transition({"source": "manual"})

func boss_target_for_ability():
	return boss_target

func to_projection() -> Dictionary:
	var boss_projection := boss_runtime.to_projection()
	return {
		"read_only": true,
		"phase": PHASE_2_ID,
		"arena_state": arena_state,
		"boss_id": BOSS_ID,
		"dungeon_id": DUNGEON_ID,
		"combat_started": arena_state in [ARENA_COMBAT, ARENA_PHASE_3_READY],
		"boss_hp": boss_target.hp if boss_target != null else 0,
		"boss_hp_max": boss_target.hp_max if boss_target != null else boss_definition.max_hp if boss_definition != null else 0,
		"boss_projection": boss_projection,
		"phase_3_ready": arena_state == ARENA_PHASE_3_READY,
		"phase_three_command": phase_three_command.duplicate(true)
	}

func _after_boss_damage(_applied_damage: int, payload: Dictionary) -> Dictionary:
	var health_update: Dictionary = boss_runtime.update_health(boss_target.hp)
	if not health_update.ok:
		return health_update
	var result := {"ok": true, "applied_damage": _applied_damage, "payload": payload.duplicate(true), "projection": to_projection()}
	if boss_target.hp <= 0:
		var transition := _commit_phase_three_transition({"source": String(payload.get("source", "damage")), "damage_payload": payload.duplicate(true)})
		if not transition.ok:
			return transition
		result["phase_three_transition"] = transition
		result["projection"] = to_projection()
	return result

func _commit_phase_three_transition(context: Dictionary) -> Dictionary:
	var resolution: Dictionary = boss_runtime.handle_resolution({"type": "victory", "run_flag": "sen_rikyu_phase2_victory"})
	if not resolution.ok:
		return resolution
	var command := GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {
		"phase": PHASE_2_ID,
		"result": {"type": "start_phase", "id": PHASE_3_ID},
		"boss_id": BOSS_ID,
		"dungeon_id": DUNGEON_ID,
		"resolution_event": resolution.event.duplicate(true),
		"context": context.duplicate(true)
	})
	phase_three_command = command.to_dictionary()
	arena_state = ARENA_PHASE_3_READY
	phase_three_transition_requested.emit(phase_three_command.duplicate(true))
	return {"ok": true, "resolution": resolution, "transition_command": command, "projection": to_projection()}

func _validate_phase_one_transition(transition_command) -> Dictionary:
	var payload := {}
	if transition_command is GameCommand:
		if transition_command.type != GameCommand.Type.NARRATIVE_RESULT:
			return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 requires a Phase 1 narrative transition command.")
		payload = transition_command.payload
	else:
		return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 requires a Phase 1 transition command.")
	if String(payload.get("event_id", "")) != PHASE_1_EVENT_ID:
		return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 must follow the Phase 1 event.")
	if String(payload.get("phase", "")) != PHASE_1_ID:
		return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 must follow Phase 1.")
	if not PHASE_1_COMMANDS.has(String(payload.get("selected_command", ""))):
		return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 requires a resolved Phase 1 tea/refusal command.")
	var result := _dictionary_value(payload.get("result", {}))
	if String(result.get("type", "")) != "start_phase" or String(result.get("id", "")) != PHASE_2_ID:
		return _fail("invalid_phase_one_transition", "Sen Rikyu Phase 2 requires an explicit start_phase command.")
	if bool(payload.get("combat_started", false)):
		return _fail("invalid_phase_one_transition", "Phase 1 transition command must not start combat itself.")
	return {"ok": true}

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
