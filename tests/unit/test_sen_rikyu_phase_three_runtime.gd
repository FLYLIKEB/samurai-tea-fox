extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")
const SenRikyuPhaseTwoRuntime = preload("res://src/dungeon/sen_rikyu_phase_two_runtime.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads Sen Rikyu Phase 3 data")
	_assert_pool_varies_by_run_record(asserts, catalog)
	_assert_ichigo_ichie_is_single_run_use(asserts, catalog)
	_assert_survival_support_and_absence_hooks_are_deterministic(asserts, catalog)
	_assert_final_victory_event_records_without_permanent_power(asserts, catalog)
	_assert_main_exposes_phase_three_runtime(asserts, catalog)

func _assert_pool_varies_by_run_record(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	var sparse := RunState.new()
	var rich := _rich_run_state()
	var sparse_pool: Dictionary = runtime.build_ability_pool(sparse)
	var rich_pool: Dictionary = runtime.build_ability_pool(rich)
	asserts.true_value(sparse_pool.ok, "sparse pool builds")
	asserts.true_value(rich_pool.ok, "rich pool builds")
	asserts.equal(_ability_ids(sparse_pool.ability_pool), ["ichigo_ichie_final_cut"], "sparse run only has baseline 一期一会 cut")
	asserts.equal(_ability_ids(rich_pool.ability_pool), ["core_tea_ware_resonance", "daimyo_mercy_reflection", "ichigo_ichie_final_cut", "memory_tea_echo"], "rich run choices/tea/memory unlock distinct final skills")

func _assert_ichigo_ichie_is_single_run_use(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	var run_state := RunState.new()
	asserts.true_value(runtime.start(_phase_two_transition(), run_state).ok, "phase three starts from phase two victory")
	var result: Dictionary = runtime.complete_with_ability("ichigo_ichie_final_cut", run_state)
	asserts.true_value(result.ok, "一期一会 ability can finish once")
	asserts.true_value(run_state.narrative_flags.has(SenRikyuPhaseThreeRuntime.ICHIGO_ICHIE_USED_FLAG), "one-time flag is recorded in run state")
	var next_runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	var blocked_pool: Dictionary = next_runtime.build_ability_pool(run_state)
	asserts.false_value(_ability_ids(blocked_pool.ability_pool).has("ichigo_ichie_final_cut"), "used 一期一会 ability is removed from available pool")
	asserts.equal(blocked_pool.blocked_abilities[0].blocked_reason, "ichigo_ichie_already_used", "blocked reason is stable")

func _assert_survival_support_and_absence_hooks_are_deterministic(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	var run_state := _rich_run_state()
	var pool: Dictionary = runtime.build_ability_pool(run_state)
	asserts.equal(pool.support_hooks.size(), 1, "surviving target produces support hook")
	asserts.equal(pool.support_hooks[0].target_id, "tea_master_oribe", "support hook targets survivor")
	asserts.equal(pool.absence_hooks.size(), 1, "fallen target produces absence hook")
	asserts.equal(pool.absence_hooks[0].target_id, "wasteland_daimyo", "absence hook targets relic")
	var repeated: Dictionary = runtime.build_ability_pool(run_state)
	asserts.equal(repeated.event.ability_ids, pool.event.ability_ids, "pool order is deterministic")
	asserts.equal(repeated.support_hooks, pool.support_hooks, "support hooks are deterministic")
	asserts.equal(repeated.absence_hooks, pool.absence_hooks, "absence hooks are deterministic")

func _assert_final_victory_event_records_without_permanent_power(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	var run_state := _rich_run_state()
	asserts.equal(runtime.complete_with_ability("memory_tea_echo", run_state).reason, "phase_three_not_active", "victory requires active phase")
	asserts.equal(runtime.start({"phase": "wrong", "result": {"type": "start_phase", "id": "sen_rikyu_phase_3"}}, run_state).reason, "invalid_phase_two_transition", "phase three rejects forged transition")
	asserts.true_value(runtime.start(_phase_two_transition(), run_state).ok, "phase three starts for rich run")
	asserts.equal(runtime.complete_with_ability("missing", run_state).reason, "phase_three_ability_unavailable", "unavailable final ability is rejected")
	var result: Dictionary = runtime.complete_with_ability("memory_tea_echo", run_state)
	asserts.true_value(result.ok, "available final ability completes Phase 3")
	asserts.equal(result.event.event_id, SenRikyuPhaseThreeRuntime.EVENT_ID, "victory event uses generated event id")
	asserts.false_value(result.event.permanent_power_granted, "victory does not grant permanent power stat")
	asserts.false_value(result.event.ending_renderer_required, "runtime does not render ending")
	asserts.equal(run_state.narrative_event_counts[SenRikyuPhaseThreeRuntime.EVENT_ID], 1, "victory event count is recorded once")
	asserts.true_value(run_state.narrative_flags.has("sen_rikyu_phase3_victory"), "victory run flag is recorded")

	var actual_runtime: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	asserts.true_value(actual_runtime.start(_actual_phase_two_command(asserts, catalog), _rich_run_state()).ok, "phase three accepts the actual Phase 2 transition command")

func _assert_main_exposes_phase_three_runtime(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = _rich_run_state()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures Phase 3 runtime")
	var started: Dictionary = main.start_sen_rikyu_phase_three(_actual_phase_two_command(asserts, catalog))
	asserts.true_value(started.ok, "main starts Phase 3")
	asserts.true_value(_ability_ids(started.ability_pool).has("core_tea_ware_resonance"), "main exposes run-derived ability pool")
	var victory: Dictionary = main.complete_sen_rikyu_phase_three("core_tea_ware_resonance")
	asserts.true_value(victory.ok, "main completes Phase 3 with selected ability")
	asserts.false_value(victory.event.permanent_power_granted, "main completion does not grant permanent stat")
	main.free()

func _rich_run_state() -> RunState:
	var state := RunState.new()
	state.choice_history = ["daimyo_relinquish_tea"]
	state.narrative_flags = ["daimyo_relinquished_tea"]
	state.discovered_records = ["memory_tea"]
	state.memory_tea_cutscene = {"schema_version": 1, "active_sequence": {}}
	state.core_tea_ware_collection = {"collected_ids": ["war_tea_caddy"]}
	state.target_survival = {"wasteland_daimyo": false, "tea_master_oribe": true}
	return state

func _phase_two_transition() -> Dictionary:
	return {
		"type": GameCommand.Type.NARRATIVE_RESULT,
		"payload": {
			"phase": "sen_rikyu_phase_2",
			"result": {"type": "start_phase", "id": "sen_rikyu_phase_3"},
			"boss_id": "sen_rikyu_phase_2",
			"dungeon_id": "final_tea_room",
			"resolution_event": {"resolution_type": "combat", "boss_id": "sen_rikyu_phase_2"}
		}
	}

func _actual_phase_two_command(asserts, catalog: DataCatalog):
	var phase_two: SenRikyuPhaseTwoRuntime = SenRikyuPhaseTwoRuntime.from_catalog(catalog).runtime
	var start_command := GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {
		"event_id": SenRikyuPhaseOneRuntime.EVENT_ID,
		"phase": "sen_rikyu_phase_1",
		"result": {"type": "start_phase", "id": "sen_rikyu_phase_2"},
		"selected_command": SenRikyuPhaseOneRuntime.COMMAND_SHARE_LAST_TEA,
		"combat_started": false
	})
	asserts.true_value(phase_two.start_from_phase_one(start_command).ok, "actual phase two starts for phase three handoff")
	var victory: Dictionary = phase_two.handle_player_attack(_combat_state(240), 100)
	asserts.true_value(victory.ok, "actual phase two victory creates phase three command")
	return victory.phase_three_transition.transition_command

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

func _ability_ids(abilities: Array) -> Array:
	var ids := []
	for ability in abilities:
		ids.append(String(ability.id))
	return ids
