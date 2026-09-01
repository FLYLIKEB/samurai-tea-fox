extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")
const CombatantState = preload("res://src/combat/combatant_state.gd")
const AbilityDefinition = preload("res://src/ability/ability_definition.gd")
const AbilityRuntime = preload("res://src/ability/ability_runtime.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

class TailQuery:
	extends RefCounted
	var tail_count: int
	var calls: Array = []

	func _init(initial_tail_count: int) -> void:
		tail_count = initial_tail_count

	func can_use_ability(ability_id: String, tail_requirement: int) -> bool:
		calls.append([ability_id, tail_requirement])
		return tail_count >= tail_requirement

func run(asserts) -> void:
	_assert_generated_catalog_loads_ability_runtime(asserts)
	_assert_equipping_slots_and_tail_query(asserts)
	_assert_damage_sample_casts_through_common_runtime(asserts)
	_assert_low_kokoro_cost_cooldown_and_insufficient_ki(asserts)
	_assert_movement_sample_uses_strategy_without_damage(asserts)
	_assert_invalid_ability_data_and_effect_type_are_rejected(asserts)

func _assert_generated_catalog_loads_ability_runtime(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for abilities")
	var runtime_result: Dictionary = AbilityRuntime.from_catalog(catalog)
	asserts.true_value(runtime_result.ok, "ability runtime initializes from generated catalog")
	if not runtime_result.ok:
		return
	var runtime: AbilityRuntime = runtime_result.runtime
	asserts.equal(runtime.equip_slots.size(), 2, "ability equip slots come from balance data")
	asserts.true_value(runtime.definitions.has("ember"), "generated attack sample ability is loaded")
	asserts.true_value(runtime.definitions.has("water_shadow"), "generated movement sample ability is loaded")
	asserts.equal(runtime.definitions["ember"].ki_cost, 14, "ability ki cost comes from generated data")
	asserts.equal(runtime.definitions["ember"].cooldown_seconds, 4.0, "ability cooldown comes from generated data")
	asserts.equal(runtime.definitions["water_shadow"].range_tiles, 2.0, "ability range comes from generated data")

func _assert_equipping_slots_and_tail_query(asserts) -> void:
	var runtime := _test_runtime()
	var tail_query := TailQuery.new(1)
	asserts.true_value(runtime.equip(0, "ember", {"tail_query": tail_query}).ok, "tail query allows eligible ability equip")
	asserts.equal(tail_query.calls[0], ["ember", 1], "tail query receives stable ability ID and requirement")

	var blocked := runtime.equip(1, "crooked_cut", {"tail_query": tail_query})
	asserts.false_value(blocked.ok, "tail query blocks ability equip when requirement is not met")
	asserts.equal(blocked.reason, "tail_requirement_not_met", "tail gate reason is explicit")

	var invalid_slot := runtime.equip(2, "ember", {"tail_count": 9})
	asserts.false_value(invalid_slot.ok, "equip rejects slots outside balance-defined capacity")
	asserts.equal(invalid_slot.reason, "invalid_slot", "invalid equip slot reason is explicit")

	var unknown := runtime.equip(0, "missing", {"tail_count": 9})
	asserts.false_value(unknown.ok, "equip rejects unknown ability IDs")
	asserts.equal(unknown.reason, "unknown_ability", "unknown ability reason is explicit")

func _assert_damage_sample_casts_through_common_runtime(asserts) -> void:
	var runtime := _test_runtime()
	var resources := PlayerResources.new(100, 100, 100, 30)
	var target := CombatantState.new("target_1", 50, 0, "dummy")
	asserts.true_value(runtime.equip(0, "ember", {"tail_count": 1}).ok, "attack sample equips")

	var result := runtime.cast(0, {
		"source_id": "player",
		"resources": resources,
		"tail_count": 1,
		"targets": [target],
		"direction": Vector2.RIGHT
	})
	asserts.true_value(result.ok, "attack sample casts through common runtime")
	if not result.ok:
		return
	asserts.equal(result.effect_type, "damage", "attack sample selects damage strategy from data type")
	asserts.equal(result.ability_id, "ember", "cast result includes stable ability ID")
	asserts.equal(result.applied_damage, 20, "attack sample applies data-driven base damage")
	asserts.equal(target.hp, 30, "target HP is reduced by ability damage")
	asserts.equal(resources.ki, 86, "ability spending consumes ki from player resources")
	asserts.equal(result.ki_cost, 14, "normal kokoro keeps base ki cost")
	asserts.equal(result.cooldown_seconds, 4.0, "cooldown comes from ability data")
	asserts.equal(target.received_damage_events[0].ability_id, "ember", "damage event carries ability ID")

	var blocked := runtime.cast(0, {
		"source_id": "player",
		"resources": resources,
		"tail_count": 1,
		"targets": [target]
	})
	asserts.false_value(blocked.ok, "ability cannot be cast again during cooldown")
	asserts.equal(blocked.reason, "ability_on_cooldown", "cooldown reason is explicit")
	runtime.tick(4.0)
	asserts.true_value(runtime.can_cast(0, {
		"resources": resources,
		"tail_count": 1,
		"targets": [target]
	}).ok, "cooldown expires through runtime tick")

func _assert_low_kokoro_cost_cooldown_and_insufficient_ki(asserts) -> void:
	var runtime := _test_runtime()
	var resources := PlayerResources.new(100, 100, 100, 30)
	resources.reduce_kokoro(70)
	resources.spend_ki(82)
	asserts.true_value(runtime.equip(0, "ember", {"tail_count": 1}).ok, "low-kokoro sample equips")
	var time_state := TimeState.new(_test_time_config())

	var can_cast := runtime.can_cast(0, {
		"resources": resources,
		"time_state": time_state,
		"tail_count": 1,
		"targets": [CombatantState.new("target_1", 50, 0)]
	})
	asserts.true_value(can_cast.ok, "low kokoro cast is allowed when adjusted cost is available")
	asserts.equal(can_cast.ki_cost, 18, "low kokoro applies configured cost multiplier and rounds up")

	var result := runtime.cast(0, {
		"source_id": "player",
		"resources": resources,
		"time_state": time_state,
		"tail_count": 1,
		"targets": [CombatantState.new("target_1", 50, 0)]
	})
	asserts.true_value(result.ok, "low-kokoro cast spends adjusted cost")
	asserts.equal(resources.ki, 0, "adjusted cost consumes remaining ki")
	runtime.tick(4.0)

	var insufficient := runtime.cast(0, {
		"source_id": "player",
		"resources": resources,
		"time_state": time_state,
		"tail_count": 1,
		"targets": [CombatantState.new("target_1", 50, 0)]
	})
	asserts.false_value(insufficient.ok, "insufficient ki is rejected by common check")
	asserts.equal(insufficient.reason, "insufficient_ki", "insufficient ki reason is explicit")

	resources.recover_ki(100)
	resources.reduce_kokoro(30)
	var depleted := runtime.cast(0, {
		"source_id": "player",
		"resources": resources,
		"time_state": time_state,
		"tail_count": 1,
		"targets": [CombatantState.new("target_1", 50, 0)]
	})
	asserts.false_value(depleted.ok, "zero kokoro prevents ability casting")
	asserts.equal(depleted.reason, "kokoro_depleted", "kokoro depletion reason is explicit")

func _assert_movement_sample_uses_strategy_without_damage(asserts) -> void:
	var runtime := _test_runtime()
	var resources := PlayerResources.new(100, 100, 100, 30)
	asserts.true_value(runtime.equip(1, "water_shadow", {"tail_count": 1}).ok, "movement sample equips")

	var result := runtime.cast(1, {
		"source_id": "player",
		"resources": resources,
		"tail_count": 1,
		"direction": Vector2.LEFT
	})
	asserts.true_value(result.ok, "movement sample casts through common runtime")
	if not result.ok:
		return
	asserts.equal(result.effect_type, "movement", "movement sample selects movement strategy from data type")
	asserts.equal(result.distance_tiles, 2.0, "movement distance uses data-driven range")
	asserts.equal(result.direction, Vector2.LEFT, "movement direction is normalized")
	asserts.equal(resources.ki, 88, "movement ability consumes data-driven ki cost")

func _assert_invalid_ability_data_and_effect_type_are_rejected(asserts) -> void:
	var missing_definition := _ability("broken", "공격", 1, 1, 1.0, 1)
	missing_definition.erase("ki_cost")
	var missing_result: Dictionary = AbilityRuntime.from_catalog(FakeCatalog.new({
		"balance": [{"id": "ability_equip_slots", "value": 2}],
		"abilities": [missing_definition]
	}))
	asserts.false_value(missing_result.ok, "missing ability field is rejected")

	var fractional_damage := _ability("broken", "공격", 1, 1, 1.0, 1)
	fractional_damage["base_damage"] = 1.5
	var fractional_result: Dictionary = AbilityRuntime.from_catalog(FakeCatalog.new({
		"balance": [{"id": "ability_equip_slots", "value": 2}],
		"abilities": [fractional_damage]
	}))
	asserts.false_value(fractional_result.ok, "fractional ability damage is rejected")

	var runtime := AbilityRuntime.new({"unknown": AbilityDefinition.new(_ability("unknown", "미지원", 1, 1, 1.0, 1))}, 1)
	asserts.true_value(runtime.equip(0, "unknown", {"tail_count": 1}).ok, "unknown effect type can be equipped as data")
	var unsupported := runtime.cast(0, {
		"resources": PlayerResources.new(100, 100, 100, 30),
		"tail_count": 1
	})
	asserts.false_value(unsupported.ok, "unsupported effect type fails before spending ki")
	asserts.equal(unsupported.reason, "unsupported_effect_type", "unsupported effect type reason is explicit")

func _test_runtime() -> AbilityRuntime:
	var result: Dictionary = AbilityRuntime.from_catalog(FakeCatalog.new({
		"balance": [{"id": "ability_equip_slots", "value": 2}],
		"abilities": [
			_ability("ember", "공격", 1, 14, 4.0, 20, 3.0),
			_ability("water_shadow", "이동", 1, 12, 5.0, 0, 2.0),
			_ability("crooked_cut", "공격", 3, 22, 6.0, 34, 1.8)
		]
	}))
	return result.runtime

func _ability(id: String, type: String, tail_requirement: int, ki_cost: int, cooldown_seconds: float, base_damage: int, range := 1.0) -> Dictionary:
	return {
		"id": id,
		"name": id,
		"type": type,
		"tail_requirement": tail_requirement,
		"ki_cost": ki_cost,
		"cooldown_seconds": cooldown_seconds,
		"base_damage": base_damage,
		"range": range,
		"duration_seconds": 0,
		"status_effect": ""
	}

func _test_time_config() -> TimeConfig:
	var result: Dictionary = TimeConfig.from_catalog(FakeCatalog.new({
		"balance": [
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
	}))
	return result.config
