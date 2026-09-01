extends RefCounted
class_name PlayerResources

var hp_max: int
var ki_max: int
var kokoro_max: int

var hp: int
var ki: int
var kokoro: int

func _init(initial_hp_max: int, initial_ki_max: int, initial_kokoro_max: int) -> void:
	hp_max = initial_hp_max
	ki_max = initial_ki_max
	kokoro_max = initial_kokoro_max
	hp = hp_max
	ki = ki_max
	kokoro = kokoro_max

func apply_damage(amount: int) -> void:
	hp = clampi(hp - max(amount, 0), 0, hp_max)

func recover_ki(amount: int) -> void:
	ki = clampi(ki + max(amount, 0), 0, ki_max)

func spend_ki(amount: int) -> bool:
	if amount < 0 or ki < amount:
		return false
	ki -= amount
	return true

func reduce_kokoro(amount: int) -> void:
	kokoro = clampi(kokoro - max(amount, 0), 0, kokoro_max)

func sleep_until_morning() -> void:
	kokoro = kokoro_max

func to_dictionary() -> Dictionary:
	return {
		"hp": hp,
		"hp_max": hp_max,
		"ki": ki,
		"ki_max": ki_max,
		"kokoro": kokoro,
		"kokoro_max": kokoro_max
	}

