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

	var consumable = mobile.command_for_button("use_consumable", Vector2i.ZERO, 3)
	asserts.equal(consumable.type, GameCommand.Type.USE_CONSUMABLE, "mobile consumable maps to shared command")
	asserts.equal(consumable.slot, 3, "mobile consumable preserves slot")

	var inventory = mobile.command_for_button("open_inventory")
	asserts.equal(inventory.type, GameCommand.Type.OPEN_INVENTORY, "mobile inventory maps to shared command")
	var crafting = mobile.command_for_button("open_crafting")
	asserts.equal(crafting.type, GameCommand.Type.OPEN_CRAFTING, "mobile crafting menu maps to shared command")
	var facilities = mobile.command_for_button("open_facilities")
	asserts.equal(facilities.type, GameCommand.Type.OPEN_FACILITIES, "mobile facilities menu maps to shared command")

	for action in ["attack", "dodge", "drink_tea", "use_consumable", "cast_ability", "interact", "open_inventory", "open_crafting", "open_facilities"]:
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
