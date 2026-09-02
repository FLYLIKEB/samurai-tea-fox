extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const RunEndProcessor = preload("res://src/meta/run_end_processor.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")

func run(asserts) -> void:
	_assert_generated_unlocks_evaluate_from_data(asserts)
	_assert_duplicate_unlocks_are_prevented(asserts)
	_assert_cumulative_conditions_use_meta_counters(asserts)
	_assert_unknown_condition_type_fails(asserts)
	_assert_unknown_reward_type_fails(asserts)
	_assert_meta_save_round_trip_preserves_unlock_state(asserts)

func _assert_generated_unlocks_evaluate_from_data(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog with canonical meta unlock fields loads: %s" % catalog_result.get("error", ""))
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {
		"reached_biome_ids": ["common_region"],
		"best_reached_biome_order": 1,
		"tail_stage": 3,
		"discovered_records": ["memory_tea"],
		"final_tea_room_reached": true
	}, catalog.get_definitions("meta_unlocks"))
	asserts.true_value(result.ok, "generated meta unlock definitions evaluate")
	asserts.equal(int(result.meta_state.run_count), 1, "run end increments meta run count")
	asserts.equal(int(result.meta_state.best_reached_biome_order), 1, "run end updates best reached biome order")
	asserts.true_value(result.meta_state.discovered_records.has("common_biome_first_entry"), "biome event grants discovered record reward")
	asserts.true_value(result.meta_state.discovered_records.has("final_tea_room_first_record"), "final tea room event grants discovered record reward")
	asserts.true_value(result.meta_state.discovered_records.has("memory_tea_first_record"), "discovery event grants discovered record reward")
	asserts.true_value(result.meta_state.unlocked_meta_flags.has("tail_stage_3_record"), "tail stage unlock definition is recorded")
	asserts.true_value(result.meta_state.unlocked_meta_flags.has("tail_stage_3_start_choice"), "tail stage reward target is unlocked")
	asserts.true_value(result.meta_state.dialogue_memory_flags.has("sen_rikyu_reunion_dialogue_1"), "run count reward grants Sen Rikyu dialogue memory flag")
	asserts.true_value(result.meta_state.dialogue_memory_flags.has("gumiho_father_loop_dialogue_1"), "run count reward grants father dialogue memory flag")
	asserts.true_value(RunEndProcessor.new().is_unlocked(result.meta_state, "common_biome_first_entry"), "query API reports unlocked definition ids")
	asserts.equal(RunEndProcessor.new().unlocked_rewards(result.meta_state, catalog.get_definitions("meta_unlocks")).size(), result.meta_state.unlocked_meta_flags.filter(func(id): return id != "tail_stage_3_start_choice").size(), "query API returns unlocked definition reward models")

func _assert_duplicate_unlocks_are_prevented(asserts) -> void:
	var processor := RunEndProcessor.new()
	var definitions := [_definition("common_biome_first_entry", "event_seen", "biome_reached:common_region", "discovered_record", "common_biome_first_entry")]
	var first: Dictionary = processor.apply_run_end_with_unlocks(_empty_meta(), {"reached_biome_ids": ["common_region"]}, definitions)
	var second: Dictionary = processor.apply_run_end_with_unlocks(first.meta_state, {"reached_biome_ids": ["common_region"]}, definitions)
	asserts.true_value(second.ok, "repeat evaluation of an already unlocked definition succeeds")
	asserts.equal(second.unlocked.size(), 0, "repeat evaluation emits no duplicate unlock result")
	asserts.equal(_count(second.meta_state.unlocked_meta_flags, "common_biome_first_entry"), 1, "definition id is stored only once")
	asserts.equal(_count(second.meta_state.discovered_records, "common_biome_first_entry"), 1, "reward target record is stored only once")

