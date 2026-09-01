extends RefCounted

const SaveCodec = preload("res://src/save/save_codec.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	var run_equipment := {"slots": {"tea_ware": {"item_id": "travel_bottle", "quantity": 1, "instance_id": "inst_tea_ware", "metadata": {"tea_ware_use_count": 4}}}}
	var run_save := SaveCodec.encode_run({"seed": 11037, "inventory": ["wood"], "equipment": run_equipment})
	var meta_save := SaveCodec.encode_meta({"run_count": 2, "discovered_records": ["oribe_bowl"], "unlocked_meta_flags": ["sen_rikyu_reunion_dialogue_1"]})

	asserts.equal(run_save.kind, "run", "run save kind is separate")
	asserts.equal(meta_save.kind, "meta", "meta save kind is separate")
	asserts.equal(run_save.schema_version, SaveCodec.CURRENT_SCHEMA_VERSION, "run save carries schema version")
	asserts.equal(meta_save.schema_version, SaveCodec.CURRENT_SCHEMA_VERSION, "meta save carries schema version")
	asserts.true_value(SaveCodec.decode_run(run_save).ok, "run save decodes")
	asserts.equal(SaveCodec.decode_run(run_save).state.equipment, run_equipment, "run save preserves equipment payload")
	asserts.equal(SaveCodec.decode_run(run_save).state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "run save keeps per-run tea ware use metadata")
	asserts.true_value(SaveCodec.decode_meta(meta_save).ok, "meta save decodes")
	asserts.false_value(SaveCodec.decode_meta(meta_save).state.has("tea_ware_use_count"), "meta save does not gain tea ware attachment state")
	asserts.false_value(SaveCodec.decode_meta(run_save).ok, "run save cannot decode as meta")
	asserts.false_value(SaveCodec.decode_run({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "run", "run": []}).ok, "run save rejects non-dictionary payload")
	asserts.false_value(SaveCodec.decode_meta({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "meta", "meta": []}).ok, "meta save rejects non-dictionary payload")

	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.completed_dungeon_ids = ["common_region"]
	state.teleport_states = {"common_region": "repairable"}
	state.repaired_teleports = ["mountain_region"]
	state.crafting_unlocks = ["common_region"]
	state.equipment = run_equipment
	state.narrative_flags = ["met_sen_rikyu"]
	state.narrative_event_counts = {"sen_rikyu_intro": 2}
	state.consumables = {
		"schema_version": 1,
		"next_action_id": 2,
		"active_action": {
			"action_id": "consumable_action_000001",
			"item_id": "bandage",
			"use_seconds": 1.0,
			"elapsed_seconds": 0.5,
			"context": {}
		}
	}
	var progression_save := SaveCodec.encode_run(state.to_dictionary())
	asserts.equal(SaveCodec.decode_run(progression_save).state.teleport_states.common_region, "repairable", "run save preserves teleport progression")
	var decoded := SaveCodec.decode_run(progression_save)
	asserts.true_value(decoded.run_state is RunState, "run save decodes to hydrated RunState")
	var progression := BiomeProgressionState.new()
	asserts.true_value(progression.configure(_fixture_biomes(), decoded.run_state).ok, "hydrated RunState resumes biome progression")
	asserts.equal(progression.current_biome_id(), "common_region", "resumed progression preserves current biome")
	asserts.equal(progression.teleport_state_for("common_region"), BiomeProgressionState.TELEPORT_REPAIRABLE, "resumed progression preserves teleport state")
	asserts.equal(progression.crafting_context().unlocked_biome_ids, ["common_region"], "resumed progression preserves crafting unlocks")
	asserts.equal(decoded.run_state.completed_dungeon_ids, ["common_region"], "hydrated run state preserves dungeon completion")
	asserts.equal(decoded.run_state.repaired_teleports, ["mountain_region"], "hydrated run state preserves repaired teleport compatibility state")
	asserts.equal(decoded.run_state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "hydrated run state preserves equipment attachment metadata")
	asserts.equal(decoded.run_state.narrative_flags, ["met_sen_rikyu"], "hydrated run state preserves narrative flags")
	asserts.equal(decoded.run_state.narrative_event_counts.sen_rikyu_intro, 2, "hydrated run state preserves narrative counts")
	asserts.equal(decoded.run_state.consumables.active_action.elapsed_seconds, 0.5, "hydrated run state preserves active consumable progress")
	progression_save.run.equipment.slots.tea_ware.metadata.tea_ware_use_count = 99
	progression_save.run.narrative_flags.append("mutated_after_decode")
	progression_save.run.consumables.active_action.elapsed_seconds = 0.75
	asserts.equal(decoded.run_state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "hydrated equipment state is detached from encoded payload")
	asserts.equal(decoded.run_state.narrative_flags, ["met_sen_rikyu"], "hydrated narrative state is detached from encoded payload")
	asserts.equal(decoded.run_state.consumables.active_action.elapsed_seconds, 0.5, "hydrated consumable state is detached from encoded payload")
	state.reset_biome_progression()
	asserts.equal(state.current_biome_id, "", "run state reset clears current biome")
	asserts.equal(state.completed_dungeon_ids, [], "run state reset clears dungeon completion")
	asserts.equal(state.teleport_states, {}, "run state reset clears teleport states")
	asserts.equal(state.crafting_unlocks, [], "run state reset clears crafting unlocks")

func _fixture_biomes() -> Array:
	return [
		{"id": "common_region", "progression_order": 1},
		{"id": "mountain_region", "progression_order": 2}
	]
