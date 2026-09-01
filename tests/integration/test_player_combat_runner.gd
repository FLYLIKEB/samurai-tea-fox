extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		failures.append("main scene loads")
		finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	var player = main.get_node("Player")
	var dummy = main.get_node("CombatDummy")
	dummy.automatic_attacks = false

	if player.combat_state == null or dummy.combatant == null:
		failures.append("main scene configures player and dummy combat from generated data")
		main.queue_free()
		finish()
		return

	player.position = Vector2.ZERO
	dummy.position = Vector2(32.0, 0.0)
	var dummy_hp_before: int = dummy.current_hp()
	if not player.submit_command(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)):
		failures.append("attack command is accepted")
	await physics_frame
	await physics_frame
	if dummy.current_hp() >= dummy_hp_before:
		failures.append("attack command damages a generic combat dummy")
	if dummy.received_hit_count() != 1:
		failures.append("one swing damages the same dummy only once")
	var directional_cases := [
		[Vector2i.UP, Vector2(0.0, -32.0)],
		[Vector2i.LEFT, Vector2(-32.0, 0.0)],
		[Vector2i.DOWN, Vector2(0.0, 32.0)]
	]
	var knockback_wall := StaticBody2D.new()
	var knockback_wall_shape := CollisionShape2D.new()
	var knockback_rectangle := RectangleShape2D.new()
	knockback_rectangle.size = Vector2(8.0, 64.0)
	knockback_wall_shape.shape = knockback_rectangle
	knockback_wall.add_child(knockback_wall_shape)
	knockback_wall.position = Vector2(-52.0, 0.0)
	root.add_child(knockback_wall)
	for directional_case in directional_cases:
		player.combat_state.tick(1.0)
		dummy.position = directional_case[1]
		var position_before: Vector2 = dummy.position
		await physics_frame
		var hit_count_before: int = dummy.received_hit_count()
		if not player.submit_command(GameCommand.new(GameCommand.Type.ATTACK, directional_case[0])):
			failures.append("attack command is accepted for direction %s" % directional_case[0])
		await physics_frame
		await physics_frame
		if dummy.received_hit_count() != hit_count_before + 1:
			failures.append("attack collision resolves for direction %s" % directional_case[0])
		if directional_case[0] == Vector2i.LEFT and dummy.position.x >= position_before.x:
			failures.append("third combo hit applies collision-aware finisher knockback")
		if directional_case[0] == Vector2i.LEFT and dummy.position.x < -41.1:
			failures.append("finisher knockback does not pass through a wall")

	var player_hp_before: int = player.resources.hp
	if dummy.attack_target(player) != 10 or player.resources.hp != player_hp_before - 10:
		failures.append("dummy attack applies exported monster damage to player HP")
	player.resources.heal_hp(player.resources.hp_max)

	if not player.submit_command(GameCommand.new(GameCommand.Type.DODGE, Vector2i.LEFT)):
		failures.append("dodge command is accepted off cooldown")
	if dummy.attack_target(player) != 0 or player.resources.hp != player.resources.hp_max:
		failures.append("dodge invulnerability prevents incoming damage")
	if player.submit_command(GameCommand.new(GameCommand.Type.DODGE, Vector2i.LEFT)):
		failures.append("dodge command is rejected during cooldown")

	for _frame in 20:
		await physics_frame
	var hp_before_hit_invulnerability: int = player.resources.hp
	if dummy.attack_target(player, 0.2) != 10:
		failures.append("player receives damage after dodge invulnerability expires")
	if dummy.attack_target(player, 0.2) != 0 or player.resources.hp != hp_before_hit_invulnerability - 10:
		failures.append("hit invulnerability blocks repeated damage events")

	player.combat_state.tick(1.0)
	player.position = Vector2.ZERO
	dummy.position = Vector2(160.0, 0.0)
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16.0, 64.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = Vector2(-30.0, 0.0)
	root.add_child(wall)
	if not player.submit_command(GameCommand.new(GameCommand.Type.DODGE, Vector2i.LEFT)):
		failures.append("dodge is ready after configured cooldown")
	for _frame in 20:
		await physics_frame
	if player.position.x >= -1.0:
		failures.append("dodge moves in the requested direction")
	if player.position.x < -16.1:
		failures.append("dodge movement does not pass through a wall")

	main.queue_free()
	wall.queue_free()
	knockback_wall.queue_free()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("Player combat integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
