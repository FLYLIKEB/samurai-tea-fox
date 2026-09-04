extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const RunStartEventSelector = preload("res://src/narrative/run_start_event_selector.gd")

func run(asserts) -> void:
	_assert_generated_run_start_events_select_by_meta_count(asserts)
	_assert_completed_start_event_does_not_reopen_in_same_run(asserts)
	_assert_force_first_run_uses_prologue_even_with_prior_meta(asserts)

func _assert_generated_run_start_events_select_by_meta_count(asserts) -> void:
	var fixture := _fixture(asserts)
	if fixture.is_empty():
		return
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var first: Dictionary = fixture.runtime.read_model_for_event(
		String(fixture.selector.select_event(run_state, {"run_count": 0}).event_id),
		run_state,
		{"run_count": 0}
	)
	var second: Dictionary = fixture.runtime.read_model_for_event(
		String(fixture.selector.select_event(run_state, {"run_count": 1}).event_id),
		run_state,
		{"run_count": 1}
	)
	var veteran: Dictionary = fixture.runtime.read_model_for_event(
		String(fixture.selector.select_event(run_state, {"run_count": 5}).event_id),
		run_state,
		{"run_count": 5}
	)
	asserts.equal(first.read_model.event_id, "first_run_prologue", "run_count 0 selects the first-run prologue")
	asserts.equal(second.read_model.event_id, "repeat_run_father_dream", "run_count 1 selects the repeat-run father dream")
	asserts.equal(veteran.read_model.event_id, "veteran_run_father_memory", "run_count >= 5 selects the more specific scent-memory start")
	asserts.false_value(first.read_model.text == second.read_model.text, "first and second run starts use different dialogue")
	asserts.false_value(second.read_model.text == veteran.read_model.text, "early and veteran repeat starts use different dialogue")
	asserts.equal(second.read_model.speaker_id, "CHR-1", "repeat-run start stays in father's memory presentation")
	asserts.equal(veteran.read_model.speaker_id, "CHR-1", "veteran repeat-run start stays in father's memory presentation")
	asserts.false_value(bool(fixture.selector.select_event(run_state, {"run_count": 5}).father_physical_actor), "father is not selected as a physical Hongguk NPC")

func _assert_completed_start_event_does_not_reopen_in_same_run(asserts) -> void:
	var fixture := _fixture(asserts)
	if fixture.is_empty():
		return
	var run_state := {"narrative_flags": [], "narrative_event_counts": {"repeat_run_father_dream": 1}, "inventory": {}, "current_biome_id": "common_region"}
	var selected: Dictionary = fixture.selector.select_event(run_state, {"run_count": 1})
	asserts.false_value(selected.ok, "completed once-per-run repeat start does not reopen in the same run")
	asserts.equal(selected.reason, "no_start_event_candidate", "completed repeat start has a stable no-candidate reason")

func _assert_force_first_run_uses_prologue_even_with_prior_meta(asserts) -> void:
	var fixture := _fixture(asserts)
	if fixture.is_empty():
		return
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var selected: Dictionary = fixture.selector.select_event(run_state, {"run_count": 4}, true)
	asserts.true_value(selected.ok, "forced new start can ignore previous meta run count")
	asserts.equal(selected.event_id, "first_run_prologue", "forced new start preserves the first-run prologue regression behavior")

func _fixture(asserts) -> Dictionary:
	var catalog := DataCatalog.new()
	var catalog_result: Dictionary = catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for run-start selector: %s" % catalog_result.get("error", ""))
	if not catalog_result.ok:
		return {}
	var runtime_result: Dictionary = NarrativeRuntime.new().from_catalog(catalog)
	asserts.true_value(runtime_result.ok, "narrative runtime accepts generated run-start events")
	if not runtime_result.ok:
		return {}
	var selector := RunStartEventSelector.new()
	var selector_result: Dictionary = selector.configure(catalog)
	asserts.true_value(selector_result.ok, "run-start selector configures from generated event metadata")
	if not selector_result.ok:
		return {}
	return {"catalog": catalog, "runtime": runtime_result.runtime, "selector": selector}
