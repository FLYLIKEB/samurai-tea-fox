extends RefCounted
class_name MainCommandCoordinator

const ActionCommandResultEffects = preload("res://src/main/action_command_result_effects.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

class Ports:
	var is_boss_action_locked: Callable
	var handle_narrative_option_command: Callable
	var submit_player_interaction: Callable
	var is_landmark_target: Callable
	var handle_landmark_interaction: Callable
	var is_repair_interaction_target: Callable
	var handle_repair_interaction_command: Callable
	var get_acquisition_service: Callable
	var handle_tea_command: Callable
	var handle_consumable_command: Callable
	var handle_sleep_command: Callable
	var handle_complete_dungeon_command: Callable
	var handle_biome_progression_command: Callable
	var travel_to_biome: Callable
	var rotate_pending_facility: Callable
	var confirm_pending_facility: Callable
	var cancel_pending_facility_placement: Callable
	var get_game_hud: Callable
	var configure_game_hud: Callable
	var handle_tea_brewing_command: Callable
	var handle_meta_codex_command: Callable
	var handle_craft_recipe_command: Callable
	var has_pending_facility_placement: Callable
	var handle_inventory_command: Callable
	var sen_rikyu_phase_two_accepts_command: Callable
	var handle_sen_rikyu_phase_two_action: Callable
	var get_player: Callable
	var sync_runtime_state: Callable
	var advance_time_for_turn: Callable
	var play_feedback_beep: Callable
	var queue_enemy_turn: Callable
	var play_sfx_event: Callable

var _ports: Ports
var _dispatcher: CommandDispatcher
var _effects: ActionCommandResultEffects

func _init(ports: Ports, dispatcher: CommandDispatcher = CommandDispatcher.new(), effects = null) -> void:
	_ports = ports
	_dispatcher = dispatcher
	_effects = effects
	if _effects == null:
		_effects = ActionCommandResultEffects.new(
			ports.sync_runtime_state,
			ports.advance_time_for_turn,
			ports.play_feedback_beep,
			ports.queue_enemy_turn,
			ports.play_sfx_event
		)

func submit_action_command(command) -> bool:
	if not command is GameCommand:
		return false
	if _call_bool(_ports.is_boss_action_locked, [command]):
		return false
	var result: Dictionary = execute_action_command(command)
	apply_action_command_result(result)
	return bool(result.get("accepted", false))

func execute_action_command(command: GameCommand) -> Dictionary:
	match command.type:
		GameCommand.Type.NARRATIVE_SELECT_OPTION:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_narrative_option_command, [command]))
		GameCommand.Type.INTERACT:
			return _interaction_result(command)
		GameCommand.Type.DRINK_TEA:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_tea_command, [command]))
		GameCommand.Type.USE_CONSUMABLE:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_consumable_command, [command]))
		GameCommand.Type.SLEEP:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_sleep_command))
		GameCommand.Type.COMPLETE_DUNGEON:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_complete_dungeon_command, [command]))
		GameCommand.Type.REPAIR_TELEPORT, GameCommand.Type.ADVANCE_BIOME:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_biome_progression_command, [command]))
		GameCommand.Type.TRAVEL_TO_BIOME:
			return _dispatcher.result_for(command, _call_bool(_ports.travel_to_biome, [String(command.payload.get("biome_id", "")), String(command.payload.get("travel_mode", "teleport"))]))
		GameCommand.Type.FACILITY_ROTATE:
			return _dispatcher.result_for(command, _call_bool(_ports.rotate_pending_facility))
		GameCommand.Type.FACILITY_CONFIRM:
			return _dispatcher.result_for(command, _call_bool(_ports.confirm_pending_facility))
		GameCommand.Type.FACILITY_CANCEL:
			return _dispatcher.result_for(command, _call_bool(_ports.cancel_pending_facility_placement))
		GameCommand.Type.OPEN_TEA_BREWING:
			return _menu_result(command, "tea_brewing", Callable(self, "_show_tea_brewing_menu"))
		GameCommand.Type.TEA_BREW_SELECT_LEAF, GameCommand.Type.TEA_BREW_SELECT_VESSEL, GameCommand.Type.TEA_BREW_SELECT_SLOT, GameCommand.Type.TEA_BREW_NAVIGATE, GameCommand.Type.BREW_TEA:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_tea_brewing_command, [command]))
		GameCommand.Type.OPEN_META_CODEX:
			return _menu_result(command, "meta_codex", Callable(self, "_show_meta_codex_menu"))
		GameCommand.Type.META_CODEX_SET_TAB, GameCommand.Type.META_CODEX_SET_FILTER, GameCommand.Type.META_CODEX_SELECT_DETAIL, GameCommand.Type.META_CODEX_NAVIGATE:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_meta_codex_command, [command]))
		GameCommand.Type.OPEN_INVENTORY:
			return _menu_result(command, "inventory", Callable(self, "_show_inventory_menu"))
		GameCommand.Type.OPEN_CRAFTING:
			_call_void(_ports.configure_game_hud)
			return _menu_result(command, "crafting", Callable(self, "_show_crafting_menu"))
		GameCommand.Type.OPEN_FACILITIES:
			_call_void(_ports.configure_game_hud)
			return _menu_result(command, "facilities", Callable(self, "_show_facilities_menu"))
		GameCommand.Type.OPEN_MAP:
			return _menu_result(command, "map", Callable(self, "_show_map_menu"))
		GameCommand.Type.HIDE_MENU:
			return _hide_menu_result(command)
		GameCommand.Type.CRAFT_RECIPE:
			var accepted := _call_bool(_ports.handle_craft_recipe_command, [command])
			return _dispatcher.result_for(command, accepted, {"placement_pending": accepted and _call_bool(_ports.has_pending_facility_placement)})
		GameCommand.Type.INVENTORY_SET_FILTER, GameCommand.Type.INVENTORY_SORT, GameCommand.Type.INVENTORY_SELECT_SLOT, GameCommand.Type.INVENTORY_NAVIGATE, GameCommand.Type.EQUIP_INVENTORY_SLOT, GameCommand.Type.UNEQUIP_SLOT, GameCommand.Type.USE_INVENTORY_SLOT:
			return _dispatcher.result_for(command, _call_bool(_ports.handle_inventory_command, [command]))
		_:
			if _call_bool(_ports.sen_rikyu_phase_two_accepts_command, [command]):
				var accepted := _call_bool(_ports.handle_sen_rikyu_phase_two_action, [command])
				return _dispatcher.result_for(command, accepted, {"consumes_turn": true, "queues_enemy_turn": true, "feedback_beep": true})
			var player = _call_object(_ports.get_player)
			return _dispatcher.result_for(command, player != null and player.submit_command(command))

