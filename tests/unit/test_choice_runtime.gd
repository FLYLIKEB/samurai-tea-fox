extends RefCounted

const ChoiceRuntime = preload("res://src/choice/choice_runtime.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const TailState = preload("res://src/player/tail_state.gd")

class FakeCatalog:
	extends RefCounted
	var data_version := "choice-fixture-v1"
	var definitions: Dictionary

	func _init(value: Dictionary) -> void:
		definitions = value

	func get_definitions(key: String) -> Array:
		return definitions.get(key, [])

func run(asserts) -> void:
	_asserts_catalog_definitions_are_data_driven(asserts)
	_asserts_choice_results_apply_to_run_state(asserts)
	_asserts_choice_tail_effects_apply_to_run_state_only(asserts)
	_asserts_duplicate_and_exclusive_choices_are_rejected(asserts)
	_asserts_availability_conditions_and_target_state_are_checked(asserts)
	_asserts_narrative_commands_apply_choices(asserts)
	_asserts_invalid_state_and_narrative_preflight_are_rejected(asserts)

func _asserts_catalog_definitions_are_data_driven(asserts) -> void:
	var runtime := ChoiceRuntime.new()
	var result: Dictionary = runtime.from_catalog(FakeCatalog.new({"choices": _definitions()}))
	asserts.true_value(result.ok, "choice definitions load from catalog")
	asserts.equal(runtime.definition_for("daimyo_relinquish_tea").choice_key, "DAIMYO_RELINQUISH_TEA", "source choice key is preserved")
	var added: Dictionary = runtime.register_definition(_definition("third_choice", "THIRD_CHOICE", "third_flag", false, false, ["寂·여백"], "세 번째 다실 영향"))
	asserts.true_value(added.ok, "a new data row can be registered without runtime code changes")
	asserts.true_value(runtime.apply_choice("third_choice", _empty_run()).ok, "new data row uses the default result pipeline")
	var invalid: Dictionary = ChoiceRuntime.new().from_catalog(FakeCatalog.new({"choices": [{"id": "broken", "name": "Broken", "status": "확정"}]}))
	asserts.false_value(invalid.ok, "missing choice result fields are rejected")

func _asserts_choice_results_apply_to_run_state(asserts) -> void:
	var runtime := _runtime(asserts)
	var run_state := _empty_run()
	var meta_state := MetaState.new().to_dictionary()
	var before_meta := meta_state.duplicate(true)
	var result: Dictionary = runtime.apply_choice("daimyo_relinquish_tea", run_state, {"target_id": "daimyo", "exclusive_group": "daimyo_resolution"})
	asserts.true_value(result.ok, "choice applies")
	asserts.equal(run_state.narrative_flags, ["daimyo_relinquished_tea"], "run flag is recorded once")
	asserts.equal(run_state.target_survival.daimyo, true, "target survival result is recorded")
	asserts.equal(run_state.philosophy_marks, ["和·공존", "敬·마주봄"], "philosophy marks are recorded without a score")
	asserts.equal(run_state.final_room_effects[0].effect, "관계형 지원 효과", "final tea room effect is projected from applied choice")
	asserts.false_value(run_state.has("morality_score"), "choice state has no hidden morality score")
	asserts.equal(result.meta_events[0].type, "choice_meta_record_requested", "meta persistence is emitted as an event")
	asserts.equal(meta_state, before_meta, "choice runtime does not mutate meta state")
	var projection: Dictionary = runtime.projection(run_state)
	asserts.equal(projection.run_flags, ["daimyo_relinquished_tea"], "projection exposes run flags")
	asserts.equal(projection.target_survival.daimyo, true, "projection exposes target survival")
	asserts.equal(projection.philosophy_marks, ["和·공존", "敬·마주봄"], "projection exposes philosophy marks")
	asserts.equal(projection.final_room_effects.size(), 1, "projection exposes final room effects")

func _asserts_choice_tail_effects_apply_to_run_state_only(asserts) -> void:
	var tail_choice := _definition("spare_old_yokai", "SPARE_OLD_YOKAI", "spared_old_yokai", true, true, ["和·공존"], "조화 경로 영향")
	tail_choice["tail_stage"] = 3
	tail_choice["tail_path_flags"] = ["humanity", "harmony"]
	var runtime := ChoiceRuntime.new()
	asserts.true_value(runtime.from_catalog(FakeCatalog.new({"choices": [tail_choice]})).ok, "choice with optional tail effect loads")
	var run_state := _empty_run()
	var meta_state := MetaState.new().to_dictionary()
	var result: Dictionary = runtime.apply_choice("spare_old_yokai", run_state)
	asserts.true_value(result.ok, "choice tail effect applies")
	asserts.equal(run_state.tails, 3, "choice tail effect mirrors tail count in run state")
	asserts.equal(run_state.tail_state.stage, 3, "choice tail effect advances run-scoped TailState")
	asserts.equal(run_state.tail_state.path_flags, ["humanity", "harmony"], "choice tail effect records stable path flags")
	asserts.equal(result.meta_events[1].type, "tail_stage_reached", "choice emits meta fact event for tail experience")
	asserts.equal(result.meta_events[1].value, 3, "tail meta event carries reached stage only")
	asserts.false_value(meta_state.has("tails"), "choice tail effect does not create persistent tail count")

	var invalid_tail_choice := _definition("yokai_regret", "YOKAI_REGRET", "yokai_regret", false, true, [], "퇴행 없음")
	invalid_tail_choice["tail_stage"] = 2
	var blocked: Dictionary = runtime.register_definition(invalid_tail_choice)
	asserts.true_value(blocked.ok, "lower tail choice data can be registered")
	var regression: Dictionary = runtime.apply_choice("yokai_regret", run_state)
	asserts.false_value(regression.ok, "choice cannot regress tail stage")
	asserts.equal(regression.reason, "tail_stage_regression", "choice tail regression has stable reason")
	asserts.false_value(run_state.choice_history.has("yokai_regret"), "failed tail preflight does not record choice")

func _asserts_duplicate_and_exclusive_choices_are_rejected(asserts) -> void:
	var runtime := _runtime(asserts)
	var run_state := _empty_run()
	asserts.true_value(runtime.apply_choice("daimyo_relinquish_tea", run_state, {"exclusive_group": "daimyo_resolution"}).ok, "first exclusive choice applies")
	var duplicate: Dictionary = runtime.apply_choice("daimyo_relinquish_tea", run_state, {"exclusive_group": "daimyo_resolution"})
	asserts.false_value(duplicate.ok, "duplicate choice is rejected")
	asserts.equal(duplicate.reason, "choice_already_applied", "duplicate rejection has a stable reason")
	var exclusive: Dictionary = runtime.apply_choice("daimyo_defeat", run_state, {"exclusive_group": "daimyo_resolution"})
	asserts.false_value(exclusive.ok, "another choice in an occupied group is rejected")
	asserts.equal(exclusive.reason, "choice_group_already_resolved", "exclusive rejection has a stable reason")
	asserts.false_value(run_state.narrative_flags.has("daimyo_defeated"), "failed choice does not partially mutate state")

func _asserts_availability_conditions_and_target_state_are_checked(asserts) -> void:
	var conditional := _definition("conditional_choice", "CONDITIONAL_CHOICE", "conditional_flag", false, true, [], "조건부 영향")
	conditional["conditions"] = [{"type": "run_flag", "id": "met_daimyo"}]
	var runtime := ChoiceRuntime.new()
	asserts.true_value(runtime.from_catalog(FakeCatalog.new({"choices": [conditional]})).ok, "conditional choice definition loads")
	var run_state := _empty_run()
	var blocked: Dictionary = runtime.apply_choice("conditional_choice", run_state, {"target_id": "daimyo", "target_alive": true})
	asserts.equal(blocked.reason, "choice_condition_failed", "unmet run condition blocks choice")
	run_state.narrative_flags.append("met_daimyo")
	var dead_target: Dictionary = runtime.apply_choice("conditional_choice", run_state, {"target_id": "daimyo", "target_alive": false})
	asserts.equal(dead_target.reason, "choice_target_unavailable", "dead target blocks a choice that requires survival")
	asserts.equal(run_state.choice_history, [], "failed availability checks do not record a choice")

func _asserts_narrative_commands_apply_choices(asserts) -> void:
	var runtime := _runtime(asserts)
	var run_state := _empty_run()
	var command := GameCommand.new(GameCommand.Type.NARRATIVE_RESULT, Vector2i.ZERO, -1, {"result": {"type": "apply_choice", "id": "daimyo_defeat"}})
	var result: Dictionary = runtime.apply_narrative_command(command, run_state, {"target_id": "daimyo"})
	asserts.true_value(result.ok, "narrative apply_choice command enters the choice result pipeline")
	asserts.true_value(run_state.narrative_flags.has("daimyo_defeated"), "narrative choice command applies its run flag")
	var wrong_command := GameCommand.new(GameCommand.Type.MOVE)
	asserts.equal(runtime.apply_narrative_command(wrong_command, run_state).reason, "invalid_choice_command", "unrelated commands are rejected")

func _asserts_invalid_state_and_narrative_preflight_are_rejected(asserts) -> void:
	var choice_runtime := _runtime(asserts)
	var null_state: Dictionary = choice_runtime.apply_choice("daimyo_defeat", null)
	asserts.false_value(null_state.ok, "null run state cannot report a successful choice")
	asserts.equal(null_state.reason, "invalid_choice_state", "invalid run state has a stable reason")
	var malformed_state := _empty_run()
	malformed_state["choice_history"] = "not-an-array"
	asserts.equal(choice_runtime.apply_choice("daimyo_defeat", malformed_state).reason, "invalid_choice_state", "malformed choice state is rejected before mutation")

	var narrative_result: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"choices": _definitions(),
		"events": [{
			"id": "daimyo_resolution",
			"name": "Daimyo Resolution",
			"status": "확정",
			"replay_policy": "once",
			"start_node_id": "start",
			"nodes": [{"id": "start", "text": "", "options": [{"id": "defeat", "display_text": "Defeat", "results": [{"type": "apply_choice", "id": "daimyo_defeat"}], "next_node_id": "", "completes_event": true}]}]
		}]
	}))
	asserts.true_value(narrative_result.ok, "choice narrative fixture initializes")
	var run_state := _empty_run()
	run_state.choice_group_selections["daimyo_resolution"] = "daimyo_relinquish_tea"
	run_state["narrative_event_counts"] = {}
	var blocked: Dictionary = narrative_result.runtime.select_option("daimyo_resolution", "start", "defeat", run_state, null, choice_runtime, {"exclusive_group": "daimyo_resolution"})
	asserts.false_value(blocked.ok, "narrative selection preflights choice availability")
	asserts.equal(blocked.reason, "choice_group_already_resolved", "preflight preserves choice rejection reason")
	asserts.equal(run_state.narrative_event_counts, {}, "failed choice preflight does not complete the narrative event")

