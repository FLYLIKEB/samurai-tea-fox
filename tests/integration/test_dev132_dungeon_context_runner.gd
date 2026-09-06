extends SceneTree

const Main = preload("res://src/main/main.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const START_MODE_META := "muchau_start_mode"
const CAPTURE_PATH := "res://docs/reports/dev-132-dungeon-context/desktop_640x360.png"

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(640, 360)
	root.set_meta(START_MODE_META, "resume")
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		_failures.append("Main scene loads")
		_finish()
		return
	var main := packed_scene.instantiate() as Main
	var unique := "%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
	main.save_store = SaveStore.new(
		"user://dev132_dungeon_context_%s/run.json" % unique,
		"user://dev132_dungeon_context_%s/meta.json" % unique
	)
	root.add_child(main)
	if not await _wait_until(func(): return main.world_data != null and main.player != null and main.dungeon_runtime != null, 10000):
		_failures.append("Main runtime becomes ready")
		await _finish_with_main(main)
		return
	var entered: Dictionary = main._ensure_playable_dungeon_runtime()
	if entered.ok:
		entered = main._ensure_current_dungeon_entered()
	if not entered.ok or not main._in_dungeon_map:
		_failures.append("Main enters dungeon")
		await _finish_with_main(main)
		return
	if main.map_read_model({"reveal_all": true}).get("bounds", {}) != {"width": 12, "height": 9}:
		_failures.append("dungeon map read model uses 12x9 bounds")
	var terrain = main.world_visuals.get_node_or_null("TerrainTileMap")
	if terrain == null or not terrain.has_method("get_used_cells") or terrain.get_used_cells().is_empty():
		_failures.append("dungeon terrain replaces overworld render")
	if main._combat_targets().size() != 3:
		_failures.append("dungeon combat targets are active")
	if main.game_hud != null and main.game_hud.narrative_dialogue_visible():
		main.game_hud.hide_narrative_dialogue()
	await process_frame
	await process_frame
	await _assert_adjacent_enemy_attack(main)
	var movement_step := _walkable_step(main)
	var start_cell: Vector2i = movement_step.get("cell", Vector2i(-1, -1))
	var move_direction: Vector2i = movement_step.get("direction", Vector2i.ZERO)
	if start_cell == Vector2i(-1, -1):
		_failures.append("dungeon has a walkable movement step")
	else:
		main.player.global_position = main.world_position_for_cell_center(start_cell)
	if start_cell != Vector2i(-1, -1) and not main.player.apply_movement_command(GameCommand.new(GameCommand.Type.MOVE, move_direction)):
		_failures.append("dungeon movement command is accepted")
	elif start_cell != Vector2i(-1, -1) and not await _wait_until(func(): return main._player_world_cell() == start_cell + move_direction, 2000):
		_failures.append("dungeon movement uses dungeon walkability")
	main.player.global_position = main.world_position_for_cell_center(Vector2i(1, 1))
	if main.player.apply_movement_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.UP)):
		_failures.append("dungeon wall blocks movement")
	await process_frame
	await process_frame
	if main.game_hud != null and main.game_hud.narrative_dialogue_visible():
		main.game_hud.hide_narrative_dialogue()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		var image := root.get_texture().get_image()
		if image == null or image.save_png(CAPTURE_PATH) != OK:
			_failures.append("dungeon capture saves")
	main._return_from_dungeon_map()
	if main._in_dungeon_map:
		_failures.append("dungeon return restores overworld mode")
	if main.map_read_model({"reveal_all": true}).get("bounds", {}) == {"width": 12, "height": 9}:
		_failures.append("dungeon return restores overworld map bounds")
	await _finish_with_main(main)

func _assert_adjacent_enemy_attack(main: Main) -> void:
	var targets := main._combat_targets()
	if targets.is_empty():
		_failures.append("dungeon exposes a regular enemy for E attack")
		return
	var target = targets.front()
	var target_cell: Vector2i = main._combat_target_cell(target)
	var attack_cell := _walkable_adjacent_cell(main, target_cell)
	if attack_cell == Vector2i(-1, -1):
		_failures.append("dungeon enemy has a walkable adjacent attack cell")
		return
	main.player.global_position = main.world_position_for_cell_center(attack_cell)
	if not main._try_dungeon_interaction_from_input():
		_failures.append("E attacks an adjacent dungeon enemy")
		return
	await process_frame
	if main.combat_dummy != target:
		_failures.append("E selects the adjacent dungeon enemy as combat target")

func _walkable_adjacent_cell(main: Main, target_cell: Vector2i) -> Vector2i:
	for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var candidate: Vector2i = target_cell + direction
		if main.world_data.is_walkable(candidate):
			return candidate
	return Vector2i(-1, -1)

func _walkable_step(main: Main) -> Dictionary:
	for y in range(main.world_data.height):
		for x in range(main.world_data.width):
			var cell := Vector2i(x, y)
			if not main.world_data.is_walkable(cell):
				continue
			for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				if main.world_data.is_walkable(cell + direction):
					return {"cell": cell, "direction": direction}
	return {}

func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() <= deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

func _finish_with_main(main) -> void:
	main.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("DEV132 dungeon context integration passed: %s" % CAPTURE_PATH)
	quit(0)
