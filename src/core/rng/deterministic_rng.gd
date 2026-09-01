extends RefCounted
class_name DeterministicRng

const MODULUS := 2147483648
const MULTIPLIER := 1103515245
const INCREMENT := 12345

var state: int

func _init(seed_value: int) -> void:
	state = seed_value % MODULUS
	if state <= 0:
		state = 1

func next_u32() -> int:
	state = int((MULTIPLIER * state + INCREMENT) % MODULUS)
	return state

func next_range(min_value: int, max_value: int) -> int:
	if max_value < min_value:
		push_error("Invalid deterministic range.")
		return min_value
	var width := max_value - min_value + 1
	return min_value + int(next_u32() % width)

func choose(values: Array):
	if values.is_empty():
		return null
	return values[next_range(0, values.size() - 1)]

