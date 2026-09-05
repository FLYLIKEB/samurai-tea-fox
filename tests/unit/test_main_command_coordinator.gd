extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MainCommandCoordinator = preload("res://src/main/main_command_coordinator.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

class HudStub:
	extends RefCounted

	var opened: Array[String] = []
	var hide_called := false

	func show_tea_brewing_menu() -> bool:
		opened.append("tea_brewing")
		return true

	func show_meta_codex_menu() -> bool:
		opened.append("meta_codex")
		return true

	func show_inventory_menu() -> bool:
		opened.append("inventory")
		return true

	func show_crafting_menu() -> bool:
		opened.append("crafting")
		return true

	func show_facilities_menu() -> bool:
		opened.append("facilities")
		return true

	func show_map_menu() -> bool:
		opened.append("map")
		return true

	func hide_menu() -> bool:
		hide_called = true
		return true

class PlayerStub:
	extends RefCounted

	var submitted: Array = []

	func submit_command(command) -> bool:
		submitted.append(command)
		return true

class AcquisitionStub:
	extends RefCounted

	var accepted := true
	var handled: Array = []

	func handle_command(command) -> Dictionary:
		handled.append(command)
		return {"ok": accepted}

var _asserts
var _hud := HudStub.new()
var _player := PlayerStub.new()
var _acquisition := AcquisitionStub.new()
var _events: Array = []

func run(asserts) -> void:
	_asserts = asserts
	_test_menu_command_uses_hud_sfx_and_dispatcher_metadata()
	_test_rejected_interaction_plays_failure_sfx_without_turn_effects()
	_test_accepted_turn_effect_order_is_preserved()
	_test_explicit_effect_order_is_preserved()
	_test_landmark_interaction_success_is_not_a_turn()

func _test_menu_command_uses_hud_sfx_and_dispatcher_metadata() -> void:
	_reset_state()
	var coordinator := _coordinator()
	var command := GameCommand.new(GameCommand.Type.OPEN_TEA_BREWING)
	var accepted := coordinator.submit_action_command(command)
	_asserts.true_value(accepted, "tea brewing menu command is accepted")
	_asserts.equal(_hud.opened, ["tea_brewing"], "tea brewing command opens the HUD menu")
	_asserts.equal(_events, [
		["sfx", SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "tea_brewing"}, "menu:tea_brewing"]
	], "accepted menu command plays the existing menu-open sfx")
	var result := coordinator.execute_action_command(command)
	_asserts.false_value(result.consumes_turn, "menu open command does not consume a turn")
	_asserts.false_value(result.queues_enemy_turn, "menu open command does not queue enemy turn")

func _test_rejected_interaction_plays_failure_sfx_without_turn_effects() -> void:
	_reset_state()
	_acquisition.accepted = false
	var coordinator := _coordinator()
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "missing_resource"})
	var accepted := coordinator.submit_action_command(command)
	_asserts.false_value(accepted, "rejected acquisition interaction remains rejected")
	_asserts.equal(_events, [
		["sfx", SfxEventRouter.EVENT_INTERACT_FAIL, {"target_id": "missing_resource"}, "interact_failed:missing_resource"]
	], "rejected interaction preserves failure sfx and skips success effects")

func _test_accepted_turn_effect_order_is_preserved() -> void:
	_reset_state()
	var coordinator := _coordinator()
	var command := GameCommand.new(GameCommand.Type.DRINK_TEA)
	var accepted := coordinator.submit_action_command(command)
	_asserts.true_value(accepted, "accepted tea command remains accepted")
	_asserts.equal(_events, ["tea", "time", "beep", "enemy"], "accepted tea command applies time, feedback, enemy queue in order")

func _test_explicit_effect_order_is_preserved() -> void:
	_reset_state()
	var coordinator := _coordinator()
	var command := GameCommand.new(GameCommand.Type.CAST_ABILITY)
	coordinator.apply_action_command_result({
		"accepted": true,
		"command": command,
		"sync_tea_runtime": true,
		"consumes_turn": true,
		"feedback_beep": true,
		"queues_enemy_turn": true
	})
	_asserts.equal(_events, ["sync", "time", "beep", "enemy"], "explicit effects keep sync, time, feedback, enemy queue order")

func _test_landmark_interaction_success_is_not_a_turn() -> void:
	_reset_state()
	var coordinator := _coordinator()
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "landmark_shrine"})
	var accepted := coordinator.submit_action_command(command)
	_asserts.true_value(accepted, "accepted landmark interaction remains accepted")
	_asserts.equal(_events, [
		["sfx", SfxEventRouter.EVENT_INTERACT_SUCCESS, {"target_id": "landmark_shrine"}, "landmark:landmark_shrine"]
	], "landmark interaction keeps success sfx and does not consume a turn")

func _coordinator() -> MainCommandCoordinator:
	var ports := MainCommandCoordinator.Ports.new()
	ports.is_boss_action_locked = func(_command): return false
	ports.handle_narrative_option_command = func(_command): return true
	ports.submit_player_interaction = func(_direction): return true
	ports.is_landmark_target = func(target_id): return String(target_id).begins_with("landmark")
	ports.handle_landmark_interaction = func(_target_id): return true
	ports.is_repair_interaction_target = func(target_id): return String(target_id).begins_with("repair")
	ports.handle_repair_interaction_command = func(_command): return {"ok": true}
	ports.get_acquisition_service = func(): return _acquisition
	ports.handle_tea_command = func(_command):
		_events.append("tea")
		return true
	ports.handle_consumable_command = func(_command): return true
	ports.handle_sleep_command = func(): return true
	ports.handle_complete_dungeon_command = func(_command): return true
	ports.handle_biome_progression_command = func(_command): return true
	ports.travel_to_biome = func(_biome_id, _travel_mode): return true
	ports.rotate_pending_facility = func(): return true
	ports.confirm_pending_facility = func(): return true
	ports.cancel_pending_facility_placement = func(): return false
	ports.get_game_hud = func(): return _hud
	ports.configure_game_hud = func(): pass
	ports.handle_tea_brewing_command = func(_command): return true
	ports.handle_meta_codex_command = func(_command): return true
	ports.handle_craft_recipe_command = func(_command): return true
	ports.has_pending_facility_placement = func(): return false
	ports.handle_inventory_command = func(_command): return true
	ports.sen_rikyu_phase_two_accepts_command = func(_command): return false
	ports.handle_sen_rikyu_phase_two_action = func(_command): return false
	ports.get_player = func(): return _player
	ports.sync_runtime_state = func(): _events.append("sync")
	ports.advance_time_for_turn = func(): _events.append("time")
	ports.play_feedback_beep = func(): _events.append("beep")
	ports.queue_enemy_turn = func(): _events.append("enemy")
	ports.play_sfx_event = func(event_id, payload, key): _events.append(["sfx", event_id, payload, key])
	return MainCommandCoordinator.new(ports)

func _reset_state() -> void:
	_hud = HudStub.new()
	_player = PlayerStub.new()
	_acquisition = AcquisitionStub.new()
	_events = []
