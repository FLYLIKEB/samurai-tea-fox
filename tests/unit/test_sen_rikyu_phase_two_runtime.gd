extends RefCounted

const AbilityDefinition = preload("res://src/ability/ability_definition.gd")
const AbilityRuntime = preload("res://src/ability/ability_runtime.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")

class PlayerProxy:
	extends RefCounted
	var combat_state
	var resources
	var ability_runtime = null
	var ability_tail_query = null
	var ability_time_state = null

	func _init(new_combat_state, new_resources) -> void:
		combat_state = new_combat_state
		resources = new_resources

	func get_combat_id() -> String:
		return "player"

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads Sen Rikyu Phase 2 data")
	_assert_arena_starts_from_phase_one_transition(asserts, catalog)
	_assert_pattern_cycle_and_phase_change_use_boss_runtime(asserts, catalog)
	_assert_sword_and_dodge_use_common_combat_contract(asserts, catalog)
	_assert_ability_damage_and_phase_three_transition(asserts, catalog)
	_assert_main_exposes_phase_two_runtime(asserts, catalog)

func _assert_arena_starts_from_phase_one_transition(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseTwoRuntime = SenRikyuPhaseTwoRuntime.from_catalog(catalog).runtime
	asserts.equal(runtime.start_from_phase_one({"phase": "sen_rikyu_phase_1", "result": {"type": "start_phase", "id": SenRikyuPhaseTwoRuntime.PHASE_2_ID}}).reason, "invalid_phase_one_transition", "phase two rejects raw forged dictionaries")
	asserts.equal(runtime.start_from_phase_one(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)).reason, "invalid_phase_one_transition", "phase two rejects non-narrative commands")
	asserts.equal(runtime.start_from_phase_one(GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {"phase": "wrong", "result": {"type": "start_phase", "id": SenRikyuPhaseTwoRuntime.PHASE_2_ID}})).reason, "invalid_phase_one_transition", "phase two rejects non-phase-one transition")
	var started: Dictionary = runtime.start_from_phase_one(_phase_one_command())
	asserts.true_value(started.ok, "phase two starts from explicit phase one command")
	asserts.equal(started.event.arena_state, SenRikyuPhaseTwoRuntime.ARENA_COMBAT, "arena switches to combat state")
	asserts.true_value(started.event.combat_started, "phase two starts combat only at arena transition")
	asserts.equal(started.projection.boss_projection.lifecycle_state, "active", "common boss runtime is active")
	asserts.equal(started.projection.boss_hp, 240, "boss hp comes from generated boss DB")
	asserts.equal(runtime.start_from_phase_one(_phase_one_command()).reason, "phase_two_already_started", "duplicate phase two start is rejected")

