extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const RunEndProcessor = preload("res://src/meta/run_end_processor.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")

func run(asserts) -> void:
	_assert_generated_unlocks_evaluate_from_data(asserts)
	_assert_duplicate_unlocks_are_prevented(asserts)
	_assert_cumulative_conditions_use_meta_counters(asserts)
	_assert_standard_discovery_and_choice_events_are_consumed(asserts)
	_assert_highest_record_and_repeat_count_conditions(asserts)
	_assert_unknown_condition_type_fails(asserts)
	_assert_unknown_condition_operator_fails(asserts)
	_assert_unknown_reward_type_fails(asserts)
	_assert_data_driven_path_ignores_undeclared_earned_meta_flags(asserts)
	_assert_unrelated_events_do_not_create_cumulative_counters(asserts)
	_assert_previous_run_query_inputs_are_accumulated(asserts)
	_assert_meta_save_round_trip_preserves_unlock_state(asserts)

func _assert_generated_unlocks_evaluate_from_data(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog with canonical meta unlock fields loads: %s" % catalog_result.get("error", ""))
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {
		"reached_biome_ids": ["common_region"],
		"best_reached_biome_order": 1,
		"tail_state": {"stage": 3, "tail_count": 3, "path_flags": ["harmony"], "transition_history": [
			{"source_kind": "run_start", "source_id": "run_start", "source_key": "RUN_START", "stage": 1, "path_flags": []},
			{"source_kind": "event", "source_id": "harmony_resolution", "source_key": "", "stage": 3, "path_flags": ["harmony"]}
		]},
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
	asserts.false_value(result.meta_state.has("tails"), "meta state does not persist tail count")
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

func _assert_standard_discovery_and_choice_events_are_consumed(asserts) -> void:
	var definitions := [
		_definition("memory_discovery", "event_seen", "discovered_record:memory_tea", "discovered_record", "memory_discovery"),
		_definition("daimyo_choice", "event_seen", "choice:daimyo_defeat", "unlock_flag", "daimyo_choice_reward")
	]
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {
		"discovery_events": [{"type": "discovery", "record_id": "memory_tea"}],
		"choice_events": [{"type": "choice_meta_record_requested", "choice_id": "daimyo_defeat"}]
	}, definitions)
	asserts.true_value(result.ok, "standard discovery and choice events evaluate")
	asserts.true_value(result.meta_state.discovered_records.has("memory_discovery"), "discovery event grants its data-driven record")
	asserts.true_value(result.meta_state.unlocked_meta_flags.has("daimyo_choice_reward"), "choice event grants its data-driven unlock flag")

func _assert_highest_record_and_repeat_count_conditions(asserts) -> void:
	var definitions := [
		_definition("second_run", "run_count_at_least", "run_count", "dialogue_memory_flag", "second_run_dialogue", 2),
		_definition("third_biome", "best_biome_order_at_least", "best_reached_biome_order", "discovered_record", "third_biome_record", 3)
	]
	var first: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {"best_reached_biome_order": 3}, definitions)
	asserts.equal(first.meta_state.best_reached_biome_order, 3, "first run stores highest reached biome order")
	asserts.false_value(first.meta_state.dialogue_memory_flags.has("second_run_dialogue"), "repeat reward stays locked before run threshold")
	var second: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(first.meta_state, {"best_reached_biome_order": 1}, definitions)
	asserts.equal(second.meta_state.best_reached_biome_order, 3, "lower later progress cannot reduce highest reached record")
	asserts.true_value(second.meta_state.dialogue_memory_flags.has("second_run_dialogue"), "repeat reward unlocks at run count threshold")

func _assert_unknown_condition_type_fails(asserts) -> void:
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {}, [
		_definition("broken_condition", "unknown_condition", "anything", "unlock_flag", "broken_reward")
	])
	asserts.false_value(result.ok, "unknown meta unlock condition type is rejected")
	asserts.equal(result.reason, "unknown_condition_type", "unknown condition failure returns stable reason")
	asserts.equal(result.definition_id, "broken_condition", "unknown condition failure names definition id")

func _assert_unknown_condition_operator_fails(asserts) -> void:
	var definition := _definition("broken_operator", "event_seen", "fixture:seen", "unlock_flag", "broken_reward")
	definition.condition_operator = "approximately"
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {"events": [{"type": "fixture", "target": "seen"}]}, [definition])
	asserts.false_value(result.ok, "unknown meta unlock condition operator is rejected")
	asserts.equal(result.reason, "unknown_condition_operator", "unknown operator failure returns stable reason")

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

