extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_generated_catalog_loads_time_values(asserts)
	_assert_phase_machine_and_kokoro_decay(asserts)
	_assert_low_kokoro_ability_cost_multiplier(asserts)
	_assert_sleep_resets_morning_fills_kokoro_and_heals_ratio(asserts)
	_assert_invalid_time_balance_data(asserts)

func _assert_generated_catalog_loads_time_values(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads")
	var config_result: Dictionary = TimeConfig.from_catalog(catalog)
	asserts.true_value(config_result.ok, "time config initializes from generated catalog")
	if not config_result.ok:
		return
	var config: TimeConfig = config_result.config
	asserts.equal(config.day_phase_duration_seconds, 300.0, "day duration comes from balance data")
	asserts.equal(config.dusk_phase_duration_seconds, 120.0, "dusk duration comes from balance data")
	asserts.equal(config.night_phase_duration_seconds, 240.0, "night duration comes from balance data")
	asserts.equal(config.late_night_phase_duration_seconds, 180.0, "late-night duration comes from balance data")
	asserts.equal(config.dusk_kokoro_decay_per_second, 0.02, "dusk kokoro decay comes from balance data")
	asserts.equal(config.night_kokoro_decay_per_second, 0.05, "night kokoro decay comes from balance data")
	asserts.equal(config.late_night_kokoro_decay_per_second, 0.1, "late-night kokoro decay comes from balance data")
	asserts.equal(config.sleep_heal_ratio, 0.2, "sleep HP heal ratio comes from balance data")

func _assert_phase_machine_and_kokoro_decay(asserts) -> void:
	var resources := _test_resources()
	var time := TimeState.new(_test_config())
	var phase_changes: Array = []
	time.phase_changed.connect(func(previous, current): phase_changes.append([previous, current]))

	time.tick(299.0, resources)
	asserts.equal(time.phase, TimeState.DAY, "day phase remains active before duration elapses")
	asserts.equal(resources.kokoro, 100, "daytime does not decay kokoro")
	time.tick(1.0, resources)
	asserts.equal(time.phase, TimeState.DUSK, "day advances to dusk")
	asserts.equal(resources.kokoro, 100, "phase boundary into dusk does not apply daytime decay")

	time.tick(50.0, resources)
	asserts.equal(resources.kokoro, 99, "dusk applies fractional kokoro decay over time")
	time.tick(70.0, resources)
	asserts.equal(time.phase, TimeState.NIGHT, "dusk advances to night")
	asserts.equal(resources.kokoro, 98, "remaining dusk duration applies configured decay")
	time.tick(240.0, resources)
	asserts.equal(time.phase, TimeState.LATE_NIGHT, "night advances to late night")
	asserts.equal(resources.kokoro, 86, "night applies configured kokoro decay")
	time.tick(180.0, resources)
	asserts.equal(time.phase, TimeState.DAY, "late night advances back to day")
	asserts.equal(resources.kokoro, 68, "late night applies configured kokoro decay")
	time.tick(300.0, resources)
	asserts.equal(resources.kokoro, 68, "next day still has no kokoro decay")
	asserts.equal(phase_changes.size(), 5, "phase transitions are observable")

func _assert_low_kokoro_ability_cost_multiplier(asserts) -> void:
	var resources := _test_resources()
	var time := TimeState.new(_test_config())
	asserts.equal(time.ability_cost_multiplier_for(resources), 1.0, "normal kokoro keeps ability cost unchanged")
	resources.reduce_kokoro(70)
	asserts.equal(resources.kokoro, 30, "test resource reaches low-kokoro threshold")
	asserts.equal(time.ability_cost_multiplier_for(resources), 1.25, "low kokoro applies configured ability cost multiplier")

func _assert_sleep_resets_morning_fills_kokoro_and_heals_ratio(asserts) -> void:
	var resources := _test_resources()
	var time := TimeState.new(_test_config())
	resources.apply_damage(30)
	resources.reduce_kokoro(40)
	time.tick(300.0 + 120.0 + 1.0, resources)
	asserts.equal(time.phase, TimeState.NIGHT, "sleep test starts away from morning")

	var result: Dictionary = time.sleep_until_morning(resources)
	asserts.equal(result.phase, TimeState.DAY, "sleep returns to morning day phase")
	asserts.equal(resources.kokoro, 100, "sleep fills kokoro")
	asserts.equal(resources.hp, 90, "sleep heals 20 percent of max HP")
	asserts.equal(result.hp_healed, 20, "sleep reports applied HP healing")

	resources.heal_hp(100)
	resources.apply_damage(5)
	var clamped: Dictionary = time.sleep_until_morning(resources)
	asserts.equal(resources.hp, 100, "sleep healing clamps to HP maximum")
	asserts.equal(clamped.hp_healed, 5, "sleep reports clamped HP healing")

func _assert_invalid_time_balance_data(asserts) -> void:
	var missing := _balance_values()
	missing.pop_back()
	var missing_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": missing}))
	asserts.false_value(missing_result.ok, "missing time balance values are rejected")
	asserts.true_value("safe_sleep_hp_recovery_ratio" in missing_result.error, "missing balance error names the stable ID")

	var invalid_duration := _balance_values()
	invalid_duration[0]["value"] = 0
	var duration_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": invalid_duration}))
	asserts.false_value(duration_result.ok, "non-positive durations are rejected")

	var invalid_decay := _balance_values()
	invalid_decay[4]["value"] = -0.1
	var decay_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": invalid_decay}))
	asserts.false_value(decay_result.ok, "negative decay is rejected")

	var zero_dusk_decay := _balance_values()
	zero_dusk_decay[4]["value"] = 0.0
	var zero_dusk_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": zero_dusk_decay}))
	asserts.false_value(zero_dusk_result.ok, "zero dusk decay is rejected")

	var equal_decay := _balance_values()
	equal_decay[5]["value"] = 0.02
	var equal_decay_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": equal_decay}))
	asserts.false_value(equal_decay_result.ok, "equal decay rates are rejected")

	var decreasing_decay := _balance_values()
	decreasing_decay[5]["value"] = 0.09
	decreasing_decay[6]["value"] = 0.08
	var decreasing_decay_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": decreasing_decay}))
	asserts.false_value(decreasing_decay_result.ok, "decreasing decay rates are rejected")

	var invalid_ratio := _balance_values()
	invalid_ratio[8]["value"] = 1.1
	var ratio_result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": invalid_ratio}))
	asserts.false_value(ratio_result.ok, "sleep heal ratio above one is rejected")

func _test_config() -> TimeConfig:
	var result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({"balance": _balance_values()}))
	return result.config

func _test_resources() -> PlayerResources:
	return PlayerResources.new(100, 100, 100, 30)

func _balance_values() -> Array:
	return [
		{"id": "day_phase_duration_seconds", "value": 300},
		{"id": "dusk_phase_duration_seconds", "value": 120},
		{"id": "night_phase_duration_seconds", "value": 240},
		{"id": "late_night_phase_duration_seconds", "value": 180},
		{"id": "dusk_kokoro_decay_per_second", "value": 0.02},
		{"id": "night_kokoro_decay_per_second", "value": 0.05},
		{"id": "late_night_kokoro_decay_per_second", "value": 0.1},
		{"id": "low_kokoro_ability_cost_increase", "value": 25},
		{"id": "safe_sleep_hp_recovery_ratio", "value": 0.2}
	]
