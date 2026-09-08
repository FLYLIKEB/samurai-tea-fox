extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	var hud := GameHud.new()
	hud._build()
	var settings_path := "Root/ActionMenuPanel/ActionMenuScroll/ShortcutGrid/"
	var settings_grid := hud.get_node_or_null("Root/ActionMenuPanel/ActionMenuScroll/ShortcutGrid") as GridContainer
	var sleep := hud.get_node_or_null(settings_path + "SleepShortcutButton") as Button
	var facilities := hud.get_node_or_null(settings_path + "FacilitiesShortcutButton") as Button
	asserts.equal(settings_grid.get_child_count() if settings_grid != null else 0, 1, "settings contains only unique actions")
	asserts.true_value(sleep == null, "sleep is available only through facility interaction")
	asserts.true_value(facilities != null, "facilities are available only in settings")
	for duplicate in ["Inventory", "Crafting", "Map", "TeaBrewing", "MetaCodex"]:
		asserts.true_value(hud.get_node_or_null(settings_path + duplicate + "ShortcutButton") == null, "settings does not duplicate %s" % duplicate)
	asserts.true_value(hud.get_node_or_null("Root/RightRailPanel") == null, "HUD removes the redundant right rail")
	asserts.true_value((hud.get_node_or_null("Root/MapPanel") as Control).visible, "HUD restores the original map panel")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/TeaBrewingNavButton") != null, "bottom nav owns tea brewing")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/InventoryNavButton") != null, "bottom nav keeps inventory")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/TeaNavButton") != null, "bottom nav keeps tea")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/CodexNavButton") != null, "bottom nav keeps codex")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/CraftingNavButton") != null, "bottom nav owns crafting")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/ActionMenuButton") == null, "action cluster does not duplicate settings")
	var commands: Array = []
	hud.mobile_command_issued.connect(func(command): commands.append(command))
	if facilities != null:
		facilities.pressed.emit()
	asserts.equal(commands.size(), 1, "each settings action emits one command")
	if commands.size() == 1:
		asserts.equal(commands[0].type, GameCommand.Type.OPEN_FACILITIES, "facilities use the shared command layer")
	hud.free()
