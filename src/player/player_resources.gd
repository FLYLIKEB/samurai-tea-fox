extends RefCounted
class_name PlayerResources

const BoundedResource = preload("res://src/player/state/bounded_resource.gd")

const HP_MAX_ID := "player_hp_max"
const KI_MAX_ID := "ki_max"
const KOKORO_MAX_ID := "kokoro_max"
const KOKORO_LOW_THRESHOLD_ID := "kokoro_low_threshold"

signal hp_changed(previous: int, current: int, maximum: int)
signal ki_changed(previous: int, current: int, maximum: int)
signal kokoro_changed(previous: int, current: int, maximum: int)
signal hp_depleted
signal ki_depleted
signal kokoro_depleted

var _hp
var _ki
var _kokoro

var hp_max: int:
	get:
		return _hp.maximum
var ki_max: int:
	get:
		return _ki.maximum
var kokoro_max: int:
	get:
		return _kokoro.maximum
var hp: int:
	get:
		return _hp.current
var ki: int:
	get:
		return _ki.current
var kokoro: int:
	get:
		return _kokoro.current
var kokoro_low_threshold: int

func _init(
	initial_hp_max: int,
	initial_ki_max: int,
	initial_kokoro_max: int,
	initial_kokoro_low_threshold: int
) -> void:
	_hp = BoundedResource.new(initial_hp_max)
	_ki = BoundedResource.new(initial_ki_max)
	_kokoro = BoundedResource.new(initial_kokoro_max)
	kokoro_low_threshold = clampi(initial_kokoro_low_threshold, 0, kokoro_max)
	_hp.changed.connect(_on_hp_changed)
	_ki.changed.connect(_on_ki_changed)
	_kokoro.changed.connect(_on_kokoro_changed)
	_hp.depleted.connect(_on_hp_depleted)
	_ki.depleted.connect(_on_ki_depleted)
	_kokoro.depleted.connect(_on_kokoro_depleted)

static func from_catalog(catalog):
	var values: Dictionary = {}
	for balance_id in [HP_MAX_ID, KI_MAX_ID, KOKORO_MAX_ID, KOKORO_LOW_THRESHOLD_ID]:
		var definition: Dictionary = catalog.find_by_id("balance", balance_id)
		if definition.is_empty() or not definition.has("value"):
			return {"ok": false, "error": "Missing required player balance value: %s" % balance_id}
		var raw_value = definition.value
		if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "error": "Player balance value must be numeric: %s" % balance_id}
		var numeric_value := float(raw_value)
		if not is_finite(numeric_value) or numeric_value != floor(numeric_value):
			return {"ok": false, "error": "Player balance value must be an integer: %s" % balance_id}
		values[balance_id] = int(numeric_value)
	if values[HP_MAX_ID] <= 0 or values[KI_MAX_ID] <= 0 or values[KOKORO_MAX_ID] <= 0:
		return {"ok": false, "error": "Player resource maximums must be positive"}
	if values[KOKORO_LOW_THRESHOLD_ID] < 0 or values[KOKORO_LOW_THRESHOLD_ID] > values[KOKORO_MAX_ID]:
		return {"ok": false, "error": "Kokoro low threshold must be within its resource bounds"}
	var resources = load("res://src/player/player_resources.gd").new(
		values[HP_MAX_ID],
		values[KI_MAX_ID],
		values[KOKORO_MAX_ID],
		values[KOKORO_LOW_THRESHOLD_ID]
	)
	return {"ok": true, "resources": resources}

func apply_damage(amount: int) -> int:
	return _hp.decrease(amount)

func heal_hp(amount: int) -> int:
	return _hp.increase(amount)

func recover_ki(amount: int) -> int:
	return _ki.increase(amount)

func spend_ki(amount: int) -> bool:
	return _ki.spend(amount)

func reduce_kokoro(amount: int) -> int:
	return _kokoro.decrease(amount)

func restore_kokoro(amount: int) -> int:
	return _kokoro.increase(amount)

func is_kokoro_low() -> bool:
	return kokoro <= kokoro_low_threshold

func sleep_until_morning() -> void:
	_kokoro.fill()

func _on_hp_changed(previous: int, current: int, maximum: int) -> void:
	hp_changed.emit(previous, current, maximum)

func _on_ki_changed(previous: int, current: int, maximum: int) -> void:
	ki_changed.emit(previous, current, maximum)

func _on_kokoro_changed(previous: int, current: int, maximum: int) -> void:
	kokoro_changed.emit(previous, current, maximum)

func _on_hp_depleted() -> void:
	hp_depleted.emit()

func _on_ki_depleted() -> void:
	ki_depleted.emit()

func _on_kokoro_depleted() -> void:
	kokoro_depleted.emit()

func to_dictionary() -> Dictionary:
	return {
		"hp": hp,
		"hp_max": hp_max,
		"ki": ki,
		"ki_max": ki_max,
		"kokoro": kokoro,
		"kokoro_max": kokoro_max,
		"kokoro_low_threshold": kokoro_low_threshold
	}
