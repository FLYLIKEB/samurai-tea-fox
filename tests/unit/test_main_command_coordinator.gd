extends RefCounted

const ActionCommandResultEffects = preload("res://src/main/action_command_result_effects.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MainCommandCoordinator = preload("res://src/main/main_command_coordinator.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

class HudStub:
	extends RefCounted

	var opened: Array[String] = []
	var hide_called := false
	var hide_return := true
	var call_log: Array = []

	func show_tea_brewing_menu() -> bool:
		opened.append("tea_brewing")
		call_log.append("show_tea_brewing")
		return true

	func show_meta_codex_menu() -> bool:
		opened.append("meta_codex")
		call_log.append("show_meta_codex")
		return true

	func show_inventory_menu() -> bool:
		opened.append("inventory")
		call_log.append("show_inventory")
		return true

	func show_crafting_menu() -> bool:
		opened.append("crafting")
		call_log.append("show_crafting")
		return true

	func show_facilities_menu() -> bool:
		opened.append("facilities")
		call_log.append("show_facilities")
		return true

	func show_map_menu() -> bool:
		opened.append("map")
		call_log.append("show_map")
		return true

	func hide_menu() -> bool:
		hide_called = true
		call_log.append("hide")
		return hide_return

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

class MainStub:
	extends RefCounted

	var game_hud := HudStub.new()
	var player := PlayerStub.new()
	var acquisition_service := AcquisitionStub.new()
	var events: Array = []
	var probes: Array = []
	var placement_cancelled := false
	var pending_facility_placement := false

	func _dungeon_boss_action_locked(command) -> bool:
		probes.append(["boss_lock", command])
		return false

	func _handle_narrative_option_command(command) -> bool:
		probes.append(["narrative", command])
		return true

	func submit_player_interaction(direction := Vector2i.ZERO) -> bool:
		probes.append(["player_interaction", direction])
		return true

	func _is_landmark_target(target_id: String) -> bool:
		probes.append(["landmark_check", target_id])
		return target_id.begins_with("landmark")

	func _handle_landmark_interaction(target_id: String) -> bool:
		probes.append(["landmark", target_id])
		return true

	func _is_repair_interaction_target(target_id: String) -> bool:
		probes.append(["repair_check", target_id])
		return target_id.begins_with("repair")

	func _handle_repair_interaction_command(command) -> Dictionary:
		probes.append(["repair", command])
		return {"ok": true}

	func _handle_tea_command(command) -> bool:
		probes.append(["tea", command])
		events.append("tea")
		return true

	func _handle_consumable_command(command) -> bool:
		probes.append(["consumable", command])
		return true

	func _handle_sleep_command() -> bool:
		probes.append("sleep")
		return true

	func _handle_complete_dungeon_command(command) -> bool:
		probes.append(["complete_dungeon", command])
		return true

	func _handle_biome_progression_command(command) -> bool:
		probes.append(["biome", command])
		return true

	func _travel_to_biome(biome_id: String, travel_mode: String) -> bool:
		probes.append(["travel", biome_id, travel_mode])
		return true

	func _rotate_pending_facility() -> bool:
		probes.append("rotate")
		return true

	func _confirm_pending_facility() -> bool:
		probes.append("confirm")
		return true

	func _cancel_pending_facility_placement() -> bool:
		probes.append("cancel_placement")
		return placement_cancelled

	func _configure_game_hud() -> void:
		game_hud.call_log.append("configure")

	func _handle_tea_brewing_command(command) -> bool:
		probes.append(["tea_brewing", command])
		return true

	func _handle_meta_codex_command(command) -> bool:
		probes.append(["meta_codex", command])
		return true

	func _handle_craft_recipe_command(command) -> bool:
		probes.append(["craft", command])
		return true

	func has_pending_facility_placement() -> bool:
		probes.append("has_pending")
		return pending_facility_placement

	func _handle_inventory_command(command) -> bool:
		probes.append(["inventory", command])
		return true

	func _sen_rikyu_phase_two_accepts_command(command) -> bool:
		probes.append(["sen_check", command])
		return false

	func _handle_sen_rikyu_phase_two_action(command) -> bool:
		probes.append(["sen_action", command])
		return false

	func _sync_run_runtime_state() -> void:
		events.append("sync")

	func _advance_time_for_turn() -> void:
		events.append("time")

	func _play_feedback_beep() -> void:
		events.append("beep")

	func _queue_enemy_turn_after_player_action() -> void:
		events.append("enemy")

	func _play_sfx_event(event_id, payload := {}, key := "") -> void:
		events.append(["sfx", event_id, payload, key])

var _asserts

func run(asserts) -> void:
	_asserts = asserts
	_test_invalid_command_guard_runs_before_any_main_probe()
	_test_menu_command_uses_hud_sfx_and_dispatcher_metadata()
	_test_rejected_interaction_plays_failure_sfx_without_turn_effects()
	_test_accepted_turn_effect_order_is_preserved()
	_test_explicit_effect_order_is_preserved()
	_test_landmark_interaction_success_is_not_a_turn()
	_test_acquisition_service_is_read_at_call_time()
	_test_game_hud_is_read_at_call_time()
	_test_player_is_read_at_call_time()
	_test_crafting_and_facility_menu_config_order_is_preserved()
	_test_hide_menu_preserves_pending_placement_cancel()

func _test_invalid_command_guard_runs_before_any_main_probe() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	var accepted := coordinator.submit_action_command(main, "not a command")
	_asserts.false_value(accepted, "invalid command is rejected")
	_asserts.equal(main.probes, [], "invalid command returns before boss-lock, dispatcher, player, acquisition, or HUD paths")
	_asserts.equal(main.events, [], "invalid command returns before effects or sfx")

func _test_menu_command_uses_hud_sfx_and_dispatcher_metadata() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.OPEN_TEA_BREWING)
	var accepted := coordinator.submit_action_command(main, command)
	_asserts.true_value(accepted, "tea brewing menu command is accepted")
	_asserts.equal(main.game_hud.opened, ["tea_brewing"], "tea brewing command opens the HUD menu")
	_asserts.equal(main.events, [
		["sfx", SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "tea_brewing"}, "menu:tea_brewing"]
	], "accepted menu command plays the existing menu-open sfx")
	var result := coordinator.execute_action_command(main, command)
	_asserts.false_value(result.consumes_turn, "menu open command does not consume a turn")
	_asserts.false_value(result.queues_enemy_turn, "menu open command does not queue enemy turn")

