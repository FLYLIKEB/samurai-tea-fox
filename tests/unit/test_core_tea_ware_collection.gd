extends RefCounted

const CoreTeaWareCollection = preload("res://src/dungeon/core_tea_ware_collection.gd")
const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const Main = preload("res://src/main/main.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunEndProcessor = preload("res://src/meta/run_end_processor.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class ProgressionBoundary:
	extends RefCounted
	var biome_id := ""
	var completed := []

	func _init(initial_biome_id: String) -> void:
		biome_id = initial_biome_id

	func current_biome_id() -> String:
		return biome_id

	func complete_dungeon(_biome_id: String) -> Dictionary:
		completed.append(_biome_id)
		return {"ok": true}

	func complete_dungeon_transaction(_biome_id: String, reward_hook: Callable) -> Dictionary:
		var reward_result: Dictionary = reward_hook.call()
		if not reward_result.ok:
			return reward_result
		completed.append(_biome_id)
		return {"ok": true}

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog loads core tea ware data")
	var service_result: Dictionary = CoreTeaWareCollection.from_catalog(catalog)
	asserts.true_value(service_result.ok, "core tea ware service configures from catalog: %s" % service_result.get("error", ""))
	var service: CoreTeaWareCollection = service_result.collection
	_assert_required_set_order(asserts, service)
	_assert_gate_requires_complete_run_set(asserts, service)
	_assert_boss_resolution_rewards(asserts, service)
	_assert_run_reset_and_meta_record_separation(asserts, service)
	_assert_save_round_trip(asserts, service)
	_assert_main_exposes_final_room_gate(asserts, catalog)
	_assert_main_wires_boss_dungeon_reward_transaction(asserts, catalog)
	_assert_main_reward_hook_failure_is_atomic(asserts, catalog)
	_assert_definition_validation(asserts)

func _assert_required_set_order(asserts, service: CoreTeaWareCollection) -> void:
	asserts.equal(service.required_order, [
		"oribe_green_glazed_bowl",
		"unbroken_failure",
		"war_tea_caddy",
		"ash_stained_iron_kettle",
		"old_incense_box"
	], "core tea ware required order is data-driven and contiguous")

func _assert_gate_requires_complete_run_set(asserts, service: CoreTeaWareCollection) -> void:
	var run_state := RunState.new()
	var empty_gate := service.final_room_gate_query(run_state)
	asserts.false_value(empty_gate.can_enter_final_room, "empty run cannot enter final tea room")
	asserts.equal(empty_gate.missing_ids, service.required_order, "empty run is missing every core tea ware")

	asserts.true_value(service.collect_core_tea_ware("war_tea_caddy", run_state, {"resolution_type": "combat"}).ok, "can collect third-order core tea ware first")
	asserts.true_value(service.collect_core_tea_ware("oribe_green_glazed_bowl", run_state, {"resolution_type": "peaceful"}).ok, "can collect first-order core tea ware later")
	var partial_gate := service.final_room_gate_query(run_state)
	asserts.false_value(partial_gate.can_enter_final_room, "partial core tea ware set keeps final gate closed")
	asserts.equal(partial_gate.collected_ids, ["oribe_green_glazed_bowl", "war_tea_caddy"], "collected ids project in required order regardless of acquisition order")
	asserts.true_value(run_state.discovered_records.has("core_tea_ware_oribe_green_glazed_bowl"), "run discovery records collected core tea ware separately")

	for item_id in ["unbroken_failure", "ash_stained_iron_kettle", "old_incense_box"]:
		asserts.true_value(service.collect_core_tea_ware(item_id, run_state).ok, "collects required core tea ware: %s" % item_id)
	var full_gate := service.final_room_gate_query(run_state)
	asserts.true_value(full_gate.can_enter_final_room, "complete current-run set opens final tea room gate")
	asserts.equal(full_gate.missing_ids, [], "complete set has no missing core tea ware")
	var duplicate := service.collect_core_tea_ware("war_tea_caddy", run_state)
	asserts.false_value(duplicate.ok, "duplicate core tea ware collection is blocked")
	asserts.equal(duplicate.reason, "duplicate_core_tea_ware", "duplicate collection has stable reason")
	var unknown := service.collect_core_tea_ware("humble_clay_bowl", run_state)
	asserts.false_value(unknown.ok, "non-core tea ware does not satisfy collection")
	asserts.equal(unknown.reason, "unknown_core_tea_ware", "non-core tea ware has stable reason")

func _assert_boss_resolution_rewards(asserts, service: CoreTeaWareCollection) -> void:
	var run_state := RunState.new()
	var combat := service.record_boss_resolution_rewards({
		"event_type": "boss_encounter_resolved",
		"resolution_type": "combat",
		"boss_id": "sample_ash_warden",
		"dungeon_id": "dungeon_1",
		"reward_item_ids": ["war_tea_caddy"]
	}, run_state)
	asserts.true_value(combat.ok, "combat boss resolution records core tea ware reward")
	asserts.equal(combat.collected, ["war_tea_caddy"], "combat reward records collected id")
	asserts.equal(run_state.core_tea_ware_collection.collected_by_id.war_tea_caddy.resolution_type, "combat", "combat reward context is preserved")

	var peaceful := service.record_boss_resolution_rewards({
		"event_type": "dungeon_cleared",
		"resolution_type": "peaceful",
		"boss_id": "sample_bamboo_guardian",
		"dungeon_id": "dungeon_4",
		"choice_key": "share_tea",
		"run_flag": "fixture_shared_tea",
		"reward_item_ids": ["oribe_green_glazed_bowl", "bandage"]
	}, run_state)
	asserts.true_value(peaceful.ok, "peaceful dungeon clear records core tea ware reward")
	asserts.equal(peaceful.collected, ["oribe_green_glazed_bowl"], "peaceful reward records only core tea ware id")
	asserts.equal(peaceful.ignored_reward_item_ids, ["bandage"], "non-core reward is ignored by core collection")
	asserts.equal(run_state.core_tea_ware_collection.collected_by_id.oribe_green_glazed_bowl.resolution_type, "peaceful", "peaceful reward context is preserved")
	var invalid := service.record_boss_resolution_rewards({"event_type": "boss_encounter_resolved", "resolution_type": "abort", "reward_item_ids": ["old_incense_box"]}, run_state)
	asserts.false_value(invalid.ok, "non-completion boss resolution cannot grant core tea ware")
	asserts.equal(invalid.reason, "invalid_resolution_type", "invalid boss resolution has stable reason")

func _assert_run_reset_and_meta_record_separation(asserts, service: CoreTeaWareCollection) -> void:
	var run_state := RunState.new()
	asserts.true_value(service.collect_core_tea_ware("oribe_green_glazed_bowl", run_state).ok, "collects core tea ware before run end")
	var meta_before := MetaState.new().to_dictionary()
	var meta_result := RunEndProcessor.new().apply_run_end(meta_before, run_state.to_dictionary())
	asserts.true_value(meta_result.discovered_records.has("core_tea_ware_oribe_green_glazed_bowl"), "meta 도감 keeps discovered core tea ware record")
	asserts.false_value(service.final_room_gate_query(RunState.new()).can_enter_final_room, "fresh run does not inherit physical core tea ware from meta records")
	run_state.reset_run_growth()
	asserts.false_value(service.final_room_gate_query(run_state).can_enter_final_room, "run growth reset clears physical core tea ware collection")
	asserts.equal(run_state.core_tea_ware_collection, {}, "reset removes collection state")

func _assert_save_round_trip(asserts, service: CoreTeaWareCollection) -> void:
	var run_state := RunState.new()
	asserts.true_value(service.collect_core_tea_ware("war_tea_caddy", run_state).ok, "collects before save")
	var decoded := SaveCodec.decode_run(SaveCodec.encode_run(run_state))
	asserts.true_value(decoded.ok, "core tea ware collection save decodes")
	asserts.equal(decoded.run_state.core_tea_ware_collection.collected_ids, ["war_tea_caddy"], "core tea ware collection survives run save round-trip")
	asserts.false_value(service.final_room_gate_query(decoded.run_state).can_enter_final_room, "partial saved collection keeps gate closed after resume")

func _assert_main_exposes_final_room_gate(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	var configured: Dictionary = main._configure_run_services(catalog)
	asserts.true_value(configured.ok, "main configures core tea ware collection service: %s" % configured.get("error", ""))
	asserts.false_value(main.final_room_gate_query().can_enter_final_room, "main final room gate starts closed")
	var reward := main.record_boss_core_tea_ware_rewards({
		"event_type": "boss_encounter_resolved",
		"resolution_type": "combat",
		"boss_id": "sample_ash_warden",
		"dungeon_id": "dungeon_1",
		"reward_item_ids": ["war_tea_caddy"]
	})
	asserts.true_value(reward.ok, "main records boss core tea ware reward")
	asserts.equal(main.final_room_gate_query().collected_ids, ["war_tea_caddy"], "main final gate query reflects recorded boss reward")
	main.free()

func _assert_main_wires_boss_dungeon_reward_transaction(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures services for dungeon reward bridge")
	var boss_id := "sample_bamboo_guardian"
	var boss_row: Dictionary = catalog.find_by_id("bosses", boss_id)
	var dungeon_row: Dictionary = catalog.find_by_id("dungeons", String(boss_row.dungeon_id))
	var progression := ProgressionBoundary.new(String(boss_row.biome_id))
	var configured: Dictionary = main.configure_dungeon_runtime(
		progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	)
	asserts.true_value(configured.ok, "main configures dungeon runtime with core tea ware reward hook")
	asserts.true_value(main.dungeon_runtime.enter_dungeon(
		"%s_instance" % boss_id,
		{"id": dungeon_row.id, "biome_id": boss_row.biome_id},
		WorldData.new(2, 2),
		{"biome_id": boss_row.biome_id, "world_seed": 3901}
	).ok, "main dungeon runtime enters boss dungeon")
	var boss := BossEncounterRuntime.new()
	asserts.true_value(boss.configure(
		BossDefinition.from_catalog(catalog, boss_id).definition,
		null,
		Callable(),
		func(event: Dictionary) -> Dictionary: return main.dungeon_runtime.complete_boss_encounter(event)
	).ok, "boss routes resolution through main-configured dungeon runtime")
	asserts.true_value(boss.start("%s_encounter" % boss_id, String(boss_row.dungeon_id)).ok, "boss starts in declared dungeon")
	asserts.true_value(boss.update_health(0).ok, "boss reaches combat victory")
	var resolved: Dictionary = boss.handle_resolution({"type": "victory"})
	asserts.true_value(resolved.ok, "boss resolution completes dungeon transaction")
	asserts.equal(main.final_room_gate_query().collected_ids, ["oribe_green_glazed_bowl", "unbroken_failure", "ash_stained_iron_kettle"], "boss/dungeon reward transaction records generated core tea ware rewards")
	asserts.equal(progression.completed, [String(boss_row.biome_id)], "core reward hook stays inside successful dungeon transaction")
	main.free()

func _assert_main_reward_hook_failure_is_atomic(asserts, catalog: DataCatalog) -> void:
	var main := Main.new()
	main.run_state = RunState.new()
	asserts.true_value(main._configure_run_services(catalog).ok, "main configures services for reward atomicity")
	var progression := ProgressionBoundary.new("common_region")
	var attempts := {"count": 0}
	var configured: Dictionary = main.configure_dungeon_runtime(
		progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)),
		func(_event: Dictionary):
			attempts.count += 1
			if attempts.count == 1:
				return false
			return {"ok": true}
	)
	asserts.true_value(configured.ok, "main configures composed reward hook")
	asserts.true_value(main.dungeon_runtime.enter_dungeon(
		"atomic_instance",
		{"id": "atomic_dungeon", "biome_id": "common_region"},
		WorldData.new(2, 2),
		{"biome_id": "common_region", "world_seed": 3902}
	).ok, "atomic fixture enters dungeon")
	var rejected: Dictionary = main.dungeon_runtime.complete_dungeon({
		"objective_complete": true,
		"resolution_type": "combat",
		"reward_item_ids": ["oribe_green_glazed_bowl"]
	})
	asserts.false_value(rejected.ok, "additional reward failure rejects dungeon completion")
	asserts.equal(main.final_room_gate_query().collected_ids, [], "failed additional hook does not mutate core tea ware collection")
	asserts.equal(progression.completed, [], "failed additional hook does not advance progression")
	var retried: Dictionary = main.dungeon_runtime.complete_dungeon({
		"objective_complete": true,
		"resolution_type": "combat",
		"reward_item_ids": ["oribe_green_glazed_bowl"]
	})
	asserts.true_value(retried.ok, "retry after external reward failure can still complete")
	asserts.equal(main.final_room_gate_query().collected_ids, ["oribe_green_glazed_bowl"], "retry records core tea ware once")
	main.free()

func _assert_definition_validation(asserts) -> void:
	var service := CoreTeaWareCollection.new()
	var duplicate := service.configure([
		{"id": "first_bowl", "core_tea_ware_order": 1},
		{"id": "second_bowl", "core_tea_ware_order": 1}
	])
	asserts.false_value(duplicate.ok, "duplicate required order is rejected")
	asserts.equal(duplicate.reason, "duplicate_core_tea_ware_order", "duplicate order has stable reason")
	var gap := service.configure([
		{"id": "first_bowl", "core_tea_ware_order": 1},
		{"id": "third_bowl", "core_tea_ware_order": 3}
	])
	asserts.false_value(gap.ok, "required order gaps are rejected")
	asserts.equal(gap.reason, "missing_core_tea_ware_order", "missing order has stable reason")
