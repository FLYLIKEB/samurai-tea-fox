extends RefCounted
class_name DesktopCommandAdapter

const ActionCommandFactory = preload("res://src/core/commands/action_command_factory.gd")

const FRAME_ACTIONS := [
	"attack",
	"dodge",
	"drink_tea",
	"sleep",
	"open_tea_brewing",
	"tea_brew_previous_leaf",
	"tea_brew_next_leaf",
	"tea_brew_previous_vessel",
	"tea_brew_next_vessel",
	"tea_brew_previous_slot",
	"tea_brew_next_slot",
	"brew_tea",
	"use_consumable",
	"cast_ability",
	"interact",
	"open_inventory",
	"open_meta_codex",
	"inventory_next",
	"inventory_previous",
	"inventory_sort",
	"inventory_use_selected",
	"inventory_equip_selected",
	"inventory_filter_all",
	"inventory_filter_consumable",
	"inventory_filter_equipment",
	"meta_codex_next",
	"meta_codex_previous",
	"open_crafting",
	"open_facilities",
	"open_map"
]

const GENERAL_FRONT_ACTIONS := [
	"dodge",
	"drink_tea",
	"sleep",
	"open_tea_brewing"
]

const TEA_BREWING_ACTIONS := [
	"tea_brew_previous_leaf",
	"tea_brew_next_leaf",
	"tea_brew_previous_vessel",
	"tea_brew_next_vessel",
	"tea_brew_previous_slot",
	"tea_brew_next_slot",
	"brew_tea"
]

const GENERAL_MIDDLE_ACTIONS := [
	"use_consumable",
	"cast_ability",
	"interact"
]

const MENU_OPEN_ACTIONS := [
	"open_inventory",
	"open_meta_codex"
]

const INVENTORY_ACTIONS := [
	"inventory_next",
	"inventory_previous",
	"inventory_sort",
	"inventory_use_selected",
	"inventory_equip_selected",
	"inventory_filter_all",
	"inventory_filter_consumable",
	"inventory_filter_equipment"
]

const META_CODEX_ACTIONS := [
	"meta_codex_next",
	"meta_codex_previous"
]

const GENERAL_BACK_ACTIONS := [
	"open_crafting",
	"open_facilities",
	"open_map"
]

func poll_movement_command():
	return movement_command_from_strengths(
		Input.get_action_strength("move_left"),
		Input.get_action_strength("move_right"),
		Input.get_action_strength("move_up"),
		Input.get_action_strength("move_down")
	)

func poll_frame_input() -> Dictionary:
	return {
		"movement_command": poll_movement_command(),
		"pressed": _pressed_actions(FRAME_ACTIONS)
	}

func movement_command_from_frame(frame_input: Dictionary):
	return frame_input.get("movement_command")

func frame_action_pressed(frame_input: Dictionary, action: String) -> bool:
	var pressed: Dictionary = frame_input.get("pressed", {})
	return bool(pressed.get(action, false))

func general_front_action_names(frame_input: Dictionary) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), GENERAL_FRONT_ACTIONS)

func tea_brewing_action_names(frame_input: Dictionary, enabled: bool) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), TEA_BREWING_ACTIONS, enabled)

func general_middle_action_names(frame_input: Dictionary, include_interact: bool) -> Array:
	var names := action_names_from_pressed(frame_input.get("pressed", {}), GENERAL_MIDDLE_ACTIONS)
	if not include_interact:
		names.erase("interact")
	return names

func menu_open_action_names(frame_input: Dictionary) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), MENU_OPEN_ACTIONS)

func inventory_action_names(frame_input: Dictionary, enabled: bool) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), INVENTORY_ACTIONS, enabled)

func meta_codex_action_names(frame_input: Dictionary, enabled: bool) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), META_CODEX_ACTIONS, enabled)

func general_back_action_names(frame_input: Dictionary) -> Array:
	return action_names_from_pressed(frame_input.get("pressed", {}), GENERAL_BACK_ACTIONS)

func action_names_from_pressed(pressed: Dictionary, action_order: Array, enabled := true) -> Array:
	var names := []
	if not enabled:
		return names
	for action in action_order:
		if bool(pressed.get(String(action), false)):
			names.append(String(action))
	return names

func movement_command_from_strengths(left: float, right: float, up: float, down: float):
	var direction := Vector2i(
		int(signf(right - left)),
		int(signf(down - up))
	)
	return ActionCommandFactory.movement_command(direction)

func command_for_action(action: String, direction := Vector2i.ZERO, slot := 0, payload := {}):
	return ActionCommandFactory.command_for_action(action, direction, slot, payload)

func _pressed_actions(actions: Array) -> Dictionary:
	var pressed := {}
	for action in actions:
		var action_name := String(action)
		pressed[action_name] = Input.is_action_just_pressed(action_name)
	return pressed
