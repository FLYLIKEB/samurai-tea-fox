extends RefCounted

const WorldToneOverlay = preload("res://src/ui/world_tone_overlay.gd")

class FakeTimeState:
	signal phase_changed(previous: StringName, current: StringName)

	var phase: StringName = &"day"

	func advance_to(next_phase: StringName) -> void:
		var previous := phase
		phase = next_phase
		phase_changed.emit(previous, phase)

func run(asserts) -> void:
	_assert_phase_presets_are_distinct(asserts)
	_assert_overlay_ignores_input_and_initializes_day(asserts)
	_assert_configure_observes_time_projection(asserts)

func _assert_phase_presets_are_distinct(asserts) -> void:
	var day := WorldToneOverlay.tone_color_for_phase(&"day")
	var dusk := WorldToneOverlay.tone_color_for_phase(&"dusk")
	var night := WorldToneOverlay.tone_color_for_phase(&"night")
	var late_night := WorldToneOverlay.tone_color_for_phase(&"late_night")
	asserts.true_value(day != dusk, "day and dusk use different world tone presets")
	asserts.true_value(dusk != night, "dusk and night use different world tone presets")
	asserts.true_value(night != late_night, "night and late night use different world tone presets")
	asserts.true_value(day.a < dusk.a and dusk.a < night.a and night.a < late_night.a, "world tone alpha increases from day to late night")

func _assert_overlay_ignores_input_and_initializes_day(asserts) -> void:
	var overlay := WorldToneOverlay.new()
	var rect := overlay.tone_rect()
	asserts.equal(overlay.layer, 0, "world tone overlay renders on the world layer below HUD CanvasLayer")
	asserts.equal(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "world tone overlay does not block pointer input")
	asserts.equal(rect.focus_mode, Control.FOCUS_NONE, "world tone overlay cannot steal focus")
	asserts.equal(rect.color, WorldToneOverlay.tone_color_for_phase(&"day"), "world tone overlay initializes with the day preset")
	asserts.true_value(overlay.fade_duration_seconds > 0.0, "world tone overlay keeps phase changes as a short fade")

func _assert_configure_observes_time_projection(asserts) -> void:
	var state := FakeTimeState.new()
	state.phase = &"night"
	var overlay := WorldToneOverlay.new()
	overlay.configure(state)
	asserts.equal(overlay.tone_rect().color, WorldToneOverlay.tone_color_for_phase(&"night"), "world tone overlay reads the initial time phase projection")
	state.advance_to(&"late_night")
	asserts.equal(overlay.tone_rect().color, WorldToneOverlay.tone_color_for_phase(&"late_night"), "world tone overlay observes phase changes without mutating time state")
