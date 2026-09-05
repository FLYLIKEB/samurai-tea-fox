extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const CommandDispatcher = preload("res://src/core/commands/command_dispatcher.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")

func run(asserts) -> void:
	var desktop := DesktopCommandAdapter.new()
	var mobile := MobileCommandAdapter.new()
	var desktop_move = desktop.movement_command_from_strengths(0.0, 1.0, 0.0, 0.0)
	var mobile_move = mobile.command_for_button("move", Vector2i.RIGHT)
	asserts.equal(desktop_move.type, GameCommand.Type.MOVE, "desktop movement maps to shared command")
	asserts.equal(desktop_move.direction, mobile_move.direction, "desktop and mobile movement share direction")

	var cancelled_move = desktop.movement_command_from_strengths(1.0, 1.0, 0.0, 0.0)
	asserts.equal(cancelled_move.direction, Vector2i.ZERO, "opposing desktop directions cancel")

	var attack = mobile.command_for_button("attack", Vector2i.RIGHT)
	asserts.equal(attack.type, GameCommand.Type.ATTACK, "mobile attack maps to shared command")
	asserts.equal(attack.direction, Vector2i.RIGHT, "mobile attack preserves direction")

	var tea = mobile.command_for_button("drink_tea", Vector2i.ZERO, 1)
	asserts.equal(tea.type, GameCommand.Type.DRINK_TEA, "mobile tea maps to shared command")
	asserts.equal(tea.slot, 1, "mobile tea preserves slot")
	asserts.equal(mobile.command_for_button("sleep").type, GameCommand.Type.SLEEP, "mobile sleep maps to shared command")
	var brewing = mobile.command_for_button("open_tea_brewing")
	asserts.equal(brewing.type, GameCommand.Type.OPEN_TEA_BREWING, "mobile tea brewing menu maps to shared command")
	var brew = mobile.command_for_button("brew_tea")
	asserts.equal(brew.type, GameCommand.Type.BREW_TEA, "mobile brew action maps to shared command")
	var codex = mobile.command_for_button("open_meta_codex")
	asserts.equal(codex.type, GameCommand.Type.OPEN_META_CODEX, "mobile meta codex maps to shared command")

	var consumable = mobile.command_for_button("use_consumable", Vector2i.ZERO, 3)
	asserts.equal(consumable.type, GameCommand.Type.USE_CONSUMABLE, "mobile consumable maps to shared command")
	asserts.equal(consumable.slot, 3, "mobile consumable preserves slot")

	var inventory = mobile.command_for_button("open_inventory")
	asserts.equal(inventory.type, GameCommand.Type.OPEN_INVENTORY, "mobile inventory maps to shared command")
	var crafting = mobile.command_for_button("open_crafting")
	asserts.equal(crafting.type, GameCommand.Type.OPEN_CRAFTING, "mobile crafting menu maps to shared command")
	var facilities = mobile.command_for_button("open_facilities")
	asserts.equal(facilities.type, GameCommand.Type.OPEN_FACILITIES, "mobile facilities menu maps to shared command")
	var map = mobile.command_for_button("open_map")
	asserts.equal(map.type, GameCommand.Type.OPEN_MAP, "mobile map menu maps to shared command")
	asserts.equal(desktop.command_for_action("complete_dungeon").type, GameCommand.Type.COMPLETE_DUNGEON, "desktop dungeon completion maps to shared command")
	asserts.equal(mobile.command_for_button("repair_teleport").type, GameCommand.Type.REPAIR_TELEPORT, "mobile teleport repair maps to shared command")

	for action in ["attack", "dodge", "drink_tea", "sleep", "open_tea_brewing", "tea_brew_select_leaf", "tea_brew_select_vessel", "tea_brew_select_slot", "tea_brew_next_leaf", "tea_brew_previous_leaf", "tea_brew_next_vessel", "tea_brew_previous_vessel", "tea_brew_next_slot", "tea_brew_previous_slot", "brew_tea", "open_meta_codex", "meta_codex_set_tab", "meta_codex_set_filter", "meta_codex_select_detail", "meta_codex_next", "meta_codex_previous", "use_consumable", "cast_ability", "interact", "open_inventory", "open_crafting", "open_facilities", "open_map", "complete_dungeon", "repair_teleport", "advance_biome", "inventory_filter", "inventory_sort", "inventory_select", "inventory_next", "inventory_previous", "equip_inventory_slot", "use_inventory_slot", "facility_rotate", "facility_confirm", "facility_cancel"]:
		_assert_platform_commands_match(asserts, desktop, mobile, action)

	asserts.equal(desktop.command_for_action("inventory_use_selected", Vector2i.LEFT, 2).type, GameCommand.Type.USE_INVENTORY_SLOT, "desktop inventory use alias is preserved")
	asserts.equal(desktop.command_for_action("inventory_equip_selected", Vector2i.LEFT, 2).type, GameCommand.Type.EQUIP_INVENTORY_SLOT, "desktop inventory equip alias is preserved")
	asserts.equal(desktop.command_for_action("inventory_filter_all").payload, {"kind": "all"}, "desktop inventory all filter payload is preserved")
	asserts.equal(desktop.command_for_action("inventory_filter_consumable").payload, {"kind": "소모품"}, "desktop inventory consumable filter payload is preserved")
	asserts.equal(desktop.command_for_action("inventory_filter_equipment").payload, {"kind": "무기"}, "desktop inventory equipment filter payload is preserved")
	var repair_command = desktop.command_for_action("repair_abandoned_workbench")
	asserts.equal(repair_command.type, GameCommand.Type.INTERACT, "desktop repair target command reuses shared interact command")
	asserts.equal(repair_command.payload, {"target_id": "wasteland_abandoned_workbench", "action_id": "repair_abandoned_workbench"}, "desktop repair target command carries target action payload")
	var recycle_command = desktop.command_for_action("recycle_abandoned_workbench")
	asserts.equal(recycle_command.payload, {"target_id": "wasteland_abandoned_workbench", "action_id": "recycle_abandoned_workbench"}, "desktop recycle target command carries target action payload")
	asserts.equal(mobile.command_for_button("inventory_use_selected"), null, "desktop-only inventory use alias is not a mobile button")
	asserts.equal(mobile.command_for_button("inventory_filter_all"), null, "desktop-only inventory filter alias is not a mobile button")

	asserts.equal(mobile.command_for_button("unknown"), null, "unknown mobile command is rejected")
	asserts.equal(desktop.command_for_action("unknown"), null, "unknown desktop command is rejected")
	_assert_desktop_frame_input_blocks(asserts, desktop)

	var dispatcher := CommandDispatcher.new()
	var received: Array = []
	dispatcher.command_issued.connect(func(command): received.append(command))
	asserts.true_value(dispatcher.dispatch(attack), "valid command is dispatched")
	asserts.false_value(dispatcher.dispatch(null), "missing command is rejected")
	asserts.false_value(dispatcher.dispatch("attack"), "non-command value is rejected")
	asserts.equal(received.size(), 1, "dispatcher emits exactly one valid command")
	asserts.equal(received[0], attack, "dispatcher preserves command identity")
	_assert_command_result_policy(asserts, dispatcher)
	_assert_menu_shortcut_keys_are_unique(asserts)
	_assert_attack_uses_e_shortcut(asserts)