func _test_rejected_interaction_plays_failure_sfx_without_turn_effects() -> void:
	var main := MainStub.new()
	main.acquisition_service.accepted = false
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "missing_resource"})
	var accepted := coordinator.submit_action_command(main, command)
	_asserts.false_value(accepted, "rejected acquisition interaction remains rejected")
	_asserts.equal(main.events, [
		["sfx", SfxEventRouter.EVENT_INTERACT_FAIL, {"target_id": "missing_resource"}, "interact_failed:missing_resource"]
	], "rejected interaction preserves failure sfx and skips success effects")

func _test_accepted_turn_effect_order_is_preserved() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.DRINK_TEA)
	var accepted := coordinator.submit_action_command(main, command)
	_asserts.true_value(accepted, "accepted tea command remains accepted")
	_asserts.equal(main.events, ["tea", "time", "beep", "enemy"], "accepted tea command applies time, feedback, enemy queue in order")

func _test_explicit_effect_order_is_preserved() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.CAST_ABILITY)
	coordinator.apply_action_command_result({
		"accepted": true,
		"command": command,
		"sync_tea_runtime": true,
		"consumes_turn": true,
		"feedback_beep": true,
		"queues_enemy_turn": true
	})
	_asserts.equal(main.events, ["sync", "time", "beep", "enemy"], "explicit effects keep sync, time, feedback, enemy queue order")

func _test_landmark_interaction_success_is_not_a_turn() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "landmark_shrine"})
	var accepted := coordinator.submit_action_command(main, command)
	_asserts.true_value(accepted, "accepted landmark interaction remains accepted")
	_asserts.equal(main.events, [
		["sfx", SfxEventRouter.EVENT_INTERACT_SUCCESS, {"target_id": "landmark_shrine"}, "landmark:landmark_shrine"]
	], "landmark interaction keeps success sfx and does not consume a turn")