func _assert_data_driven_path_ignores_undeclared_earned_meta_flags(asserts) -> void:
	var definitions := [_definition("declared_biome_entry", "event_seen", "biome_reached:common_region", "discovered_record", "declared_biome_entry")]
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {
		"reached_biome_ids": ["common_region"],
		"earned_meta_flags": ["legacy_bypass_flag"]
	}, definitions)
	asserts.true_value(result.ok, "data-driven run end with legacy earned flags succeeds")
	asserts.true_value(result.meta_state.unlocked_meta_flags.has("declared_biome_entry"), "declared unlock definition id persists")
	asserts.false_value(result.meta_state.unlocked_meta_flags.has("legacy_bypass_flag"), "undeclared earned meta flag is ignored by data-driven path")

func _assert_unrelated_events_do_not_create_cumulative_counters(asserts) -> void:
	var definitions := [_definition("third_memory_tea", "cumulative_event_count_at_least", "discovered_record:memory_tea", "discovered_record", "third_memory_tea", 3)]
	var result: Dictionary = RunEndProcessor.new().apply_run_end_with_unlocks(_empty_meta(), {
		"events": [
			{"type": "fixture", "target": "unrelated"},
			{"type": "discovered_record", "target": "memory_tea"}
		]
	}, definitions)
	asserts.true_value(result.ok, "data-driven run end with unrelated events succeeds")
	asserts.equal(int(result.meta_state.meta_unlock_counters.get("discovered_record:memory_tea", 0)), 1, "declared cumulative event target counter increments")
	asserts.false_value(result.meta_state.meta_unlock_counters.has("fixture:unrelated"), "unrelated event target is not persisted as a meta unlock counter")

func _assert_meta_save_round_trip_preserves_unlock_state(asserts) -> void:
	var meta := _empty_meta()
	meta.run_count = 2
	meta.best_reached_biome_order = 3
	meta.discovered_records = ["memory_tea_first_record"]
	meta.unlocked_meta_flags = ["memory_tea_first_record"]
	meta.dialogue_memory_flags = ["sen_rikyu_reunion_dialogue_1"]
	meta.meta_unlock_counters = {"discovered_record:memory_tea": 3}
	meta.past_choice_ids = ["daimyo_relinquish_tea"]
	meta.reached_place_ids = ["mountain_region"]
	meta.death_record_ids = ["wild_dog_ambush"]
	var save := SaveCodec.encode_meta(meta)
	var decoded: Dictionary = SaveCodec.decode_meta(save)
	asserts.true_value(decoded.ok, "meta save with unlock counters decodes")
	asserts.equal(decoded.state.discovered_records, ["memory_tea_first_record"], "meta save preserves discovered records")
	asserts.equal(decoded.state.unlocked_meta_flags, ["memory_tea_first_record"], "meta save preserves unlocked definition ids")
	asserts.equal(decoded.state.dialogue_memory_flags, ["sen_rikyu_reunion_dialogue_1"], "meta save preserves dialogue memory flags")
	asserts.equal(int(decoded.state.meta_unlock_counters["discovered_record:memory_tea"]), 3, "meta save preserves cumulative counters")
	asserts.equal(decoded.state.past_choice_ids, ["daimyo_relinquish_tea"], "meta save preserves past choice query inputs")
	asserts.equal(decoded.state.reached_place_ids, ["mountain_region"], "meta save preserves reached place query inputs")
	asserts.equal(decoded.state.death_record_ids, ["wild_dog_ambush"], "meta save preserves death record query inputs")

func _assert_previous_run_query_inputs_are_accumulated(asserts) -> void:
	var processor := RunEndProcessor.new()
	var first := processor.apply_run_end(_empty_meta(), {
		"choice_history": ["daimyo_relinquish_tea"],
		"reached_biome_ids": ["common_region"],
		"current_biome_id": "mountain_region",
		"final_tea_room_reached": true,
		"death_record_id": "wild_dog_ambush"
	})
	var second := processor.apply_run_end(first, {
		"choice_history": ["daimyo_relinquish_tea"],
		"reached_place_ids": ["mountain_shrine"],
		"death_record_ids": ["wild_dog_ambush", "boss_defeat"]
	})
	asserts.equal(second.past_choice_ids, ["daimyo_relinquish_tea"], "past choice IDs accumulate without duplicates")
	asserts.equal(second.reached_place_ids, ["common_region", "mountain_region", "final_tea_room", "mountain_shrine"], "reached place IDs accumulate from stable run summary fields")
	asserts.equal(second.death_record_ids, ["wild_dog_ambush", "boss_defeat"], "death record IDs accumulate without duplicates")
	asserts.equal(int(second.run_count), 2, "query input accumulation preserves run count behavior")

func _empty_meta() -> Dictionary:
	return {
		"run_count": 0,
		"best_reached_biome_order": 0,
		"discovered_records": [],
		"unlocked_meta_flags": [],
		"dialogue_memory_flags": [],
		"meta_unlock_counters": {},
		"past_choice_ids": [],
		"reached_place_ids": [],
		"death_record_ids": []
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
