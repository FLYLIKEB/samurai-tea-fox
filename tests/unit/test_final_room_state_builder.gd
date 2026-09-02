extends RefCounted

const CoreTeaWareCollection = preload("res://src/dungeon/core_tea_ware_collection.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const FinalRoomStateBuilder = preload("res://src/meta/final_room_state_builder.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads final room state data")
	var builder_result: Dictionary = FinalRoomStateBuilder.from_catalog(catalog)
	asserts.true_value(builder_result.ok, "final room state builder configures")
	var builder: FinalRoomStateBuilder = builder_result.builder
	_assert_choice_survival_and_relic_projection(asserts, builder)
	_assert_core_tea_ware_and_philosophy_projection(asserts, catalog, builder)
	_assert_deterministic_snapshot(asserts, builder)
	_assert_missing_data_fallback(asserts)
	_assert_main_exposes_read_model(asserts, catalog)

func _assert_choice_survival_and_relic_projection(asserts, builder: FinalRoomStateBuilder) -> void:
	var run_state := RunState.new()
	run_state.choice_history = ["daimyo_relinquish_tea", "missing_choice"]
	run_state.target_survival = {"daimyo": true, "oribe": false}
	run_state.final_room_effects = [{"choice_id": "daimyo_relinquish_tea", "effect": "나눈 차입이 열린 채 놓인다."}]
	var result: Dictionary = builder.build(run_state)
	asserts.true_value(result.ok, "final room state builds from run traces")
	var state: Dictionary = result.state
	asserts.equal(state.choice_traces.size(), 2, "choice traces preserve run choice order")
	asserts.equal(state.choice_traces[0].choice_key, "DAIMYO_RELINQUISH_TEA", "known choice trace uses data definition")
	asserts.equal(state.choice_traces[0].final_room_effect, "나눈 차입이 열린 채 놓인다.", "run effect overrides definition snapshot when present")
	asserts.equal(state.choice_traces[1].choice_key, "missing_choice", "missing choice falls back to stable id")
	asserts.equal(state.surviving_characters.size(), 1, "living target appears as character")
	asserts.equal(state.surviving_characters[0].target_id, "daimyo", "living target id is preserved")
	asserts.equal(state.surviving_characters[0].character_id, "chr_2", "living target uses stable final_room_target_ids character relation")
	asserts.equal(state.surviving_characters[0].placement_key, "character_daimyo_present", "living target gets character placement key")
	asserts.equal(state.relics.size(), 1, "dead target appears as relic")
	asserts.equal(state.relics[0].target_id, "oribe", "dead target id is preserved")
	asserts.equal(state.relics[0].placement_key, "relic_oribe_absent", "dead target gets relic placement key")
	asserts.false_value(state.has("morality_score"), "final room read model exposes no numeric morality score")
	asserts.false_value(state.has("good_score"), "final room read model exposes no hidden good score")

func _assert_core_tea_ware_and_philosophy_projection(asserts, catalog: DataCatalog, builder: FinalRoomStateBuilder) -> void:
	var collection: CoreTeaWareCollection = CoreTeaWareCollection.from_catalog(catalog).collection
	var run_state := RunState.new()
	asserts.true_value(collection.collect_core_tea_ware("war_tea_caddy", run_state).ok, "collects third core tea ware")
	asserts.true_value(collection.collect_core_tea_ware("oribe_green_glazed_bowl", run_state).ok, "collects first core tea ware")
	run_state.philosophy_marks = ["敬·마주봄", "和·공존", "敬·마주봄"]
	var state: Dictionary = builder.build(run_state).state
	asserts.equal(state.tea_ware_placements.size(), 2, "collected core tea ware becomes display placements")
	asserts.equal(state.tea_ware_placements[0].item_id, "oribe_green_glazed_bowl", "tea ware placements sort by core order")
	asserts.equal(state.tea_ware_placements[0].placement_key, "tea_ware_oribe_green_glazed_bowl_display", "tea ware placement key is deterministic")
	asserts.equal(state.tea_ware_placements[1].item_id, "war_tea_caddy", "later-order tea ware follows")
	asserts.equal(state.philosophy_marks, ["敬·마주봄", "和·공존"], "philosophy projection de-duplicates while preserving first-seen order")
	asserts.true_value(String(state.philosophy_combination_key).length() > 0, "philosophy combination has a deterministic key")
	asserts.true_value(state.space_state_keys.has("core_tea_ware_2"), "space keys summarize tea ware count")
	var other_run := RunState.new()
	other_run.philosophy_marks = ["清·절제", "요괴성·힘"]
	var other_state: Dictionary = builder.build(other_run).state
	asserts.false_value(other_state.philosophy_combination_key == state.philosophy_combination_key, "different canonical philosophy marks do not collide in the combination key")

func _assert_deterministic_snapshot(asserts, builder: FinalRoomStateBuilder) -> void:
	var run_state := RunState.new()
	run_state.choice_history = ["daimyo_defeat"]
	run_state.target_survival = {"oribe": false, "daimyo": true}
	run_state.philosophy_marks = ["清·절제", "요괴성·힘"]
	var first: Dictionary = builder.build(run_state).state
	var second: Dictionary = builder.build(run_state).state
	asserts.equal(second, first, "same run input builds identical final room state")
	asserts.equal(first.relics[0].target_id, "oribe", "target survival projection has deterministic target sorting")

func _assert_missing_data_fallback(asserts) -> void:
	var builder := FinalRoomStateBuilder.new()
	var run_state := {
		"choice_history": ["unknown_choice"],
		"final_room_effects": [],
		"target_survival": {"unknown_target": false},
		"philosophy_marks": [],
		"core_tea_ware_collection": {"schema_version": 1, "collected_ids": ["unknown_teaware"], "collected_by_id": {}}
	}
	var state: Dictionary = builder.build(run_state).state
	asserts.equal(state.choice_traces[0].display_text, "unknown_choice", "missing choice data falls back to id")
	asserts.equal(state.relics[0].name, "unknown_target", "missing character data falls back to target id")
	asserts.equal(state.tea_ware_placements[0].name, "unknown_teaware", "missing item data falls back to item id")
	asserts.equal(state.philosophy_combination_key, "none", "missing philosophy data uses explicit empty key")

func _assert_main_exposes_read_model(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures final room builder")
	main.run_state.choice_history = ["daimyo_relinquish_tea"]
	main.run_state.target_survival = {"daimyo": true}
	var read_model: Dictionary = main.final_room_state_read_model()
	asserts.true_value(read_model.ok, "main exposes final room state read model")
	asserts.equal(read_model.state.choice_traces[0].choice_id, "daimyo_relinquish_tea", "main read model uses current run choice traces")
	asserts.equal(read_model.state.surviving_characters[0].placement_key, "character_daimyo_present", "main read model projects living character placement")
	main.free()
