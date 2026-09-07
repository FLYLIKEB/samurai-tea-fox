extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("main scene loads for shortcut runtime test")
		quit(1)
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await physics_frame
	for _index in range(90):
		if main.get_node_or_null("LoadingOverlay") == null:
			break
		await process_frame
	var hud = main.get_node_or_null("GameHud")
	if hud == null:
		_failures.append("runtime is missing GameHud")
	else:
		if hud.has_method("narrative_dialogue_visible") and hud.narrative_dialogue_visible():
			hud.hide_narrative_dialogue()
			await process_frame
		await _press_and_assert_menu(hud, "CraftingShortcutButton", "제작법")
		var close := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuTitleBar/CloseMenuButton") as Button
		if close == null:
			_failures.append("crafting menu is missing close button")
		else:
			close.pressed.emit()
			await process_frame
		await _press_and_assert_menu(hud, "MapShortcutButton", "지도")
	main.queue_free()
	await process_frame
	if _failures.is_empty():
		print("HUD shortcut runtime menu checks passed: 2")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _press_and_assert_menu(hud, button_name: String, expected_title: String) -> void:
	var button := hud.get_node_or_null("Root/ShortcutPanel/ShortcutRow/%s" % button_name) as Button
	if button == null:
		_failures.append("runtime is missing %s" % button_name)
		return
	await _click(button)
	var panel := hud.get_node_or_null("Root/MenuPanel") as Control
	var title := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuTitleBar/MenuTitleLabel") as Label
	if panel == null or not panel.visible:
		_failures.append("%s click does not open MenuPanel" % button_name)
	if title == null or title.text != expected_title:
		_failures.append("%s click shows title '%s' instead of '%s'" % [button_name, title.text if title != null else "", expected_title])

func _click(button: Button) -> void:
	var click_position := button.get_global_rect().get_center()
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = click_position
		event.global_position = click_position
		event.pressed = is_pressed
		root.push_input(event, true)
		await process_frame
