extends RefCounted

const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunLifecycleService = preload("res://src/save/run_lifecycle_service.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const TEST_DIRECTORY := "user://dev24_run_lifecycle_tests"
const RUN_PATH := TEST_DIRECTORY + "/run.json"
const META_PATH := TEST_DIRECTORY + "/meta.json"

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-dev24"

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

func run(asserts) -> void:
	_cleanup()
	_assert_generated_catalog_exposes_dev24_canon(asserts)
	_cleanup()
	_assert_resurrection_consumes_one_item_and_continues_same_run(asserts)
	_cleanup()
	_assert_max_owned_resurrection_count_is_inventory_enforced(asserts)
	_cleanup()
	_assert_confirmed_death_invalidates_run_without_touching_meta(asserts)
	_cleanup()
	_assert_crash_retry_and_rollback_do_not_restore_dead_run(asserts)
	_cleanup()
	_assert_invalidation_high_water_survives_lower_epoch_and_restart(asserts)
	_cleanup()
	_assert_stale_invalidation_retry_preserves_newer_fresh_run(asserts)
	_cleanup()
	_assert_invalidation_failures_do_not_expose_fresh_run_and_retry(asserts)
	_cleanup()

func _assert_generated_catalog_exposes_dev24_canon(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads with DEV-24 data")
	asserts.equal(catalog.find_by_id("items", "item_29").effect_type, "부활", "ITM-29 runtime item keeps data-defined resurrection effect")
	asserts.equal(catalog.find_balance_value("balance_24"), 0.35, "BAL-24 revive HP ratio is exported")
	asserts.equal(catalog.find_balance_value("balance_25"), 2.0, "BAL-25 revive invulnerability is exported")
	asserts.equal(catalog.find_balance_value("balance_26"), 1.0, "BAL-26 max owned count is exported")

func _assert_resurrection_consumes_one_item_and_continues_same_run(asserts) -> void:
	var runtime := _fixture_runtime()
	var inventory: InventoryModel = runtime.inventory
	asserts.true_value(inventory.add_item("item_29", 1).ok, "resurrection item can be stocked")
	var resources: PlayerResources = _fixture_resources()
	var combat := CombatState.new(_fixture_combat_config())
	resources.apply_damage(resources.hp_max)

	var result: Dictionary = runtime.lifecycle.resolve_lethal_hp(resources, inventory, combat, "player")

	asserts.true_value(result.ok, "lethal HP resolves through lifecycle service")
	asserts.true_value(result.resurrected, "data-defined resurrection item prevents confirmed death")
	asserts.equal(result.item_id, "item_29", "resurrection resolves by stable item id")
	asserts.equal(inventory.get_total_quantity("item_29"), 0, "resurrection consumes exactly one item")
	asserts.equal(resources.hp, 35, "revive HP uses BAL-24 ratio")
	asserts.true_value(combat.is_hit_invulnerable("player"), "revive applies BAL-25 invulnerability")
	combat.tick(1.99)
	asserts.true_value(combat.is_hit_invulnerable("player"), "revive invulnerability keeps its data-defined duration")
	combat.tick(0.02)
	asserts.false_value(combat.is_hit_invulnerable("player"), "revive invulnerability expires after BAL-25")
	asserts.false_value(runtime.lifecycle.death_pending, "resurrection clears death pending")
	asserts.false_value(runtime.lifecycle.death_confirmed, "resurrection does not confirm death")

func _assert_max_owned_resurrection_count_is_inventory_enforced(asserts) -> void:
	var runtime := _fixture_runtime()
	var inventory: InventoryModel = runtime.inventory
	asserts.true_value(inventory.add_item("item_29", 1).ok, "first resurrection item is accepted")
	var second: Dictionary = inventory.add_item("item_29", 1)
	asserts.false_value(second.ok, "second resurrection item is rejected")
	asserts.equal(second.reason, "max_owned_exceeded", "max owned failure has stable reason")
	asserts.equal(inventory.get_total_quantity("item_29"), 1, "failed max-owned add is atomic")

func _assert_confirmed_death_invalidates_run_without_touching_meta(asserts) -> void:
	var runtime := _fixture_runtime()
	var resources: PlayerResources = _fixture_resources()
	resources.apply_damage(resources.hp_max)
	var pending: Dictionary = runtime.lifecycle.resolve_lethal_hp(resources, runtime.inventory)
	asserts.true_value(pending.ok, "lethal HP without item enters lifecycle")
	asserts.equal(pending.state, "death_pending", "absence of resurrection item creates death pending")

	var store := SaveStore.new(RUN_PATH, META_PATH)
	var run_state := _run_state(7, 0)
	var meta_state := _meta_state()
	asserts.true_value(store.save_run(run_state).ok, "old run save is present before death confirmation")
	asserts.true_value(store.save_meta(meta_state).ok, "meta save is present before death confirmation")
	var meta_before := FileAccess.get_file_as_string(META_PATH)

	var confirmed: Dictionary = runtime.lifecycle.confirm_death(store, run_state)

	asserts.true_value(confirmed.ok, "pending death can be confirmed")
	asserts.true_value(confirmed.death_confirmed, "death confirmed is separate lifecycle state")
	asserts.false_value(FileAccess.file_exists(RUN_PATH), "confirmed death removes old run save")
	asserts.true_value(FileAccess.file_exists(RUN_PATH + ".invalidated.json"), "confirmed death writes a run invalidation marker")
	asserts.equal(FileAccess.get_file_as_string(META_PATH), meta_before, "confirmed death preserves meta save bytes")
	asserts.equal(store.load_meta().state.discovered_records, meta_state.discovered_records, "meta discovered records remain logically unchanged")
	asserts.equal(store.load_meta().state.unlocked_meta_flags, meta_state.unlocked_meta_flags, "meta unlock flags remain logically unchanged")

func _assert_crash_retry_and_rollback_do_not_restore_dead_run(asserts) -> void:
	var runtime := _fixture_runtime()
	var store := SaveStore.new(RUN_PATH, META_PATH)
	var old_run := _run_state(31, 0)
	asserts.true_value(store.save_run(old_run).ok, "pre-death run save writes")
	var old_run_bytes := FileAccess.get_file_as_string(RUN_PATH)
	runtime.lifecycle.death_pending = true
	var confirmed: Dictionary = runtime.lifecycle.confirm_death(store, old_run)
	asserts.true_value(confirmed.ok, "death confirmation invalidates old epoch")
	asserts.false_value(SaveStore.new(RUN_PATH, META_PATH).load_run().ok, "process restart after invalidation cannot resume a dead run")

	_write_text(RUN_PATH, old_run_bytes)
	var rollback: Dictionary = SaveStore.new(RUN_PATH, META_PATH).load_run()
	asserts.false_value(rollback.ok, "restored pre-death run save is rejected")
	asserts.equal(rollback.reason, "stale_run_save", "rollback rejection uses lifecycle epoch high-water mark")

	var fresh_run: RunState = runtime.lifecycle.create_fresh_run_after_confirmed_death(confirmed.invalidated_lifecycle_epoch, 99)
	asserts.true_value(store.save_run(fresh_run).ok, "fresh run with newer lifecycle epoch can be persisted")
	var loaded_fresh := SaveStore.new(RUN_PATH, META_PATH).load_run()
	asserts.true_value(loaded_fresh.ok, "fresh run resumes after confirmed death")
	asserts.equal(loaded_fresh.state.seed, 99, "fresh run seed replaces the discarded run")
	asserts.equal(loaded_fresh.state.lifecycle_epoch, 1, "fresh run advances lifecycle epoch")
	_write_text(RUN_PATH, old_run_bytes)
	asserts.false_value(SaveStore.new(RUN_PATH, META_PATH).load_run().ok, "older pre-death save remains rejected after fresh run exists")

func _assert_invalidation_high_water_survives_lower_epoch_and_restart(asserts) -> void:
	var store := SaveStore.new(RUN_PATH, META_PATH)
	var high_run := _run_state(51, 5)
	asserts.true_value(store.save_run(high_run).ok, "high epoch run is persisted before invalidation")
	asserts.true_value(store.invalidate_run(high_run).ok, "high epoch invalidation succeeds")

	var restarted := SaveStore.new(RUN_PATH, META_PATH)
	var lower: Dictionary = restarted.invalidate_run(_run_state(52, 1))
	asserts.true_value(lower.ok, "lower epoch invalidation retry is idempotent")
	asserts.equal(lower.invalidated_lifecycle_epoch, 5, "lower retry preserves invalidation high-water")
	_write_text(RUN_PATH, JSON.stringify(SaveCodec.encode_run(_run_state(53, 3))))
	var rollback := SaveStore.new(RUN_PATH, META_PATH).load_run()
	asserts.false_value(rollback.ok, "restart still rejects epoch below preserved high-water")
	asserts.equal(rollback.reason, "stale_run_save", "preserved high-water rejects restored stale bytes")

func _assert_stale_invalidation_retry_preserves_newer_fresh_run(asserts) -> void:
	var old_run := _run_state(54, 0)
	var initial_store := SaveStore.new(RUN_PATH, META_PATH)
	asserts.true_value(initial_store.save_run(old_run).ok, "old epoch is persisted before confirmed invalidation")
	var invalidated: Dictionary = initial_store.invalidate_run(old_run)
	asserts.true_value(invalidated.ok, "old epoch invalidation succeeds")
	var fresh_run := _run_state(55, 1)
	asserts.true_value(initial_store.save_run(fresh_run).ok, "newer fresh epoch becomes resumable")

	var restarted_retry_store := SaveStore.new(RUN_PATH, META_PATH)
	var stale_retry: Dictionary = restarted_retry_store.invalidate_run(old_run)
	asserts.true_value(stale_retry.ok, "stale invalidation retry is an idempotent success")
	asserts.equal(stale_retry.get("state", ""), "stale_invalidation_ignored", "stale retry reports that the newer run was preserved")
	asserts.true_value(bool(stale_retry.get("preserved_newer_run", false)), "stale retry explicitly preserves the newer on-disk run")
	asserts.false_value(bool(stale_retry.get("run_removed", true)), "stale retry reports that no run file was removed")
	asserts.equal(int(stale_retry.get("current_lifecycle_epoch", -1)), 1, "stale retry reports the preserved fresh epoch")

	var runtime := _fixture_runtime()
	runtime.lifecycle.death_pending = true
	var propagated: Dictionary = runtime.lifecycle.confirm_death(SaveStore.new(RUN_PATH, META_PATH), old_run)
	asserts.true_value(propagated.ok, "lifecycle accepts preserved newer run as idempotent success")
	asserts.equal(propagated.get("state", ""), "newer_run_preserved", "lifecycle propagates preserved-run state")
	asserts.true_value(bool(propagated.get("preserved_newer_run", false)), "lifecycle propagates preserved-run identity")
	asserts.equal(int(propagated.get("current_lifecycle_epoch", -1)), 1, "lifecycle propagates current persisted epoch")
	var propagated_run = propagated.get("current_run_state")
	asserts.true_value(propagated_run is RunState, "lifecycle propagates hydrated current RunState")
	if propagated_run is RunState:
		asserts.equal(propagated_run.seed, 55, "lifecycle propagates exact persisted run payload")
	asserts.false_value(runtime.lifecycle.death_confirmed, "stale death retry does not confirm another death")

	var restarted_loader := SaveStore.new(RUN_PATH, META_PATH)
	var loaded_fresh: Dictionary = restarted_loader.load_run()
	asserts.true_value(loaded_fresh.ok, "process restart still loads the newer fresh run after stale retry")
	if loaded_fresh.ok:
		asserts.equal(loaded_fresh.state.lifecycle_epoch, 1, "stale retry does not delete fresh lifecycle epoch")
		asserts.equal(loaded_fresh.state.seed, 55, "stale retry preserves the exact fresh run payload")

func _assert_invalidation_failures_do_not_expose_fresh_run_and_retry(asserts) -> void:
	var old_run := _run_state(61, 0)
	var baseline_store := SaveStore.new(RUN_PATH, META_PATH)
	asserts.true_value(baseline_store.save_run(old_run).ok, "failure fixture persists the old run")
	var injector := SaveFailureInjector.new(RUN_PATH)
	var failing_store := SaveStore.new(RUN_PATH, META_PATH, injector.replace, injector.remove)
	var runtime := _fixture_runtime()
	runtime.lifecycle.death_pending = true

	injector.fail_marker_replace = true
	var marker_failure: Dictionary = runtime.lifecycle.confirm_death(failing_store, old_run)
	asserts.false_value(marker_failure.ok, "marker replacement failure aborts death confirmation")
	asserts.false_value(runtime.lifecycle.death_confirmed, "failed marker replacement exposes no confirmed/fresh lifecycle")
	asserts.equal(SaveStore.new(RUN_PATH, META_PATH).load_run().state.seed, 61, "failed marker replacement leaves old run resumable")
	injector.fail_marker_replace = false
	var marker_retry: Dictionary = runtime.lifecycle.confirm_death(failing_store, old_run)
	asserts.true_value(marker_retry.ok, "marker replacement retry succeeds safely")

	_cleanup()
	old_run = _run_state(62, 0)
	asserts.true_value(baseline_store.save_run(old_run).ok, "remove failure fixture persists the old run")
	runtime = _fixture_runtime()
	runtime.lifecycle.death_pending = true
	injector.fail_run_remove = true
	var remove_failure: Dictionary = runtime.lifecycle.confirm_death(failing_store, old_run)
	asserts.false_value(remove_failure.ok, "old run removal failure aborts death confirmation")
	asserts.false_value(runtime.lifecycle.death_confirmed, "failed old run removal exposes no confirmed/fresh lifecycle")
	asserts.equal(SaveStore.new(RUN_PATH, META_PATH).load_run().reason, "stale_run_save", "written marker rejects old bytes after remove failure")
	injector.fail_run_remove = false
	var remove_retry: Dictionary = runtime.lifecycle.confirm_death(failing_store, old_run)
	asserts.true_value(remove_retry.ok, "old run removal retry succeeds safely")
	var fresh: RunState = runtime.lifecycle.create_fresh_run_after_confirmed_death(remove_retry.invalidated_lifecycle_epoch, 63)
	asserts.true_value(failing_store.save_run(fresh).ok, "fresh run is persisted only after successful invalidation retry")
	var restarted_fresh := SaveStore.new(RUN_PATH, META_PATH).load_run()
	asserts.true_value(restarted_fresh.ok, "restart loads the fresh run after confirmed death")
	asserts.equal(restarted_fresh.state.seed, 63, "restart exposes only the fresh run")

class SaveFailureInjector:
	extends RefCounted
	var run_save_path: String
	var fail_marker_replace := false
	var fail_run_remove := false

	func _init(path: String) -> void:
		run_save_path = path

	func replace(from_path: String, to_path: String) -> int:
		if fail_marker_replace and to_path.ends_with(".invalidated.json"):
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))

	func remove(path: String) -> int:
		if fail_run_remove and path == run_save_path:
			return ERR_CANT_CREATE
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fixture_runtime() -> Dictionary:
	var catalog := _fixture_catalog()
	var lifecycle_result: Dictionary = RunLifecycleService.from_catalog(catalog)
	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	return {"lifecycle": lifecycle_result.run_lifecycle_service, "inventory": inventory_result.inventory}

