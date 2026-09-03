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

	for action in ["attack", "dodge", "drink_tea", "sleep", "open_tea_brewing", "tea_brew_select_leaf", "tea_brew_select_vessel", "tea_brew_select_slot", "tea_brew_next_leaf", "tea_brew_previous_leaf", "tea_brew_next_vessel", "tea_brew_previous_vessel", "tea_brew_next_slot", "tea_brew_previous_slot", "brew_tea", "open_meta_codex", "meta_codex_set_tab", "meta_codex_set_filter", "meta_codex_select_detail", "meta_codex_next", "meta_codex_previous", "use_consumable", "cast_ability", "interact", "open_inventory", "open_crafting", "open_facilities", "open_map", "complete_dungeon", "repair_teleport", "advance_biome", "inventory_sort", "inventory_select", "inventory_next", "inventory_previous", "equip_inventory_slot", "use_inventory_slot"]:
		var desktop_command = desktop.command_for_action(action, Vector2i.LEFT, 2)
		var mobile_command = mobile.command_for_button(action, Vector2i.LEFT, 2)
		asserts.equal(desktop_command.type, mobile_command.type, "%s type matches across platforms" % action)
		asserts.equal(desktop_command.direction, mobile_command.direction, "%s direction matches across platforms" % action)
		asserts.equal(desktop_command.slot, mobile_command.slot, "%s slot matches across platforms" % action)

	asserts.equal(mobile.command_for_button("unknown"), null, "unknown mobile command is rejected")
	asserts.equal(desktop.command_for_action("unknown"), null, "unknown desktop command is rejected")

	var dispatcher := CommandDispatcher.new()
	var received: Array = []
	dispatcher.command_issued.connect(func(command): received.append(command))
	asserts.true_value(dispatcher.dispatch(attack), "valid command is dispatched")
	asserts.false_value(dispatcher.dispatch(null), "missing command is rejected")
	asserts.false_value(dispatcher.dispatch("attack"), "non-command value is rejected")
	asserts.equal(received.size(), 1, "dispatcher emits exactly one valid command")
	asserts.equal(received[0], attack, "dispatcher preserves command identity")
	_assert_menu_shortcut_keys_are_unique(asserts)
	_assert_attack_uses_e_shortcut(asserts)

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
