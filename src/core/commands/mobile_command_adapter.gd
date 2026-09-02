extends RefCounted
class_name MobileCommandAdapter

const GameCommand = preload("res://src/core/commands/game_command.gd")

func command_for_button(button_id: String, direction := Vector2i.ZERO, slot := 0, payload := {}):
	match button_id:
		"move":
			return GameCommand.new(GameCommand.Type.MOVE, direction)
		"attack":
			return GameCommand.new(GameCommand.Type.ATTACK, direction)
		"dodge":
			return GameCommand.new(GameCommand.Type.DODGE, direction)
		"drink_tea":
			return GameCommand.new(GameCommand.Type.DRINK_TEA, Vector2i.ZERO, slot)
		"open_tea_brewing":
			return GameCommand.new(GameCommand.Type.OPEN_TEA_BREWING)
		"tea_brew_select_leaf":
			return GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_LEAF, Vector2i.ZERO, slot, payload)
		"tea_brew_select_vessel":
			return GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_VESSEL, Vector2i.ZERO, slot, payload)
		"tea_brew_select_slot":
			return GameCommand.new(GameCommand.Type.TEA_BREW_SELECT_SLOT, Vector2i.ZERO, slot, {"slot_index": slot})
		"tea_brew_next_leaf":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "leaf"})
		"tea_brew_previous_leaf":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": "leaf"})
		"tea_brew_next_vessel":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "vessel"})
		"tea_brew_previous_vessel":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": "vessel"})
		"tea_brew_next_slot":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.RIGHT, -1, {"target": "slot"})
		"tea_brew_previous_slot":
			return GameCommand.new(GameCommand.Type.TEA_BREW_NAVIGATE, Vector2i.LEFT, -1, {"target": "slot"})
		"brew_tea":
			return GameCommand.new(GameCommand.Type.BREW_TEA)
		"use_consumable":
			return GameCommand.new(GameCommand.Type.USE_CONSUMABLE, Vector2i.ZERO, slot)
		"cast_ability":
			return GameCommand.new(GameCommand.Type.CAST_ABILITY, direction, slot)
		"interact":
			return GameCommand.new(GameCommand.Type.INTERACT)
		"open_inventory":
			return GameCommand.new(GameCommand.Type.OPEN_INVENTORY)
		"inventory_filter":
			return GameCommand.new(GameCommand.Type.INVENTORY_SET_FILTER, Vector2i.ZERO, -1, payload)
		"inventory_sort":
			return GameCommand.new(GameCommand.Type.INVENTORY_SORT)
		"inventory_select":
			return GameCommand.new(GameCommand.Type.INVENTORY_SELECT_SLOT, Vector2i.ZERO, slot, {"slot_index": slot})
		"inventory_next":
			return GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.RIGHT)
		"inventory_previous":
			return GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE, Vector2i.LEFT)
		"equip_inventory_slot":
			return GameCommand.new(GameCommand.Type.EQUIP_INVENTORY_SLOT, Vector2i.ZERO, slot, {"slot_index": slot})
		"use_inventory_slot":
			return GameCommand.new(GameCommand.Type.USE_INVENTORY_SLOT, Vector2i.ZERO, slot, {"slot_index": slot})
		"open_crafting":
			return GameCommand.new(GameCommand.Type.OPEN_CRAFTING)
		"open_facilities":
			return GameCommand.new(GameCommand.Type.OPEN_FACILITIES)
		"open_map":
			return GameCommand.new(GameCommand.Type.OPEN_MAP)
		_:
			return null
