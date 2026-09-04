extends SceneTree

const CombatConfig = preload("res://src/combat/combat_config.gd")
const CombatDummy = preload("res://src/combat/combat_dummy.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const Main = preload("res://src/main/main.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var target := Node2D.new()
	target.name = "Target"
	target.global_position = Vector2.ZERO
	root.add_child(target)

	var dummy := _combat_dummy()
	root.add_child(dummy)
	await process_frame

	var catalog := DataCatalog.new()
	var catalog_result: Dictionary = catalog.load_from_directory("res://data/generated")
	if not catalog_result.ok:
		failures.append("generated catalog loads for enemy interpolation test")
		_finish(dummy, target)
		return
	var configured: Dictionary = dummy.configure_combat(catalog, target, _combat_config())
	if not configured.ok:
		failures.append("combat dummy configures from generated monster data: %s" % configured.get("error", "unknown"))
		_finish(dummy, target)
		return

	var start_cell := Vector2i(5, 0)
	var destination_cell := Vector2i(4, 0)
	var tile_size := 32.0
	dummy.configure_grid_navigation(null, Vector2.ZERO, tile_size)
	dummy.global_position = Vector2(float(start_cell.x) * tile_size, float(start_cell.y) * tile_size)
	target.global_position = Vector2.ZERO

	var started_steps: Array = []
	var finished_steps: Array = []
	dummy.grid_step_started.connect(func(from_cell: Vector2i, to_cell: Vector2i): started_steps.append([from_cell, to_cell]))
	dummy.grid_step_finished.connect(func(cell: Vector2i): finished_steps.append(cell))

	var turn_result: Dictionary = dummy.take_turn(target)
	if not bool(turn_result.get("ok", false)) or String(turn_result.get("action", "")) != "move":
		failures.append("enemy turn resolves as a move when target is outside attack range")
	if started_steps != [[start_cell, destination_cell]]:
		failures.append("enemy turn starts exactly one cardinal grid step")
	if turn_result.get("cell", Vector2i.ZERO) != destination_cell:
		failures.append("enemy move result reports the destination logical cell")
	if dummy.current_grid_cell() != destination_cell:
		failures.append("enemy logical cell advances before presentation tween finishes")

	var source_position := Vector2(float(start_cell.x) * tile_size, 0.0)
	var destination_position := Vector2(float(destination_cell.x) * tile_size, 0.0)
	if dummy.global_position != source_position:
		failures.append("enemy visual position stays on the source tile when the turn resolves")
	if not dummy.is_grid_step_active():
		failures.append("enemy movement presentation tween becomes active")

	var main := Main.new()
	main.combat_dummy = dummy
	var snapshot: Dictionary = main._snapshot_overworld_enemy_state()
	var saved_cell := Vector2i(int(snapshot.get("cell", {}).get("x", -1)), int(snapshot.get("cell", {}).get("y", -1)))
	if saved_cell != destination_cell:
		failures.append("main enemy snapshot records the logical destination during interpolation")
	main.free()

	if dummy.get("_grid_step_tween") != null:
		dummy.get("_grid_step_tween").custom_step(0.05)
	if dummy.global_position == source_position or dummy.global_position == destination_position:
		failures.append("enemy visual position interpolates between source and destination during tween")

	var repeated_turn: Dictionary = dummy.take_turn(target)
	if String(repeated_turn.get("reason", "")) != "grid_step_active":
		failures.append("enemy ignores repeated turn commands while movement tween is active")
	if dummy.global_position == destination_position:
		failures.append("repeated turn command does not snap the enemy to the destination")

	await create_timer(0.25).timeout
	if dummy.is_grid_step_active():
		failures.append("enemy movement tween eventually finishes")
	if dummy.global_position != destination_position:
		failures.append("enemy presentation tween ends on the destination tile center")
	if finished_steps != [destination_cell]:
		failures.append("enemy movement emits one finished signal for the destination cell")

	_finish(dummy, target)

func _combat_dummy() -> CombatDummy:
	var dummy := CombatDummy.new()
	dummy.name = "CombatDummy"
	dummy.automatic_attacks = false
	dummy.attack_range_pixels = 16.0
	dummy.add_child(Sprite2D.new())
	dummy.get_child(0).name = "Sprite2D"
	var body := Polygon2D.new()
	body.name = "Body"
	dummy.add_child(body)
	var headband := Polygon2D.new()
	headband.name = "Headband"
	dummy.add_child(headband)
	var health_fill := Polygon2D.new()
	health_fill.name = "HealthFill"
	dummy.add_child(health_fill)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(14.0, 18.0)
	shape.shape = rectangle
	dummy.add_child(shape)
	return dummy

func _combat_config() -> CombatConfig:
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

func _finish(dummy: Node, target: Node) -> void:
	dummy.queue_free()
	target.queue_free()
	if failures.is_empty():
		print("Enemy move interpolation integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