func _runtime(asserts) -> ChoiceRuntime:
	var result: Dictionary = ChoiceRuntime.new().from_catalog(FakeCatalog.new({"choices": _definitions()}))
	asserts.true_value(result.ok, "choice fixture initializes")
	return result.runtime

func _empty_run() -> Dictionary:
	return {
		"narrative_flags": [],
		"inventory": {},
		"current_biome_id": "common_region",
		"choice_history": [],
		"choice_group_selections": {},
		"target_survival": {},
		"philosophy_marks": [],
		"final_room_effects": [],
		"tail_state": TailState.default_dictionary(),
		"tails": 1
	}

func _definitions() -> Array:
	return [
		_definition("daimyo_relinquish_tea", "DAIMYO_RELINQUISH_TEA", "daimyo_relinquished_tea", true, true, ["和·공존", "敬·마주봄"], "관계형 지원 효과"),
		_definition("daimyo_defeat", "DAIMYO_DEFEAT", "daimyo_defeated", true, true, ["清·절제", "요괴성·힘"], "자원 압박형 효과")
	]

func _definition(id: String, choice_key: String, run_flag: String, meta_record: bool, target_survives: bool, philosophy_marks: Array, final_room_effect: String) -> Dictionary:
	return {
		"id": id,
		"name": id,
		"status": "확정",
		"choice_key": choice_key,
		"run_flag": run_flag,
		"display_text": id,
		"resolution": "다도",
		"meta_record": meta_record,
		"target_survives": target_survives,
		"philosophy_marks": philosophy_marks,
		"final_room_effect": final_room_effect
	}