func _assert_pattern_cycle_and_phase_change_use_boss_runtime(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseTwoRuntime = SenRikyuPhaseTwoRuntime.from_catalog(catalog).runtime
	asserts.true_value(runtime.start_from_phase_one(_phase_one_command()).ok, "pattern fixture starts")
	var first: Dictionary = runtime.tick(2.0)
	asserts.true_value(first.scheduled, "first pattern schedules")
	asserts.equal(first.event.pattern_id, "single_cut", "first generated pattern is selected")
	var second: Dictionary = runtime.tick(2.0)
	asserts.true_value(second.scheduled, "second pattern schedules")
	asserts.equal(second.event.pattern_id, "tea_room_step", "patterns cycle through generated phase data")
	var combat := _combat_state(140)
	asserts.true_value(runtime.handle_player_attack(combat, 100).ok, "attack damages boss into next phase")
	combat.tick(2.0)
	var third: Dictionary = runtime.tick(2.0)
	asserts.true_value(third.scheduled, "desperate phase pattern schedules")
	asserts.equal(third.event.phase_id, "empty_cup_pressure", "boss runtime changes phase from HP threshold")
	asserts.equal(third.event.pattern_id, "returning_cut", "second phase starts its own pattern cursor")

func _assert_sword_and_dodge_use_common_combat_contract(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseTwoRuntime = SenRikyuPhaseTwoRuntime.from_catalog(catalog).runtime
	asserts.true_value(runtime.start_from_phase_one(_phase_one_command()).ok, "combat fixture starts")
	var combat := _combat_state(30)
	var hit: Dictionary = runtime.handle_player_attack(combat, 100)
	asserts.true_value(hit.ok, "player sword attack hits through common CombatState")
	asserts.equal(hit.applied_damage, 30, "damage comes from common combat config")
	asserts.equal(hit.payload.damage_event.type, "damage", "sword hit uses common damage event contract")
	asserts.equal(runtime.to_projection().boss_hp, 210, "boss HP is updated by common hit result")
	var dodge: Dictionary = runtime.handle_player_dodge(combat)
	asserts.true_value(dodge.ok, "player dodge uses common CombatState")
	asserts.true_value(combat.is_dodge_invulnerable(), "dodge grants common invulnerability window")
	asserts.equal(dodge.event.event_type, "sen_rikyu_phase_two_dodge", "dodge produces arena read event")
	asserts.equal(runtime.transition_to_phase_three().reason, "phase_three_condition_not_met", "phase three cannot start before victory")

func _assert_ability_damage_and_phase_three_transition(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseTwoRuntime = SenRikyuPhaseTwoRuntime.from_catalog(catalog).runtime
	asserts.true_value(runtime.start_from_phase_one(_phase_one_command()).ok, "ability fixture starts")
	var ability_runtime := _ability_runtime(asserts)
	asserts.true_value(ability_runtime.equip(0, "phase_cut", {"tail_count": 1}).ok, "ability equips through shared runtime")
	var resources := PlayerResources.new(100, 100, 100, 20)
	var result: Dictionary = runtime.cast_player_ability(ability_runtime, 0, {"resources": resources, "tail_count": 1})
	asserts.true_value(result.ok, "ability damages Sen Rikyu through shared runtime")
	asserts.equal(result.payload.ability_result.effect_type, "damage", "ability result keeps shared damage effect contract")
	asserts.true_value(result.has("phase_three_transition"), "lethal ability triggers phase three transition")
	asserts.equal(result.phase_three_transition.transition_command.type, GameCommand.Type.NARRATIVE_RESULT, "phase three transition is an explicit command")
	asserts.equal(result.phase_three_transition.transition_command.payload.result.id, SenRikyuPhaseTwoRuntime.PHASE_3_ID, "transition command targets Phase 3")
	asserts.equal(result.phase_three_transition.resolution.event.resolution_type, "combat", "victory is committed through common boss resolution")
	asserts.equal(runtime.transition_to_phase_three().reason, "phase_three_already_requested", "duplicate Phase 3 transition is rejected")

func _assert_main_exposes_phase_two_runtime(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures Sen Rikyu Phase 2 runtime")
	var started: Dictionary = main.start_sen_rikyu_phase_two(_phase_one_command())
	asserts.true_value(started.ok, "main starts Phase 2 from Phase 1 command")
	asserts.equal(main.sen_rikyu_phase_two_runtime.to_projection().arena_state, SenRikyuPhaseTwoRuntime.ARENA_COMBAT, "main exposes active Phase 2 arena")
	main.player = _fake_player(30)
	asserts.true_value(main.submit_action_command(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)), "main routes active Phase 2 attack into arena runtime")
	asserts.equal(main.sen_rikyu_phase_two_runtime.to_projection().boss_hp, 210, "main-routed attack damages Sen Rikyu arena target")
	main.free()

func _phase_one_command() -> GameCommand:
	return GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {
		"event_id": SenRikyuPhaseOneRuntime.EVENT_ID,
		"phase": "sen_rikyu_phase_1",
		"result": {"type": "start_phase", "id": SenRikyuPhaseTwoRuntime.PHASE_2_ID},
		"selected_command": SenRikyuPhaseOneRuntime.COMMAND_SHARE_LAST_TEA,
		"combat_started": false
	})

func _fake_player(damage: int):
	return PlayerProxy.new(_combat_state(damage), PlayerResources.new(100, 100, 100, 20))

func _combat_state(damage: int) -> CombatState:
	return CombatState.new(CombatConfig.new({
		"basic_attack_combo_hits": 3,
		"finisher_knockback_tiles": 1.0,
		"dodge_cooldown_seconds": 0.5,
		"dodge_distance_tiles": 2.0,
		"dodge_invulnerability_seconds": 0.2,
		"ki_attack_multiplier_0": 1.0,
		"ki_attack_multiplier_100": 1.0,
		"ki_max": 100,
		"hit_invulnerability_seconds": 0.1,
		"weapon_id": "fixture_sword",
		"weapon_base_damage": damage,
		"weapon_range_tiles": 1.0,
		"weapon_attack_speed": 10.0
	}))

func _ability_runtime(asserts) -> AbilityRuntime:
	var definition_result: Dictionary = AbilityDefinition.from_dictionary({
		"id": "phase_cut",
		"name": "Phase Cut",
		"type": "공격",
		"tail_requirement": 0,
		"ki_cost": 0,
		"cooldown_seconds": 0.0,
		"base_damage": 240,
		"range": 3.0,
		"duration_seconds": 0.0,
		"status_effect": ""
	})
	asserts.true_value(definition_result.ok, "ability fixture definition is valid")
	return AbilityRuntime.new({"phase_cut": definition_result.definition}, 1)
