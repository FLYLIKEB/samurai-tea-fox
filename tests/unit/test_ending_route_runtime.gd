extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const EndingRouteRuntime = preload("res://src/meta/ending_route_runtime.gd")
const Main = preload("res://src/main/main.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunBootstrapCoordinator = preload("res://src/main/run_bootstrap_coordinator.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const SenRikyuPhaseThreeRuntime = preload("res://src/dungeon/sen_rikyu_phase_three_runtime.gd")

const TEST_DIRECTORY := "user://dev146_ending_new_run_tests"
const RUN_PATH := TEST_DIRECTORY + "/run.json"
const META_PATH := TEST_DIRECTORY + "/meta.json"

class Box:
	extends RefCounted
	var value

class SaveStoreProbe:
	extends RefCounted
	var store: SaveStore
	var fail_run_save := false
	var meta_path: String:
		get: return store.meta_path

	func _init(run_path: String, meta_save_path: String) -> void:
		store = SaveStore.new(run_path, meta_save_path)

	func save_run(state) -> Dictionary:
		if fail_run_save:
			return {"ok": false, "reason": "injected_run_save_failure", "error": "Injected run save failure."}
		return store.save_run(state)

	func save_meta(state) -> Dictionary:
		return store.save_meta(state)

	func load_meta() -> Dictionary:
		return store.load_meta()

	func load_run() -> Dictionary:
		return store.load_run()

	func invalidate_run(state = null) -> Dictionary:
		return store.invalidate_run(state)

func run(asserts) -> void:
	_cleanup()
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads ending route data")
	_assert_priority_and_composite_routes(asserts, catalog)
	_assert_epilogue_never_becomes_primary(asserts, catalog)
	_assert_default_boundary_and_unsupported_conditions(asserts, catalog)
	_assert_meta_record_is_idempotent_and_saved(asserts, catalog)
	_assert_credits_new_run_hook(asserts, catalog)
	_assert_main_exposes_ending_runtime(asserts, catalog)
	_assert_ending_request_persists_meta_and_activates_fresh_run(asserts, catalog)
	_assert_real_phase_three_result_feeds_ending(asserts, catalog)
	_cleanup()

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
	asserts.equal(model.read_model.run_identity.lifecycle_epoch, main.run_state.lifecycle_epoch, "main ending read model carries run identity")
	var meta := MetaState.new()
	asserts.true_value(main.record_ending_to_meta(meta, model.read_model).recorded, "main records ending to meta")
	main.free()

func _assert_ending_request_persists_meta_and_activates_fresh_run(asserts, catalog: DataCatalog) -> void:
	var store := SaveStoreProbe.new(RUN_PATH, META_PATH)
	var old_run := _rich_run()
	old_run.data_version = catalog.data_version
	old_run.seed = 441
	old_run.lifecycle_epoch = 3
	old_run.currency = 99
	old_run.tails = 4
	old_run.inventory = {"green_tea_leaf": 7}
	old_run.abilities = ["memory_tea_echo"]
	old_run.teleport_states = {"rainforest": "repaired"}
	old_run.crafting_unlocks = ["wood_incense_burner"]
	old_run.placed_facilities = [{"facility_item_id": "portable_brazier"}]
	asserts.true_value(store.save_run(old_run).ok, "ending fixture persists the completed run")
	var prior_meta := MetaState.new()
	prior_meta.discovered_records = ["memory_tea"]
	prior_meta.unlocked_meta_flags = ["existing_unlock"]
	asserts.true_value(store.save_meta(prior_meta).ok, "ending fixture persists prior meta")

	var ending_runtime: EndingRouteRuntime = EndingRouteRuntime.from_catalog(catalog).runtime
	var read_model: Dictionary = ending_runtime.evaluate(old_run).read_model
	read_model["run_identity"] = {"lifecycle_epoch": old_run.lifecycle_epoch, "seed": old_run.seed}
	var active_run := Box.new()
	var lifecycle := RunLifecycleService.new()
	lifecycle.death_pending = true
	lifecycle.death_confirmed = true
	var ports := RunBootstrapCoordinator.Ports.new()
	ports.get_catalog = func(): return catalog
	ports.get_run_state = func(): return old_run
	ports.get_save_store = func(): return store
	ports.get_ending_route_runtime = func(): return ending_runtime
	ports.get_run_lifecycle_service = func(): return lifecycle
	ports.activate_run_state = func(state): active_run.value = state; return {"ok": true}
	var coordinator := RunBootstrapCoordinator.new(ports, 0)

	store.fail_run_save = true
	var failed: Dictionary = coordinator.complete_ending_new_run(read_model)
	asserts.false_value(failed.ok, "failed fresh-run save does not report a successful transition")
	asserts.equal(active_run.value, null, "failed save does not activate a fresh run")
	store.fail_run_save = false
	var completed: Dictionary = coordinator.complete_ending_new_run(read_model)
	asserts.true_value(completed.ok, "retry completes the ending transition")
	asserts.equal(completed.state, "fresh_run", "ending transition reports a fresh run")
	asserts.true_value(active_run.value is RunState, "fresh run becomes active")
	asserts.equal(active_run.value.lifecycle_epoch, 4, "fresh run advances the completed run identity")
	asserts.equal(active_run.value.currency, 0, "fresh run clears run currency")
	asserts.equal(active_run.value.tails, 1, "fresh run clears tail growth")
	asserts.equal(active_run.value.inventory, {}, "fresh run clears inventory")
	asserts.equal(active_run.value.abilities, [], "fresh run clears run abilities")
	asserts.equal(active_run.value.teleport_states, {}, "fresh run clears teleport state")
	asserts.equal(active_run.value.crafting_unlocks, [], "fresh run clears crafting unlocks")
	asserts.equal(active_run.value.placed_facilities, [], "fresh run clears placed facilities")
	asserts.false_value(lifecycle.death_pending, "fresh run resets pending lifecycle state")
	asserts.false_value(lifecycle.death_confirmed, "fresh run resets confirmed lifecycle state")
	var loaded_meta: Dictionary = store.load_meta()
	asserts.true_value(loaded_meta.ok, "ending meta reloads after transition")
	asserts.equal(loaded_meta.meta_state.run_count, 1, "save failure retry does not duplicate run-end count")
	asserts.equal(loaded_meta.meta_state.ending_records.size(), 1, "save failure retry does not duplicate ending records")
	asserts.true_value(loaded_meta.meta_state.discovered_records.has("memory_tea"), "memory meta survives the new run")
	asserts.true_value(loaded_meta.meta_state.unlocked_meta_flags.has("existing_unlock"), "existing meta unlock survives the new run")
	var persisted_run: Dictionary = store.load_run()
	asserts.true_value(persisted_run.ok, "fresh run reloads from disk")
	asserts.equal(persisted_run.run_state.lifecycle_epoch, 4, "reloaded run keeps fresh identity")
	var duplicate: Dictionary = coordinator.complete_ending_new_run(read_model)
	asserts.true_value(duplicate.ok and duplicate.duplicate, "duplicate credits request is idempotent")
	asserts.equal(store.load_meta().meta_state.run_count, 1, "duplicate request does not add another run-end record")
	asserts.equal(store.load_run().run_state.lifecycle_epoch, 4, "duplicate request does not create another run")

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

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".invalidated.json", META_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := DirAccess.open("user://")
	if directory != null:
		directory.remove(TEST_DIRECTORY.trim_prefix("user://"))
