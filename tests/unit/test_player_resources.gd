extends RefCounted

const PlayerResources = preload("res://src/player/player_resources.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")

class FakeCatalog:
	extends RefCounted
	var values: Dictionary

	func _init(initial_values: Dictionary) -> void:
		values = initial_values

	func find_by_id(_dataset: String, id: String) -> Dictionary:
		if not values.has(id):
			return {}
		return {"id": id, "value": values[id]}

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated balance snapshot loads")
	var factory_result: Dictionary = PlayerResources.from_catalog(catalog)
	asserts.true_value(factory_result.ok, "player resources initialize from balance snapshot")
	if not factory_result.ok:
		return
	var resources = factory_result.resources
	asserts.equal(resources.hp_max, 100, "HP maximum comes from balance data")
	asserts.equal(resources.ki_max, 100, "ki maximum comes from balance data")
	asserts.equal(resources.kokoro_max, 100, "kokoro maximum comes from balance data")
	asserts.equal(resources.kokoro_low_threshold, 30, "kokoro threshold comes from balance data")
	_assert_invalid_balance_data(asserts)

	var hp_changes: Array = []
	var hp_depleted_count := [0]
	var ki_changes: Array = []
	var ki_depleted_count := [0]
	var kokoro_changes: Array = []
	var kokoro_depleted_count := [0]
	resources.hp_changed.connect(func(previous, current, maximum): hp_changes.append([previous, current, maximum]))
	resources.hp_depleted.connect(func(): hp_depleted_count[0] += 1)
	resources.ki_changed.connect(func(previous, current, maximum): ki_changes.append([previous, current, maximum]))
	resources.ki_depleted.connect(func(): ki_depleted_count[0] += 1)
	resources.kokoro_changed.connect(func(previous, current, maximum): kokoro_changes.append([previous, current, maximum]))
	resources.kokoro_depleted.connect(func(): kokoro_depleted_count[0] += 1)
	asserts.equal(resources.apply_damage(25), 25, "damage reports the applied amount")
	asserts.equal(resources.hp, 75, "damage reduces HP")
	asserts.equal(resources.apply_damage(-10), 0, "negative damage is rejected")
	asserts.equal(resources.heal_hp(50), 25, "explicit healing clamps at maximum")
	asserts.equal(resources.hp, 100, "healing cannot exceed HP maximum")
	resources.apply_damage(999)
	asserts.equal(resources.hp, 0, "damage clamps HP at zero")
	asserts.equal(hp_depleted_count[0], 1, "HP depletion emits once on the transition to zero")
	resources.apply_damage(1)
	asserts.equal(hp_depleted_count[0], 1, "HP depletion does not repeat at zero")
	asserts.equal(hp_changes.size(), 3, "HP change emits only when HP actually changes")

	asserts.true_value(resources.spend_ki(40), "ki spending succeeds with sufficient ki")
	asserts.equal(resources.ki, 60, "ability spending uses ki")
	asserts.false_value(resources.spend_ki(61), "ki spending fails when insufficient")
	asserts.equal(resources.recover_ki(100), 40, "ki recovery clamps at maximum")
	asserts.true_value(resources.spend_ki(100), "ki can be spent down to zero")
	asserts.equal(ki_depleted_count[0], 1, "ki depletion is observable")
	asserts.equal(ki_changes.size(), 3, "ki changes are observable")
	resources.recover_ki(100)

	resources.reduce_kokoro(100)
	asserts.equal(resources.kokoro, 0, "kokoro clamps to zero")
	asserts.equal(kokoro_depleted_count[0], 1, "kokoro depletion is observable")
	asserts.true_value(resources.is_kokoro_low(), "zero kokoro is below the configured threshold")
	asserts.equal(resources.restore_kokoro(30), 30, "kokoro restoration is explicit")
	asserts.true_value(resources.is_kokoro_low(), "configured threshold is inclusive")
	resources.restore_kokoro(1)
	asserts.false_value(resources.is_kokoro_low(), "kokoro above the threshold is not low")
	asserts.equal(kokoro_changes.size(), 3, "kokoro changes are observable")

	resources.heal_hp(40)
	var damaged_hp: int = resources.hp
	resources.recover_ki(1)
	resources.reduce_kokoro(1)
	asserts.equal(resources.hp, damaged_hp, "other state changes do not naturally recover HP")
	_assert_snapshot_delta_publish_is_prevalidated_and_emission_only(asserts)

func _assert_snapshot_delta_publish_is_prevalidated_and_emission_only(asserts) -> void:
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var before := resources.to_dictionary()
	resources.set_block_signals(true)
	resources.recover_ki(12)
	var after := resources.to_dictionary()
	var prepared: Dictionary = resources.prepare_snapshot_delta(before, after)
	asserts.true_value(prepared.ok, "current resource snapshot prepares a commit token")
	var stale := after.duplicate(true)
	stale.ki = 63
	asserts.equal(resources.prepare_snapshot_delta(before, stale).reason, "stale_resource_snapshot", "stale resource delta is rejected before commit")
	var events := []
	resources.ki_changed.connect(func(previous: int, current: int, maximum: int) -> void: events.append([previous, current, maximum]))
	resources.set_block_signals(false)
	resources.publish_snapshot_delta(prepared.token)
	asserts.equal(events, [[50, 62, 100]], "prepared resource commit publishes its captured delta exactly once")

func _assert_invalid_balance_data(asserts) -> void:
	var valid := {
		"player_hp_max": 100,
		"ki_max": 100,
		"kokoro_max": 100,
		"kokoro_low_threshold": 30
	}
	var missing := valid.duplicate()
	missing.erase("ki_max")
	var missing_result: Dictionary = PlayerResources.from_catalog(FakeCatalog.new(missing))
	asserts.false_value(missing_result.ok, "missing balance values are rejected")
	asserts.true_value("ki_max" in missing_result.error, "missing balance error names the stable ID")

	var non_numeric := valid.duplicate()
	non_numeric["player_hp_max"] = "100"
	var non_numeric_result: Dictionary = PlayerResources.from_catalog(FakeCatalog.new(non_numeric))
	asserts.false_value(non_numeric_result.ok, "non-numeric balance values are rejected")

	var fractional := valid.duplicate()
	fractional["ki_max"] = 99.5
	var fractional_result: Dictionary = PlayerResources.from_catalog(FakeCatalog.new(fractional))
	asserts.false_value(fractional_result.ok, "fractional balance values are rejected")

	var negative_maximum := valid.duplicate()
	negative_maximum["kokoro_max"] = -1
	var maximum_result: Dictionary = PlayerResources.from_catalog(FakeCatalog.new(negative_maximum))
	asserts.false_value(maximum_result.ok, "non-positive maximums are rejected")

	var invalid_threshold := valid.duplicate()
	invalid_threshold["kokoro_low_threshold"] = 101
	var threshold_result: Dictionary = PlayerResources.from_catalog(FakeCatalog.new(invalid_threshold))
	asserts.false_value(threshold_result.ok, "out-of-range kokoro thresholds are rejected")
