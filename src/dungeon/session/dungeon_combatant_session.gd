extends RefCounted
class_name DungeonCombatantSession

var enemy_nodes: Array = []
var overworld_generated_world: Dictionary = {}
var overworld_world_data_snapshot: Dictionary = {}
var overworld_player_cell := Vector2i.ZERO
var overworld_combat_dummy_cell := Vector2i.ZERO
var overworld_combat_dummy = null
var overworld_combat_dummy_state: Dictionary = {}

func combat_targets(in_dungeon_map: bool, overworld_target, boss_owner_id: String, boss_combat_available: bool) -> Array:
	var targets := []
	if in_dungeon_map:
		for enemy in enemy_nodes:
			if _is_live_combatant(enemy):
				if enemy.name == boss_owner_id and not boss_combat_available:
					continue
				targets.append(enemy)
	elif _is_live_combatant(overworld_target):
		targets.append(overworld_target)
	return targets

func regular_combat_targets(in_dungeon_map: bool, boss_owner_id: String) -> Array:
	var targets := []
	if not in_dungeon_map:
		return targets
	for enemy in enemy_nodes:
		if _is_live_combatant(enemy) and enemy.name != boss_owner_id:
			targets.append(enemy)
	return targets

func boss_node(boss_owner_id: String) -> Node2D:
	for enemy in enemy_nodes:
		if is_instance_valid(enemy) and enemy.name == boss_owner_id:
			return enemy
	return null

func regular_monster_ids(count: int, generated_world: Dictionary, catalog) -> Array:
	var ids: Array = []
	var source_world: Dictionary = overworld_generated_world if not overworld_generated_world.is_empty() else generated_world
	var pool: Dictionary = source_world.get("monster_spawn_pool", {})
	var entries = pool.get("entries", [])
	if entries is Array:
		for entry in entries:
			if not entry is Dictionary:
				continue
			var monster_id := String(entry.get("monster_id", ""))
			if monster_id.is_empty() or ids.has(monster_id):
				continue
			if catalog != null and catalog.has_method("find_by_id") and catalog.find_by_id("monsters", monster_id).is_empty():
				continue
			ids.append(monster_id)
	if ids.is_empty():
		ids.append("road_bandit")
	var source_count := ids.size()
	while ids.size() < count:
		ids.append(ids[ids.size() % source_count])
	return ids.slice(0, count)

func clear_dungeon_combatants(restore_overworld := true) -> Dictionary:
	for enemy in enemy_nodes:
		if not is_instance_valid(enemy) or enemy == overworld_combat_dummy:
			continue
		if enemy.has_method("deactivate_runtime"):
			enemy.deactivate_runtime()
		else:
			enemy.visible = false
		enemy.queue_free()
	enemy_nodes.clear()
	var restored_target = null
	if restore_overworld and overworld_combat_dummy != null:
		restored_target = overworld_combat_dummy
		if restored_target.has_method("restore_after_world_transition"):
			restored_target.restore_after_world_transition(overworld_combat_dummy_state)
		else:
			restored_target.visible = bool(overworld_combat_dummy_state.get("visible", true))
		overworld_combat_dummy_state.clear()
	return {"ok": true, "combat_target": restored_target}

func _is_live_combatant(target) -> bool:
	return target != null \
		and is_instance_valid(target) \
		and target.visible \
		and target.has_method("current_hp") \
		and int(target.current_hp()) > 0
