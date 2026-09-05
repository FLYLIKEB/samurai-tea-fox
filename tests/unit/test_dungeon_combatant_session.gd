extends RefCounted

const DungeonCombatantSession = preload("res://src/main/dungeon_combatant_session.gd")

class TestCombatant:
	extends Node2D

	var hp := 10

	func current_hp() -> int:
		return hp

class Catalog:
	extends RefCounted

	func find_by_id(dataset: String, id: String) -> Dictionary:
		if dataset == "monsters" and id in ["road_bandit", "tea_thief"]:
			return {"id": id}
		return {}

func run(asserts) -> void:
	_assert_combat_targets_hide_locked_boss(asserts)
	_assert_regular_monster_ids_filter_unknown_ids_and_fill_count(asserts)

func _assert_combat_targets_hide_locked_boss(asserts) -> void:
	var session := DungeonCombatantSession.new()
	var regular := TestCombatant.new()
	regular.name = "dungeon_enemy_0"
	var boss := TestCombatant.new()
	boss.name = "dungeon_boss"
	session.enemy_nodes = [regular, boss]

	asserts.equal(session.combat_targets(true, null, "dungeon_boss", false), [regular], "locked boss is excluded from dungeon combat targets")
	asserts.equal(session.combat_targets(true, null, "dungeon_boss", true), [regular, boss], "boss becomes a combat target after the gate opens")
	asserts.equal(session.regular_combat_targets(true, "dungeon_boss"), [regular], "regular target query excludes boss nodes")

	regular.free()
	boss.free()

func _assert_regular_monster_ids_filter_unknown_ids_and_fill_count(asserts) -> void:
	var session := DungeonCombatantSession.new()
	session.overworld_generated_world = {
		"monster_spawn_pool": {
			"entries": [
				{"monster_id": "missing_monster"},
				{"monster_id": "tea_thief"}
			]
		}
	}

	asserts.equal(session.regular_monster_ids(3, {}, Catalog.new()), ["tea_thief", "tea_thief", "tea_thief"], "regular monster ids use known pool entries and repeat to requested count")
