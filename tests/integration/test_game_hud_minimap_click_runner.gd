extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var hud := GameHud.new()
	root.add_child(hud)
	await process_frame
	hud.mobile_command_issued.connect(func(command):
		if command.type == GameCommand.Type.OPEN_MAP:
			hud.show_map_menu()
	)
	var button := hud.get_node_or_null("Root/MapPanel/MapOpenButton") as Button
	if button != null:
		var position := button.get_global_rect().get_center()
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = position
			event.global_position = position
			event.pressed = pressed
			root.push_input(event, true)
			await process_frame
	var panel := hud.get_node_or_null("Root/MenuPanel") as Control
	var title := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuTitleBar/MenuTitleLabel") as Label
	var passed: bool = button != null and panel != null and panel.visible and title != null and title.text == "지도"
	hud.queue_free()
	if passed:
		print("HUD minimap click opens map menu")
		quit(0)
		return
	push_error("HUD minimap click did not open map menu")
	quit(1)
