extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")

class FakeCatalog:
	extends RefCounted

	var data_version := "fixture-v1"
	var definitions: Dictionary

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

func run(asserts) -> void:
	_assert_generated_events_execute_from_data(asserts)
	_assert_true_false_conditions_alter_options(asserts)
	_assert_branching_and_result_commands(asserts)
	_assert_once_and_repeat_policies(asserts)
	_assert_bad_references_are_rejected(asserts)
	_assert_bad_graph_shapes_are_rejected(asserts)
	_assert_result_contracts_are_rejected(asserts)
	_assert_grant_item_requires_item_definitions(asserts)
	_assert_run_meta_boundary(asserts)
	_assert_read_model_does_not_mutate_state(asserts)

func _assert_generated_events_execute_from_data(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog with narrative events loads: %s" % catalog_result.get("error", ""))
	var runtime_result: Dictionary = NarrativeRuntime.new().from_catalog(catalog)
	asserts.true_value(runtime_result.ok, "narrative runtime initializes from generated events")
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var meta_state := {"dialogue_memory_flags": [], "unlocked_meta_flags": [], "run_count": 0}
	var teahouse_model: Dictionary = runtime_result.runtime.read_model_for_event("roadside_teahouse_intro", run_state, meta_state)
	var shrine_model: Dictionary = runtime_result.runtime.read_model_for_event("mountain_shrine_echo", run_state, meta_state)
	asserts.true_value(teahouse_model.ok, "first sample story event opens from generated data")
	asserts.true_value(shrine_model.ok, "second sample story event opens from generated data")

func _assert_true_false_conditions_alter_options(asserts) -> void:
	var runtime: NarrativeRuntime = _fixture_runtime(asserts)
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var model: Dictionary = runtime.read_model_for_event("roadside_teahouse_intro", run_state)
	asserts.equal(_option_ids(model.read_model), ["accept_kettle"], "false run_flag condition hides unavailable option")
	run_state.narrative_flags = ["accepted_roadside_kettle"]
	var after_flag: Dictionary = runtime.read_model_for_event("roadside_teahouse_intro", run_state)
	asserts.equal(_option_ids(after_flag.read_model), ["ask_again"], "true run_flag condition reveals alternate option")

func _assert_branching_and_result_commands(asserts) -> void:
	var runtime: NarrativeRuntime = _fixture_runtime(asserts)
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var choice: Dictionary = runtime.select_option("roadside_teahouse_intro", "start", "accept_kettle", run_state)
	asserts.true_value(choice.ok, "available option can be selected")
	asserts.equal(choice.next_node_id, "thanks", "option branches to next node")
	asserts.equal(choice.read_model.node_id, "thanks", "branch selection returns next read model")
	asserts.equal(choice.commands.size(), 2, "option emits one command per result")
	asserts.equal(choice.commands[0].type, GameCommand.Type.NARRATIVE_RESULT, "result is emitted as a domain command")
	asserts.equal(choice.commands[0].payload.result.type, "set_run_flag", "result command preserves stable result type")
	asserts.equal(choice.commands[0].payload.result.id, "accepted_roadside_kettle", "result command preserves stable result id")
	asserts.equal(choice.commands[1].payload.result.id, "ash_stained_iron_kettle", "grant_item result targets an existing item stable id")
	asserts.false_value(run_state.narrative_flags.has("accepted_roadside_kettle"), "selecting an option does not apply result state directly")

func _assert_once_and_repeat_policies(asserts) -> void:
	var runtime: NarrativeRuntime = _fixture_runtime(asserts)
	var run_state := {"narrative_flags": ["accepted_roadside_kettle"], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var finish_once: Dictionary = runtime.select_option("roadside_teahouse_intro", "start", "ask_again", run_state)
	asserts.true_value(finish_once.ok, "once event can complete first time")
	asserts.equal(int(run_state.narrative_event_counts.roadside_teahouse_intro), 1, "once event completion is recorded in run state")
	asserts.false_value(runtime.read_model_for_event("roadside_teahouse_intro", run_state).ok, "once event cannot reopen after completion")
	var stale_selection: Dictionary = runtime.select_option("roadside_teahouse_intro", "start", "ask_again", run_state)
	asserts.false_value(stale_selection.ok, "stale selection cannot bypass once replay policy after completion")
	asserts.equal(stale_selection.reason, "event_already_completed", "stale selection returns explicit once replay failure")
	var repeat_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var finish_repeat: Dictionary = runtime.select_option("mountain_shrine_echo", "start", "ordinary_prayer", repeat_state)
	asserts.true_value(finish_repeat.ok, "repeat event completes")
	asserts.true_value(runtime.read_model_for_event("mountain_shrine_echo", repeat_state).ok, "repeat event can reopen after completion")

func _assert_bad_references_are_rejected(asserts) -> void:
	var bad_start: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({"events": [{
		"id": "bad_start",
		"name": "Bad Start",
		"status": "확정",
		"replay_policy": "once",
		"start_node_id": "missing",
		"nodes": [{"id": "start", "text": "", "options": []}]
	}]}))
	asserts.false_value(bad_start.ok, "event with missing start node is rejected")
	var bad_next: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({"events": [{
		"id": "bad_next",
		"name": "Bad Next",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [{"id": "start", "text": "", "options": [{"id": "go", "display_text": "Go", "next_node_id": "missing", "results": []}]}]
	}]}))
	asserts.false_value(bad_next.ok, "option with missing next node is rejected")

