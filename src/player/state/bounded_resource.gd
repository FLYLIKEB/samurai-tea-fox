extends RefCounted
class_name BoundedResource

signal changed(previous: int, current: int, maximum: int)
signal depleted

var _maximum: int
var _current: int

var maximum: int:
	get:
		return _maximum
var current: int:
	get:
		return _current

func _init(initial_maximum: int, initial_current = null) -> void:
	_maximum = maxi(initial_maximum, 0)
	_current = maximum if initial_current == null else clampi(int(initial_current), 0, maximum)

func increase(amount: int) -> int:
	if amount <= 0:
		return 0
	var applied := mini(amount, maximum - current)
	_set_current(current + applied)
	return applied

func decrease(amount: int) -> int:
	if amount <= 0:
		return 0
	var applied := mini(amount, current)
	_set_current(current - applied)
	return applied

func spend(amount: int) -> bool:
	if amount < 0 or amount > current:
		return false
	_set_current(current - amount)
	return true

func fill() -> int:
	return increase(maximum - current)

func _set_current(value: int) -> void:
	var previous := current
	_current = clampi(value, 0, maximum)
	if current == previous:
		return
	changed.emit(previous, current, maximum)
	if previous > 0 and current == 0:
		depleted.emit()
