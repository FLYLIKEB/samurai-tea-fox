extends RefCounted

const AbilityDefinition = preload("res://src/ability/ability_definition.gd")
const TailState = preload("res://src/player/tail_state.gd")

func run(asserts) -> void:
	_assert_default_run_state(asserts)
	_assert_choice_and_event_transitions_use_stable_ids(asserts)
	_assert_forward_only_stage_contract(asserts)
	_assert_transition_history_validation(asserts)
	_assert_ability_candidates_are_tail_gated(asserts)
	_assert_serialization_round_trip_is_detached(asserts)

func _assert_default_run_state(asserts) -> void:
	var tail := TailState.new()
	asserts.equal(tail.stage, 1, "tail state starts each run at stage one")
	asserts.equal(tail.tail_count, 1, "tail count mirrors the run tail stage")
	asserts.equal(tail.path_flags, [], "tail state starts without path flags")
	asserts.equal(tail.transition_history[0].source_kind, "run_start", "tail history records run start")

func _assert_choice_and_event_transitions_use_stable_ids(asserts) -> void:
	var tail := TailState.new()
	var choice_result := tail.apply_choice_result({
		"id": "mercy_at_old_gate",
		"choice_key": "MERCY_AT_OLD_GATE",
		"tail_stage": 2,
		"tail_path_flags": ["humanity", "harmony"]
	})
	asserts.true_value(choice_result.ok, "stable choice tail result applies")
	asserts.true_value(choice_result.advanced, "choice tail result advances stage")
	asserts.equal(tail.stage, 2, "choice result advances to requested stage")
	asserts.equal(tail.path_flags, ["humanity", "harmony"], "choice result records stable path flags")

	var event_result := tail.apply_event_result({
		"id": "fox_fire_trial",
		"tail_stage": 3,
		"tail_path_flags": ["yokai_nature"]
	})
	asserts.true_value(event_result.ok, "stable event tail result applies")
	asserts.equal(tail.stage, 3, "event result advances stage")
	asserts.equal(tail.path_flags, ["humanity", "harmony", "yokai_nature"], "event result appends unique path flags")

	var invalid_choice := TailState.new().apply_choice_result({
		"id": "Display Name",
		"choice_key": "DISPLAY_NAME",
		"tail_stage": 2
	})
	asserts.false_value(invalid_choice.ok, "display-name source IDs are rejected")
	asserts.equal(invalid_choice.reason, "invalid_tail_source_id", "invalid source ID has stable reason")

	var invalid_flag := TailState.new().apply_event_result({
		"id": "fox_fire_trial",
		"tail_stage": 2,
		"tail_path_flags": ["morality_score"]
	})
	asserts.false_value(invalid_flag.ok, "unsupported path flags are rejected")
	asserts.equal(invalid_flag.reason, "invalid_tail_path_flag", "unsupported path flag has stable reason")

func _assert_forward_only_stage_contract(asserts) -> void:
	var tail := TailState.new({"stage": 3, "tail_count": 3})
	var history_size := tail.transition_history.size()
	var same := tail.apply_transition("event", "same_stage_echo", 3, ["harmony"])
	asserts.true_value(same.ok, "same-stage path projection can apply")
	asserts.false_value(same.advanced, "same-stage transition is not an advance")
	asserts.true_value(same.changed, "same-stage transition reports a newly added path flag")
	asserts.equal(tail.stage, 3, "same-stage transition keeps stage")
	asserts.equal(tail.transition_history.size(), history_size + 1, "same-stage path change records a transition")
	asserts.equal(tail.transition_history[-1].source_kind, "event", "same-stage transition records the stable source kind")
	asserts.equal(tail.transition_history[-1].source_id, "same_stage_echo", "same-stage transition records the stable source ID")
	asserts.equal(tail.transition_history[-1].stage, 3, "same-stage transition records the current stage")
	asserts.equal(tail.transition_history[-1].path_flags, ["harmony"], "same-stage transition records newly added flags")
	var duplicate := tail.apply_transition("event", "same_stage_echo", 3, ["harmony"])
	asserts.false_value(duplicate.changed, "same-stage duplicate flag reports no state change")
	asserts.equal(tail.transition_history.size(), history_size + 1, "same-stage duplicate flag does not add history")
	var backward := tail.apply_transition("event", "old_echo", 2)
	asserts.false_value(backward.ok, "tail stage cannot regress")
	asserts.equal(backward.reason, "tail_stage_regression", "regression has stable reason")
	asserts.equal(tail.stage, 3, "failed regression does not mutate stage")

