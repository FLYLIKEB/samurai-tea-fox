extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const CombatState = preload("res://src/combat/combat_state.gd")
const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const MonsterDefinition = preload("res://src/enemy/monster_definition.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")

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

class HookProbe:
	extends RefCounted
	var death_events: Array = []
	var drop_events: Array = []
	var damage_events: Array = []
	var stagger_events: Array = []

	func on_damaged(event: Dictionary, applied_damage: int) -> void:
		damage_events.append({"event": event, "applied_damage": applied_damage})

	func on_staggered(event: Dictionary, applied_stagger: float) -> void:
		stagger_events.append({"event": event, "applied_stagger": applied_stagger})

	func on_defeated(event: Dictionary) -> void:
		death_events.append(event)

	func on_drop_requested(event: Dictionary) -> void:
		drop_events.append(event)

class DummySignalProbe:
	extends RefCounted
	var defeated_no_arg_count := 0
	var monster_defeat_events: Array = []
	var defeat_events: Array = []

	func on_defeated() -> void:
		defeated_no_arg_count += 1

	func on_monster_defeated(event: Dictionary) -> void:
		monster_defeat_events.append(event)

	func on_defeat_event(event: Dictionary) -> void:
		defeat_events.append(event)

func run(asserts) -> void:
	_assert_generated_definitions_load(asserts)
	_assert_spawn_factory_uses_same_runtime_for_two_monsters(asserts)
	_assert_data_snapshot_changes_runtime_stats(asserts)
	_assert_combat_dummy_refreshes_sprite_after_reconfigure(asserts)
	_assert_damage_stagger_death_and_drop_hooks(asserts)
	_assert_damage_ignores_dead_and_zero_applied_hits(asserts)
	_assert_spawn_factory_accepts_pool_behavior_variant(asserts)
	_assert_combat_dummy_preserves_no_arg_defeated_signal(asserts)
	_assert_combat_dummy_damage_popup_is_world_anchored(asserts)
	_assert_invalid_data_is_rejected(asserts)

