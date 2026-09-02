extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const MemoryTeaCutsceneRuntime = preload("res://src/narrative/memory_tea_cutscene_runtime.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const TeaService = preload("res://src/tea/tea_service.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads memory tea data")
	_assert_memory_tea_completion_starts_cutscene(asserts, catalog)
	_assert_regular_tea_does_not_start_cutscene(asserts, catalog)
	_assert_skip_records_once_and_blocks_replay(asserts)
	_assert_snapshot_resume_then_complete(asserts)
	_assert_invalid_memory_event_reference_fails(asserts)
	_assert_main_routes_memory_tea_completion(asserts, catalog)

func _assert_memory_tea_completion_starts_cutscene(asserts, catalog: DataCatalog) -> void:
	var fixture := _memory_tea_completion(asserts, catalog)
	var runtime := MemoryTeaCutsceneRuntime.new()
	asserts.true_value(runtime.configure(catalog.data_version).ok, "memory cutscene runtime configures")
	var run_state := RunState.new()
	var meta_state := MetaState.new()
	var start := runtime.start_from_drink_completion(fixture.completion, run_state, meta_state)
	asserts.true_value(start.ok, "memory tea completion starts a cutscene: %s" % start.get("error", ""))
	asserts.true_value(start.started, "memory tea start reports started")
	asserts.equal(start.sequence.event_id, "memory_tea_father_spring_pan_fired_tea", "memory event id is resolved from tea data")
	asserts.equal(start.sequence.tea_id, "father_spring_pan_fired_tea", "sequence carries memory tea id")
	asserts.equal(start.sequence.memory_strength, 24, "sequence carries memory strength")
	asserts.true_value(String(start.sequence.memory_evidence).contains("백국 구미호"), "sequence carries memory evidence")
	asserts.true_value(start.sequence.frames.size() >= 3, "sequence exposes short pixel cutscene frames")
	var finished := runtime.complete_current(run_state, meta_state)
	asserts.true_value(finished.ok, "memory cutscene completes")
	asserts.true_value(finished.completed, "completion reason is complete")
	asserts.equal(run_state.discovered_records, ["memory_tea"], "run discovery records memory tea once")
	asserts.equal(run_state.narrative_event_counts.memory_tea_father_spring_pan_fired_tea, 1, "run event count records memory event once")
	asserts.equal(meta_state.discovered_records, ["memory_tea"], "meta record hook records memory tea")
	asserts.equal(finished.meta_events[0].type, "discovery", "finish emits meta discovery hook event")
	asserts.equal(finished.meta_events[0].memory_strength, 24, "meta event carries strength")
	asserts.true_value(String(finished.meta_events[0].memory_evidence).contains("백국 구미호"), "meta event carries evidence")

func _assert_regular_tea_does_not_start_cutscene(asserts, catalog: DataCatalog) -> void:
	var fixture := _tea_completion(asserts, catalog, "tea_8")
	var runtime := MemoryTeaCutsceneRuntime.new()
	runtime.configure(catalog.data_version)
	var start := runtime.start_from_drink_completion(fixture.completion, RunState.new(), MetaState.new())
	asserts.true_value(start.ok, "ordinary tea detection succeeds")
	asserts.false_value(start.started, "ordinary tea does not start memory cutscene")
	asserts.equal(start.reason, "tea_has_no_memory", "ordinary tea has explicit no-memory reason")

func _assert_skip_records_once_and_blocks_replay(asserts) -> void:
	var runtime := MemoryTeaCutsceneRuntime.new()
	runtime.configure("fixture-version")
	var run_state := RunState.new()
	var meta_state := MetaState.new()
	var start := runtime.start_from_drink_completion(_completion_with_memory("memory_tea_fixture", "fixture_memory_tea", 7, "fixture evidence"), run_state, meta_state)
	asserts.true_value(start.started, "fixture memory tea starts")
	var skipped := runtime.skip_current(run_state, meta_state)
	asserts.true_value(skipped.ok, "skip succeeds")
	asserts.true_value(skipped.skipped, "skip result marks skipped")
	asserts.equal(run_state.discovered_records, ["memory_tea"], "skip records discovery")
	var duplicate := runtime.start_from_drink_completion(_completion_with_memory("memory_tea_fixture", "fixture_memory_tea", 7, "fixture evidence"), run_state, meta_state)
	asserts.true_value(duplicate.ok, "duplicate policy returns non-fatal result")
	asserts.false_value(duplicate.started, "completed memory event does not replay")
	asserts.equal(duplicate.reason, "memory_already_discovered", "duplicate replay policy is explicit")
	asserts.equal(run_state.discovered_records, ["memory_tea"], "duplicate discovery remains unique")
	var distinct := runtime.start_from_drink_completion(_completion_with_memory("memory_tea_other", "other_memory_tea", 8, "other evidence"), run_state, meta_state)
	asserts.true_value(distinct.started, "aggregate memory_tea meta record does not suppress distinct memory event ids")

func _assert_snapshot_resume_then_complete(asserts) -> void:
	var runtime := MemoryTeaCutsceneRuntime.new()
	runtime.configure("fixture-version")
	var start := runtime.start_from_drink_completion(_completion_with_memory("memory_tea_resume", "resume_memory_tea", 9, "resume evidence"), RunState.new())
	asserts.true_value(start.started, "resume fixture starts")
	var restored := MemoryTeaCutsceneRuntime.new()
	asserts.true_value(restored.configure("fixture-version").ok, "restored runtime configures")
	asserts.true_value(restored.load_snapshot(runtime.to_snapshot()).ok, "active cutscene snapshot reloads")
	var run_state := RunState.new()
	var completed := restored.complete_current(run_state)
	asserts.true_value(completed.ok, "restored cutscene completes")
	asserts.equal(completed.sequence.event_id, "memory_tea_resume", "restored sequence preserves event id")
	asserts.equal(run_state.discovered_records, ["memory_tea"], "restored completion records discovery")
	var encoded := SaveCodec.encode_run(run_state)
	var decoded := SaveCodec.decode_run(encoded)
	asserts.true_value(decoded.ok, "run save with discovered records decodes")
	asserts.equal(decoded.run_state.discovered_records, ["memory_tea"], "run discovered records survive save round-trip")
	var active_state := RunState.new()
	active_state.memory_tea_cutscene = runtime.to_snapshot()
	var active_decoded := SaveCodec.decode_run(SaveCodec.encode_run(active_state))
	asserts.true_value(active_decoded.ok, "run save with active memory cutscene decodes")
	asserts.equal(active_decoded.run_state.memory_tea_cutscene.active_sequence.event_id, "memory_tea_resume", "active cutscene state survives run save round-trip")

func _assert_invalid_memory_event_reference_fails(asserts) -> void:
	var runtime := MemoryTeaCutsceneRuntime.new()
	runtime.configure("fixture-version")
	var invalid := runtime.start_from_drink_completion(_completion_with_memory("bad:event", "fixture_memory_tea", 7, "fixture evidence"), RunState.new())
	asserts.false_value(invalid.ok, "invalid memory event id is rejected")
	asserts.equal(invalid.reason, "invalid_memory_event_id", "invalid event reference has explicit reason")
	var missing := runtime.complete_current(RunState.new())
	asserts.false_value(missing.ok, "completing without active cutscene fails")
	asserts.equal(missing.reason, "no_active_cutscene", "missing active sequence has explicit reason")

func _assert_main_routes_memory_tea_completion(asserts, catalog: DataCatalog) -> void:
	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = RunState.new()
	var services: Dictionary = runtime._configure_run_services(catalog)
	asserts.true_value(services.ok, "main configures memory tea runtime")
	asserts.true_value(runtime.inventory.add_item("father_spring_pan_fired_tea", 1).ok, "main fixture stocks memory tea")
	asserts.true_value(runtime.inventory.add_item("humble_clay_bowl", 1).ok, "main fixture stocks vessel")
	asserts.true_value(runtime.tea_service.brew("father_spring_pan_fired_tea", "humble_clay_bowl", runtime.inventory, 0).ok, "main fixture brews memory tea")
	asserts.true_value(runtime._handle_tea_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, 0, {"action": "drink_tea"})), "main tea command completes memory tea")
	asserts.false_value(runtime.memory_tea_cutscene_runtime.active_sequence.is_empty(), "main starts memory cutscene from tea completion")
	asserts.equal(runtime.run_state.memory_tea_cutscene.active_sequence.event_id, "memory_tea_father_spring_pan_fired_tea", "main persists active memory cutscene snapshot")
	var saved: RunState = RunState.from_dictionary(runtime.snapshot_run_state())
	var restored: Main = Main.new()
	restored.catalog = catalog
	restored.run_state = saved
	asserts.true_value(restored._configure_run_services(catalog).ok, "main restores active memory cutscene runtime")
	asserts.equal(restored.memory_tea_cutscene_runtime.active_sequence.event_id, "memory_tea_father_spring_pan_fired_tea", "restored main resumes active memory cutscene")
	var finished: Dictionary = restored.skip_memory_tea_cutscene()
	asserts.true_value(finished.ok, "main skip completes memory cutscene")
	asserts.equal(restored.run_state.discovered_records, ["memory_tea"], "main records memory discovery once after skip")
	runtime.free()
	restored.free()

