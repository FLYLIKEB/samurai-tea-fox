extends RefCounted
class_name GameCommand

enum Type {
	MOVE,
	ATTACK,
	DODGE,
	DRINK_TEA,
	USE_CONSUMABLE,
	CAST_ABILITY,
	INTERACT,
	NARRATIVE_RESULT,
	OPEN_INVENTORY,
	OPEN_CRAFTING,
	OPEN_FACILITIES,
	HIDE_MENU,
	CRAFT_RECIPE,
	SLEEP,
	COMPLETE_DUNGEON,
	REPAIR_TELEPORT,
	ADVANCE_BIOME
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
