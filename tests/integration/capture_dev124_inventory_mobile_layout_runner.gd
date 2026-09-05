extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")

const CAPTURE_DIR := "res://docs/reports/dev-124-inventory-mobile-layout"
const VIEWPORTS := [
	{"name": "mobile_360x640", "size": Vector2i(360, 640)},
	{"name": "narrow_480x270", "size": Vector2i(480, 270)},
	{"name": "desktop_1280x720", "size": Vector2i(1280, 720)}
]

var _failures: Array[String] = []

class FakeResources:
	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

class FakePlayer:
	var resources := FakeResources.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	for viewport_case in VIEWPORTS:
		await _capture_and_assert(String(viewport_case.name), viewport_case.size)
	if _failures.is_empty():
		print("DEV-124 inventory mobile layout captures saved: %s" % CAPTURE_DIR)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _capture_and_assert(case_name: String, viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % case_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fixture := _fixture()
	var runtime: InventoryCommandRuntime = fixture.runtime
	runtime.select_slot(int(fixture.leaf_slot))
	var hud := GameHud.new()
	viewport.add_child(hud)
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {
		"inventory": fixture.inventory,
		"inventory_command_runtime": runtime,
		"catalog": fixture.catalog
	})
	hud.show_inventory_menu()
	await _settle(hud)
	await _assert_inventory_leaf_menu(case_name, hud, viewport_size)
	_save_capture(case_name, viewport)
	var close := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuTitleBar/CloseMenuButton") as Button
	if close == null:
		_failures.append("%s missing close button" % case_name)
	else:
		var close_commands: Array = []
		hud.mobile_command_issued.connect(func(command): close_commands.append(command), CONNECT_ONE_SHOT)
		close.pressed.emit()
		await _settle(hud)
		if close_commands.is_empty() or close_commands[0].type != GameCommand.Type.HIDE_MENU:
			_failures.append("%s close button did not emit hide-menu command" % case_name)
	runtime.select_slot(int(fixture.bandage_slot))
	hud.show_inventory_menu()
	await _settle(hud)
	await _assert_selected_action_accessible(case_name, hud, viewport_size)
	viewport.queue_free()
	await process_frame

func _settle(hud: GameHud) -> void:
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	hud._apply_safe_area_layout()
	await process_frame

func _assert_inventory_leaf_menu(case_name: String, hud: GameHud, viewport_size: Vector2i) -> void:
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel", viewport_size)
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuTitleBar", viewport_size)
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuTitleBar/MenuTitleLabel", viewport_size)
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuTitleBar/CloseMenuButton", viewport_size)
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuScroll", viewport_size)
	_assert_visible_rect_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuScroll/MenuContent/InventoryToolbar", viewport_size)
	_assert_visible_horizontal_inside(case_name, hud, "Root/MenuPanel/MenuRows/MenuScroll/MenuContent/InventorySlotStrip", viewport_size)
	for text in ["인벤토리", "차 & 도구", "전체", "찻잎", "소모품", "서호용정"]:
		var node := _find_text_control(hud, text)
		if node == null:
			_failures.append("%s missing text %s" % [case_name, text])
		else:
			_assert_control_rect_inside(case_name, "%s text" % text, node, viewport_size)
	var title := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuTitleBar/MenuTitleLabel") as Label
	if title == null:
		_failures.append("%s missing menu title label" % case_name)
	elif title.text != "인벤토리" or title.get_global_rect().size.x < 48.0:
		_failures.append("%s menu title label is collapsed: text=%s rect=%s" % [case_name, title.text, title.get_global_rect()])
	if _find_text_control(hud, "사용") != null:
		_failures.append("%s tea leaf exposes a direct use button" % case_name)
	var commands: Array = []
	hud.mobile_command_issued.connect(func(command): commands.append(command), CONNECT_ONE_SHOT)
	var filter := _find_button_with_text(hud, "찻잎")
	if filter == null:
		_failures.append("%s missing tea leaf filter button" % case_name)
	else:
		filter.pressed.emit()
		await process_frame
		if commands.is_empty() or commands[0].type != GameCommand.Type.INVENTORY_SET_FILTER:
			_failures.append("%s tea leaf filter did not emit inventory filter command" % case_name)

