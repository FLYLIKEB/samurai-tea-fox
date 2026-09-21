extends RefCounted
class_name MainCommandCoordinator

const ActionCommandResultEffects = preload("res://src/main/action_command_result_effects.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

var _dispatcher: CommandDispatcher
var _effects: ActionCommandResultEffects

func _init(dispatcher: CommandDispatcher, effects: ActionCommandResultEffects) -> void:
	_dispatcher = dispatcher
	_effects = effects

func submit_action_command(main, command) -> bool:
	if not command is GameCommand:
		return false
	if main._dungeon_boss_action_locked(command):
		return false
	var result: Dictionary = execute_action_command(main, command)
	apply_action_command_result(result)
	return bool(result.get("accepted", false))

func execute_action_command(main, command: GameCommand) -> Dictionary:
	match command.type:
		GameCommand.Type.NARRATIVE_SELECT_OPTION:
			return _dispatcher.result_for(command, main._handle_narrative_option_command(command))
		GameCommand.Type.INTERACT:
			return _interaction_result(main, command)
		GameCommand.Type.DRINK_TEA:
			return _dispatcher.result_for(command, main._handle_tea_command(command))
		GameCommand.Type.USE_CONSUMABLE:
			return _dispatcher.result_for(command, main._handle_consumable_command(command))
		GameCommand.Type.SLEEP:
			return _dispatcher.result_for(command, main._handle_sleep_command())
		GameCommand.Type.COMPLETE_DUNGEON:
			return _dispatcher.result_for(command, main._handle_complete_dungeon_command(command))
		GameCommand.Type.REPAIR_TELEPORT, GameCommand.Type.ADVANCE_BIOME:
			return _dispatcher.result_for(command, main._handle_biome_progression_command(command))
		GameCommand.Type.TRAVEL_TO_BIOME:
			return _dispatcher.result_for(command, main._travel_to_biome(String(command.payload.get("biome_id", "")), String(command.payload.get("travel_mode", "teleport"))))
		GameCommand.Type.FACILITY_ROTATE:
			return _dispatcher.result_for(command, main._rotate_pending_facility())
		GameCommand.Type.FACILITY_CONFIRM:
			return _dispatcher.result_for(command, main._confirm_pending_facility())
		GameCommand.Type.FACILITY_CANCEL:
			return _dispatcher.result_for(command, main._cancel_pending_facility_placement())
		GameCommand.Type.OPEN_TEA_BREWING:
			return _menu_result(main, command, "tea_brewing", Callable(self, "_show_tea_brewing_menu"))
		GameCommand.Type.TEA_BREW_SELECT_LEAF, GameCommand.Type.TEA_BREW_SELECT_VESSEL, GameCommand.Type.TEA_BREW_SELECT_SLOT, GameCommand.Type.TEA_BREW_NAVIGATE, GameCommand.Type.BREW_TEA:
			return _dispatcher.result_for(command, main._handle_tea_brewing_command(command))
		GameCommand.Type.OPEN_META_CODEX:
			return _menu_result(main, command, "meta_codex", Callable(self, "_show_meta_codex_menu"))
		GameCommand.Type.META_CODEX_SET_TAB, GameCommand.Type.META_CODEX_SET_FILTER, GameCommand.Type.META_CODEX_SELECT_DETAIL, GameCommand.Type.META_CODEX_NAVIGATE:
			return _dispatcher.result_for(command, main._handle_meta_codex_command(command))
		GameCommand.Type.OPEN_INVENTORY:
			return _menu_result(main, command, "inventory", Callable(self, "_show_inventory_menu"))
		GameCommand.Type.OPEN_CRAFTING:
			main._configure_game_hud()
			return _menu_result(main, command, "crafting", Callable(self, "_show_crafting_menu"))
		GameCommand.Type.OPEN_FACILITIES:
			main._configure_game_hud()
			return _menu_result(main, command, "facilities", Callable(self, "_show_facilities_menu"))
		GameCommand.Type.OPEN_MAP:
			return _menu_result(main, command, "map", Callable(self, "_show_map_menu"))
		GameCommand.Type.HIDE_MENU:
			return _hide_menu_result(main, command)
		GameCommand.Type.CRAFT_RECIPE:
			var accepted: bool = main._handle_craft_recipe_command(command)
			return _dispatcher.result_for(command, accepted, {"placement_pending": accepted and main.has_pending_facility_placement()})
		GameCommand.Type.INVENTORY_SET_FILTER, GameCommand.Type.INVENTORY_SORT, GameCommand.Type.INVENTORY_SELECT_SLOT, GameCommand.Type.INVENTORY_NAVIGATE, GameCommand.Type.EQUIP_INVENTORY_SLOT, GameCommand.Type.UNEQUIP_SLOT, GameCommand.Type.USE_INVENTORY_SLOT:
			return _dispatcher.result_for(command, main._handle_inventory_command(command))
		_:
			if main._sen_rikyu_phase_two_accepts_command(command):
				var accepted: bool = main._handle_sen_rikyu_phase_two_action(command)
				return _dispatcher.result_for(command, accepted, {"consumes_turn": true, "queues_enemy_turn": true, "feedback_beep": true})
			var player = main.player
			return _dispatcher.result_for(command, player != null and player.submit_command(command))

func apply_action_command_result(result: Dictionary) -> void:
	_effects.apply(result)

func _interaction_result(main, command: GameCommand) -> Dictionary:
	var target_id := String(command.payload.get("target_id", ""))
	if target_id.is_empty():
		return _dispatcher.result_for(command, main.submit_player_interaction(command.direction), {"consumes_turn": false, "queues_enemy_turn": false})
	if main._is_landmark_target(target_id):
		var landmark_accepted: bool = main._handle_landmark_interaction(target_id)
		if landmark_accepted:
			main._play_sfx_event(SfxEventRouter.EVENT_INTERACT_SUCCESS, {"target_id": target_id}, "landmark:%s" % target_id)
		return _dispatcher.result_for(command, landmark_accepted, {"consumes_turn": false, "queues_enemy_turn": false, "interact_failure_sfx": false})
	if main._is_repair_interaction_target(target_id):
		var repair_result: Dictionary = main._handle_repair_interaction_command(command)
		var repaired := bool(repair_result.get("ok", false))
		return _dispatcher.result_for(command, repaired, {"consumes_turn": repaired, "queues_enemy_turn": repaired})
	var acquisition_service = main.acquisition_service
	var accepted: bool = acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
	return _dispatcher.result_for(command, accepted)

func _menu_result(main, command: GameCommand, menu_id: String, show_menu: Callable) -> Dictionary:
	var accepted: bool = show_menu.call(main)
	if accepted:
		main._play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": menu_id}, "menu:%s" % menu_id)
	return _dispatcher.result_for(command, accepted)

func _hide_menu_result(main, command: GameCommand) -> Dictionary:
	var placement_cancelled: bool = main._cancel_pending_facility_placement()
	var hud = main.game_hud
	var accepted: bool = (hud != null and hud.hide_menu()) or placement_cancelled
	if accepted:
		main._play_sfx_event(SfxEventRouter.EVENT_UI_MENU_CLOSE, {"placement_cancelled": placement_cancelled}, "menu:hide")
	return _dispatcher.result_for(command, accepted)

func _show_tea_brewing_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_tea_brewing_menu()

func _show_meta_codex_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_meta_codex_menu()

func _show_inventory_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_inventory_menu()

func _show_crafting_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_crafting_menu()

func _show_facilities_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_facilities_menu()

func _show_map_menu(main) -> bool:
	var hud = main.game_hud
	return hud != null and hud.show_map_menu()