func _assert_cumulative_conditions_use_meta_counters(asserts) -> void:
	var processor := RunEndProcessor.new()
	var definitions := [_definition("third_memory_tea", "cumulative_event_count_at_least", "discovered_record:memory_tea", "discovered_record", "third_memory_tea", 3)]
	var meta := _empty_meta()
	var first: Dictionary = processor.apply_run_end_with_unlocks(meta, {"discovered_records": ["memory_tea"]}, definitions)
	asserts.true_value(first.ok, "first cumulative event evaluation succeeds")
	asserts.equal(first.unlocked.size(), 0, "first cumulative event stays locked below threshold")
	var second: Dictionary = processor.apply_run_end_with_unlocks(first.meta_state, {"discovered_records": ["memory_tea"]}, definitions)
	asserts.equal(second.unlocked.size(), 0, "second cumulative event stays locked below threshold")
	var third: Dictionary = processor.apply_run_end_with_unlocks(second.meta_state, {"discovered_records": ["memory_tea"]}, definitions)
	asserts.equal(third.unlocked.size(), 1, "third cumulative event unlocks at threshold")
	asserts.equal(int(third.meta_state.meta_unlock_counters["discovered_record:memory_tea"]), 3, "meta counter persists cumulative progress")

func _assert_unknown_condition_type_fails(asserts) -> void:
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {}, [
		_definition("broken_condition", "unknown_condition", "anything", "unlock_flag", "broken_reward")
	])
	asserts.false_value(result.ok, "unknown meta unlock condition type is rejected")
	asserts.equal(result.reason, "unknown_condition_type", "unknown condition failure returns stable reason")
	asserts.equal(result.definition_id, "broken_condition", "unknown condition failure names definition id")

func _assert_unknown_reward_type_fails(asserts) -> void:
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {"events": [{"type": "fixture", "target": "seen"}]}, [{
		"id": "broken_reward",
		"condition_event": "event_seen",
		"condition_target": "fixture:seen",
		"condition_operator": "equals",
		"threshold": 1,
		"reward_kind": "grant_permanent_attack",
		"reward_target": "attack_up",
		"reward_quantity": 1
	}])
	asserts.false_value(result.ok, "unknown meta unlock reward type is rejected")
	asserts.equal(result.reason, "unknown_reward_type", "unknown reward failure returns stable reason")
	asserts.equal(result.definition_id, "broken_reward", "unknown reward failure names definition id")

func _assert_meta_save_round_trip_preserves_unlock_state(asserts) -> void:
	var meta := _empty_meta()
	meta.run_count = 2
	meta.best_reached_biome_order = 3
	meta.discovered_records = ["memory_tea_first_record"]
	meta.unlocked_meta_flags = ["memory_tea_first_record"]
	meta.dialogue_memory_flags = ["sen_rikyu_reunion_dialogue_1"]
	meta.meta_unlock_counters = {"discovered_record:memory_tea": 3}
	var save := SaveCodec.encode_meta(meta)
	var decoded: Dictionary = SaveCodec.decode_meta(save)
	asserts.true_value(decoded.ok, "meta save with unlock counters decodes")
	asserts.equal(decoded.state.discovered_records, ["memory_tea_first_record"], "meta save preserves discovered records")
	asserts.equal(decoded.state.unlocked_meta_flags, ["memory_tea_first_record"], "meta save preserves unlocked definition ids")
	asserts.equal(decoded.state.dialogue_memory_flags, ["sen_rikyu_reunion_dialogue_1"], "meta save preserves dialogue memory flags")
	asserts.equal(int(decoded.state.meta_unlock_counters["discovered_record:memory_tea"]), 3, "meta save preserves cumulative counters")

func _empty_meta() -> Dictionary:
	return {
		"run_count": 0,
		"best_reached_biome_order": 0,
		"discovered_records": [],
		"unlocked_meta_flags": [],
		"dialogue_memory_flags": [],
		"meta_unlock_counters": {}
	}

func _definition(id: String, condition_event: String, condition_target: String, reward_kind: String, reward_target: String, threshold := 1) -> Dictionary:
	return {
		"id": id,
		"name": id,
		"status": "테스트",
		"condition_event": condition_event,
		"condition_target": condition_target,
		"condition_operator": "at_least" if threshold > 1 else "equals",
		"threshold": threshold,
		"reward_kind": reward_kind,
		"reward_target": reward_target,
		"reward_quantity": 1
	}

func _count(values: Array, id: String) -> int:
	var total := 0
	for value in values:
		if value == id:
			total += 1
	return total