func _test_acquisition_service_is_read_at_call_time() -> void:
	var main := MainStub.new()
	var first_service := AcquisitionStub.new()
	var second_service := AcquisitionStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "resource_node"})
	main.acquisition_service = first_service
	_asserts.true_value(coordinator.submit_action_command(main, command), "first acquisition service accepts command")
	main.acquisition_service = second_service
	_asserts.true_value(coordinator.submit_action_command(main, command), "second acquisition service accepts command")
	_asserts.equal(first_service.handled.size(), 1, "first acquisition service was used before swap")
	_asserts.equal(second_service.handled.size(), 1, "second acquisition service was used after swap")

func _test_game_hud_is_read_at_call_time() -> void:
	var main := MainStub.new()
	var first_hud := HudStub.new()
	var second_hud := HudStub.new()
	var coordinator := _coordinator(main)
	main.game_hud = first_hud
	_asserts.true_value(coordinator.submit_action_command(main, GameCommand.new(GameCommand.Type.OPEN_INVENTORY)), "first HUD accepts inventory menu")
	main.game_hud = second_hud
	_asserts.true_value(coordinator.submit_action_command(main, GameCommand.new(GameCommand.Type.OPEN_INVENTORY)), "second HUD accepts inventory menu")
	_asserts.equal(first_hud.opened, ["inventory"], "first HUD was used before swap")
	_asserts.equal(second_hud.opened, ["inventory"], "second HUD was used after swap")

func _test_player_is_read_at_call_time() -> void:
	var main := MainStub.new()
	var first_player := PlayerStub.new()
	var second_player := PlayerStub.new()
	var coordinator := _coordinator(main)
	var command := GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)
	main.player = first_player
	_asserts.true_value(coordinator.submit_action_command(main, command), "first player accepts fallback command")
	main.player = second_player
	_asserts.true_value(coordinator.submit_action_command(main, command), "second player accepts fallback command")
	_asserts.equal(first_player.submitted.size(), 1, "first player was used before swap")
	_asserts.equal(second_player.submitted.size(), 1, "second player was used after swap")

func _test_crafting_and_facility_menu_config_order_is_preserved() -> void:
	var main := MainStub.new()
	var coordinator := _coordinator(main)
	_asserts.true_value(coordinator.submit_action_command(main, GameCommand.new(GameCommand.Type.OPEN_CRAFTING)), "crafting menu opens")
	_asserts.equal(main.game_hud.call_log, ["configure", "show_crafting"], "crafting config happens before showing menu")
	main.game_hud.call_log = []
	_asserts.true_value(coordinator.submit_action_command(main, GameCommand.new(GameCommand.Type.OPEN_FACILITIES)), "facilities menu opens")
	_asserts.equal(main.game_hud.call_log, ["configure", "show_facilities"], "facility config happens before showing menu")

func _test_hide_menu_preserves_pending_placement_cancel() -> void:
	var main := MainStub.new()
	main.placement_cancelled = true
	main.game_hud.hide_return = false
	var coordinator := _coordinator(main)
	var accepted := coordinator.submit_action_command(main, GameCommand.new(GameCommand.Type.HIDE_MENU))
	_asserts.true_value(accepted, "hide menu accepts a cancelled pending placement even when HUD had no open menu")
	_asserts.equal(main.events, [
		["sfx", SfxEventRouter.EVENT_UI_MENU_CLOSE, {"placement_cancelled": true}, "menu:hide"]
	], "hide menu keeps close sfx for placement cancellation")

func _coordinator(main: MainStub) -> MainCommandCoordinator:
	var effects := ActionCommandResultEffects.new(
		Callable(main, "_sync_run_runtime_state"),
		Callable(main, "_advance_time_for_turn"),
		Callable(main, "_play_feedback_beep"),
		Callable(main, "_queue_enemy_turn_after_player_action"),
		Callable(main, "_play_sfx_event")
	)
	return MainCommandCoordinator.new(CommandDispatcher.new(), effects)