func _memory_tea_completion(asserts, catalog: DataCatalog) -> Dictionary:
	return _tea_completion(asserts, catalog, "father_spring_pan_fired_tea")

func _tea_completion(asserts, catalog: DataCatalog, tea_id: String) -> Dictionary:
	var tea_result: Dictionary = TeaService.from_catalog(catalog)
	asserts.true_value(tea_result.ok, "tea service configures for %s" % tea_id)
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	asserts.true_value(inventory_result.ok, "inventory configures for %s" % tea_id)
	var tea: TeaService = tea_result.tea_service
	var inventory: InventoryModel = inventory_result.inventory
	asserts.true_value(inventory.add_item(tea_id, 1).ok, "tea item can be added: %s" % tea_id)
	asserts.true_value(inventory.add_item("humble_clay_bowl", 1).ok, "vessel can be added")
	asserts.true_value(tea.brew(tea_id, "humble_clay_bowl", inventory, 0).ok, "tea brews: %s" % tea_id)
	var action: Dictionary = tea.start_drinking(0).action
	var completion: Dictionary = tea.complete_drinking(action)
	asserts.true_value(completion.ok, "tea completes: %s" % tea_id)
	return {"tea": tea, "inventory": inventory, "completion": completion}

func _completion_with_memory(event_id: String, tea_id: String, strength: int, evidence: String) -> Dictionary:
	return {
		"ok": true,
		"consumed": true,
		"effect": {
			"memory": {
				"has_memory": true,
				"event_id": event_id,
				"tea_id": tea_id,
				"tea_name": tea_id,
				"strength": strength,
				"evidence": evidence
			}
		}
	}