func _assert_generated_definitions_load(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads with monster runtime fields")
	var bandit_result: Dictionary = MonsterDefinition.from_catalog(catalog, "road_bandit")
	asserts.true_value(bandit_result.ok, "road bandit monster definition loads")
	if bandit_result.ok:
		var bandit: MonsterDefinition = bandit_result.definition
		asserts.equal(bandit.hp, 70, "monster HP loads from data")
		asserts.equal(bandit.stagger_resistance, 0.2, "monster stagger resistance loads from data")
		asserts.equal(bandit.movement_speed, 1.6, "monster movement speed loads from data")
		asserts.equal(bandit.attack, 10, "monster attack loads from data")
		asserts.equal(bandit.attack_period_seconds, 1.8, "monster attack period loads from data")

func _assert_spawn_factory_uses_same_runtime_for_two_monsters(asserts) -> void:
	var factory := MonsterSpawnFactory.new(_runtime_catalog())
	var bandit_result: Dictionary = factory.spawn("road_bandit")
	var dog_result: Dictionary = factory.spawn("wild_dog")
	asserts.true_value(bandit_result.ok, "factory spawns road bandit")
	asserts.true_value(dog_result.ok, "factory spawns wild dog")
	if bandit_result.ok and dog_result.ok:
		asserts.equal(bandit_result.monster.get_script(), dog_result.monster.get_script(), "two definitions use the same MonsterState runtime")
		asserts.equal(bandit_result.monster.definition_id, "road_bandit", "bandit runtime keeps definition stable ID")
		asserts.equal(dog_result.monster.definition_id, "wild_dog", "dog runtime keeps definition stable ID")
		asserts.equal(bandit_result.monster.hp_max, 70, "bandit runtime HP comes from definition")
		asserts.equal(dog_result.monster.hp_max, 45, "dog runtime HP comes from definition")
		asserts.equal(dog_result.monster.movement_speed, 2.4, "dog runtime movement speed comes from definition")

func _assert_data_snapshot_changes_runtime_stats(asserts) -> void:
	var base_catalog := _runtime_catalog()
	var changed_catalog := _runtime_catalog()
	changed_catalog.definitions.monsters[0]["hp"] = 88
	changed_catalog.definitions.monsters[0]["attack"] = 13
	changed_catalog.definitions.monsters[0]["movement_speed"] = 1.9
	var base_result: Dictionary = MonsterSpawnFactory.new(base_catalog).spawn("road_bandit")
	var changed_result: Dictionary = MonsterSpawnFactory.new(changed_catalog).spawn("road_bandit")
	asserts.true_value(base_result.ok, "base monster spawns")
	asserts.true_value(changed_result.ok, "changed monster spawns")
	if base_result.ok and changed_result.ok:
		asserts.equal(base_result.monster.hp_max, 70, "base data snapshot controls base HP")
		asserts.equal(changed_result.monster.hp_max, 88, "changed data snapshot alters runtime HP")
		asserts.equal(changed_result.monster.attack, 13, "changed data snapshot alters runtime attack")
		asserts.equal(changed_result.monster.movement_speed, 1.9, "changed data snapshot alters runtime movement")

func _assert_combat_dummy_refreshes_sprite_after_reconfigure(asserts) -> void:
	var dummy := CombatDummy.new()
	var sprite := Sprite2D.new()
	dummy.sprite = sprite
	dummy.monster_id = "road_bandit"
	dummy._apply_sprite()
	asserts.equal(dummy._resolved_sprite_asset_id, "monster_road_bandit_front_idle", "dummy starts with the road bandit sprite")
	dummy.monster_id = "wild_dog"
	var configured: Dictionary = dummy.configure_combat(_runtime_catalog(), null, _test_combat_config())
	asserts.true_value(configured.ok, "dummy reconfigures as wild dog")
	asserts.equal(dummy._resolved_sprite_asset_id, "monster_wild_dog_front_idle", "dummy refreshes the sprite after monster reconfigure")
	dummy.free()

func _assert_damage_stagger_death_and_drop_hooks(asserts) -> void:
	var spawn_result: Dictionary = MonsterSpawnFactory.new(_runtime_catalog()).spawn("wild_dog", {"combat_id": "wild_dog_test"})
	asserts.true_value(spawn_result.ok, "wild dog spawns for damage lifecycle")
	if not spawn_result.ok:
		return
	var monster = spawn_result.monster
	var probe := HookProbe.new()
	monster.damaged.connect(probe.on_damaged)
	monster.staggered.connect(probe.on_staggered)
	monster.defeated.connect(probe.on_defeated)
	monster.drop_requested.connect(probe.on_drop_requested)
	var applied: int = monster.apply_damage_event({
		"type": "damage",
		"source_id": "player",
		"target_id": "wild_dog_test",
		"damage": 10,
		"stagger": 1.25
	})
	asserts.equal(applied, 10, "monster applies incoming damage")
	asserts.equal(monster.hp, 35, "monster HP decreases")
	asserts.equal(probe.damage_events.size(), 1, "monster emits damage hook")
	asserts.equal(probe.stagger_events.size(), 1, "monster emits stagger hook when stagger exceeds resistance")
	if not probe.stagger_events.is_empty():
		asserts.equal(probe.stagger_events[0].applied_stagger, 1.15, "stagger resistance reduces incoming stagger")

	var combat := CombatState.new(_test_combat_config())
	var swing := combat.start_basic_attack("player", 100.0)
	asserts.true_value(swing.ok, "combat state starts swing for monster hit contract")
	if swing.ok:
		var hit: Dictionary = combat.apply_swing_hit(swing, monster)
		asserts.true_value(hit.ok, "combat hit contract damages MonsterState")
		asserts.equal(hit.applied_damage, 26, "common combat state reports damage applied to monster")
		asserts.equal(monster.hp, 9, "combat hit reduces MonsterState HP")

	var killing_damage: int = monster.apply_damage_event({"type": "damage", "source_id": "player", "damage": 99})
	asserts.equal(killing_damage, 9, "killing damage clamps to remaining HP")
	asserts.equal(probe.death_events.size(), 1, "monster emits one standard death event")
	asserts.equal(probe.drop_events.size(), 1, "monster emits one drop request hook")
	if not probe.death_events.is_empty():
		asserts.equal(probe.death_events[0].type, "monster_defeated", "death event has standard type")
		asserts.equal(probe.death_events[0].definition_id, "wild_dog", "death event includes definition ID")
	if not probe.drop_events.is_empty():
		asserts.equal(probe.drop_events[0].type, "monster_drop_requested", "drop hook has standard type")
		asserts.equal(probe.drop_events[0].combat_id, "wild_dog_test", "drop hook includes combat ID")
	monster.apply_damage_event({"type": "damage", "source_id": "player", "damage": 1})
	asserts.equal(probe.death_events.size(), 1, "monster death hook emits once")
	asserts.equal(probe.drop_events.size(), 1, "monster drop request emits once")

func _assert_damage_ignores_dead_and_zero_applied_hits(asserts) -> void:
	var spawn_result: Dictionary = MonsterSpawnFactory.new(_runtime_catalog()).spawn(
		"wild_dog",
		{"combat_id": "wild_dog_zero"}
	)
	asserts.true_value(spawn_result.ok, "wild dog spawns for zero damage lifecycle")
	if not spawn_result.ok:
		return
	var monster = spawn_result.monster
	var probe := HookProbe.new()
	monster.damaged.connect(probe.on_damaged)
	monster.staggered.connect(probe.on_staggered)
	monster.defeated.connect(probe.on_defeated)
	monster.drop_requested.connect(probe.on_drop_requested)

	var zero_damage: int = monster.apply_damage_event({
		"type": "damage",
		"source_id": "player",
		"damage": 0,
		"stagger": 99.0
	})
	asserts.equal(zero_damage, 0, "zero damage applies no monster damage")
	asserts.equal(monster.hp, 45, "zero damage leaves monster HP unchanged")
	asserts.equal(monster.received_damage_events.size(), 0, "zero applied damage is not recorded")
	asserts.equal(monster.received_stagger_events.size(), 0, "zero applied damage does not create stagger history")
	asserts.equal(probe.damage_events.size(), 0, "zero applied damage emits no damage hook")
	asserts.equal(probe.stagger_events.size(), 0, "zero applied damage emits no stagger hook")

	var killing_damage: int = monster.apply_damage_event({
		"type": "damage",
		"source_id": "player",
		"damage": 99
	})
	asserts.equal(killing_damage, 45, "killing hit defeats monster")
	asserts.equal(monster.received_damage_events.size(), 1, "killing hit is the only recorded damage event")
	asserts.equal(probe.death_events.size(), 1, "killing hit emits one death event")
	asserts.equal(probe.drop_events.size(), 1, "killing hit emits one drop request")

	var dead_rehit: int = monster.apply_damage_event({
		"type": "damage",
		"source_id": "player",
		"damage": 4,
		"stagger": 99.0
	})
	asserts.equal(dead_rehit, 0, "dead monster re-hit returns zero early")
	asserts.equal(monster.received_damage_events.size(), 1, "dead monster re-hit is not recorded")
	asserts.equal(monster.received_stagger_events.size(), 0, "dead monster re-hit does not create stagger history")
	asserts.equal(probe.death_events.size(), 1, "dead monster re-hit does not re-emit death")
	asserts.equal(probe.drop_events.size(), 1, "dead monster re-hit does not re-request drops")

func _assert_spawn_factory_accepts_pool_behavior_variant(asserts) -> void:
	var spawned: Dictionary = MonsterSpawnFactory.new(_runtime_catalog()).spawn(
		"road_bandit",
		{"combat_id": "road_bandit_rare", "behavior_type_override": "희귀"}
	)
	asserts.true_value(spawned.ok, "spawn factory accepts a data-driven rare behavior variant")
	if spawned.ok:
		asserts.equal(spawned.monster.definition_id, "road_bandit", "rare variant keeps the base monster definition id")
		asserts.equal(spawned.behavior.behavior_type, "희귀", "rare variant uses the rare behavior strategy")

func _assert_combat_dummy_preserves_no_arg_defeated_signal(asserts) -> void:
	var dummy := CombatDummy.new()
	var probe := DummySignalProbe.new()
	dummy.defeated.connect(probe.on_defeated)
	dummy.monster_defeated.connect(probe.on_monster_defeated)
	dummy.defeat_event.connect(probe.on_defeat_event)
	var event := {"type": "monster_defeated", "combat_id": "dummy_test", "definition_id": "wild_dog"}

	dummy._on_monster_defeated(event)

	asserts.equal(probe.defeated_no_arg_count, 1, "CombatDummy defeated remains no-arg compatible")
	asserts.equal(probe.monster_defeat_events.size(), 1, "CombatDummy emits event-bearing monster_defeated signal")
	asserts.equal(probe.defeat_events.size(), 1, "CombatDummy emits event-bearing defeat_event signal")
	if not probe.monster_defeat_events.is_empty():
		asserts.equal(probe.monster_defeat_events[0].combat_id, "dummy_test", "monster_defeated carries event")
	if not probe.defeat_events.is_empty():
		asserts.equal(probe.defeat_events[0].definition_id, "wild_dog", "defeat_event carries event")

func _assert_combat_dummy_damage_popup_is_world_anchored(asserts) -> void:
	var dummy := CombatDummy.new()
	dummy._show_damage_popup(17)
	var popup := dummy.get_node_or_null("DamagePopup") as Label
	asserts.true_value(popup != null, "combat target owns its damage popup in world space")
	asserts.equal(popup.text, "-17", "damage popup shows applied damage")
	asserts.true_value(popup.visible, "damage popup becomes visible on hit")
	asserts.true_value(popup.position.y < -16.0, "damage popup appears above the enemy sprite and health bar")
	asserts.true_value(popup.get_theme_color("font_color").r > popup.get_theme_color("font_color").g * 2.0, "damage popup uses red text")
	asserts.true_value(popup.get_theme_font("font") != null, "damage popup uses the project pixel font")
	asserts.equal(popup.get_theme_font_size("font_size"), 13, "damage popup uses a readable pixel font size")
	asserts.equal(popup.get_theme_constant("outline_size"), 1, "damage popup keeps a crisp one-pixel outline")
	asserts.equal(popup.get_theme_constant("shadow_offset_x"), 2, "damage popup uses an integer pixel shadow")
	dummy.free()

func _assert_invalid_data_is_rejected(asserts) -> void:
	var missing: Dictionary = MonsterDefinition.from_dictionary({"id": "broken", "hp": 10, "attack": 1, "movement_speed": 1.0, "attack_period_seconds": 1.0})
	asserts.false_value(missing.ok, "missing stagger resistance is rejected")
	var fractional_hp: Dictionary = MonsterDefinition.from_dictionary(_monster("broken_hp", 10.5, 1.0, 1.0, 1, 1.0))
	asserts.false_value(fractional_hp.ok, "fractional monster HP is rejected")
	var zero_speed: Dictionary = MonsterDefinition.from_dictionary(_monster("broken_speed", 10, 1.0, 0.0, 1, 1.0))
	asserts.false_value(zero_speed.ok, "zero monster movement speed is rejected")
	var negative_attack: Dictionary = MonsterDefinition.from_dictionary(_monster("broken_attack", 10, 1.0, 1.0, -1, 1.0))
	asserts.false_value(negative_attack.ok, "negative monster attack is rejected")
	var zero_period: Dictionary = MonsterDefinition.from_dictionary(_monster("broken_period", 10, 1.0, 1.0, 1, 0.0))
	asserts.false_value(zero_period.ok, "zero monster attack period is rejected")

func _runtime_catalog() -> FakeCatalog:
	return FakeCatalog.new({
		"monsters": [
			_monster("road_bandit", 70, 0.2, 1.6, 10, 1.8, "근접"),
			_monster("wild_dog", 45, 0.1, 2.4, 8, 1.4, "돌진")
		]
	})

func _monster(id: String, hp, stagger_resistance, movement_speed, attack, attack_period_seconds, behavior_type := "근접") -> Dictionary:
	return {
		"id": id,
		"name": id,
		"status": "테스트",
		"kind": "테스트",
		"hp": hp,
		"stagger_resistance": stagger_resistance,
		"movement_speed": movement_speed,
		"attack": attack,
		"attack_period_seconds": attack_period_seconds,
		"behavior_type": behavior_type
	}

func _test_combat_config() -> CombatConfig:
	return CombatConfig.new({
		"basic_attack_combo_hits": 3,
		"finisher_knockback_tiles": 0.5,
		"dodge_cooldown_seconds": 0.9,
		"dodge_distance_tiles": 1.8,
		"dodge_invulnerability_seconds": 0.18,
		"ki_attack_multiplier_0": 0.7,
		"ki_attack_multiplier_100": 1.3,
		"ki_max": 100.0,
		"hit_invulnerability_seconds": 0.2,
		"weapon_id": "short_travel_sword",
		"weapon_base_damage": 20,
		"weapon_range_tiles": 1.5,
		"weapon_attack_speed": 1.25
	})