func apply_action_command_result(result: Dictionary) -> void:
	_effects.apply(result)

func _interaction_result(command: GameCommand) -> Dictionary:
	var target_id := String(command.payload.get("target_id", ""))
	if target_id.is_empty():
		return _dispatcher.result_for(command, _call_bool(_ports.submit_player_interaction, [command.direction]), {"consumes_turn": false, "queues_enemy_turn": false})
	if _call_bool(_ports.is_landmark_target, [target_id]):
		var landmark_accepted := _call_bool(_ports.handle_landmark_interaction, [target_id])
		if landmark_accepted:
			_call_void(_ports.play_sfx_event, [SfxEventRouter.EVENT_INTERACT_SUCCESS, {"target_id": target_id}, "landmark:%s" % target_id])
		return _dispatcher.result_for(command, landmark_accepted, {"consumes_turn": false, "queues_enemy_turn": false, "interact_failure_sfx": false})
	if _call_bool(_ports.is_repair_interaction_target, [target_id]):
		var repair_result := _call_dictionary(_ports.handle_repair_interaction_command, [command])
		var repaired := bool(repair_result.get("ok", false))
		return _dispatcher.result_for(command, repaired, {"consumes_turn": repaired, "queues_enemy_turn": repaired})
	var acquisition_service = _call_object(_ports.get_acquisition_service)
	var accepted: bool = acquisition_service != null and bool(acquisition_service.handle_command(command).ok)
	return _dispatcher.result_for(command, accepted)

func _menu_result(command: GameCommand, menu_id: String, show_menu: Callable) -> Dictionary:
	var accepted: bool = _call_bool(show_menu)
	if accepted:
		_call_void(_ports.play_sfx_event, [SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": menu_id}, "menu:%s" % menu_id])
	return _dispatcher.result_for(command, accepted)

func _hide_menu_result(command: GameCommand) -> Dictionary:
	var placement_cancelled := _call_bool(_ports.cancel_pending_facility_placement)
	var hud = _call_object(_ports.get_game_hud)
	var accepted: bool = (hud != null and hud.hide_menu()) or placement_cancelled
	if accepted:
		_call_void(_ports.play_sfx_event, [SfxEventRouter.EVENT_UI_MENU_CLOSE, {"placement_cancelled": placement_cancelled}, "menu:hide"])
	return _dispatcher.result_for(command, accepted)

func _show_tea_brewing_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_tea_brewing_menu()

func _show_meta_codex_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_meta_codex_menu()

func _show_inventory_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_inventory_menu()

func _show_crafting_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_crafting_menu()

func _show_facilities_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_facilities_menu()

func _show_map_menu() -> bool:
	var hud = _call_object(_ports.get_game_hud)
	return hud != null and hud.show_map_menu()

func _call_bool(callback: Callable, arguments := []) -> bool:
	if not callback.is_valid():
		return false
	return bool(callback.callv(arguments))

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	if not callback.is_valid():
		return {}
	var result = callback.callv(arguments)
	return result if result is Dictionary else {}

func _call_object(callback: Callable):
	if not callback.is_valid():
		return null
	return callback.call()

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)
