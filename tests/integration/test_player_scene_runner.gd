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
	elif sprite.texture.resource_path != "res://assets/sprites/characters/fox_samurai/fox_samurai_front_idle_32x32.png":
		failures.append("player scene starts with the manifest front-facing asset")
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null or not camera.enabled:
		failures.append("player owns an enabled camera")

	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16.0, 64.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = Vector2(24.0, 0.0)
	root.add_child(wall)

	player.position = Vector2.ZERO
	player.submit_command(GameCommand.new(GameCommand.Type.MOVE, Vector2i.RIGHT))
	await physics_frame
	await physics_frame
	if sprite.texture.resource_path != "res://assets/sprites/characters/fox_samurai/fox_samurai_right_idle_32x32.png":
		failures.append("player movement resolves the right-facing stable asset ID")
	for _index in 38:
		await physics_frame

	if player.position.x < 1.0:
		failures.append("player advances when a movement command is submitted")
	elif player.position.x > 10.1:
		failures.append("player does not pass through a wall")

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
