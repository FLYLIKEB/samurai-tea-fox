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
	asserts.equal(first.read_model.event_id, "story_pro_01", "run_count 0 selects the canonical first prologue scene")
	asserts.equal(first.read_model.text, "아버지?", "first-run start uses the canonical Notion dialogue text")
	asserts.equal(second.read_model.event_id, "story_pro_r_father_early", "run_count 1 selects the canonical early return dialogue")
	asserts.equal(veteran.read_model.event_id, "story_pro_r_father_late", "run_count >= 5 selects the canonical late return dialogue")
	asserts.true_value(bool(fixture.selector.select_event(run_state, {"run_count": 0}).chain_scene_sequence), "first-run start continues through the exported prologue sequence")
	asserts.false_value(bool(fixture.selector.select_event(run_state, {"run_count": 1}).get("chain_scene_sequence", false)), "repeat-run memory remains a single event")
	asserts.false_value(first.read_model.text == second.read_model.text, "first and second run starts use different dialogue")
	asserts.false_value(second.read_model.text == veteran.read_model.text, "early and veteran repeat starts use different dialogue")
	asserts.equal(second.read_model.speaker_id, "NOTEBOOK", "repeat-run start uses the canonical notebook memory speaker")
	asserts.equal(veteran.read_model.speaker_id, "NOTEBOOK", "veteran repeat-run start uses the canonical notebook memory speaker")
	asserts.false_value(bool(fixture.selector.select_event(run_state, {"run_count": 5}).father_physical_actor), "father is not selected as a physical Hongguk NPC")

func _assert_completed_start_event_does_not_reopen_in_same_run(asserts) -> void:
	var fixture := _fixture(asserts)
	if fixture.is_empty():
		return
	var run_state := {"narrative_flags": [], "narrative_event_counts": {"story_pro_r_father_early": 1}, "inventory": {}, "current_biome_id": "common_region"}
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
	asserts.equal(selected.event_id, "story_pro_01", "forced new start preserves the canonical first prologue behavior")

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
