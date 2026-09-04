extends RefCounted
class_name MobileCommandAdapter

const ActionCommandFactory = preload("res://src/core/commands/action_command_factory.gd")

const BUTTON_IDS := [
	"move",
	"attack",
	"dodge",
	"drink_tea",
	"sleep",
	"open_tea_brewing",
	"tea_brew_select_leaf",
	"tea_brew_select_vessel",
	"tea_brew_select_slot",
	"tea_brew_next_leaf",
	"tea_brew_previous_leaf",
	"tea_brew_next_vessel",
	"tea_brew_previous_vessel",
	"tea_brew_next_slot",
	"tea_brew_previous_slot",
	"brew_tea",
	"open_meta_codex",
	"meta_codex_set_tab",
	"meta_codex_set_filter",
	"meta_codex_select_detail",
	"meta_codex_next",
	"meta_codex_previous",
	"use_consumable",
	"cast_ability",
	"interact",
	"open_inventory",
	"inventory_filter",
	"inventory_sort",
	"inventory_select",
	"inventory_next",
	"inventory_previous",
	"equip_inventory_slot",
	"use_inventory_slot",
	"open_crafting",
	"open_facilities",
	"open_map",
	"complete_dungeon",
	"repair_teleport",
	"advance_biome",
	"facility_rotate",
	"facility_confirm",
	"facility_cancel",
]

func command_for_button(button_id: String, direction := Vector2i.ZERO, slot := 0, payload := {}):
	if not (button_id in BUTTON_IDS):
		return null
	if button_id == "move":
		return ActionCommandFactory.movement_command(direction)
	return ActionCommandFactory.command_for_action(button_id, direction, slot, payload)
