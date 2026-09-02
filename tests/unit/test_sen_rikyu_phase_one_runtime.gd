extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SenRikyuPhaseOneRuntime = preload("res://src/dungeon/sen_rikyu_phase_one_runtime.gd")

class FakeTeaService:
	extends RefCounted
	var prepared := true
	var consumed := false
	var starts := 0
	var completes := 0

	func has_prepared_tea(slot_index: int) -> bool:
		return prepared and slot_index == 0

	func start_drinking(slot_index: int, context := {}) -> Dictionary:
		if not has_prepared_tea(slot_index):
			return {"ok": false, "reason": "empty_quickslot", "error": "fixture"}
		starts += 1
		return {"ok": true, "action": {"slot": slot_index, "prepared_id": "fixture_prepared", "tea_id": "fixture_tea", "context": context.duplicate(true)}}

	func complete_drinking(action: Dictionary, _resources = null) -> Dictionary:
		if int(action.get("slot", -1)) != 0:
			return {"ok": false, "reason": "bad_action", "error": "fixture"}
		prepared = false
		consumed = true
		completes += 1
		return {"ok": true, "consumed": true, "action": action.duplicate(true), "effect": {}}

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads Sen Rikyu phase one data")
	_assert_start_reveals_name_without_combat(asserts, catalog)
	_assert_share_last_tea_uses_choice_and_meta_branch(asserts, catalog)
	_assert_refuse_last_tea_transitions_without_combat(asserts, catalog)
	_assert_invalid_or_missing_tea_never_starts_combat(asserts, catalog)
	_assert_main_exposes_phase_one_runtime(asserts, catalog)

func _assert_start_reveals_name_without_combat(asserts, catalog: DataCatalog) -> void:
	var runtime: SenRikyuPhaseOneRuntime = SenRikyuPhaseOneRuntime.from_catalog(catalog, FakeTeaService.new()).runtime
	var started: Dictionary = runtime.start(RunState.new(), {})
	asserts.true_value(started.ok, "Sen Rikyu phase one starts")
	asserts.equal(started.name_reveal_event.from_name, "???", "phase one starts from hidden name")
	asserts.equal(started.name_reveal_event.revealed_name, "센리큐", "phase one reveals Sen Rikyu")
	asserts.false_value(started.name_reveal_event.combat_started, "name reveal does not start combat")
	asserts.equal(started.projection.revealed_name, "센리큐", "projection exposes revealed name after hook")
	asserts.false_value(started.projection.combat_started, "phase one projection keeps combat disabled")
	asserts.equal(started.read_model.options.size(), 2, "start read model exposes tea/refusal options")

func _assert_share_last_tea_uses_choice_and_meta_branch(asserts, catalog: DataCatalog) -> void:
	var tea := FakeTeaService.new()
	var runtime: SenRikyuPhaseOneRuntime = SenRikyuPhaseOneRuntime.from_catalog(catalog, tea).runtime
	var run_state := RunState.new()
	run_state.narrative_flags.append("daimyo_relinquished_tea")
	run_state.choice_history.append("daimyo_relinquish_tea")
	var meta_state := {"run_count": 3, "past_choice_ids": [], "dialogue_memory_flags": [], "unlocked_meta_flags": [], "reached_place_ids": [], "death_record_ids": []}
	asserts.true_value(runtime.start(run_state, meta_state).ok, "phase one starts for shared tea")
	var result: Dictionary = runtime.handle_command(SenRikyuPhaseOneRuntime.COMMAND_SHARE_LAST_TEA, {"slot": 0}, run_state, meta_state)
	asserts.true_value(result.ok, "sharing last tea resolves phase one")
	asserts.true_value(result.consumed, "sharing last tea consumes prepared tea")
	asserts.true_value(tea.consumed, "tea service observed the last tea consumption")
	asserts.false_value(result.combat_started, "sharing last tea does not start attack combat")
	asserts.equal(result.dialogue_branch.id, "shared_past_mercy", "past choice branch wins over generic repetition branch")
	asserts.true_value(run_state.narrative_flags.has("sen_rikyu_phase1_shared_tea"), "share command records run flag")
	asserts.true_value(run_state.narrative_flags.has("sen_rikyu_phase1_dialogue_past_choice"), "selected dialogue records branch flag")
	asserts.equal(run_state.narrative_event_counts[SenRikyuPhaseOneRuntime.EVENT_ID], 1, "phase one records narrative completion")
	asserts.equal(result.transition_command.type, GameCommand.Type.NARRATIVE_RESULT, "phase two transition is an explicit command")
	asserts.equal(result.transition_command.payload.result.id, SenRikyuPhaseOneRuntime.PHASE_2_ID, "transition command targets phase two")
	asserts.false_value(result.transition_command.payload.combat_started, "phase two transition command does not start combat itself")
	asserts.true_value(result.projection.phase_2_ready, "projection marks phase two as ready")
	asserts.equal(runtime.handle_command(SenRikyuPhaseOneRuntime.COMMAND_REFUSE_LAST_TEA).reason, "phase_one_not_active", "phase one cannot be completed twice")

