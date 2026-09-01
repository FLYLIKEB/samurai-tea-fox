extends RefCounted

const SaveCodec = preload("res://src/save/save_codec.gd")
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

	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.completed_dungeon_ids = ["common_region"]
	state.teleport_states = {"common_region": "repairable"}
	state.crafting_unlocks = ["common_region"]
	var progression_save := SaveCodec.encode_run(state.to_dictionary())
	asserts.equal(SaveCodec.decode_run(progression_save).state.teleport_states.common_region, "repairable", "run save preserves teleport progression")
	state.reset_biome_progression()
	asserts.equal(state.current_biome_id, "", "run state reset clears current biome")
	asserts.equal(state.completed_dungeon_ids, [], "run state reset clears dungeon completion")
	asserts.equal(state.teleport_states, {}, "run state reset clears teleport states")
	asserts.equal(state.crafting_unlocks, [], "run state reset clears crafting unlocks")
