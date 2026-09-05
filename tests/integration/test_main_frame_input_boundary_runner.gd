extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")
const TestAssert = preload("res://tests/support/test_assert.gd")
const FrameInputMain = preload("res://tests/support/main_frame_input_probe.gd")

class FramePlayer:
	extends Node2D
	var submitted: Array = []

	func submit_command(command) -> bool:
		submitted.append(command)
		return true

class FrameHud:
	extends Node
	var menu_id := ""

	func active_menu_id() -> String:
		return menu_id

	func show_tea_brewing_menu() -> bool:
		menu_id = "tea_brewing"
		return true

	func show_inventory_menu() -> bool:
		menu_id = "inventory"
		return true

	func show_meta_codex_menu() -> bool:
		menu_id = "meta_codex"
		return true

class FrameInventoryRuntime:
	extends RefCounted
	var selected_slot_index := 2

	func read_model() -> Dictionary:
		return {"selected_slot_index": selected_slot_index}

var asserts := TestAssert.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	await _assert_movement_is_submitted_before_actions()
	await _assert_attack_world_interaction_suppresses_same_frame_interact()
	await _assert_same_frame_tea_menu_commands_use_entry_eligibility()
	await _assert_same_frame_inventory_commands_use_latest_slot()
	await _assert_same_frame_meta_codex_commands_use_entry_eligibility()
	if asserts.ok():
		print("Main frame input boundary characterization passed")
		quit(0)
		return
	for failure in asserts.failures:
		push_error(failure)
	quit(1)

func _assert_movement_is_submitted_before_actions() -> void:
	var main = _frame_main()
	await _process_frame_with_actions(main, ["move_right", "dodge"])

	asserts.equal(main.player.submitted.size(), 1, "frame input submits movement through player first")
	asserts.equal(main.player.submitted[0].type, GameCommand.Type.MOVE, "frame input movement command keeps move type")
	asserts.equal(main.player.submitted[0].direction, Vector2i.RIGHT, "frame input preserves keyboard movement direction")
	asserts.equal(main.submitted_actions.size(), 1, "frame input submits the same-frame action after movement")
	asserts.equal(main.submitted_actions[0].type, GameCommand.Type.DODGE, "frame input preserves action command after movement")
	asserts.equal(main.submitted_actions[0].direction, Vector2i.RIGHT, "frame input shares movement direction with dodge")
	asserts.equal(main.trace, ["action:%d:movement_count=1" % GameCommand.Type.DODGE], "action submission observes that movement was already submitted")
	_free_frame_main(main)

func _assert_attack_world_interaction_suppresses_same_frame_interact() -> void:
	var dungeon_main = _frame_main()
	dungeon_main.dungeon_interaction_result = true
	await _process_frame_with_actions(dungeon_main, ["attack", "interact"])
	asserts.equal(dungeon_main.submitted_actions.size(), 0, "handled dungeon attack suppresses same-frame interact and regular attack")
	asserts.equal(dungeon_main.trace, ["try_dungeon"], "handled dungeon attack does not call landmark fallback")
	_free_frame_main(dungeon_main)

	var landmark_main = _frame_main()
	landmark_main.landmark_interaction_result = true
	await _process_frame_with_actions(landmark_main, ["attack", "interact"])
	asserts.equal(landmark_main.submitted_actions.size(), 0, "handled landmark attack suppresses same-frame interact and regular attack")
	asserts.equal(landmark_main.trace, ["try_dungeon", "try_landmark"], "landmark fallback runs after dungeon attack path declines")
	_free_frame_main(landmark_main)

	var attack_main = _frame_main()
	await _process_frame_with_actions(attack_main, ["attack", "interact"])
	asserts.equal(_types(attack_main.submitted_actions), [GameCommand.Type.ATTACK, GameCommand.Type.INTERACT], "unhandled attack submits regular attack before same-frame interact")
	asserts.equal(attack_main.trace, [
		"try_dungeon",
		"try_landmark",
		"action:%d:movement_count=1" % GameCommand.Type.ATTACK,
		"player_interaction:(0, 0):movement_count=1"
	], "unhandled attack and interact preserve current frame ordering")
	_free_frame_main(attack_main)

func _assert_same_frame_tea_menu_commands_use_entry_eligibility() -> void:
	var main = _frame_main()
	await _process_frame_with_actions(main, ["open_tea_brewing", "tea_brew_next_leaf"])

	asserts.equal(_types(main.submitted_actions), [GameCommand.Type.OPEN_TEA_BREWING, GameCommand.Type.TEA_BREW_NAVIGATE], "tea menu opening enables same-frame tea navigation")
	asserts.equal(main.submitted_actions[1].payload, {"target": "leaf"}, "tea same-frame navigation keeps leaf payload")
	_free_frame_main(main)

func _assert_same_frame_inventory_commands_use_latest_slot() -> void:
	var main = _frame_main()
	await _process_frame_with_actions(main, ["open_inventory", "inventory_next", "inventory_use_selected", "inventory_equip_selected"])

	asserts.equal(_types(main.submitted_actions), [
		GameCommand.Type.OPEN_INVENTORY,
		GameCommand.Type.INVENTORY_NAVIGATE,
		GameCommand.Type.USE_INVENTORY_SLOT,
		GameCommand.Type.EQUIP_INVENTORY_SLOT
	], "inventory block uses entry eligibility for all same-frame commands")
	asserts.equal(main.submitted_actions[2].slot, 4, "inventory use samples the latest selected slot after navigation")
	asserts.equal(main.submitted_actions[3].slot, 4, "inventory equip keeps running after a prior command changes the active menu")
	_free_frame_main(main)

func _assert_same_frame_meta_codex_commands_use_entry_eligibility() -> void:
	var main = _frame_main()
	await _process_frame_with_actions(main, ["open_meta_codex", "meta_codex_next"])

	asserts.equal(_types(main.submitted_actions), [GameCommand.Type.OPEN_META_CODEX, GameCommand.Type.META_CODEX_NAVIGATE], "meta codex opening enables same-frame codex navigation")
	asserts.equal(main.submitted_actions[1].direction, Vector2i.RIGHT, "meta codex same-frame navigation keeps next direction")
	_free_frame_main(main)

func _frame_main():
	var main := FrameInputMain.new()
	main.player = FramePlayer.new()
	main.game_hud = FrameHud.new()
	main.inventory_command_runtime = FrameInventoryRuntime.new()
	return main

func _free_frame_main(main) -> void:
	main.player.free()
	main.game_hud.free()
	main.free()

func _process_frame_with_actions(main, actions: Array) -> void:
	_press(actions)
	await physics_frame
	main._physics_process(0.016)
	await _release(actions)

func _press(actions: Array) -> void:
	for action in actions:
		Input.action_press(String(action))

func _release(actions: Array) -> void:
	for action in actions:
		Input.action_release(String(action))
	await physics_frame

func _types(commands: Array) -> Array:
	var result := []
	for command in commands:
		result.append(command.type)
	return result