func _assert_bad_graph_shapes_are_rejected(asserts) -> void:
	var duplicate_node: Dictionary = _runtime_result_from_events([{
		"id": "duplicate_node",
		"name": "Duplicate Node",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [
			{"id": "start", "text": "", "options": [{"id": "done", "display_text": "Done", "results": [], "completes_event": true}]},
			{"id": "start", "text": "", "options": [{"id": "done", "display_text": "Done", "results": [], "completes_event": true}]}
		]
	}])
	asserts.false_value(duplicate_node.ok, "duplicate node ids are rejected")
	asserts.equal(duplicate_node.reason, "duplicate_node_id", "duplicate node ids return explicit reason")
	var duplicate_option: Dictionary = _runtime_result_from_events([{
		"id": "duplicate_option",
		"name": "Duplicate Option",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [{"id": "start", "text": "", "options": [
			{"id": "done", "display_text": "Done", "results": [], "completes_event": true},
			{"id": "done", "display_text": "Done Again", "results": [], "completes_event": true}
		]}]
	}])
	asserts.false_value(duplicate_option.ok, "duplicate option ids are rejected")
	asserts.equal(duplicate_option.reason, "duplicate_option_id", "duplicate option ids return explicit reason")
	var no_completion: Dictionary = _runtime_result_from_events([{
		"id": "no_completion",
		"name": "No Completion",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [{"id": "start", "text": "", "options": [{"id": "wait", "display_text": "Wait", "results": [], "next_node_id": "", "completes_event": false}]}]
	}])
	asserts.false_value(no_completion.ok, "all reachable dialogue paths must complete")
	asserts.equal(no_completion.reason, "non_terminating_dialogue_path", "non-completing leaf returns explicit reason")
	var cycle: Dictionary = _runtime_result_from_events([{
		"id": "cycle",
		"name": "Cycle",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [
			{"id": "start", "text": "", "options": [{"id": "loop", "display_text": "Loop", "results": [], "next_node_id": "again", "completes_event": false}]},
			{"id": "again", "text": "", "options": [{"id": "back", "display_text": "Back", "results": [], "next_node_id": "start", "completes_event": false}]}
		]
	}])
	asserts.false_value(cycle.ok, "reachable dialogue cycles are rejected")
	asserts.equal(cycle.reason, "dialogue_cycle", "cycle returns explicit reason")

