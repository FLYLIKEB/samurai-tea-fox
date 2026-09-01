extends RefCounted
class_name GameCommand

enum Type {
	MOVE,
	ATTACK,
	DODGE,
	DRINK_TEA,
	CAST_ABILITY,
	INTERACT,
	OPEN_INVENTORY,
	SLEEP
}

var type: int
var direction: Vector2i = Vector2i.ZERO
var slot: int = -1
var payload: Dictionary = {}

func _init(command_type: int, command_direction := Vector2i.ZERO, command_slot := -1, command_payload := {}) -> void:
	type = command_type
	direction = command_direction
	slot = command_slot
	payload = command_payload

func to_dictionary() -> Dictionary:
	return {
		"type": type,
		"direction": {"x": direction.x, "y": direction.y},
		"slot": slot,
		"payload": payload
	}

static func move(command_direction: Vector2i):
	return GameCommand.new(Type.MOVE, command_direction)

static func attack(command_direction: Vector2i):
	return GameCommand.new(Type.ATTACK, command_direction)

static func dodge(command_direction: Vector2i):
	return GameCommand.new(Type.DODGE, command_direction)

static func drink_tea(command_slot: int):
	return GameCommand.new(Type.DRINK_TEA, Vector2i.ZERO, command_slot)

static func cast_ability(command_slot: int, command_direction: Vector2i):
	return GameCommand.new(Type.CAST_ABILITY, command_direction, command_slot)

static func interact():
	return GameCommand.new(Type.INTERACT)
