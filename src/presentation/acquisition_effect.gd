extends Node2D
class_name AcquisitionEffect

const FONT_PATH := "res://assets/fonts/galmuri/Galmuri11.ttf"
const DURATION_SECONDS := 0.65
const LABEL_RISE_PIXELS := 10.0
const PARTICLE_DIRECTIONS := [
	Vector2.UP,
	Vector2(0.707, -0.707),
	Vector2.RIGHT,
	Vector2(0.707, 0.707),
	Vector2.DOWN,
	Vector2(-0.707, 0.707),
	Vector2.LEFT,
	Vector2(-0.707, -0.707)
]

var effect_kind := "pickup"
var item_label := ""
var quantity := 0
var _elapsed_seconds := 0.0
var _caption: Label

func configure(kind: String, display_name: String, amount: int, world_position: Vector2) -> void:
	effect_kind = kind
	item_label = display_name
	quantity = maxi(amount, 0)
	position = world_position
	z_index = 20
	_ensure_caption()
	_caption.text = "%s %s x%d" % [_verb(), item_label, quantity]
	_caption.position = Vector2(-48.0, -28.0)
	_caption.modulate = Color.WHITE
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed_seconds = minf(_elapsed_seconds + maxf(delta, 0.0), DURATION_SECONDS)
	var progress := _elapsed_seconds / DURATION_SECONDS
	if _caption != null:
		_caption.position.y = roundf(-28.0 - LABEL_RISE_PIXELS * progress)
		_caption.modulate.a = clampf(1.0 - maxf(progress - 0.55, 0.0) / 0.45, 0.0, 1.0)
	queue_redraw()
	if _elapsed_seconds >= DURATION_SECONDS:
		queue_free()

func _draw() -> void:
	var progress := _elapsed_seconds / DURATION_SECONDS
	var burst_progress := minf(progress / 0.72, 1.0)
	var radius := roundf(3.0 + 11.0 * burst_progress)
	var alpha := clampf(1.0 - maxf(progress - 0.38, 0.0) / 0.62, 0.0, 1.0)
	var color := _effect_color()
	color.a = alpha
	for direction in PARTICLE_DIRECTIONS:
		var particle_position: Vector2 = (Vector2(direction) * radius).round()
		draw_rect(Rect2(particle_position - Vector2.ONE, Vector2(2.0, 2.0)), color)
	if progress < 0.35:
		draw_arc(Vector2.ZERO, roundf(4.0 + progress * 12.0), 0.0, TAU, 12, color, 1.0, false)

func _ensure_caption() -> void:
	if _caption != null:
		return
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.size = Vector2(96.0, 16.0)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.add_theme_color_override("font_color", _effect_color())
	_caption.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 1.0))
	_caption.add_theme_constant_override("outline_size", 1)
	var font := ResourceLoader.load(FONT_PATH) as Font
	if font is FontFile:
		var font_file := font as FontFile
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if font != null:
		_caption.add_theme_font_override("font", font)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

func _verb() -> String:
	return "채집" if effect_kind == "gatherable" else "획득"

func _effect_color() -> Color:
	return Color(0.59, 0.60, 0.28, 1.0) if effect_kind == "gatherable" else Color(0.84, 0.65, 0.36, 1.0)
