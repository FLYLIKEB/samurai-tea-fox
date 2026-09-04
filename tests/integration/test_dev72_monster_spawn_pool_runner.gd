extends SceneTree

const TestAssert = preload("res://tests/support/test_assert.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DataSchemaValidator = preload("res://src/core/data/data_schema_validator.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const MonsterSpawnPoolResolver = preload("res://src/world/generation/monster_spawn_pool_resolver.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func _init() -> void:
	var asserts := TestAssert.new()
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "generated data loads for DEV-72 spawn pool")
	if loaded.ok:
		_assert_spawn_pool_filters(asserts, catalog)
		_assert_world_generation_connects_spawn_pool(asserts, catalog)
		_assert_spawn_factory_accepts_pool_variant(asserts)
		_assert_generated_monster_day_night_validation(asserts)
	if asserts.ok():
		print("All tests passed: DEV-72 monster spawn pool")
		quit(0)
		return
	for failure in asserts.failures:
		push_error(failure)
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
