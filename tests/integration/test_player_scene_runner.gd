extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed_scene := load("res://scenes/actors/player.tscn") as PackedScene
	if packed_scene == null:
		failures.append("player scene loads")
		finish()
		return

	var player := packed_scene.instantiate() as CharacterBody2D
	if player == null:
		failures.append("player scene instantiates as CharacterBody2D")
		finish()
		return
	root.add_child(player)
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		failures.append("player scene resolves the front sprite through the asset manifest")
	elif player._current_sprite_asset_id != "fox_samurai_front_idle":
		failures.append("player scene starts with the manifest front-facing asset")
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null or not camera.enabled:
		failures.append("player owns an enabled camera")

	player.position = Vector2.ZERO
	var started_steps: Array = []
	player.grid_step_started.connect(func(from_cell: Vector2i, to_cell: Vector2i): started_steps.append([from_cell, to_cell]))
	player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.RIGHT))
	await physics_frame
	await physics_frame
	if sprite.texture == null or player._current_sprite_asset_id != "chr_8_fox_samurai_walk":
		failures.append("player movement switches to the stable walk asset ID")
	elif Vector2i(sprite.hframes, sprite.vframes) != Vector2i(8, 4) or sprite.frame_coords.y != 2:
		failures.append("player movement selects the east row of the 8x4 walk sheet")
	player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	for _index in 28:
		await physics_frame
	if started_steps.is_empty() or started_steps[0] != [Vector2i.ZERO, Vector2i.RIGHT]:
		failures.append("player starts movement as one cardinal grid step")
	if absf(player.position.x - 32.0) > 0.6 or absf(player.position.y) > 0.6:
		failures.append("player movement finishes on the next tile center")
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16.0, 64.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = Vector2(56.0, 0.0)
	root.add_child(wall)

	player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.RIGHT))
	for _index in 28:
		await physics_frame

	if absf(player.position.x - 32.0) > 0.6:
		failures.append("blocked grid movement keeps the player on the source tile")
	elif player.position.x > 42.1:
		failures.append("blocked grid movement does not pass through a wall")

	player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.ZERO))
	await physics_frame
	if player._current_sprite_asset_id != "fox_samurai_right_idle":
		failures.append("player stopping restores the last facing idle asset")
	elif Vector2i(sprite.hframes, sprite.vframes) != Vector2i.ONE:
		failures.append("player stopping restores a single-frame sprite")

	player.queue_free()
	wall.queue_free()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("Player scene integration passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
