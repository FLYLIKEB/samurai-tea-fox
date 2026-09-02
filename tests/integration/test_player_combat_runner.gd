extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")

var failures: Array[String] = []

class TailQuery:
	extends RefCounted
	var tail_count: int
	var calls: Array = []

	func _init(initial_tail_count: int) -> void:
		tail_count = initial_tail_count

	func can_use_ability(ability_id: String, tail_requirement: int) -> bool:
		calls.append([ability_id, tail_requirement])
		return tail_count >= tail_requirement

class AbilityTimeProbe:
	extends RefCounted
	var calls := 0

	func ability_cost_multiplier_for(resources) -> float:
		calls += 1
		return 1.25 if resources.is_kokoro_low() else 1.0

class AbilityTargetQuery:
	extends RefCounted
	var target
	var calls: Array = []

	func _init(initial_target) -> void:
		target = initial_target

	func targets_for_ability(source, definition, direction: Vector2) -> Array:
		calls.append([source.get_combat_id(), definition.id, direction])
		return [target]

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

	var ability_tail_query := TailQuery.new(1)
	var ability_time_probe := AbilityTimeProbe.new()
	var ability_target_query := AbilityTargetQuery.new(dummy)
	player.configure_ability_context(ability_tail_query, ability_time_probe, ability_target_query)
	var equip_result: Dictionary = player.equip_ability(0, "ember")
	if not equip_result.ok:
		failures.append("player equips ability through injected tail query")
	player.resources.reduce_kokoro(70)
	player.resources.spend_ki(82)
	var ability_hp_before: int = dummy.current_hp()
	if not player.submit_command(GameCommand.new(GameCommand.Type.CAST_ABILITY, Vector2i.RIGHT, 0)):
		failures.append("cast ability command is accepted with injected context")
	if dummy.current_hp() != ability_hp_before - 20:
		failures.append("cast ability target query passes a target to the damage strategy")
	if player.resources.ki != 0:
		failures.append("cast ability receives time-state low-kokoro cost multiplier")
	if ability_tail_query.calls.size() < 2:
		failures.append("injected tail query is used for both equip and cast")
	if ability_time_probe.calls != 1:
		failures.append("cast ability passes time_state into cost calculation")
	if ability_target_query.calls.is_empty() or ability_target_query.calls[0][1] != "ember":
		failures.append("public ability target query receives the selected definition")
	player.ability_runtime.tick(4.0)
	player.resources.recover_ki(player.resources.ki_max)
	player.resources.restore_kokoro(player.resources.kokoro_max)

	player.position = Vector2.ZERO
	dummy.position = Vector2(32.0, 0.0)
	var dummy_hp_before: int = dummy.current_hp()
	var dummy_hit_count_before: int = dummy.received_hit_count()
	if not player.submit_command(GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)):
		failures.append("attack command is accepted")
	await physics_frame
	await physics_frame
	if dummy.current_hp() >= dummy_hp_before:
		failures.append("attack command damages a generic combat dummy")
	if dummy.received_hit_count() != dummy_hit_count_before + 1:
		failures.append("one swing damages the same dummy only once")
	if dummy.get("_hit_effect_remaining") <= 0.0:
		failures.append("monster hit starts a visible hit flash effect")
	var dummy_sprite := dummy.get_node_or_null("Sprite2D") as Sprite2D
	if dummy_sprite != null and dummy_sprite.modulate == Color.WHITE:
		failures.append("monster hit flash tints the promoted sprite")
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
		dummy.combatant.hp = dummy.combatant.hp_max
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

	dummy.automatic_attacks = true
	dummy.position = Vector2(160.0, 0.0)
	player.position = Vector2.ZERO
	var monster_steps: Array = []
	dummy.grid_step_started.connect(func(from_cell: Vector2i, to_cell: Vector2i): monster_steps.append([from_cell, to_cell]))
	for _frame in 180:
		await physics_frame
	if monster_steps.is_empty():
		failures.append("automatic monster movement starts as cardinal grid steps")
	elif monster_steps[0][0] != Vector2i(5, 0) or monster_steps[0][1] != Vector2i(4, 0):
		failures.append("automatic monster movement targets one adjacent tile toward the player")
	if absf(fmod(absf(dummy.position.x), 32.0)) > 0.6 and absf(fmod(absf(dummy.position.x), 32.0) - 32.0) > 0.6:
		failures.append("automatic monster movement remains aligned to tile units")
	dummy.automatic_attacks = false

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
