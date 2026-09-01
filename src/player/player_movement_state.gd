extends RefCounted
class_name PlayerMovementState

enum Facing {
	DOWN,
	LEFT,
	RIGHT,
	UP
}

var facing: Facing = Facing.DOWN

func resolve(direction: Vector2i) -> Vector2:
	if direction == Vector2i.ZERO:
		return Vector2.ZERO

	if abs(direction.x) >= abs(direction.y) and direction.x != 0:
		facing = Facing.RIGHT if direction.x > 0 else Facing.LEFT
		return Vector2(sign(direction.x), 0.0)
	else:
		facing = Facing.DOWN if direction.y > 0 else Facing.UP
		return Vector2(0.0, sign(direction.y))
