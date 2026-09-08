extends CanvasLayer
class_name SleepTransitionPresenter

const FADE_DURATION := 0.8
const SLEEP_MESSAGE_DURATION := 2.0

var _fade_rect: ColorRect
var _sleep_label: Label
var _tween: Tween

func _ready() -> void:
	_setup_fade_rect()
	_setup_sleep_label()
	print_debug("💤 SleepTransitionPresenter ready")

func _setup_fade_rect() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

func _setup_sleep_label() -> void:
	_sleep_label = Label.new()
	_sleep_label.text = "잠을 자다..."
	_sleep_label.add_theme_font_size_override("font_size", 32)
	_sleep_label.set_anchors_preset(Control.PRESET_CENTER)
	_sleep_label.modulate.a = 0.0
	add_child(_sleep_label)

func play_sleep_transition() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)

	# Fade to black
	_tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_DURATION)
	_tween.tween_property(_sleep_label, "modulate:a", 1.0, FADE_DURATION * 0.5)

	_tween.chain()
	_tween.tween_callback(func() -> void:
		await get_tree().create_timer(SLEEP_MESSAGE_DURATION).timeout
	)

	_tween.chain()
	# Fade from black
	_tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_DURATION)
	_tween.tween_property(_sleep_label, "modulate:a", 0.0, FADE_DURATION * 0.5)

	print_debug("✓ Sleep transition completed")

func _on_tween_finished() -> void:
	_tween = null