func _assert_result_contracts_are_rejected(asserts) -> void:
	var unknown_type: Dictionary = _runtime_result_from_events([_single_result_event({"type": "grant_currency", "id": "coins", "quantity": 1})])
	asserts.false_value(unknown_type.ok, "unknown narrative result types are rejected")
	asserts.equal(unknown_type.reason, "invalid_result_type", "unknown result type returns explicit reason")
	var missing_quantity: Dictionary = _runtime_result_from_events([_single_result_event({"type": "grant_item", "id": "ash_stained_iron_kettle"})])
	asserts.false_value(missing_quantity.ok, "grant_item requires quantity")
	asserts.equal(missing_quantity.reason, "missing_result_quantity", "missing quantity returns explicit reason")
	var bad_quantity: Dictionary = _runtime_result_from_events([_single_result_event({"type": "grant_item", "id": "ash_stained_iron_kettle", "quantity": 0})])
	asserts.false_value(bad_quantity.ok, "grant_item quantity must be positive")
	asserts.equal(bad_quantity.reason, "invalid_result_quantity", "invalid quantity returns explicit reason")
	var bad_item: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"items": [{"id": "ash_stained_iron_kettle", "name": "재 묻은 철솥", "status": "초안"}],
		"events": [_single_result_event({"type": "grant_item", "id": "missing_item", "quantity": 1})]
	}))
	asserts.false_value(bad_item.ok, "grant_item targets must exist in catalog items when catalog items are available")
	asserts.equal(bad_item.reason, "missing_result_item", "missing grant item returns explicit reason")
	var missing_choices: Dictionary = _runtime_result_from_events([_single_result_event({"type": "apply_choice", "id": "daimyo_defeat"})])
	asserts.false_value(missing_choices.ok, "apply_choice requires choice definitions")
	asserts.equal(missing_choices.reason, "missing_choices_dataset", "missing choice definitions return explicit reason")
	var known_choice: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"items": [{"id": "ash_stained_iron_kettle", "name": "재 묻은 철솥", "status": "초안"}],
		"choices": [{"id": "daimyo_defeat"}],
		"events": [_single_result_event({"type": "apply_choice", "id": "daimyo_defeat"})]
	}))
	asserts.true_value(known_choice.ok, "apply_choice accepts a defined choice id")
	var multiple_choices: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"choices": [{"id": "daimyo_defeat"}],
		"events": [{
			"id": "multiple_choice_results", "name": "Multiple", "status": "확정", "replay_policy": "once", "start_node_id": "start",
			"nodes": [{"id": "start", "options": [{"id": "done", "display_text": "Done", "results": [{"type": "apply_choice", "id": "daimyo_defeat"}, {"type": "apply_choice", "id": "daimyo_defeat"}], "next_node_id": "", "completes_event": true}]}]
		}]
	}))
	asserts.false_value(multiple_choices.ok, "one narrative option cannot apply multiple choices")
	asserts.equal(multiple_choices.reason, "multiple_choice_results", "multiple choice result rejection has a stable reason")

func _assert_grant_item_requires_item_definitions(asserts) -> void:
	var events_only_grant: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"events": [_single_result_event({"type": "grant_item", "id": "ash_stained_iron_kettle", "quantity": 1})]
	}))
	asserts.false_value(events_only_grant.ok, "events-only catalog with grant_item is rejected")
	asserts.equal(events_only_grant.reason, "missing_items_dataset", "missing item definitions return explicit reason")

	var empty_items_grant: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"items": [],
		"events": [_single_result_event({"type": "grant_item", "id": "ash_stained_iron_kettle", "quantity": 1})]
	}))
	asserts.false_value(empty_items_grant.ok, "grant_item result id membership is always checked")
	asserts.equal(empty_items_grant.reason, "missing_result_item", "empty item definitions cannot satisfy grant_item membership")

	var events_only_flag: Dictionary = NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"events": [_single_result_event({"type": "set_run_flag", "id": "accepted_roadside_kettle"})]
	}))
	asserts.true_value(events_only_flag.ok, "set_run_flag-only events do not require item definitions")

func _assert_run_meta_boundary(asserts) -> void:
	var runtime: NarrativeRuntime = _fixture_runtime(asserts)
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {}, "current_biome_id": "common_region"}
	var no_meta: Dictionary = runtime.read_model_for_event("mountain_shrine_echo", run_state)
	asserts.true_value(no_meta.ok, "allowed meta condition can evaluate without leaking run state")
	asserts.equal(_option_ids(no_meta.read_model), ["ordinary_prayer"], "missing meta defaults to false for meta_flag and true for meta_not_flag")
	var meta_state := {"dialogue_memory_flags": ["remembered_old_shrine"], "unlocked_meta_flags": [], "run_count": 3}
	var with_meta: Dictionary = runtime.read_model_for_event("mountain_shrine_echo", run_state, meta_state)
	asserts.equal(_option_ids(with_meta.read_model), ["remembered_prayer"], "explicit allowed meta condition can alter options")
	var boundary_runtime: NarrativeRuntime = _runtime_from_events(asserts, [{
		"id": "bad_meta_condition",
		"name": "Bad Meta Condition",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [{"id": "start", "text": "", "options": [{"id": "bad", "display_text": "Bad", "conditions": [{"type": "meta_inventory_has_item", "id": "wood"}], "results": [], "next_node_id": "", "completes_event": true}]}]
	}])
	var boundary_result: Dictionary = boundary_runtime.read_model_for_event("bad_meta_condition", run_state, meta_state)
	asserts.false_value(boundary_result.ok, "non-allowlisted meta condition type cannot query meta state")

