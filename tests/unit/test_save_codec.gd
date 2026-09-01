extends RefCounted

const SaveCodec = preload("res://src/save/save_codec.gd")

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
