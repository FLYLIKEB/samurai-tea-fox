extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	var hud := GameHud.new()
	hud._build()
	var facilities := hud.get_node_or_null("Root/FacilitiesShortcutButton") as Button
	var settings := hud.get_node_or_null("Root/ActionMenuPanel/SettingsRows")
	var volume := hud.get_node_or_null("Root/ActionMenuPanel/SettingsRows/GameVolumeSlider") as HSlider
	var home := hud.get_node_or_null("Root/ActionMenuPanel/SettingsRows/ReturnHomeButton") as Button
	asserts.true_value(facilities != null, "facilities has an always-visible shortcut")
	asserts.true_value(settings != null, "settings opens a dedicated settings window")
	asserts.true_value(volume != null, "settings exposes game volume")
	asserts.true_value(home != null, "settings exposes return to home")
	var master_bus := AudioServer.get_bus_index("Master")
	var original_db := AudioServer.get_bus_volume_db(master_bus)
	var original_muted := AudioServer.is_bus_mute(master_bus)
	if volume != null:
		volume.value_changed.emit(35.0)
		asserts.true_value(absf(db_to_linear(AudioServer.get_bus_volume_db(master_bus)) - 0.35) < 0.01, "volume slider controls the master bus")
	AudioServer.set_bus_volume_db(master_bus, original_db)
	AudioServer.set_bus_mute(master_bus, original_muted)
	asserts.true_value(hud.get_node_or_null("Root/RightRailPanel") == null, "HUD removes the redundant right rail")
	asserts.true_value((hud.get_node_or_null("Root/MapPanel") as Control).visible, "HUD restores the original map panel")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/TeaBrewingNavButton") != null, "bottom nav owns tea brewing")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/InventoryNavButton") != null, "bottom nav keeps inventory")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/TeaNavButton") != null, "bottom nav keeps tea")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/CodexNavButton") != null, "bottom nav keeps codex")
	asserts.true_value(hud.get_node_or_null("Root/BottomNavPanel/BottomNavRow/CraftingNavButton") != null, "bottom nav owns crafting")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionRows/ActionMenuBar/ActionMenuButton") == null, "action cluster does not duplicate settings")
	var commands: Array = []
	var home_requests := []
	hud.mobile_command_issued.connect(func(command): commands.append(command))
	hud.return_to_start_requested.connect(func(): home_requests.append(true))
	if facilities != null:
		facilities.pressed.emit()
	if home != null:
		home.pressed.emit()
	asserts.equal(commands.size(), 1, "each settings action emits one command")
	if commands.size() == 1:
		asserts.equal(commands[0].type, GameCommand.Type.OPEN_FACILITIES, "facilities use the shared command layer")
	asserts.equal(home_requests.size(), 1, "home button requests presentation navigation")
	hud.free()
