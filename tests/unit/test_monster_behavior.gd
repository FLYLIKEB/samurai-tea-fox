extends RefCounted

const MonsterBehaviorRuntime = preload("res://src/enemy/behavior/monster_behavior_runtime.gd")
const MonsterDefinition = preload("res://src/enemy/monster_definition.gd")
const MonsterSpawnFactory = preload("res://src/enemy/monster_spawn_factory.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary

	func _init(monsters: Array) -> void:
		definitions = {"monsters": monsters}

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_definition_requires_supported_behavior(asserts)
	_assert_factory_builds_shared_runtime_with_role_strategies(asserts)
	_assert_target_detection_and_loss(asserts)
	_assert_melee_and_attack_cadence(asserts)
	_assert_delta_ticks_are_deterministic(asserts)
	_assert_charge_windup_transition(asserts)
	_assert_ranged_distance_control(asserts)
	_assert_disruptor_and_rare_actions(asserts)
	_assert_stagger_interrupts_behavior(asserts)
	_assert_factory_connects_stagger_event(asserts)
	_assert_navigation_rejects_blocked_cells(asserts)

func _assert_definition_requires_supported_behavior(asserts) -> void:
	var valid: Dictionary = MonsterDefinition.from_dictionary(_monster("bandit", "근접", 10, 1.8, 1.6))
	asserts.true_value(valid.ok, "supported behavior type loads from monster data")
	if valid.ok:
		asserts.equal(valid.definition.behavior_type, "근접", "definition preserves behavior type")
	var missing: Dictionary = MonsterDefinition.from_dictionary(_monster("missing", "", 10, 1.8, 1.6))
	asserts.false_value(missing.ok, "missing behavior type is rejected")
	var unsupported: Dictionary = MonsterDefinition.from_dictionary(_monster("unknown", "순간이동", 10, 1.8, 1.6))
	asserts.false_value(unsupported.ok, "unsupported behavior type is rejected")

func _assert_factory_builds_shared_runtime_with_role_strategies(asserts) -> void:
	var factory := MonsterSpawnFactory.new(FakeCatalog.new([
		_monster("bandit", "근접", 10, 1.8, 1.6),
		_monster("dog", "돌진", 8, 1.4, 2.4),
		_monster("archer", "원거리", 6, 2.0, 1.3)
	]))
	var bandit: Dictionary = factory.spawn("bandit")
	var dog: Dictionary = factory.spawn("dog")
	var archer: Dictionary = factory.spawn("archer")
	asserts.true_value(bandit.ok and dog.ok and archer.ok, "three behavior roles spawn through one factory")
	if bandit.ok and dog.ok and archer.ok:
		asserts.equal(bandit.behavior.get_script(), dog.behavior.get_script(), "melee and charge share one behavior runtime")
		asserts.equal(dog.behavior.get_script(), archer.behavior.get_script(), "charge and ranged share one behavior runtime")
		asserts.equal(bandit.behavior.behavior_type, "근접", "melee strategy comes from data")
		asserts.equal(dog.behavior.behavior_type, "돌진", "charge strategy comes from data")
		asserts.equal(archer.behavior.behavior_type, "원거리", "ranged strategy comes from data")

func _assert_target_detection_and_loss(asserts) -> void:
	var runtime = _runtime("근접")
	var world := WorldData.new(8, 8)
	var pursue: Dictionary = runtime.tick(0.0, _observation(Vector2i(1, 1), Vector2i(4, 1), false), world)
	asserts.equal(pursue.type, "navigate", "detected target produces navigation command")
	asserts.equal(runtime.target_id, "player", "runtime remembers detected target")
	var lost: Dictionary = runtime.tick(0.1, {"detected": false}, world)
	asserts.equal(lost.type, "idle", "lost target stops behavior")
	asserts.equal(runtime.target_id, "", "lost target clears remembered target")

func _assert_melee_and_attack_cadence(asserts) -> void:
	var runtime = _runtime("근접", 1.5)
	var world := WorldData.new(8, 8)
	var in_range := _observation(Vector2i(1, 1), Vector2i(2, 1), true)
	var first: Dictionary = runtime.tick(0.0, in_range, world)
	asserts.equal(first.type, "attack", "melee attacks in common sensor range")
	asserts.equal(first.damage, 10, "attack intent uses monster data damage")
	var cooling: Dictionary = runtime.tick(1.0, in_range, world)
	asserts.equal(cooling.reason, "attack_cooldown", "attack period blocks early repeat")
	var ready: Dictionary = runtime.tick(0.5, in_range, world)
	asserts.equal(ready.type, "attack", "attack repeats exactly after data period")

func _assert_delta_ticks_are_deterministic(asserts) -> void:
	var whole = _runtime("근접", 1.5)
	var split = _runtime("근접", 1.5)
	var world := WorldData.new(8, 8)
	var in_range := _observation(Vector2i(1, 1), Vector2i(2, 1), true)
	whole.tick(0.0, in_range, world)
	split.tick(0.0, in_range, world)
	var whole_command: Dictionary = whole.tick(1.0, in_range, world)
	split.tick(0.4, in_range, world)
	var split_command: Dictionary = split.tick(0.6, in_range, world)
	var whole_state: Dictionary = whole.to_dictionary()
	var split_state: Dictionary = split.to_dictionary()
	asserts.equal(whole_state.state, split_state.state, "split delta ticks preserve behavior state")
	asserts.true_value(
		absf(float(whole_state.attack_cooldown_remaining) - float(split_state.attack_cooldown_remaining)) < 0.000001,
		"split delta ticks preserve behavior timers"
	)
	asserts.equal(whole_command, split_command, "split delta ticks preserve emitted command at equal elapsed time")

func _assert_charge_windup_transition(asserts) -> void:
	var runtime = _runtime("돌진")
	var world := WorldData.new(8, 8)
	var observation := _observation(Vector2i(1, 1), Vector2i(4, 1), false)
	observation["charge_opportunity"] = true
	var windup: Dictionary = runtime.tick(0.0, observation, world)
	asserts.equal(windup.reason, "charge_windup", "charge role enters windup first")
	observation["windup_complete"] = true
	var charge: Dictionary = runtime.tick(0.0, observation, world)
	asserts.equal(charge.type, "navigate", "completed windup emits charge navigation")
	asserts.equal(charge.reason, "charge", "charge command preserves strategy reason")

func _assert_ranged_distance_control(asserts) -> void:
	var runtime = _runtime("원거리")
	var world := WorldData.new(8, 8)
	var close := _observation(Vector2i(3, 3), Vector2i(4, 3), true)
	close["too_close"] = true
	var retreat: Dictionary = runtime.tick(0.0, close, world)
	asserts.equal(retreat.type, "navigate", "ranged role retreats when sensor reports too close")
	asserts.equal(retreat.to_cell, Vector2i(2, 3), "ranged retreat moves away from target")
	close["too_close"] = false
	var attack: Dictionary = runtime.tick(0.0, close, world)
	asserts.equal(attack.type, "attack", "ranged role attacks inside preferred range")

func _assert_disruptor_and_rare_actions(asserts) -> void:
	var world := WorldData.new(8, 8)
	var in_range := _observation(Vector2i(1, 1), Vector2i(2, 1), true)
	var disruptor = _runtime("방해")
	var rare = _runtime("희귀")
	asserts.equal(disruptor.tick(0.0, in_range, world).attack_kind, "disrupt", "disruptor strategy emits disrupt attack intent")
	asserts.equal(rare.tick(0.0, in_range, world).attack_kind, "rare", "rare strategy emits rare action intent")

func _assert_stagger_interrupts_behavior(asserts) -> void:
	var runtime = _runtime("근접")
	var world := WorldData.new(8, 8)
	var in_range := _observation(Vector2i(1, 1), Vector2i(2, 1), true)
	runtime.interrupt_for_stagger(0.6)
	var interrupted: Dictionary = runtime.tick(0.25, in_range, world)
	asserts.equal(interrupted.reason, "staggered", "stagger suppresses attack and movement")
	var recovered: Dictionary = runtime.tick(0.35, in_range, world)
	asserts.equal(recovered.type, "attack", "behavior resumes at deterministic recovery tick")

func _assert_factory_connects_stagger_event(asserts) -> void:
	var factory := MonsterSpawnFactory.new(FakeCatalog.new([_monster("bandit", "근접", 10, 1.0, 1.6)]))
	var spawned: Dictionary = factory.spawn("bandit", {"combat_id": "bandit_1"})
	asserts.true_value(spawned.ok, "monster spawns for stagger signal integration")
	if not spawned.ok:
		return
	spawned.monster.apply_stagger_event({"stagger": 2.0, "stagger_duration_seconds": 0.5})
	var command: Dictionary = spawned.behavior.tick(
		0.1,
		_observation(Vector2i(1, 1), Vector2i(2, 1), true),
		WorldData.new(8, 8)
	)
	asserts.equal(command.reason, "staggered", "monster stagger signal interrupts its shared behavior runtime")

func _assert_navigation_rejects_blocked_cells(asserts) -> void:
	var world := WorldData.new(8, 8)
	world.set_terrain(Vector2i(2, 1), "wall", false)
	var runtime = _runtime("근접")
	var blocked: Dictionary = runtime.tick(
		0.0,
		_observation(Vector2i(1, 1), Vector2i(4, 1), false),
		world
	)
	asserts.equal(blocked.type, "idle", "blocked world cell suppresses navigation")
	asserts.equal(blocked.reason, "blocked", "blocked navigation reports stable reason")
	world.set_terrain(Vector2i(2, 1), "ground", true)
	world.reserve_entity("other", Vector2i(2, 1))
	var occupied: Dictionary = runtime.tick(
		0.0,
		_observation(Vector2i(1, 1), Vector2i(4, 1), false),
		world
	)
	asserts.equal(occupied.reason, "blocked", "occupied world cell suppresses navigation")

func _runtime(behavior_type: String, attack_period_seconds := 1.0):
	var result: Dictionary = MonsterDefinition.from_dictionary(
		_monster("test_monster", behavior_type, 10, attack_period_seconds, 2.0)
	)
	return MonsterBehaviorRuntime.new(result.definition, "monster_1")

func _observation(self_cell: Vector2i, target_cell: Vector2i, in_attack_range: bool) -> Dictionary:
	return {
		"detected": true,
		"target_id": "player",
		"self_cell": self_cell,
		"target_cell": target_cell,
		"in_attack_range": in_attack_range
	}

func _monster(id: String, behavior_type: String, attack: int, attack_period_seconds: float, movement_speed: float) -> Dictionary:
	return {
		"id": id,
		"name": id,
		"status": "테스트",
		"kind": "테스트",
		"hp": 50,
		"stagger_resistance": 0.5,
		"movement_speed": movement_speed,
		"attack": attack,
		"attack_period_seconds": attack_period_seconds,
		"behavior_type": behavior_type
	}