func _assert_refuse_last_tea_transitions_without_combat(asserts, catalog: DataCatalog) -> void:
	var tea := FakeTeaService.new()
	var runtime: SenRikyuPhaseOneRuntime = SenRikyuPhaseOneRuntime.from_catalog(catalog, tea).runtime
	var run_state := RunState.new()
	var meta_state := {"run_count": 2, "past_choice_ids": [], "dialogue_memory_flags": [], "unlocked_meta_flags": [], "reached_place_ids": [], "death_record_ids": []}
	asserts.true_value(runtime.start(run_state, meta_state).ok, "phase one starts for refusal")
	var result: Dictionary = runtime.handle_command(SenRikyuPhaseOneRuntime.COMMAND_REFUSE_LAST_TEA, {}, run_state, meta_state)
	asserts.true_value(result.ok, "refusing last tea resolves phase one")
	asserts.false_value(result.consumed, "refusal does not consume prepared tea")
	asserts.false_value(tea.consumed, "tea service is not used by refusal")
	asserts.false_value(result.combat_started, "refusal still does not start combat in phase one")
	asserts.equal(result.dialogue_branch.id, "refused_repetition", "meta run count selects repetition refusal dialogue")
	asserts.true_value(run_state.narrative_flags.has("sen_rikyu_phase1_refused_tea"), "refusal records run flag")
	asserts.equal(result.transition_command.payload.result.id, SenRikyuPhaseOneRuntime.PHASE_2_ID, "refusal also hands off to phase two explicitly")

func _assert_invalid_or_missing_tea_never_starts_combat(asserts, catalog: DataCatalog) -> void:
	var missing_tea := FakeTeaService.new()
	missing_tea.prepared = false
	var runtime: SenRikyuPhaseOneRuntime = SenRikyuPhaseOneRuntime.from_catalog(catalog, missing_tea).runtime
	asserts.true_value(runtime.start(RunState.new(), {}).ok, "phase one starts for missing-tea check")
	var missing: Dictionary = runtime.handle_command(SenRikyuPhaseOneRuntime.COMMAND_SHARE_LAST_TEA, {"slot": 0}, RunState.new(), {})
	asserts.false_value(missing.ok, "sharing requires prepared tea")
	asserts.equal(missing.reason, "missing_prepared_tea", "missing tea has stable reason")
	asserts.false_value(runtime.to_projection().combat_started, "missing tea failure does not start combat")

	var attack_runtime: SenRikyuPhaseOneRuntime = SenRikyuPhaseOneRuntime.from_catalog(catalog, FakeTeaService.new()).runtime
	asserts.true_value(attack_runtime.start(RunState.new(), {}).ok, "phase one starts for attack rejection")
	var attack: Dictionary = attack_runtime.handle_command("attack_first", {}, RunState.new(), {})
	asserts.false_value(attack.ok, "phase one rejects attack command")
	asserts.equal(attack.reason, "invalid_phase_one_command", "attack rejection has stable reason")
	asserts.false_value(attack_runtime.to_projection().combat_started, "rejected attack does not start combat")

func _assert_main_exposes_phase_one_runtime(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures Sen Rikyu phase one runtime")
	var started: Dictionary = main.start_sen_rikyu_phase_one({})
	asserts.true_value(started.ok, "main starts Sen Rikyu phase one")
	asserts.equal(started.projection.revealed_name, "센리큐", "main exposes name reveal projection")
	var invalid: Dictionary = main.handle_sen_rikyu_phase_one_command("attack_first", {}, {})
	asserts.false_value(invalid.ok, "main-routed phase one rejects direct attack")
	asserts.false_value(main.sen_rikyu_phase_one_runtime.to_projection().combat_started, "main-routed rejection keeps combat disabled")
	main.free()
