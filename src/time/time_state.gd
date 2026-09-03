extends RefCounted
class_name TimeState

const TimeConfig = preload("res://src/time/time_config.gd")

const DAY := &"day"
const DUSK := &"dusk"
const NIGHT := &"night"
const LATE_NIGHT := &"late_night"

const PHASE_ORDER := [DAY, DUSK, NIGHT, LATE_NIGHT]

signal phase_changed(previous: StringName, current: StringName)

var config: TimeConfig
var phase: StringName = DAY
var phase_elapsed_seconds := 0.0
var _kokoro_decay_carry := 0.0

func _init(initial_config: TimeConfig) -> void:
	config = initial_config

func tick(delta_seconds: float, resources) -> void:
	var remaining_delta := maxf(delta_seconds, 0.0)
	while remaining_delta > 0.0:
		var remaining_in_phase := config.phase_duration_seconds(phase) - phase_elapsed_seconds
		var step := minf(remaining_delta, remaining_in_phase)
		_apply_kokoro_decay(step, resources)
		phase_elapsed_seconds += step
		remaining_delta -= step
		if phase_elapsed_seconds >= config.phase_duration_seconds(phase):
			_advance_phase()

func sleep_until_morning(resources) -> Dictionary:
	var previous_phase := phase
	phase = DAY
	phase_elapsed_seconds = 0.0
	_kokoro_decay_carry = 0.0
	if previous_phase != phase:
		phase_changed.emit(previous_phase, phase)

	var kokoro_restored: int = resources.restore_kokoro(resources.kokoro_max)
	var hp_to_heal := int(floor(resources.hp_max * config.sleep_heal_ratio))
	var hp_healed: int = resources.heal_hp(hp_to_heal)
	return {
		"phase": phase,
		"kokoro_restored": kokoro_restored,
		"hp_healed": hp_healed
	}

func to_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"phase": String(phase),
		"phase_elapsed_seconds": phase_elapsed_seconds,
		"kokoro_decay_carry": _kokoro_decay_carry
	}

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	var loaded_phase := StringName(String(snapshot.get("phase", String(DAY))))
	if not PHASE_ORDER.has(loaded_phase):
		return {"ok": false, "reason": "invalid_time_phase", "error": "Saved time phase is invalid: %s" % String(loaded_phase)}
	var duration := config.phase_duration_seconds(loaded_phase)
	var elapsed := float(snapshot.get("phase_elapsed_seconds", 0.0))
	if not is_finite(elapsed) or elapsed < 0.0 or elapsed >= duration:
		return {"ok": false, "reason": "invalid_time_elapsed", "error": "Saved time phase elapsed value is invalid."}
	var carry := float(snapshot.get("kokoro_decay_carry", 0.0))
	if not is_finite(carry) or carry < 0.0:
		return {"ok": false, "reason": "invalid_time_decay_carry", "error": "Saved time decay carry is invalid."}
	var previous := phase
	phase = loaded_phase
	phase_elapsed_seconds = elapsed
	_kokoro_decay_carry = carry
	if previous != phase:
		phase_changed.emit(previous, phase)
	return {"ok": true, "snapshot": to_snapshot()}

func ability_cost_multiplier_for(resources) -> float:
	return config.ability_cost_multiplier_for(resources)

func _apply_kokoro_decay(seconds: float, resources) -> void:
	var decay_per_second := config.kokoro_decay_per_second(phase)
	if decay_per_second <= 0.0 or seconds <= 0.0:
		return
	_kokoro_decay_carry += decay_per_second * seconds
	var whole_decay := int(floor(_kokoro_decay_carry))
	if whole_decay <= 0:
		return
	var applied: int = resources.reduce_kokoro(whole_decay)
	_kokoro_decay_carry -= whole_decay
	if applied < whole_decay:
		_kokoro_decay_carry = 0.0

func _advance_phase() -> void:
	var previous := phase
	var index := PHASE_ORDER.find(phase)
	phase = PHASE_ORDER[(index + 1) % PHASE_ORDER.size()]
	phase_elapsed_seconds = 0.0
	if phase == DAY:
		_kokoro_decay_carry = 0.0
	phase_changed.emit(previous, phase)
