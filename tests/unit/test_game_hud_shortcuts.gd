extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	var hud := GameHud.new()
	hud._build()
	var crafting := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/CraftingShortcutButton") as Button
	var map := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/MapShortcutButton") as Button
	asserts.true_value(crafting != null, "crafting is always available outside the secondary drawer")
	asserts.true_value(map != null, "map is always available outside the secondary drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/CraftingButton") == null, "crafting is not duplicated in the secondary drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/MapButton") == null, "map is not duplicated in the secondary drawer")
	var commands: Array = []
	hud.mobile_command_issued.connect(func(command): commands.append(command))
	for button in [crafting, map]:
		if button == null:
			continue
		asserts.equal(button.text, "", "%s is icon-only" % button.name)
		asserts.equal(button.custom_minimum_size, Vector2(44, 44), "%s has a clear touch target" % button.name)
		asserts.true_value(button.icon != null, "%s has a visible icon" % button.name)
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		asserts.true_value(style != null and style.corner_radius_top_left >= 22, "%s is circular" % button.name)
	if crafting != null:
		crafting.pressed.emit()
	if map != null:
		map.pressed.emit()
	asserts.equal(commands.size(), 2, "each shortcut emits exactly one command")
	if commands.size() == 2:
		asserts.equal(commands[0].type, GameCommand.Type.OPEN_CRAFTING, "crafting shortcut uses the shared command layer")
		asserts.equal(commands[1].type, GameCommand.Type.OPEN_MAP, "map shortcut uses the shared command layer")
	hud.free()