func _assert_transition_history_validation(asserts) -> void:
	var malformed_start := _snapshot_with_history(2, [
		_history_entry("run_start", "run_start", 2)
	])
	var start_result := TailState.validate_dictionary(malformed_start)
	asserts.false_value(start_result.ok, "tail history rejects a run start above stage one")
	asserts.equal(start_result.reason, "invalid_tail_history_start", "malformed history start has a stable reason")

	var backward := _snapshot_with_history(3, [
		_history_entry("run_start", "run_start", 1),
		_history_entry("event", "fox_fire_trial", 3),
		_history_entry("choice", "mercy_at_old_gate", 2)
	])
	var backward_result := TailState.validate_dictionary(backward)
	asserts.false_value(backward_result.ok, "tail history rejects backward recorded stages")
	asserts.equal(backward_result.reason, "tail_history_stage_regression", "backward history has a stable reason")

	var current_exceed := _snapshot_with_history(2, [
		_history_entry("run_start", "run_start", 1),
		_history_entry("event", "fox_fire_trial", 3)
	])
	var exceed_result := TailState.validate_dictionary(current_exceed)
	asserts.false_value(exceed_result.ok, "tail history rejects a recorded stage above current stage")
	asserts.equal(exceed_result.reason, "tail_history_stage_exceeds_current", "current-stage exceed has a stable reason")

func _assert_ability_candidates_are_tail_gated(asserts) -> void:
	var tail := TailState.new({"stage": 3, "tail_count": 3})
	var definitions := {
		"ember": AbilityDefinition.new({"id": "ember", "tail_requirement": 1}),
		"crooked_cut": AbilityDefinition.new({"id": "crooked_cut", "tail_requirement": 3}),
		"once_one_meeting": AbilityDefinition.new({"id": "once_one_meeting", "tail_requirement": 9})
	}
	asserts.equal(tail.candidate_ability_ids(definitions), ["crooked_cut", "ember"], "tail state returns candidate ability IDs by stable requirement")
	asserts.true_value(tail.can_use_ability("crooked_cut", 3), "stage three can use stage three ability")
	asserts.false_value(tail.can_use_ability("once_one_meeting", 9), "stage three cannot use stage nine ability")

func _assert_serialization_round_trip_is_detached(asserts) -> void:
	var tail := TailState.new()
	asserts.true_value(tail.apply_transition("choice", "mercy_at_old_gate", 2, ["humanity"], "MERCY_AT_OLD_GATE").ok, "fixture transition applies")
	var snapshot := tail.to_dictionary()
	var restored_result := TailState.from_dictionary(snapshot)
	asserts.true_value(restored_result.ok, "tail state round trip validates")
	var restored: TailState = restored_result.tail_state
	snapshot.path_flags.append("mutated_after_decode")
	snapshot.transition_history[0].stage = 9
	asserts.equal(restored.path_flags, ["humanity"], "tail state restores detached path flags")
	asserts.equal(restored.transition_history[0].stage, 1, "tail state restores detached transition history")

func _snapshot_with_history(current_stage: int, history: Array) -> Dictionary:
	return {
		"stage": current_stage,
		"tail_count": current_stage,
		"path_flags": [],
		"transition_history": history
	}

func _history_entry(source_kind: String, source_id: String, entry_stage: int) -> Dictionary:
	return {
		"source_kind": source_kind,
		"source_id": source_id,
		"source_key": "RUN_START" if source_kind == "run_start" else "",
		"stage": entry_stage,
		"path_flags": []
	}