func _fixture_catalog() -> FakeCatalog:
	return FakeCatalog.new({
		"balance": [
			{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 2},
			{"id": "balance_24", "name": "부활 HP 회복 비율", "status": "확정", "value": 0.35},
			{"id": "balance_25", "name": "부활 직후 무적시간", "status": "확정", "value": 2.0},
			{"id": "balance_26", "name": "부활 아이템 최대 보유 수", "status": "확정", "value": 1}
		],
		"items": [
			{"id": "item_29", "name": "부활 차씨", "status": "확정", "type": "소모품", "effect_type": "부활", "max_stack": 1, "max_owned": 1},
			{"id": "wood", "name": "목재", "status": "확정", "type": "재료", "max_stack": 10}
		],
		"teas": []
	})

func _fixture_resources() -> PlayerResources:
	return PlayerResources.new(100, 100, 100, 30)

func _fixture_combat_config() -> CombatConfig:
	return CombatConfig.new({
		"basic_attack_combo_hits": 1,
		"finisher_knockback_tiles": 0.0,
		"dodge_cooldown_seconds": 0.0,
		"dodge_distance_tiles": 1.0,
		"dodge_invulnerability_seconds": 0.0,
		"ki_attack_multiplier_0": 1.0,
		"ki_attack_multiplier_100": 1.0,
		"ki_max": 100.0,
		"hit_invulnerability_seconds": 0.0,
		"weapon_id": "fixture_weapon",
		"weapon_base_damage": 1,
		"weapon_range_tiles": 1.0,
		"weapon_attack_speed": 1.0
	})

func _run_state(seed: int, lifecycle_epoch: int) -> RunState:
	var state := RunState.new()
	state.seed = seed
	state.lifecycle_epoch = lifecycle_epoch
	state.data_version = "fixture-dev24"
	return state

func _meta_state() -> MetaState:
	var state := MetaState.new()
	state.run_count = 4
	state.best_reached_biome_order = 2
	state.discovered_records = ["oribe_bowl"]
	state.unlocked_meta_flags = ["sen_rikyu_reunion_dialogue_1"]
	state.dialogue_memory_flags = ["father_remembers_previous_run"]
	state.meta_unlock_counters = {"choice:fixture": 1}
	return state

func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", RUN_PATH + ".invalidated.json", RUN_PATH + ".invalidated.json.tmp", META_PATH, META_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