func _assert_read_model_does_not_mutate_state(asserts) -> void:
	var runtime: NarrativeRuntime = _fixture_runtime(asserts)
	var run_state := {"narrative_flags": [], "narrative_event_counts": {}, "inventory": {"ash_stained_iron_kettle": 0}, "current_biome_id": "common_region"}
	var before := run_state.duplicate(true)
	var model: Dictionary = runtime.read_model_for_event("roadside_teahouse_intro", run_state)
	asserts.true_value(model.ok, "read model can be built")
	asserts.equal(run_state, before, "presentation read model does not mutate run state")

func _fixture_runtime(asserts) -> NarrativeRuntime:
	return _runtime_from_events(asserts, _fixture_events())

func _runtime_result_from_events(events: Array) -> Dictionary:
	return NarrativeRuntime.new().from_catalog(FakeCatalog.new({
		"items": [{"id": "ash_stained_iron_kettle", "name": "재 묻은 철솥", "status": "초안"}],
		"events": events
	}))

func _runtime_from_events(asserts, events: Array) -> NarrativeRuntime:
	var result: Dictionary = _runtime_result_from_events(events)
	asserts.true_value(result.ok, "fixture narrative runtime initializes")
	return result.runtime

func _option_ids(read_model: Dictionary) -> Array:
	var ids: Array = []
	for option in read_model.options:
		ids.append(option.id)
	return ids

func _single_result_event(result: Dictionary) -> Dictionary:
	return {
		"id": "single_result_event",
		"name": "Single Result Event",
		"status": "확정",
		"replay_policy": "repeat",
		"start_node_id": "start",
		"nodes": [{"id": "start", "text": "", "options": [{"id": "done", "display_text": "Done", "results": [result], "next_node_id": "", "completes_event": true}]}]
	}

func _fixture_events() -> Array:
	return [
		{
			"id": "roadside_teahouse_intro",
			"name": "길가 찻집 첫 만남",
			"status": "확정",
			"replay_policy": "once",
			"start_node_id": "start",
			"nodes": [
				{
					"id": "start",
					"speaker_id": "traveler_host",
					"text": "찻집 주인이 낡은 다관을 조심스레 내민다.",
					"options": [
						{
							"id": "accept_kettle",
							"display_text": "다관을 받는다",
							"conditions": [{"type": "run_not_flag", "id": "accepted_roadside_kettle"}],
							"results": [
								{"type": "set_run_flag", "id": "accepted_roadside_kettle"},
								{"type": "grant_item", "id": "ash_stained_iron_kettle", "quantity": 1}
							],
							"next_node_id": "thanks",
							"completes_event": false
						},
						{
							"id": "ask_again",
							"display_text": "이미 받은 다관을 보여준다",
							"conditions": [{"type": "run_flag", "id": "accepted_roadside_kettle"}],
							"results": [{"type": "set_run_flag", "id": "showed_roadside_kettle"}],
							"next_node_id": "",
							"completes_event": true
						}
					]
				},
				{
					"id": "thanks",
					"speaker_id": "traveler_host",
					"text": "주인은 여행길의 첫 물맛을 잊지 말라고 말한다.",
					"options": [{"id": "bow_and_leave", "display_text": "고개 숙여 인사한다", "conditions": [], "results": [{"type": "set_run_flag", "id": "left_roadside_teahouse"}], "next_node_id": "", "completes_event": true}]
				}
			]
		},
		{
			"id": "mountain_shrine_echo",
			"name": "산길 신사의 메아리",
			"status": "확정",
			"replay_policy": "repeat",
			"start_node_id": "start",
			"nodes": [
				{
					"id": "start",
					"speaker_id": "shrine_keeper",
					"text": "신사 지기가 오늘 길에 남은 향을 묻는다.",
					"options": [
						{"id": "ordinary_prayer", "display_text": "무사한 길을 빈다", "conditions": [{"type": "meta_not_flag", "id": "remembered_old_shrine"}], "results": [{"type": "set_run_flag", "id": "offered_ordinary_prayer"}], "next_node_id": "", "completes_event": true},
						{"id": "remembered_prayer", "display_text": "전에 들은 종소리를 떠올린다", "conditions": [{"type": "meta_flag", "id": "remembered_old_shrine"}], "results": [{"type": "set_run_flag", "id": "answered_shrine_memory"}], "next_node_id": "", "completes_event": true}
					]
				}
			]
		}
	]
