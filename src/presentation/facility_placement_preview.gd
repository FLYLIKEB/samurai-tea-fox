extends Node2D
class_name FacilityPlacementPreview

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")

var origin := Vector2i(-1, -1)
var footprint := Vector2i.ONE
var tile_size := RuntimeConstants.float_value("world.tile_size_pixels")
var valid := false
var sprite: Sprite2D

func configure(next_origin: Vector2i, next_footprint: Vector2i, next_tile_size: float, next_valid: bool, texture: Texture2D, rotation_quarter_turns: int) -> void:
	origin = next_origin
	tile_size = next_tile_size
	footprint = _visual_footprint(next_footprint, texture, rotation_quarter_turns)
	valid = next_valid
	_ensure_sprite()
	sprite.texture = texture
	sprite.visible = texture != null
	sprite.position = Vector2(origin) * tile_size + Vector2(footprint) * tile_size * 0.5
	sprite.rotation = float(rotation_quarter_turns) * PI * 0.5
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.58) if valid else Color(1.0, 0.32, 0.28, 0.58)
	queue_redraw()

func clear() -> void:
	origin = Vector2i(-1, -1)
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _ensure_sprite() -> void:
	if sprite != null:
		return
	sprite = Sprite2D.new()
	sprite.name = "FacilityGhostSprite"
	sprite.centered = true
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.58)
	add_child(sprite)

func _draw() -> void:
	if origin.x < 0 or origin.y < 0:
		return
	var fill := Color(0.20, 0.78, 0.34, 0.28) if valid else Color(0.88, 0.12, 0.10, 0.38)
	var outline := Color(0.40, 1.0, 0.48, 0.95) if valid else Color(1.0, 0.18, 0.12, 0.95)
	for y in range(footprint.y):
		for x in range(footprint.x):
			var rect := Rect2(Vector2(origin + Vector2i(x, y)) * tile_size, Vector2.ONE * tile_size)
			draw_rect(rect, fill, true)
			draw_rect(rect, outline, false, 2.0)

func _visual_footprint(defined_footprint: Vector2i, texture: Texture2D, rotation_quarter_turns: int) -> Vector2i:
	if texture == null or tile_size <= 0.0:
		return defined_footprint
	var texture_size := texture.get_size()
	if absi(rotation_quarter_turns) % 2 == 1:
		texture_size = Vector2(texture_size.y, texture_size.x)
	return Vector2i(
		maxi(defined_footprint.x, ceili(texture_size.x / tile_size)),
		maxi(defined_footprint.y, ceili(texture_size.y / tile_size))
	)