func _assert_command_result_policy(asserts, dispatcher: CommandDispatcher) -> void:
	var attack := GameCommand.new(GameCommand.Type.ATTACK, Vector2i.RIGHT)
	var accepted_attack: Dictionary = dispatcher.result_for(attack, true)
	asserts.true_value(accepted_attack.accepted, "accepted attack remains accepted")
	asserts.true_value(accepted_attack.consumes_turn, "accepted attack consumes a turn")
	asserts.true_value(accepted_attack.queues_enemy_turn, "accepted attack queues one enemy turn")
	asserts.false_value(accepted_attack.feedback_beep, "player combat feedback is owned by combat signals")

	var failed_attack: Dictionary = dispatcher.result_for(attack, false)
	asserts.false_value(failed_attack.accepted, "failed attack remains rejected")
	asserts.false_value(failed_attack.consumes_turn, "failed command never consumes a turn")
	asserts.false_value(failed_attack.queues_enemy_turn, "failed command never queues an enemy turn")
	asserts.false_value(failed_attack.feedback_beep, "failed command never gets success feedback")

	var tea: Dictionary = dispatcher.result_for(GameCommand.new(GameCommand.Type.DRINK_TEA), true)
	asserts.true_value(tea.consumes_turn, "accepted tea start consumes one turn")
	asserts.true_value(tea.queues_enemy_turn, "accepted tea start queues enemy turn")
	asserts.true_value(tea.feedback_beep, "accepted tea start has success feedback")

	var inventory: Dictionary = dispatcher.result_for(GameCommand.new(GameCommand.Type.INVENTORY_NAVIGATE), true)
	asserts.false_value(inventory.consumes_turn, "inventory navigation is not a turn")
	asserts.false_value(inventory.queues_enemy_turn, "inventory navigation does not queue enemies")
	asserts.true_value(inventory.feedback_beep, "accepted inventory command has feedback")

	var placement_recipe: Dictionary = dispatcher.result_for(GameCommand.new(GameCommand.Type.CRAFT_RECIPE), true, {"placement_pending": true})
	asserts.true_value(placement_recipe.accepted, "facility placement request is accepted")
	asserts.false_value(placement_recipe.consumes_turn, "pending facility placement does not consume a turn yet")
	asserts.false_value(placement_recipe.queues_enemy_turn, "pending facility placement does not queue enemies")

