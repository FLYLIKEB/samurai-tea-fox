extends RefCounted
class_name MainInputCoordinator

const GameCommand = preload("res://src/core/commands/game_command.gd")

func process_frame(main, delta: float) -> void:
	if main._death_transition_active:
		return
	main.tick_tea_runtime(delta)
	main.tick_consumable_runtime(delta)
	main._update_dungeon_sign_visibility()
	if main.has_pending_facility_placement():
		return
	main._record_current_map_discovery()
	var desktop_frame: Dictionary = main._desktop_adapter.poll_frame_input()
	var desktop_command = main._desktop_adapter.movement_command_from_frame(desktop_frame)
	main.player.submit_command(main.movement_command_for_current_inputs(desktop_command))
	var interaction_handled := false
	if main._desktop_adapter.frame_action_pressed(desktop_frame, "attack"):
		main._dungeon_debug("E/attack 입력 감지: player_cell=%s in_dungeon=%s" % [main.world_cell_from_world_position(main.player.global_position) if main.player != null else "nil", main._in_dungeon_map])
		interaction_handled = main._try_dungeon_interaction_from_input()
		if not interaction_handled:
			interaction_handled = main._try_landmark_interaction_from_input()
		main._dungeon_debug("E/attack 처리 결과: dungeon_handled=%s in_dungeon=%s" % [interaction_handled, main._in_dungeon_map])
		if not interaction_handled:
			main.submit_desktop_action_command("attack", desktop_command.direction)
	for action in main._desktop_adapter.general_front_action_names(desktop_frame):
		main.submit_desktop_action_command(action, desktop_command.direction)
	var tea_brewing_open: bool = main._is_hud_menu_open("tea_brewing")
	for action in main._desktop_adapter.tea_brewing_action_names(desktop_frame, tea_brewing_open):
		main.submit_desktop_action_command(action)
	for action in main._desktop_adapter.general_middle_action_names(desktop_frame, not interaction_handled):
		main.submit_desktop_action_command(action, desktop_command.direction)
	for action in main._desktop_adapter.menu_open_action_names(desktop_frame):
		main.submit_desktop_action_command(action)
	var inventory_open: bool = main._is_hud_menu_open("inventory")
	for action in main._desktop_adapter.inventory_action_names(desktop_frame, inventory_open):
		var slot: int = main._selected_inventory_slot_index() if action in ["inventory_use_selected", "inventory_equip_selected"] else 0
		main.submit_desktop_action_command(action, Vector2i.ZERO, slot)
	var meta_codex_open: bool = main._is_hud_menu_open("meta_codex")
	for action in main._desktop_adapter.meta_codex_action_names(desktop_frame, meta_codex_open):
		main.submit_desktop_action_command(action)
	for action in main._desktop_adapter.general_back_action_names(desktop_frame):
		main.submit_desktop_action_command(action)

func handle_unhandled_input(main, event) -> bool:
	var handled := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world_position: Vector2 = main.world_position_from_viewport_position(event.position)
		handled = main.submit_pointer_interaction(mouse_world_position)
		if not handled:
			handled = main.submit_pointer_movement(mouse_world_position)
	elif event is InputEventScreenTouch and event.pressed:
		var touch_world_position: Vector2 = main.world_position_from_viewport_position(event.position)
		handled = main.submit_pointer_interaction(touch_world_position)
		if not handled:
			handled = main.submit_pointer_movement(touch_world_position)
	return handled
