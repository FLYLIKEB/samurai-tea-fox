extends "res://src/main/main.gd"

var submitted_actions: Array = []
var trace: Array[String] = []
var dungeon_interaction_result := false
var landmark_interaction_result := false

func _ready() -> void:
	set_physics_process(false)

func submit_action_command(command) -> bool:
	trace.append("action:%d:movement_count=%d" % [command.type, player.submitted.size()])
	submitted_actions.append(command)
	match command.type:
		GameCommand.Type.OPEN_TEA_BREWING:
			game_hud.show_tea_brewing_menu()
		GameCommand.Type.OPEN_INVENTORY:
			game_hud.show_inventory_menu()
		GameCommand.Type.OPEN_META_CODEX:
			game_hud.show_meta_codex_menu()
		GameCommand.Type.INVENTORY_NAVIGATE:
			inventory_command_runtime.selected_slot_index = 4
		GameCommand.Type.USE_INVENTORY_SLOT:
			game_hud.menu_id = ""
		_:
			pass
	return true

func submit_player_interaction(direction := Vector2i.ZERO) -> bool:
	trace.append("player_interaction:%s:movement_count=%d" % [direction, player.submitted.size()])
	submitted_actions.append(GameCommand.new(GameCommand.Type.INTERACT, direction))
	return true

func _try_dungeon_interaction_from_input() -> bool:
	trace.append("try_dungeon")
	return dungeon_interaction_result

func _try_landmark_interaction_from_input() -> bool:
	trace.append("try_landmark")
	return landmark_interaction_result
