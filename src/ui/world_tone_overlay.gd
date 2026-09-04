extends CanvasLayer
class_name WorldToneOverlay

const PHASE_DAY := &"day"
const PHASE_DUSK := &"dusk"
const PHASE_NIGHT := &"night"
const PHASE_LATE_NIGHT := &"late_night"
const TONE_RECT_NAME := "ToneRect"

@export var fade_duration_seconds := 0.28

var time_state
var _tone_rect: ColorRect
var _active_tween: Tween
var _current_phase := PHASE_DAY

func _init() -> void:
	layer = 0

func _ready() -> void:
	_ensure_tone_rect()
	set_phase(_current_phase, false)

func configure(next_time_state) -> void:
	if time_state != null and time_state.has_signal("phase_changed"):
		var previous_callback := Callable(self, "_on_phase_changed")
		if time_state.is_connected("phase_changed", previous_callback):
			time_state.disconnect("phase_changed", previous_callback)
	time_state = next_time_state
	if time_state != null:
		_current_phase = StringName(_object_property(time_state, "phase", String(PHASE_DAY)))
		if time_state.has_signal("phase_changed"):
			var callback := Callable(self, "_on_phase_changed")
			if not time_state.is_connected("phase_changed", callback):
				time_state.connect("phase_changed", callback)
	set_phase(_current_phase, false)

func set_phase(phase: StringName, animated := true) -> void:
	_current_phase = phase
	_ensure_tone_rect()
	var target_color := tone_color_for_phase(phase)
	if _active_tween != null:
		_active_tween.kill()
		_active_tween = null
	if animated and is_inside_tree() and fade_duration_seconds > 0.0:
		_active_tween = create_tween()
		_active_tween.tween_property(_tone_rect, "color", target_color, fade_duration_seconds)
		return
	_tone_rect.color = target_color

static func tone_color_for_phase(phase: StringName) -> Color:
	match phase:
		PHASE_DUSK:
			return Color(0.86, 0.43, 0.16, 0.11)
		PHASE_NIGHT:
			return Color(0.05, 0.08, 0.22, 0.18)
		PHASE_LATE_NIGHT:
			return Color(0.02, 0.03, 0.12, 0.24)
		_:
			return Color(1.0, 0.92, 0.68, 0.025)

func tone_rect() -> ColorRect:
	_ensure_tone_rect()
	return _tone_rect

func _ensure_tone_rect() -> void:
	if _tone_rect != null:
		return
	_tone_rect = get_node_or_null(TONE_RECT_NAME) as ColorRect
	if _tone_rect == null:
		_tone_rect = ColorRect.new()
		_tone_rect.name = TONE_RECT_NAME
		add_child(_tone_rect)
		_tone_rect.color = tone_color_for_phase(_current_phase)
	_tone_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tone_rect.offset_left = 0.0
	_tone_rect.offset_top = 0.0
	_tone_rect.offset_right = 0.0
	_tone_rect.offset_bottom = 0.0
	_tone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tone_rect.focus_mode = Control.FOCUS_NONE

func _on_phase_changed(_previous: StringName, current: StringName) -> void:
	set_phase(current, true)

func _object_property(object, property_name: String, default_value = null):
	if object == null:
		return default_value
	for property in object.get_property_list():
		if String(property.name) == property_name:
			return object.get(property_name)
	return default_value
