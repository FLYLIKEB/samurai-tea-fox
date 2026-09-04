extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const Main = preload("res://src/main/main.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const MonsterSpawnPoolResolver = preload("res://src/world/generation/monster_spawn_pool_resolver.gd")
const PlayerController = preload("res://src/player/player_controller.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const RUN_PATH := "user://dev72_spawn_pool_run.save.json"
const META_PATH := "user://dev72_spawn_pool_meta.save.json"

func _init() -> void:
	_cleanup()
	var asserts := TestAssert.new()
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "generated data loads for DEV-72 spawn pool")
	if loaded.ok:
		_assert_spawn_pool_filters(asserts, catalog)
		_assert_world_generation_connects_spawn_pool(asserts, catalog)
		_assert_spawn_factory_accepts_pool_variant(asserts)
		_assert_main_runtime_consumes_spawn_pool(asserts, catalog)
		_assert_main_runtime_falls_back_when_pool_is_empty(asserts, catalog)
		_assert_generated_monster_day_night_validation(asserts)
	if asserts.ok():
		print("All tests passed: DEV-72 monster spawn pool")
		_cleanup()
		quit(0)
		return
	for failure in asserts.failures:
		push_error(failure)
	_cleanup()
	quit(1)

func _assert_spawn_pool_filters(asserts, catalog: DataCatalog) -> void:
	var resolver := MonsterSpawnPoolResolver.new()
	var biome: Dictionary = catalog.find_by_id("biomes", "common_region")
	var monsters := catalog.get_definitions("monsters")
	var day := resolver.resolve(biome, monsters, "day", 42117, catalog.data_version)
	var night := resolver.resolve(biome, monsters, "night", 42117, catalog.data_version)
	var repeated := resolver.resolve(biome, monsters, "night", 42117, catalog.data_version)
	var late_night := resolver.resolve(biome, monsters, "late_night", 42117, catalog.data_version)

	asserts.equal(day.time_bucket, "day", "day phase resolves to day spawn bucket")
	asserts.equal(night.time_bucket, "night", "night phase resolves to night spawn bucket")
	asserts.equal(late_night.time_bucket, "night", "late night uses the night spawn bucket")
	asserts.false_value(day.candidate_ids.has("foxfire"), "day pool excludes night-only monster rows")
	asserts.true_value(night.candidate_ids.has("foxfire"), "night pool includes night-only monster rows from DB")
	asserts.equal(night, repeated, "same seed, biome, data version, and time produce the same spawn pool")
	asserts.true_value(day != night, "same biome has different day and night monster pools")
	asserts.true_value(night.rare_variant.get("rare", false), "night pool exposes one rare pattern variant")
	asserts.equal(night.rare_variant.get("behavior_type_override", ""), "희귀", "rare night variant reuses the existing rare behavior pattern")
	asserts.true_value(night.spawnable_ids.has(night.rare_variant.get("id", "")), "rare variant is spawnable through pool metadata")
	asserts.true_value(_skipped_ids(night).has("foxfire"), "night-only rows without runtime stats are tracked as skipped, not spawned")

	for biome_definition in catalog.get_definitions("biomes"):
		if String(biome_definition.get("type", "")) != "바이옴":
			continue
		var day_pool := resolver.resolve(biome_definition, monsters, "day", 42117, catalog.data_version)
		var night_pool := resolver.resolve(biome_definition, monsters, "night", 42117, catalog.data_version)
		asserts.true_value(day_pool.candidate_ids.size() > 0, "%s has day monster candidates from generated data" % biome_definition.id)
		asserts.true_value(night_pool.candidate_ids.size() > 0, "%s has night monster candidates from generated data" % biome_definition.id)

func _assert_world_generation_connects_spawn_pool(asserts, catalog: DataCatalog) -> void:
	var generator := WorldGenerator.new()
	var biome: Dictionary = catalog.find_by_id("biomes", "common_region")
	var options := {
		"monster_definitions": catalog.get_definitions("monsters"),
		"time_phase": "night"
	}
	var generated := generator.generate(42117, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	var repeated := generator.generate(42117, catalog.data_version, biome, catalog.get_definitions("balance"), catalog.get_definitions("items"), options)
	asserts.true_value(generated.ok, "world generation succeeds with monster spawn pool context")
	asserts.true_value(repeated.ok, "repeated world generation succeeds with monster spawn pool context")
	if generated.ok and repeated.ok:
		asserts.equal(generated.monster_spawn_pool, repeated.monster_spawn_pool, "world stores deterministic spawn pool for same seed and time")
		asserts.equal(generated.monster_spawn_pool.time_bucket, "night", "world records night spawn bucket")

func _assert_spawn_factory_accepts_pool_variant(asserts) -> void:
	var catalog := FakeCatalog.new([
		{
			"id": "road_bandit",
			"name": "road_bandit",
			"status": "테스트",
			"kind": "도적·무사",
			"hp": 70,
			"stagger_resistance": 0.2,
			"movement_speed": 1.6,
			"attack": 10,
			"attack_period_seconds": 1.8,
			"behavior_type": "근접"
		}
	])
	var spawned: Dictionary = MonsterSpawnFactory.new(catalog).spawn("road_bandit", {
		"combat_id": "road_bandit_rare",
		"behavior_type_override": "희귀"
	})
	asserts.true_value(spawned.ok, "spawn factory accepts a data-driven rare behavior variant")
	if spawned.ok:
		asserts.equal(spawned.monster.definition_id, "road_bandit", "rare variant keeps the base monster definition id")
		asserts.equal(spawned.behavior.behavior_type, "희귀", "rare variant uses the rare behavior strategy")

func _assert_main_runtime_consumes_spawn_pool(asserts, catalog: DataCatalog) -> void:
	var day_runtime := _configured_main_runtime(catalog, "day", 42117)
	var night_runtime := _configured_main_runtime(catalog, "night", 42117)
	asserts.true_value(day_runtime.result.ok, "day overworld runtime configures from generated spawn pool")
	asserts.true_value(night_runtime.result.ok, "night overworld runtime configures from generated spawn pool")
	if day_runtime.result.ok and night_runtime.result.ok:
		var day_active: Dictionary = day_runtime.main.generated_world.get("active_monster_spawn", {})
		var night_active: Dictionary = night_runtime.main.generated_world.get("active_monster_spawn", {})
		var day_entry: Dictionary = day_active.get("entry", {})
		var night_entry: Dictionary = night_active.get("entry", {})
		asserts.equal(day_active.get("source", ""), "monster_spawn_pool", "day runtime uses the generated spawn pool instead of fixed fallback")
		asserts.equal(night_active.get("source", ""), "monster_spawn_pool", "night runtime uses the generated spawn pool instead of fixed fallback")
		asserts.equal(day_runtime.main.combat_dummy.monster_id, day_entry.get("monster_id", ""), "day dummy monster id matches selected pool entry")
		asserts.equal(day_runtime.main.combat_dummy.combatant.definition_id, day_entry.get("monster_id", ""), "day combatant comes from selected pool entry")
		asserts.equal(day_runtime.main.combat_dummy.combatant.behavior_type, day_entry.get("behavior_type", ""), "day combatant behavior matches pool entry")
		asserts.equal(night_runtime.main.combat_dummy.monster_id, night_entry.get("monster_id", ""), "night dummy monster id matches selected pool entry")
		asserts.equal(night_runtime.main.combat_dummy.combatant.definition_id, night_entry.get("monster_id", ""), "night combatant comes from selected pool entry")
		asserts.equal(night_runtime.main.combat_dummy.combatant.behavior_type, night_entry.get("behavior_type_override", night_entry.get("behavior_type", "")), "night combatant consumes pool behavior override")
		asserts.true_value(bool(night_entry.get("rare", false)), "night runtime selects the rare variant from the generated pool")
		asserts.equal(night_runtime.main.combat_dummy.combatant.behavior_type, "희귀", "night rare variant reaches MonsterSpawnFactory and combat state")
		var repeated_night := _configured_main_runtime(catalog, "night", 42117)
		asserts.true_value(repeated_night.result.ok, "repeated night overworld runtime configures")
		if repeated_night.result.ok:
			asserts.equal(repeated_night.main.generated_world.active_monster_spawn, night_active, "same seed and night phase produce the same active runtime spawn")
		_free_runtime(repeated_night)
	_free_runtime(day_runtime)
	_free_runtime(night_runtime)

func _assert_main_runtime_falls_back_when_pool_is_empty(asserts, catalog: DataCatalog) -> void:
	var runtime := _configured_main_services(catalog, "day", 42117)
	asserts.true_value(runtime.result.ok, "fallback fixture services configure")
	if runtime.result.ok:
		var combat: Dictionary = runtime.main._configure_combat_lifecycle()
		asserts.true_value(combat.ok, "fallback fixture combat lifecycle configures")
		runtime.main.generated_world = {
			"ok": true,
			"monster_spawn_pool": {"entries": []}
		}
		var configured: Dictionary = runtime.main._configure_overworld_combat_from_spawn_pool()
		asserts.true_value(configured.ok, "empty spawn pool falls back to the fixed road bandit")
		asserts.equal(configured.get("source", ""), "fallback", "fallback is explicit when pool is empty")
		asserts.equal(runtime.main.combat_dummy.monster_id, "road_bandit", "empty pool fallback uses road_bandit")
		asserts.equal(runtime.main.combat_dummy.combatant.definition_id, "road_bandit", "fallback combatant is spawned through MonsterSpawnFactory")
	_free_runtime(runtime)

func _assert_generated_monster_day_night_validation(asserts) -> void:
	var validator := DataSchemaValidator.new()
	var invalid := validator.validate_catalog({
		"monsters": [{"id": "broken_spawn_window", "name": "broken", "status": "테스트", "day_night": "비 오는 밤"}]
	}, {
		"monsters": {"required_fields": ["id", "name", "status", "day_night"]}
	})
	asserts.false_value(invalid.ok, "monster day/night spawn windows are validated from generated data")
	if not invalid.ok:
		asserts.true_value("day_night" in invalid.error, "invalid monster day/night error names the field")

func _skipped_ids(pool: Dictionary) -> Dictionary:
	var ids := {}
	for row in pool.get("skipped_ids", []):
		ids[String(row.get("id", ""))] = true
	return ids

func _configured_main_runtime(catalog: DataCatalog, phase: String, seed: int) -> Dictionary:
	var runtime := _configured_main_services(catalog, phase, seed)
	if not runtime.result.ok:
		return runtime
	var combat: Dictionary = runtime.main._configure_combat_lifecycle()
	if not combat.ok:
		runtime.result = combat
		return runtime
	var world: Dictionary = runtime.main._configure_world_for_current_run()
	runtime.result = world
	return runtime

func _configured_main_services(catalog: DataCatalog, phase: String, seed: int) -> Dictionary:
	var main := Main.new()
	var player := PlayerController.new()
	var dummy := CombatDummy.new()
	var world_root := Node2D.new()
	var hud := GameHud.new()
	dummy.automatic_attacks = false
	main.catalog = catalog
	main.player = player
	main.combat_dummy = dummy
	main.world_visuals = world_root
	main.game_hud = hud
	main.save_store = SaveStore.new(RUN_PATH, META_PATH)
	main.run_state = RunState.new()
	main.run_state.seed = seed
	main.run_state.data_version = catalog.data_version
	var services: Dictionary = main._configure_run_services(catalog)
	if not services.ok:
		return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": services}
	if phase != "day":
		var snapshot: Dictionary = main.time_state.to_snapshot()
		snapshot["phase"] = phase
		snapshot["phase_elapsed_seconds"] = 0.0
		var loaded_phase: Dictionary = main.time_state.load_snapshot(snapshot)
		if not loaded_phase.ok:
			return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": loaded_phase}
	return {"main": main, "player": player, "dummy": dummy, "world_root": world_root, "hud": hud, "result": {"ok": true}}

func _free_runtime(runtime: Dictionary) -> void:
	for key in ["main", "player", "dummy", "world_root", "hud"]:
		var node = runtime.get(key, null)
		if node != null and is_instance_valid(node):
			node.free()

func _cleanup() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", META_PATH, META_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

class FakeCatalog:
	extends RefCounted
	var monsters: Array

	func _init(initial_monsters: Array) -> void:
		monsters = initial_monsters

	func find_by_id(dataset: String, id: String) -> Dictionary:
		if dataset != "monsters":
			return {}
		for monster in monsters:
			if String(monster.get("id", "")) == id:
				return monster
		return {}