func _assert_desktop_frame_input_blocks(asserts, desktop: DesktopCommandAdapter) -> void:
	var frame_input := {
		"movement_command": desktop.movement_command_from_strengths(0.0, 1.0, 0.0, 0.0),
		"pressed": {
			"attack": true,
			"dodge": true,
			"open_tea_brewing": true,
			"tea_brew_next_leaf": true,
			"open_inventory": true,
			"inventory_next": true,
			"inventory_use_selected": true,
			"open_meta_codex": true,
			"meta_codex_next": true,
			"open_map": true
		}
	}
	asserts.equal(desktop.movement_command_from_frame(frame_input).direction, Vector2i.RIGHT, "desktop frame preserves movement command")
	asserts.true_value(desktop.frame_action_pressed(frame_input, "attack"), "desktop frame exposes attack press")
	asserts.equal(desktop.general_front_action_names(frame_input), ["dodge", "open_tea_brewing"], "desktop frame general front actions keep current order")
	asserts.equal(desktop.tea_brewing_action_names(frame_input, false), [], "closed tea menu emits no tea navigation")
	asserts.equal(desktop.tea_brewing_action_names(frame_input, true), ["tea_brew_next_leaf"], "open tea menu emits same-frame tea navigation")
	asserts.equal(desktop.general_middle_action_names(frame_input, false), [], "handled world interaction suppresses same-frame interact")
	asserts.equal(desktop.menu_open_action_names(frame_input), ["open_inventory", "open_meta_codex"], "desktop frame menu open actions keep order")
	asserts.equal(desktop.inventory_action_names(frame_input, true), ["inventory_next", "inventory_use_selected"], "desktop frame inventory actions keep navigation before selected use")
	asserts.equal(desktop.meta_codex_action_names(frame_input, true), ["meta_codex_next"], "desktop frame meta codex actions keep navigation")
	asserts.equal(desktop.general_back_action_names(frame_input), ["open_map"], "desktop frame general back actions keep order")

func _assert_platform_commands_match(asserts, desktop: DesktopCommandAdapter, mobile: MobileCommandAdapter, action: String) -> void:
	var payload := {"kind": "test", "tab": "items", "biome_id": "forest"}
	var desktop_command = desktop.command_for_action(action, Vector2i.LEFT, 2, payload)
	var mobile_command = mobile.command_for_button(action, Vector2i.LEFT, 2, payload)
	asserts.equal(desktop_command.type, mobile_command.type, "%s type matches across platforms" % action)
	asserts.equal(desktop_command.direction, mobile_command.direction, "%s direction matches across platforms" % action)
	asserts.equal(desktop_command.slot, mobile_command.slot, "%s slot matches across platforms" % action)
	asserts.equal(desktop_command.payload, mobile_command.payload, "%s payload matches across platforms" % action)

func _assert_attack_uses_e_shortcut(asserts) -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	asserts.equal(_project_input_keycode(text, "attack"), 69, "attack uses the E keyboard shortcut")

func _assert_menu_shortcut_keys_are_unique(asserts) -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	var menu_actions := ["open_inventory", "open_crafting", "open_facilities", "open_map", "open_tea_brewing", "open_meta_codex"]
	var keycodes := {}
	for action in menu_actions:
		var keycode := _project_input_keycode(text, action)
		asserts.true_value(keycode > 0, "%s has a keyboard binding" % action)
		asserts.false_value(keycodes.has(keycode), "%s does not share a shortcut with %s" % [action, String(keycodes.get(keycode, ""))])
		keycodes[keycode] = action

func _project_input_keycode(text: String, action: String) -> int:
	var start := text.find("%s={" % action)
	if start < 0:
		return -1
	var section_end := text.find("\n}", start)
	if section_end < 0:
		return -1
	var section := text.substr(start, section_end - start)
	var marker := "\"keycode\":"
	var marker_index := section.find(marker)
	if marker_index < 0:
		return -1
	var value_start := marker_index + marker.length()
	var value_end := section.find(",", value_start)
	return int(section.substr(value_start, value_end - value_start))
