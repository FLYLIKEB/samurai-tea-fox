extends RefCounted

const SaveCodec = preload("res://src/save/save_codec.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const RunState = preload("res://src/save/run_state.gd")
const MetaState = preload("res://src/save/meta_state.gd")

const TEST_DIRECTORY := "user://dev14_save_store_tests"
const RUN_PATH := TEST_DIRECTORY + "/run.json"
const META_PATH := TEST_DIRECTORY + "/meta.json"

func run(asserts) -> void:
	_cleanup()
	var store := SaveStore.new(RUN_PATH, META_PATH)
	var run_state := _full_run_state()
	var meta_state := _full_meta_state()

	asserts.true_value(store.save_run(run_state).ok, "interruption run save is written atomically")
	asserts.true_value(store.save_meta(meta_state).ok, "meta save is written to its separate path")
	asserts.true_value(FileAccess.file_exists(RUN_PATH), "run save uses the run path")
	asserts.true_value(FileAccess.file_exists(META_PATH), "meta save uses the meta path")

	var resumed_run := store.load_run()
	var resumed_meta := store.load_meta()
	asserts.true_value(resumed_run.ok, "interrupted run resumes from disk")
	asserts.true_value(resumed_meta.ok, "meta state resumes from disk")
	var disk_canonical_run: Dictionary = RunState.from_dictionary(JSON.parse_string(JSON.stringify(run_state.to_dictionary()))).to_dictionary()
	asserts.equal(resumed_run.state, disk_canonical_run, "same-run resume preserves every RunState snapshot field")
	asserts.equal(resumed_meta.state, meta_state.to_dictionary(), "meta resume preserves every MetaState snapshot field")
	asserts.true_value(resumed_run.run_state is RunState, "run load returns hydrated RunState")
	asserts.true_value(resumed_meta.meta_state is MetaState, "meta load returns hydrated MetaState")

	var raw_run = JSON.parse_string(FileAccess.get_file_as_string(RUN_PATH))
	var raw_meta = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	asserts.equal(raw_run.kind, "run", "run file contains only a run envelope")
	asserts.false_value(raw_run.has("meta"), "run file does not contain meta payload")
	asserts.equal(raw_meta.kind, "meta", "meta file contains only a meta envelope")
	asserts.false_value(raw_meta.has("run"), "meta file does not contain run payload")

	_write_text(RUN_PATH, "{not valid json")
	var corrupt_result := store.load_run()
	asserts.false_value(corrupt_result.ok, "corrupt JSON is rejected")
	asserts.true_value("Corrupt JSON" in corrupt_result.error, "corrupt JSON reports a clear error")

	_write_text(RUN_PATH, JSON.stringify({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "run"}))
	asserts.false_value(store.load_run().ok, "missing payload is rejected")
	asserts.false_value(SaveCodec.decode_run({"schema_version": 1, "kind": "run", "run": {}}).ok, "missing required run field is rejected")
	asserts.false_value(SaveCodec.decode_meta({"schema_version": 1, "kind": "meta", "meta": {}}).ok, "missing required meta field is rejected")
	asserts.false_value(SaveCodec.decode_run({"schema_version": 1, "kind": "run", "run": {"seed": "invalid"}}).ok, "wrongly typed run field is rejected")
	_write_text(RUN_PATH, JSON.stringify({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION + 1, "kind": "run", "run": {}}))
	var future_result := store.load_run()
	asserts.false_value(future_result.ok, "unsupported future schema is rejected")
	asserts.true_value("future" in future_result.error, "future schema reports a clear error")

	var migrated := SaveCodec.decode_run({
		"schema_version": 1,
		"kind": "run",
		"run": {"seed": 27}
	})
	asserts.true_value(migrated.ok, "schema migration boundary adds explicit v1 module defaults")
	asserts.equal(migrated.state.acquisitions, {}, "migration defaults missing acquisition snapshot")
	asserts.equal(migrated.state.dungeon_runtime_state, {}, "migration defaults missing dungeon snapshot")

	asserts.true_value(store.save_run(run_state).ok, "baseline target exists before replacement failure")
	var failed_state := _full_run_state()
	failed_state.seed = 999
	var failing_store := SaveStore.new(RUN_PATH, META_PATH, _fail_replace)
	var failed_replace := failing_store.save_run(failed_state)
	asserts.false_value(failed_replace.ok, "atomic replacement failure is reported")
	asserts.equal(store.load_run().state.seed, run_state.seed, "replacement failure preserves the previous target")
	asserts.false_value(FileAccess.file_exists(RUN_PATH + ".tmp"), "replacement failure removes the temporary file")

	_cleanup()

func _full_run_state() -> RunState:
	var state := RunState.new()
	state.data_version = "fixture-data-v1"
	state.seed = 11037
	state.current_biome_id = "common_region"
	state.inventory = {"slots": [{"item_id": "wood", "quantity": 2}]}
	state.equipment = {"slots": {"tea_ware": {"item_id": "travel_bottle"}}}
	state.currency = 7
	state.tails = 2
	state.abilities = ["fox_dash"]
	state.completed_dungeon_ids = ["common_region"]
	state.completed_runtime_dungeon_ids = ["fixture_dungeon"]
	state.dungeon_runtime_state = {"instance_id": "fixture_instance", "return_context": {"biome_id": "common_region"}}
	state.teleport_states = {"common_region": "repairable"}
	state.repaired_teleports = ["mountain_region"]
	state.crafting_unlocks = ["common_region"]
	state.narrative_flags = ["met_sen_rikyu"]
	state.narrative_event_counts = {"sen_rikyu_intro": 2}
	state.consumables = {"schema_version": 1, "active_action": {"item_id": "bandage"}}
	state.choice_history = ["daimyo_relinquish_tea"]
	state.choice_group_selections = {"daimyo_resolution": "daimyo_relinquish_tea"}
	state.target_survival = {"daimyo": true}
	state.philosophy_marks = ["和·공존"]
	state.final_room_effects = [{"choice_id": "daimyo_relinquish_tea"}]
	state.acquisitions = {
		"gatherables": [{"node_id": "tree_01", "depleted": true}],
		"pickups": [{"pickup_id": "pickup_000001", "item_id": "wood"}],
		"processed_drop_request_ids": ["drop_01"]
	}
	return state

func _full_meta_state() -> MetaState:
	var state := MetaState.new()
	state.run_count = 3
	state.best_reached_biome_order = 2
	state.discovered_records = ["oribe_bowl"]
	state.unlocked_meta_flags = ["sen_rikyu_reunion_dialogue_1"]
	state.dialogue_memory_flags = ["father_remembers_previous_run"]
	return state

func _fail_replace(_from_path: String, _to_path: String) -> int:
	return ERR_CANT_CREATE

func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", META_PATH, META_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
