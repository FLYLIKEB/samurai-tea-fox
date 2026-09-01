extends RefCounted
class_name TimeConfig

const DAY_DURATION_ID := "day_phase_duration_seconds"
const DUSK_DURATION_ID := "dusk_phase_duration_seconds"
const NIGHT_DURATION_ID := "night_phase_duration_seconds"
const LATE_NIGHT_DURATION_ID := "late_night_phase_duration_seconds"
const DUSK_KOKORO_DECAY_ID := "dusk_kokoro_decay_per_second"
const NIGHT_KOKORO_DECAY_ID := "night_kokoro_decay_per_second"
const LATE_NIGHT_KOKORO_DECAY_ID := "late_night_kokoro_decay_per_second"
const LOW_KOKORO_ABILITY_COST_INCREASE_ID := "low_kokoro_ability_cost_increase"
const SLEEP_HEAL_RATIO_ID := "safe_sleep_hp_recovery_ratio"

var day_phase_duration_seconds: float
var dusk_phase_duration_seconds: float
var night_phase_duration_seconds: float
var late_night_phase_duration_seconds: float
var dusk_kokoro_decay_per_second: float
var night_kokoro_decay_per_second: float
var late_night_kokoro_decay_per_second: float
var low_kokoro_ability_cost_increase_percent: float
var sleep_heal_ratio: float

func _init(values := {}) -> void:
	day_phase_duration_seconds = float(values.day_phase_duration_seconds)
	dusk_phase_duration_seconds = float(values.dusk_phase_duration_seconds)
	night_phase_duration_seconds = float(values.night_phase_duration_seconds)
	late_night_phase_duration_seconds = float(values.late_night_phase_duration_seconds)
	dusk_kokoro_decay_per_second = float(values.dusk_kokoro_decay_per_second)
	night_kokoro_decay_per_second = float(values.night_kokoro_decay_per_second)
	late_night_kokoro_decay_per_second = float(values.late_night_kokoro_decay_per_second)
	low_kokoro_ability_cost_increase_percent = float(values.low_kokoro_ability_cost_increase_percent)
	sleep_heal_ratio = float(values.sleep_heal_ratio)

static func from_catalog(catalog) -> Dictionary:
	var values := {}
	var balance_fields := {
		DAY_DURATION_ID: "day_phase_duration_seconds",
		DUSK_DURATION_ID: "dusk_phase_duration_seconds",
		NIGHT_DURATION_ID: "night_phase_duration_seconds",
		LATE_NIGHT_DURATION_ID: "late_night_phase_duration_seconds",
		DUSK_KOKORO_DECAY_ID: "dusk_kokoro_decay_per_second",
		NIGHT_KOKORO_DECAY_ID: "night_kokoro_decay_per_second",
		LATE_NIGHT_KOKORO_DECAY_ID: "late_night_kokoro_decay_per_second",
		LOW_KOKORO_ABILITY_COST_INCREASE_ID: "low_kokoro_ability_cost_increase_percent",
		SLEEP_HEAL_RATIO_ID: "sleep_heal_ratio"
	}
	for id in balance_fields.keys():
		var required_value := _required_balance_value(catalog, id)
		if not required_value.ok:
			return required_value
		values[balance_fields[id]] = required_value.value

	for field in [
		"day_phase_duration_seconds",
		"dusk_phase_duration_seconds",
		"night_phase_duration_seconds",
		"late_night_phase_duration_seconds"
	]:
		if float(values[field]) <= 0.0:
			return {"ok": false, "error": "Time phase durations must be positive: %s" % field}

	for field in [
		"dusk_kokoro_decay_per_second",
		"night_kokoro_decay_per_second",
		"late_night_kokoro_decay_per_second",
		"low_kokoro_ability_cost_increase_percent"
	]:
		if float(values[field]) < 0.0:
			return {"ok": false, "error": "Time balance values must be non-negative: %s" % field}

	if not (
		0.0 < float(values.dusk_kokoro_decay_per_second)
		and float(values.dusk_kokoro_decay_per_second) < float(values.night_kokoro_decay_per_second)
		and float(values.night_kokoro_decay_per_second) < float(values.late_night_kokoro_decay_per_second)
	):
		return {"ok": false, "error": "Kokoro decay rates must increase by phase: dusk < night < late_night"}

	if float(values.sleep_heal_ratio) < 0.0 or float(values.sleep_heal_ratio) > 1.0:
		return {"ok": false, "error": "Sleep heal ratio must be between 0 and 1"}

	return {"ok": true, "config": load("res://src/time/time_config.gd").new(values)}

func ability_cost_multiplier_for(resources) -> float:
	if resources.is_kokoro_low():
		return 1.0 + (low_kokoro_ability_cost_increase_percent / 100.0)
	return 1.0

func phase_duration_seconds(phase: StringName) -> float:
	match phase:
		&"day":
			return day_phase_duration_seconds
		&"dusk":
			return dusk_phase_duration_seconds
		&"night":
			return night_phase_duration_seconds
		&"late_night":
			return late_night_phase_duration_seconds
		_:
			return 0.0

func kokoro_decay_per_second(phase: StringName) -> float:
	match phase:
		&"dusk":
			return dusk_kokoro_decay_per_second
		&"night":
			return night_kokoro_decay_per_second
		&"late_night":
			return late_night_kokoro_decay_per_second
		_:
			return 0.0

static func _required_balance_value(catalog, id: String) -> Dictionary:
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return {"ok": false, "error": "Missing required time balance value: %s" % id}
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "Time balance value must be numeric: %s" % id}
	var numeric_value := float(value)
	if not is_finite(numeric_value):
		return {"ok": false, "error": "Time balance value must be finite: %s" % id}
	return {"ok": true, "value": numeric_value}