func _assert_selected_action_accessible(case_name: String, hud: GameHud, viewport_size: Vector2i) -> void:
	var scroll := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll") as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 100000
		await process_frame
	var use_button := _find_button_with_text(hud, "사용")
	if use_button == null:
		_failures.append("%s selected consumable use action is missing" % case_name)
		return
	_assert_control_rect_inside(case_name, "selected consumable use action", use_button, viewport_size)
	var commands: Array = []
	hud.mobile_command_issued.connect(func(command): commands.append(command), CONNECT_ONE_SHOT)
	use_button.pressed.emit()
	await process_frame
	if commands.is_empty() or commands[0].type != GameCommand.Type.USE_INVENTORY_SLOT:
		_failures.append("%s selected consumable action did not emit use-slot command" % case_name)

func _assert_visible_rect_inside(case_name: String, root_node: Node, path: String, viewport_size: Vector2i) -> void:
	var node := root_node.get_node_or_null(path) as Control
	if node == null:
		_failures.append("%s missing %s" % [case_name, path])
		return
	if not node.visible:
		_failures.append("%s %s is hidden" % [case_name, path])
		return
	_assert_control_rect_inside(case_name, path, node, viewport_size)

func _assert_visible_horizontal_inside(case_name: String, root_node: Node, path: String, viewport_size: Vector2i) -> void:
	var node := root_node.get_node_or_null(path) as Control
	if node == null:
		_failures.append("%s missing %s" % [case_name, path])
		return
	if not node.visible:
		_failures.append("%s %s is hidden" % [case_name, path])
		return
	var rect := node.get_global_rect()
	if rect.position.x < -0.01 or rect.end.x > float(viewport_size.x) + 0.01:
		_failures.append("%s %s outside horizontal viewport bounds: %s within %s" % [case_name, path, rect, viewport_size])

func _assert_control_rect_inside(case_name: String, label: String, control: Control, viewport_size: Vector2i) -> void:
	var rect := control.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_failures.append("%s %s has empty rect: %s" % [case_name, label, rect])
		return
	if rect.position.x < -0.01 or rect.position.y < -0.01 or rect.end.x > float(viewport_size.x) + 0.01 or rect.end.y > float(viewport_size.y) + 0.01:
		_failures.append("%s %s outside viewport: %s within %s" % [case_name, label, rect, viewport_size])

func _save_capture(case_name: String, viewport: SubViewport) -> void:
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s capture requires a rendering display driver" % case_name)
		return
	var capture_path := "%s/%s.png" % [CAPTURE_DIR, case_name]
	var save_result := image.save_png(capture_path)
	if save_result != OK:
		_failures.append("%s failed to save %s" % [case_name, capture_path])

func _fixture() -> Dictionary:
	var catalog := DataCatalog.new()
	catalog.load_from_directory("res://data/generated")
	var inventory: InventoryModel = InventoryModel.from_catalog(catalog).inventory
	var equipment: EquipmentModel = EquipmentModel.from_catalog(catalog).equipment
	var consumable: ConsumableService = ConsumableService.from_catalog(catalog).consumable_service
	inventory.add_item("father_spring_pan_fired_tea", 3)
	inventory.add_item("bandage", 2)
	inventory.add_item("short_travel_sword", 1)
	var runtime := InventoryCommandRuntime.new()
	runtime.configure(inventory, equipment, consumable, "dev-124")
	return {
		"catalog": catalog,
		"inventory": inventory,
		"runtime": runtime,
		"leaf_slot": inventory.first_slot_with_item("father_spring_pan_fired_tea"),
		"bandage_slot": inventory.first_slot_with_item("bandage")
	}

func _find_button_with_text(node: Node, text: String) -> Button:
	if node is Button and text in (node as Button).text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_with_text(child, text)
		if found != null:
			return found
	return null

func _find_text_control(node: Node, text: String) -> Control:
	if node is Label and text in (node as Label).text:
		return node as Control
	if node is Button and text in (node as Button).text:
		return node as Control
	for child in node.get_children():
		var found := _find_text_control(child, text)
		if found != null:
			return found
	return null
