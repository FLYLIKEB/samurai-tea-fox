extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const CombatantState = preload("res://src/combat/combatant_state.gd")

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
	_assert_generated_catalog_loads_combat_values(asserts)
	_assert_catalog_uses_explicit_weapon_and_monster_values(asserts)
	_assert_missing_combat_data_is_rejected(asserts)
	_assert_combo_damage_events_and_duplicate_prevention(asserts)
	_assert_hit_invulnerability_blocks_new_swings_until_tick(asserts)
	_assert_dodge_cooldown_and_invulnerability_tick(asserts)

func _assert_generated_catalog_loads_combat_values(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads")
	var config_result: Dictionary = CombatConfig.from_catalog(catalog)
	asserts.true_value(config_result.ok, "combat config initializes from generated catalog")
	if not config_result.ok:
		return
	var config: CombatConfig = config_result.config
	asserts.equal(config.basic_attack_combo_hits, 3, "combo hit count comes from balance data")
	asserts.equal(config.finisher_knockback_tiles, 0.5, "finisher knockback comes from balance data")
	asserts.equal(config.dodge_cooldown_seconds, 0.9, "dodge cooldown comes from balance data")
	asserts.equal(config.dodge_distance_tiles, 1.8, "dodge distance comes from balance data")
	asserts.equal(config.dodge_invulnerability_seconds, 0.18, "dodge invulnerability comes from balance data")
	asserts.equal(config.hit_invulnerability_seconds, 0.2, "hit invulnerability comes from balance data")
	asserts.equal(config.ki_attack_multiplier_0, 0.7, "low ki multiplier comes from balance data")
	asserts.equal(config.ki_attack_multiplier_100, 1.3, "high ki multiplier comes from balance data")
	asserts.equal(config.weapon_id, "short_travel_sword", "default weapon stable ID is loaded")
	asserts.equal(config.weapon_base_damage, 14, "weapon damage comes from item data")
	asserts.equal(config.weapon_range_tiles, 1.15, "weapon range comes from item data")
	asserts.equal(config.weapon_attack_speed, 1.0, "weapon attack speed comes from item data")

	var monster_result: Dictionary = CombatantState.from_catalog(catalog, "road_bandit", "bandit_1")
	asserts.true_value(monster_result.ok, "road bandit combatant initializes from generated catalog")
	if monster_result.ok:
		var bandit: CombatantState = monster_result.combatant
		asserts.equal(bandit.hp_max, 70, "road bandit HP comes from monster data")
		asserts.equal(bandit.attack, 10, "road bandit attack comes from monster data")

func _assert_catalog_uses_explicit_weapon_and_monster_values(asserts) -> void:
	var config_result: Dictionary = CombatConfig.from_catalog(FakeCatalog.new({
		"balance": _balance_values(),
		"items": [{"id": "short_travel_sword", "base_damage": 20, "range": 1.5, "attack_speed": 1.25}],
		"monsters": [{"id": "road_bandit", "hp": 44, "attack": 9}]
	}))
	asserts.true_value(config_result.ok, "combat config initializes from explicit catalog fields")
	if config_result.ok:
		var config: CombatConfig = config_result.config
		asserts.equal(config.weapon_base_damage, 20, "weapon base damage is data-driven")
		asserts.equal(config.weapon_range_tiles, 1.5, "weapon range is data-driven")
		asserts.equal(config.weapon_attack_speed, 1.25, "weapon attack speed is data-driven")

	var monster_result: Dictionary = CombatantState.from_catalog(FakeCatalog.new({
		"monsters": [{"id": "road_bandit", "hp": 44, "attack": 9}]
	}), "road_bandit")
	asserts.true_value(monster_result.ok, "combatant initializes from explicit monster fields")
	if monster_result.ok:
		var bandit: CombatantState = monster_result.combatant
		asserts.equal(bandit.hp_max, 44, "road bandit HP is data-driven")
		asserts.equal(bandit.attack, 9, "road bandit attack is data-driven")

func _assert_missing_combat_data_is_rejected(asserts) -> void:
	var missing_weapon_field: Dictionary = CombatConfig.from_catalog(FakeCatalog.new({
		"balance": _balance_values(),
		"items": [{"id": "short_travel_sword", "base_damage": 20, "range": 1.5}]
	}))
	asserts.false_value(missing_weapon_field.ok, "missing weapon combat fields are rejected without fallback values")

	var missing_monster_field: Dictionary = CombatantState.from_catalog(FakeCatalog.new({
		"monsters": [{"id": "road_bandit", "hp": 44}]
	}), "road_bandit")
	asserts.false_value(missing_monster_field.ok, "missing monster combat fields are rejected without fallback values")
	var fractional_weapon_damage: Dictionary = CombatConfig.from_catalog(FakeCatalog.new({
		"balance": _balance_values(),
		"items": [{"id": "short_travel_sword", "base_damage": 20.5, "range": 1.5, "attack_speed": 1.25}]
	}))
	asserts.false_value(fractional_weapon_damage.ok, "fractional weapon damage is rejected")
	var invalid_monster_hp: Dictionary = CombatantState.from_catalog(FakeCatalog.new({
		"monsters": [{"id": "road_bandit", "hp": 0, "attack": 9.5}]
	}), "road_bandit")
	asserts.false_value(invalid_monster_hp.ok, "zero HP and fractional monster attack are rejected")

func _assert_combo_damage_events_and_duplicate_prevention(asserts) -> void:
	var config := _test_config()
	var combat := CombatState.new(config)
	var target := CombatantState.new("target_1", 100, 0, "dummy")
	var first: Dictionary = combat.start_basic_attack("player", 0.0)
	var blocked_attack: Dictionary = combat.start_basic_attack("player", 50.0)
	asserts.false_value(blocked_attack.ok, "weapon attack speed starts a data-driven attack cooldown")
	combat.tick(0.8)
	var second: Dictionary = combat.start_basic_attack("player", 50.0)
	combat.tick(0.8)
	var third: Dictionary = combat.start_basic_attack("player", 100.0)
	combat.tick(0.8)
	var fourth: Dictionary = combat.start_basic_attack("player", 100.0)

	asserts.equal(first.combo_hit, 1, "first swing starts combo")
	asserts.equal(second.combo_hit, 2, "second swing advances combo")
	asserts.equal(third.combo_hit, 3, "third swing reaches finisher")
	asserts.true_value(third.is_finisher, "third swing is finisher")
	asserts.equal(third.knockback_tiles, 0.5, "finisher applies configured knockback")
	asserts.equal(fourth.combo_hit, 1, "combo wraps after finisher")
	asserts.equal(first.damage, 14, "zero ki uses low multiplier")
	asserts.equal(second.damage, 20, "mid ki interpolates between multipliers")
	asserts.equal(third.damage, 26, "full ki uses high multiplier")

	var hit: Dictionary = combat.apply_swing_hit(third, target)
	asserts.true_value(hit.ok, "swing can damage a duck-typed target")
	if hit.ok:
		asserts.equal(hit.event.source_id, "player", "damage event includes source")
		asserts.equal(hit.event.target_id, "target_1", "damage event includes target")
		asserts.equal(hit.event.weapon_id, "short_travel_sword", "damage event includes weapon")
		asserts.equal(hit.event.combo_hit, 3, "damage event includes combo hit")
		asserts.true_value(hit.event.is_finisher, "damage event marks finisher")
		asserts.equal(target.hp, 74, "target receives event damage")
		asserts.equal(target.received_damage_events.size(), 1, "target records applied damage event")

	var duplicate_hit: Dictionary = combat.apply_swing_hit(third, target)
	asserts.false_value(duplicate_hit.ok, "same swing cannot hit the same target twice")
	asserts.equal(duplicate_hit.reason, CombatState.DUPLICATE_TARGET_REASON, "duplicate target reason is explicit")
	combat.finish_swing(third)
	var finished_hit: Dictionary = combat.apply_swing_hit(third, target)
	asserts.false_value(finished_hit.ok, "finished swing state is expired")

func _assert_hit_invulnerability_blocks_new_swings_until_tick(asserts) -> void:
	var combat := CombatState.new(_test_config())
	var target := CombatantState.new("target_1", 100, 0, "dummy")
	var first: Dictionary = combat.start_basic_attack("player", 100.0)
	var hit: Dictionary = combat.apply_swing_hit(first, target, 1.0)
	asserts.true_value(hit.ok, "first hit applies hit invulnerability")
	asserts.true_value(combat.is_hit_invulnerable("target_1"), "target is hit-invulnerable after damage")

	combat.tick(0.8)
	var second: Dictionary = combat.start_basic_attack("player", 100.0)
	var blocked: Dictionary = combat.apply_swing_hit(second, target)
	asserts.false_value(blocked.ok, "new swing is blocked by target hit invulnerability")
	asserts.equal(blocked.reason, CombatState.HIT_INVULNERABLE_REASON, "hit invulnerability reason is explicit")

	combat.tick(0.2)
	asserts.false_value(combat.is_hit_invulnerable("target_1"), "hit invulnerability expires through tick")
	var unblocked: Dictionary = combat.apply_swing_hit(second, target)
	asserts.true_value(unblocked.ok, "new swing can hit after invulnerability expires")

func _assert_dodge_cooldown_and_invulnerability_tick(asserts) -> void:
	var combat := CombatState.new(_test_config())
	asserts.true_value(combat.is_dodge_ready(), "dodge starts ready")
	var dodge: Dictionary = combat.start_dodge()
	asserts.true_value(dodge.ok, "dodge starts when off cooldown")
	asserts.equal(dodge.distance_tiles, 1.8, "dodge reports configured distance")
	asserts.true_value(combat.is_dodge_invulnerable(), "dodge grants temporary invulnerability")
	asserts.false_value(combat.is_dodge_ready(), "dodge starts cooldown")

	var blocked: Dictionary = combat.start_dodge()
	asserts.false_value(blocked.ok, "dodge cannot restart during cooldown")
	asserts.equal(blocked.reason, "dodge_on_cooldown", "dodge cooldown reason is explicit")

	combat.tick(0.18)
	asserts.false_value(combat.is_dodge_invulnerable(), "dodge invulnerability expires before cooldown")
	asserts.false_value(combat.is_dodge_ready(), "dodge cooldown can outlast invulnerability")
	combat.tick(0.72)
	asserts.true_value(combat.is_dodge_ready(), "dodge cooldown expires through tick")

func _balance_values() -> Array:
	return [
		{"id": "basic_attack_combo_hits", "value": 3},
		{"id": "basic_combo_finisher_knockback_tiles", "value": 0.5},
		{"id": "dodge_cooldown_seconds", "value": 0.9},
		{"id": "dodge_distance_tiles", "value": 1.8},
		{"id": "dodge_invulnerability_seconds", "value": 0.18},
		{"id": "ki_attack_multiplier_0", "value": 0.7},
		{"id": "ki_attack_multiplier_100", "value": 1.3},
		{"id": "ki_max", "value": 100},
		{"id": "hit_invulnerability_seconds", "value": 0.2}
	]

func _test_config() -> CombatConfig:
	var result: Dictionary = CombatConfig.from_catalog(FakeCatalog.new({
		"balance": _balance_values(),
		"items": [{"id": "short_travel_sword", "base_damage": 20, "range": 1.5, "attack_speed": 1.25}]
	}))
	return result.config
