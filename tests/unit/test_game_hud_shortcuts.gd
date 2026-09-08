extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	var hud := GameHud.new()
	hud._build()
	var crafting := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/CraftingShortcutButton") as Button
	var map := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/MapShortcutButton") as Button
	var sleep := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/SleepShortcutButton") as Button
	var brewing := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/TeaBrewingShortcutButton") as Button
	var codex := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/MetaCodexShortcutButton") as Button
	var facilities := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/FacilitiesShortcutButton") as Button
	asserts.true_value(crafting != null, "crafting is always available outside the secondary drawer")
	asserts.true_value(map != null, "map is always available outside the secondary drawer")
	asserts.true_value(sleep != null, "sleep is always available outside the secondary drawer")
	asserts.true_value(brewing != null, "tea brewing is always available outside the secondary drawer")
	asserts.true_value(codex != null, "codex is always available outside the secondary drawer")
	asserts.true_value(facilities != null, "facilities are always available outside the secondary drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/CraftingButton") == null, "crafting is not duplicated in the secondary drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/MapButton") == null, "map is not duplicated in the secondary drawer")
	asserts.true_value(hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ActionMenuGrid/SleepButton") == null, "sleep is not duplicated in the secondary drawer")
	var commands: Array = []
	hud.mobile_command_issued.connect(func(command): commands.append(command))
	for button in [crafting, map, sleep, brewing, codex, facilities]:
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
	if sleep != null:
		sleep.pressed.emit()
	if brewing != null:
		brewing.pressed.emit()
	if codex != null:
		codex.pressed.emit()
	if facilities != null:
		facilities.pressed.emit()
	asserts.equal(commands.size(), 6, "each shortcut emits exactly one command")
	if commands.size() == 6:
		asserts.equal(commands[0].type, GameCommand.Type.OPEN_CRAFTING, "crafting shortcut uses the shared command layer")
		asserts.equal(commands[1].type, GameCommand.Type.OPEN_MAP, "map shortcut uses the shared command layer")
		asserts.equal(commands[2].type, GameCommand.Type.SLEEP, "sleep shortcut uses the shared command layer")
		asserts.equal(commands[3].type, GameCommand.Type.OPEN_TEA_BREWING, "brewing shortcut uses the shared command layer")
		asserts.equal(commands[4].type, GameCommand.Type.OPEN_META_CODEX, "codex shortcut uses the shared command layer")
		asserts.equal(commands[5].type, GameCommand.Type.OPEN_FACILITIES, "facilities shortcut uses the shared command layer")
	hud.free()
