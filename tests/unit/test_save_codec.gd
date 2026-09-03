extends RefCounted

const SaveCodec = preload("res://src/save/save_codec.gd")
const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const TailState = preload("res://src/player/tail_state.gd")

func run(asserts) -> void:
	var run_equipment := {"slots": {"tea_ware": {"item_id": "travel_bottle", "quantity": 1, "instance_id": "inst_tea_ware", "metadata": {"tea_ware_use_count": 4}}}}
	var choice_state := {
		"choice_history": ["daimyo_relinquish_tea"],
		"choice_group_selections": {"daimyo_resolution": "daimyo_relinquish_tea"},
		"target_survival": {"daimyo": true},
		"philosophy_marks": ["和·공존"],
		"final_room_effects": [{"choice_id": "daimyo_relinquish_tea", "effect": "관계형 지원 효과"}]
	}
	var run_payload := {"seed": 11037, "inventory": ["wood"], "equipment": run_equipment, "tail_state": _tail_snapshot(2, ["humanity"])}
	run_payload.merge(choice_state)
	var run_save := SaveCodec.encode_run(run_payload)
	var meta_save := SaveCodec.encode_meta({
		"run_count": 2,
		"discovered_records": ["oribe_bowl"],
		"unlocked_meta_flags": ["sen_rikyu_reunion_dialogue_1"],
		"past_choice_ids": ["daimyo_relinquish_tea"],
		"reached_place_ids": ["mountain_region"],
		"death_record_ids": ["wild_dog_ambush"]
	})

	asserts.equal(run_save.kind, "run", "run save kind is separate")
	asserts.equal(meta_save.kind, "meta", "meta save kind is separate")
	asserts.equal(run_save.schema_version, SaveCodec.CURRENT_SCHEMA_VERSION, "run save carries schema version")
	asserts.equal(meta_save.schema_version, SaveCodec.CURRENT_SCHEMA_VERSION, "meta save carries schema version")
	asserts.true_value(SaveCodec.decode_run(run_save).ok, "run save decodes")
	asserts.equal(SaveCodec.decode_run(run_save).state.equipment, run_equipment, "run save preserves equipment payload")
	asserts.equal(SaveCodec.decode_run(run_save).state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "run save keeps per-run tea ware use metadata")
	asserts.equal(SaveCodec.decode_run(run_save).state.tail_state.stage, 2, "run save preserves tail state stage")
	asserts.equal(SaveCodec.decode_run(run_save).state.tails, 2, "run save mirrors tail count from tail state")
	var decoded_choice: Dictionary = SaveCodec.decode_run(run_save)
	for field in choice_state:
		asserts.equal(decoded_choice.state[field], choice_state[field], "run save preserves choice field '%s'" % field)
		asserts.equal(decoded_choice.run_state.get(field), choice_state[field], "hydrated RunState preserves choice field '%s'" % field)
	asserts.true_value(SaveCodec.decode_meta(meta_save).ok, "meta save decodes")
	asserts.equal(SaveCodec.decode_meta(meta_save).state.past_choice_ids, ["daimyo_relinquish_tea"], "meta save preserves past choice stable IDs")
	asserts.equal(SaveCodec.decode_meta(meta_save).state.reached_place_ids, ["mountain_region"], "meta save preserves reached place stable IDs")
	asserts.equal(SaveCodec.decode_meta(meta_save).state.death_record_ids, ["wild_dog_ambush"], "meta save preserves death record stable IDs")
	asserts.false_value(SaveCodec.decode_meta(meta_save).state.has("tea_ware_use_count"), "meta save does not gain tea ware attachment state")
	asserts.false_value(run_save.run.has("past_choice_ids"), "run save remains separate from previous-run choice memory")
	asserts.false_value(run_save.run.has("reached_place_ids"), "run save remains separate from reached-place memory")
	asserts.false_value(run_save.run.has("death_record_ids"), "run save remains separate from death memory")
	asserts.false_value(SaveCodec.decode_meta(run_save).ok, "run save cannot decode as meta")
	asserts.false_value(SaveCodec.decode_run({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "run", "run": []}).ok, "run save rejects non-dictionary payload")
	asserts.false_value(SaveCodec.decode_meta({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "meta", "meta": []}).ok, "meta save rejects non-dictionary payload")
	var legacy_meta := SaveCodec.decode_meta({"schema_version": 1, "kind": "meta", "meta": {"run_count": 4}})
	asserts.true_value(legacy_meta.ok, "legacy schema-v1 meta save receives new query defaults")
	asserts.equal(legacy_meta.state.past_choice_ids, [], "legacy schema-v1 defaults past choices")
	asserts.equal(legacy_meta.state.reached_place_ids, [], "legacy schema-v1 defaults reached places")
	asserts.equal(legacy_meta.state.death_record_ids, [], "legacy schema-v1 defaults death records")
	var malformed_meta := MetaState.new().to_dictionary()
	malformed_meta.run_count = 1
	malformed_meta.death_record_ids = "wild_dog_ambush"
	asserts.false_value(SaveCodec.decode_meta({"schema_version": 1, "kind": "meta", "meta": malformed_meta}).ok, "meta save rejects malformed query input types")
	for field in ["past_choice_ids", "reached_place_ids", "death_record_ids"]:
		var malformed_ids := MetaState.new().to_dictionary()
		malformed_ids.run_count = 1
		malformed_ids[field] = ["valid_id", "Display Name", 42, ""]
		asserts.false_value(SaveCodec.decode_meta({"schema_version": 1, "kind": "meta", "meta": malformed_ids}).ok, "meta save rejects malformed stable IDs in '%s'" % field)
		asserts.false_value(SaveCodec.validate_meta_snapshot(malformed_ids).ok, "meta snapshot validation rejects malformed stable IDs in '%s'" % field)
	asserts.false_value(SaveCodec.decode_run({"schema_version": SaveCodec.CURRENT_SCHEMA_VERSION, "kind": "run", "run": {"seed": 1, "tail_state": {"stage": 3, "tail_count": 2, "path_flags": [], "transition_history": []}}}).ok, "run save rejects malformed tail state")
	var invalid_history_flag := TailState.default_dictionary()
	invalid_history_flag.transition_history[0].path_flags = ["morality_score"]
	asserts.false_value(SaveCodec.decode_run({"schema_version": 1, "kind": "run", "run": {"seed": 1, "tail_state": invalid_history_flag}}).ok, "run save rejects invalid tail history path flags")
	var non_array_history_flags := TailState.default_dictionary()
	non_array_history_flags.transition_history[0].path_flags = "humanity"
	asserts.false_value(SaveCodec.decode_run({"schema_version": 1, "kind": "run", "run": {"seed": 1, "tail_state": non_array_history_flags}}).ok, "run save rejects non-array tail history path flags")
	var legacy_run := SaveCodec.decode_run({"schema_version": 1, "kind": "run", "run": {"seed": 77, "tails": 4}})
	asserts.true_value(legacy_run.ok, "legacy v1 run without tail state decodes")
	asserts.equal(legacy_run.state.tails, 4, "legacy v1 run preserves tail count")
	asserts.equal(legacy_run.state.tail_state.stage, 4, "legacy v1 run synthesizes tail stage before defaults")
	asserts.equal(legacy_run.state.tail_state.transition_history[0].stage, 1, "legacy v1 synthesized history starts at stage one")
	asserts.equal(legacy_run.state.tail_state.transition_history[-1].source_id, "legacy_tail_count", "legacy v1 synthesized history records a stable migration source")

	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.completed_dungeon_ids = ["common_region"]
	state.completed_runtime_dungeon_ids = ["fixture_dungeon"]
	state.dungeon_runtime_state = {
		"schema_version": 1,
		"instance_id": "fixture_instance",
		"dungeon_id": "fixture_dungeon",
		"biome_id": "common_region",
		"lifecycle_state": "active",
		"return_context": {"biome_id": "common_region", "world_seed": 11037}
	}
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
	state.time = {"schema_version": 1, "phase": "night", "phase_elapsed_seconds": 12.5, "kokoro_decay_carry": 0.25}
	state.acquisitions = {
		"schema_version": 1,
		"next_pickup_id": 2,
		"gatherables": [{"node_id": "tree_01", "definition_id": "fixture_tree_common", "position": {"x": 1, "y": 2}, "depleted": true}],
		"pickups": [{"pickup_id": "pickup_000001", "item_id": "wood", "quantity": 1, "position": {"x": 1, "y": 2}, "source": {"source_kind": "gatherable"}}],
		"processed_drop_request_ids": []
	}
	state.placed_facilities = [{
		"biome_id": "common_region",
		"facility_item_id": "wooden_workbench",
		"owner_id": "wooden_workbench@4,5",
		"origin": {"x": 4, "y": 5},
		"metadata": {"installed_by_player": true}
	}]
	state.trade_stock = {"shop_1": 2}
	state.tail_state = _tail_snapshot(3, ["yokai_nature"])
	state.tails = 3
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
	asserts.equal(decoded.run_state.completed_runtime_dungeon_ids, ["fixture_dungeon"], "hydrated run state preserves canonical dungeon completion")
	asserts.equal(decoded.run_state.dungeon_runtime_state.instance_id, "fixture_instance", "hydrated run state preserves active dungeon instance")
	asserts.equal(decoded.run_state.repaired_teleports, ["mountain_region"], "hydrated run state preserves repaired teleport compatibility state")
	asserts.equal(decoded.run_state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "hydrated run state preserves equipment attachment metadata")
	asserts.equal(decoded.run_state.narrative_flags, ["met_sen_rikyu"], "hydrated run state preserves narrative flags")
	asserts.equal(decoded.run_state.narrative_event_counts.sen_rikyu_intro, 2, "hydrated run state preserves narrative counts")
	asserts.equal(decoded.run_state.consumables.active_action.elapsed_seconds, 0.5, "hydrated run state preserves active consumable progress")
	asserts.equal(decoded.run_state.time.phase, "night", "hydrated run state preserves time phase")
	asserts.true_value(decoded.run_state.acquisitions.gatherables[0].depleted, "hydrated run state preserves gatherable depletion")
	asserts.equal(decoded.run_state.placed_facilities[0].facility_item_id, "wooden_workbench", "run save preserves player-installed facilities")
	asserts.equal(decoded.run_state.acquisitions.pickups[0].item_id, "wood", "hydrated run state preserves world pickups")
	asserts.equal(decoded.run_state.trade_stock.shop_1, 2, "hydrated run state preserves trade stock")
	asserts.equal(decoded.run_state.tail_state.stage, 3, "hydrated run state preserves tail stage")
	asserts.equal(decoded.run_state.tail_state.path_flags, ["yokai_nature"], "hydrated run state preserves tail path flags")
	progression_save.run.equipment.slots.tea_ware.metadata.tea_ware_use_count = 99
	progression_save.run.narrative_flags.append("mutated_after_decode")
	progression_save.run.consumables.active_action.elapsed_seconds = 0.75
	progression_save.run.time.phase = "day"
	progression_save.run.acquisitions.pickups[0].quantity = 99
	progression_save.run.tail_state.path_flags.append("mutated_after_decode")
	asserts.equal(decoded.run_state.equipment.slots.tea_ware.metadata.tea_ware_use_count, 4, "hydrated equipment state is detached from encoded payload")
	asserts.equal(decoded.run_state.narrative_flags, ["met_sen_rikyu"], "hydrated narrative state is detached from encoded payload")
	asserts.equal(decoded.run_state.consumables.active_action.elapsed_seconds, 0.5, "hydrated consumable state is detached from encoded payload")
	asserts.equal(decoded.run_state.time.phase, "night", "hydrated time state is detached from encoded payload")
	asserts.equal(decoded.run_state.acquisitions.pickups[0].quantity, 1, "hydrated acquisition state is detached from encoded payload")
	asserts.equal(decoded.run_state.tail_state.path_flags, ["yokai_nature"], "hydrated tail state is detached from encoded payload")
	state.reset_biome_progression()
	asserts.equal(state.current_biome_id, "", "run state reset clears current biome")
	asserts.equal(state.completed_dungeon_ids, [], "run state reset clears dungeon completion")
	asserts.equal(state.completed_runtime_dungeon_ids, [], "run state reset clears canonical dungeon completion")
	asserts.equal(state.dungeon_runtime_state, {}, "run state reset clears active dungeon runtime")
	asserts.equal(state.teleport_states, {}, "run state reset clears teleport states")
	asserts.equal(state.crafting_unlocks, [], "run state reset clears crafting unlocks")
	asserts.equal(state.placed_facilities, [], "biome progression reset clears installed facilities")
	state.reset_run_growth()
	asserts.equal(state.tails, 1, "run growth reset returns tails to one")
	asserts.equal(state.tail_state, TailState.default_dictionary(), "run growth reset returns tail state to default")
	asserts.equal(state.abilities, [], "run growth reset clears run ability candidates")

func _fixture_biomes() -> Array:
	return [
		{"id": "common_region", "progression_order": 1},
		{"id": "mountain_region", "progression_order": 2}
	]

func _tail_snapshot(stage: int, flags: Array) -> Dictionary:
	var tail := TailState.new()
	if stage > 1 or not flags.is_empty():
		var result := tail.apply_transition("event", "test_tail_growth", stage, flags)
		if not result.ok:
			return {}
	return tail.to_dictionary()
