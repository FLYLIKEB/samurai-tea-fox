extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const Main = preload("res://src/main/main.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads ending route data")
	_assert_priority_and_composite_routes(asserts, catalog)
	_assert_epilogue_never_becomes_primary(asserts, catalog)
	_assert_default_boundary_and_unsupported_conditions(asserts, catalog)
	_assert_meta_record_is_idempotent_and_saved(asserts, catalog)
	_assert_credits_new_run_hook(asserts, catalog)
	_assert_main_exposes_ending_runtime(asserts, catalog)
	_assert_real_phase_three_result_feeds_ending(asserts, catalog)

func _assert_priority_and_composite_routes(asserts, catalog: DataCatalog) -> void:
	var runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var result: Dictionary = runtime.evaluate(_rich_run())
	asserts.true_value(result.ok, "ending evaluation succeeds")
	asserts.equal(result.read_model.ending_ids, ["ending_teahouse_memory", "ending_foxfire_witness"], "highest primary route combines with epilogue route")
	asserts.equal(result.read_model.endings[0].priority, 100, "primary ending priority wins conflicts")
	asserts.equal(result.read_model.credits_hook.type, "show_credits", "read model includes replayable credits hook")
	asserts.true_value(result.read_model.new_run_hook.reset_run_growth, "read model includes new run transition hook")

func _assert_epilogue_never_becomes_primary(asserts, catalog: DataCatalog) -> void:
	var runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var run_state := RunState.new()
	run_state.narrative_flags = ["sen_rikyu_phase3_ability_memory_tea_echo"]
	var result: Dictionary = runtime.evaluate(run_state)
	asserts.true_value(result.ok, "epilogue-only state still evaluates")
	asserts.equal(result.read_model.ending_ids, [EndingRouteRuntime.DEFAULT_ENDING_ID, "ending_foxfire_witness"], "default primary stays ahead of epilogue composite")
	asserts.equal(result.read_model.primary_ending_id, EndingRouteRuntime.DEFAULT_ENDING_ID, "epilogue route cannot become primary ending")
	var meta := MetaState.new()
	asserts.true_value(runtime.record_to_meta(result.read_model, meta).recorded, "epilogue-only composite records")
	asserts.equal(meta.ending_records[0].primary_ending_id, EndingRouteRuntime.DEFAULT_ENDING_ID, "meta primary remains the primary group ending")

func _assert_default_boundary_and_unsupported_conditions(asserts, catalog: DataCatalog) -> void:
	var runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var sparse: Dictionary = runtime.evaluate(RunState.new())
	asserts.true_value(sparse.ok, "sparse run falls back")
	asserts.equal(sparse.read_model.ending_ids, [EndingRouteRuntime.DEFAULT_ENDING_ID], "default ending handles empty run record")
	var custom := EndingRouteRuntime.new()
	custom.ending_definitions = [{"id": "ending_bad", "name": "bad", "ending_key": "bad", "priority": 1, "exclusive_group": "primary", "ending_conditions": [{"type": "karma_score", "id": "good"}], "start_node_id": "result"}]
	asserts.equal(custom.evaluate(RunState.new()).reason, "unsupported_ending_condition", "unsupported numeric morality condition is rejected")

func _assert_meta_record_is_idempotent_and_saved(asserts, catalog: DataCatalog) -> void:
	var runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var read_model: Dictionary = runtime.evaluate(_rich_run()).read_model
	var meta := MetaState.new()
	var first: Dictionary = runtime.record_to_meta(read_model, meta)
	asserts.true_value(first.recorded, "ending meta record is written")
	var duplicate: Dictionary = runtime.record_to_meta(read_model, meta)
	asserts.false_value(duplicate.recorded, "duplicate ending meta record is ignored")
	asserts.equal(runtime.record_to_meta(read_model, null).reason, "missing_meta_state", "missing meta state is rejected")
	asserts.equal(meta.ending_records.size(), 1, "meta records one ending result")
	asserts.equal(meta.ending_records[0].primary_ending_id, "ending_teahouse_memory", "meta record carries primary ending")
	var decoded: Dictionary = SaveCodec.decode_meta(SaveCodec.encode_meta(meta))
	asserts.true_value(decoded.ok, "meta save decodes with ending records")
	asserts.equal(decoded.meta_state.ending_records[0].ending_ids, ["ending_teahouse_memory", "ending_foxfire_witness"], "ending records survive meta save round-trip")

func _assert_credits_new_run_hook(asserts, catalog: DataCatalog) -> void:
	var runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var read_model: Dictionary = runtime.evaluate(_rich_run()).read_model
	var request: Dictionary = runtime.request_new_run_after_credits(read_model)
	asserts.true_value(request.ok, "new run request hook succeeds")
	asserts.equal(request.event.hook.after, "credits", "new run waits for credits hook")
	asserts.true_value(request.event.hook.reset_run_growth, "new run hook requests run growth reset")

func _assert_main_exposes_ending_runtime(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = _rich_run()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures ending runtime")
	var model: Dictionary = main.ending_read_model()
	asserts.true_value(model.ok, "main evaluates ending read model")
	var meta := MetaState.new()
	asserts.true_value(main.record_ending_to_meta(meta, model.read_model).recorded, "main records ending to meta")
	asserts.true_value(main.request_new_run_after_credits(model.read_model).ok, "main exposes credits/new-run hook")
	main.free()

func _assert_real_phase_three_result_feeds_ending(asserts, catalog: DataCatalog) -> void:
	var run_state := _rich_run()
	run_state.narrative_flags.clear()
	var phase_three: SenRikyuPhaseThreeRuntime = SenRikyuPhaseThreeRuntime.from_catalog(catalog).runtime
	asserts.true_value(phase_three.start(_phase_two_transition(), run_state).ok, "phase three starts for ending handoff")
	asserts.true_value(phase_three.complete_with_ability("memory_tea_echo", run_state).ok, "real phase three completion records selected ability flag")
	var endings: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var model: Dictionary = endings.evaluate(run_state)
	asserts.true_value(model.read_model.ending_ids.has("ending_foxfire_witness"), "ending route reads real phase three selected ability flag")

func _rich_run() -> RunState:
	var state := RunState.new()
	state.choice_history = ["daimyo_relinquish_tea"]
	state.discovered_records = ["memory_tea"]
	state.target_survival = {"oribe": true}
	state.core_tea_ware_collection = {"collected_ids": ["war_tea_caddy"]}
	state.philosophy_marks = ["和·공존"]
	state.narrative_flags = ["sen_rikyu_phase3_ability_memory_tea_echo"]
	return state

func _phase_two_transition() -> Dictionary:
	return {
		"type": 7,
		"payload": {
			"phase": "sen_rikyu_phase_2",
			"result": {"type": "start_phase", "id": "sen_rikyu_phase_3"},
			"boss_id": "sen_rikyu_phase_2",
			"dungeon_id": "final_tea_room",
			"resolution_event": {"resolution_type": "combat", "boss_id": "sen_rikyu_phase_2"}
		}
	}
