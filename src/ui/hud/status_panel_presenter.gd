extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

const ICON_HP := "ui_hp_heart_icon"
const ICON_KI := "ui_tea_cup_icon"
const ICON_KOKORO := "ui_tea_leaf_icon"
const PORTRAIT_PLAYER := "portrait_chr_8_muchau"
const STATUS_PANEL_SIZE := Vector2(184, 104)
const PORTRAIT_BOX_SIZE := Vector2(40, 40)
const RESOURCE_ICON_COUNT := 5
const RESOURCE_ICON_SIZE := Vector2(12, 12)
const EQUIPMENT_ICON_SIZE := Vector2(15, 15)
const EQUIPMENT_SLOT_SIZE := Vector2(28, 24)
const RESOURCE_DETAIL_PANEL_SIZE := Vector2(172, 62)
const EQUIPMENT_SLOT_KEYS := ["weapon", "armor", "tea_ware"]
const EQUIPMENT_SLOT_LABELS := {"weapon": "무기", "armor": "방어", "tea_ware": "다구"}
const EQUIPMENT_SLOT_SHORT_LABELS := {"weapon": "무", "armor": "방", "tea_ware": "다"}

var labels := {}
var _panels := {}
var _equipment_slots := {}
var _resource_detail_label: Label
var _resource_detail_id := ""
var _texture_resolver: Callable
var _item_icon_reference: Callable
var _request_layout: Callable
var _runtime_read_model: Callable

func build(parent: Control, deps: Dictionary) -> Dictionary:
	_texture_resolver = deps.get("texture_resolver", Callable())
	_item_icon_reference = deps.get("item_icon_reference", Callable())
	_request_layout = deps.get("request_layout", Callable())
	_runtime_read_model = deps.get("runtime_read_model", Callable())
	var status_panel := _panel(STATUS_PANEL_SIZE)
	status_panel.name = "StatusPanel"
	status_panel.clip_contents = true
	status_panel.theme = PixelUiTheme.create_parchment()
	status_panel.add_theme_stylebox_override("panel", PixelUiTheme.hud_status_style())
	parent.add_child(status_panel)
	_panels.status = status_panel
	var status_body := HBoxContainer.new()
	status_body.name = "StatusBody"
	_ignore_mouse(status_body)
	status_body.add_theme_constant_override("separation", 6)
	status_panel.add_child(status_body)
	var portrait_box := _portrait_box(PORTRAIT_PLAYER)
	portrait_box.name = "PlayerPortrait"
	status_body.add_child(portrait_box)
	var status_rows := VBoxContainer.new()
	status_rows.name = "StatusRows"
	_ignore_mouse(status_rows)
	status_rows.add_theme_constant_override("separation", 1)
	status_body.add_child(status_rows)
	labels.hp = _add_resource_icon_row(status_rows, "hp", ICON_HP, "체력", Color(0.86, 0.28, 0.16, 1.0))
	labels.ki = _add_resource_icon_row(status_rows, "ki", ICON_KI, "기운", Color(0.82, 0.53, 0.19, 1.0))
	labels.kokoro = _add_resource_icon_row(status_rows, "kokoro", ICON_KOKORO, "心", Color(0.48, 0.40, 0.56, 1.0))
	status_rows.add_child(_build_equipment_strip())
	_build_resource_detail_panel(parent)
	return _panels.duplicate()

func update(model: Dictionary) -> void:
	_set_label("hp", "체력")
	_set_label("ki", "기운")
	_set_label("kokoro", "心")
	_update_resource_icons("hp_icons", int(model.hp), int(model.hp_max))
	_update_resource_icons("ki_icons", int(model.ki), int(model.ki_max))
	_update_resource_icons("kokoro_icons", int(model.kokoro), int(model.kokoro_max))
	_update_equipment_strip(model.get("equipment", {}))
	_update_resource_detail(model)

func equipment_hud_snapshot() -> Dictionary:
	var snapshot := {}
	for slot_key in EQUIPMENT_SLOT_KEYS:
		var nodes: Dictionary = _equipment_slots.get(slot_key, {})
		var label := nodes.get("name") as Label
		var icon := nodes.get("icon") as TextureRect
		var cell := nodes.get("cell") as Control
		snapshot[slot_key] = {
			"slot_key": slot_key,
			"slot_label": String(EQUIPMENT_SLOT_LABELS.get(slot_key, slot_key)),
			"item_id": String(cell.get_meta("item_id", "")) if cell != null else "",
			"name": String(cell.get_meta("name", "")) if cell != null else "",
			"display_text": label.text if label != null else "",
			"icon_reference": String(icon.get_meta("icon_reference", "")) if icon != null else "",
			"icon_has_texture": icon != null and icon.texture != null,
			"tooltip": cell.tooltip_text if cell != null else ""
		}
	return snapshot

func panel(id: String) -> Control:
	return _panels.get(id) as Control

func _build_equipment_strip() -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.name = "EquipmentStrip"
	_ignore_mouse(strip)
	strip.add_theme_constant_override("separation", 1)
	_equipment_slots.clear()
	for slot_key in EQUIPMENT_SLOT_KEYS:
		var cell := PanelContainer.new()
		cell.name = "Equipment%s" % String(slot_key).to_pascal_case()
		cell.custom_minimum_size = EQUIPMENT_SLOT_SIZE
		cell.add_theme_stylebox_override("panel", _equipment_slot_style(false))
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		strip.add_child(cell)
		var rows := VBoxContainer.new()
		rows.name = "Rows"
		rows.alignment = BoxContainer.ALIGNMENT_CENTER
		rows.add_theme_constant_override("separation", 0)
		_ignore_mouse(rows)
		cell.add_child(rows)
		var icon := TextureRect.new()
		icon.name = "ItemIcon"
		icon.custom_minimum_size = EQUIPMENT_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(icon)
		var label := _label(String(EQUIPMENT_SLOT_SHORT_LABELS.get(slot_key, slot_key)), 7)
		label.name = "ItemName"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.93, 0.83, 0.63, 1.0))
		label.custom_minimum_size = Vector2(EQUIPMENT_SLOT_SIZE.x - 4.0, 8.0)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rows.add_child(label)
		_equipment_slots[slot_key] = {"cell": cell, "icon": icon, "name": label}
	return strip

func _update_equipment_strip(equipment: Dictionary) -> void:
	for slot_key in EQUIPMENT_SLOT_KEYS:
		var nodes: Dictionary = _equipment_slots.get(slot_key, {})
		var cell := nodes.get("cell") as PanelContainer
		var icon := nodes.get("icon") as TextureRect
		var label := nodes.get("name") as Label
		if cell == null or icon == null or label == null:
			continue
		var payload := _dictionary_value(equipment.get(slot_key, {}))
		var item_id := String(payload.get("item_id", ""))
		var definition := _dictionary_value(payload.get("definition", {}))
		if item_id.is_empty():
			_set_equipment_slot_empty(slot_key, cell, icon, label)
			continue
		var name := String(definition.get("name", item_id))
		var kind := String(definition.get("type", definition.get("kind", EQUIPMENT_SLOT_LABELS.get(slot_key, ""))))
		var icon_reference := String(_item_icon_reference.call(item_id, kind, definition)) if _item_icon_reference.is_valid() else ""
		icon.texture = _load_texture(icon_reference) if not icon_reference.is_empty() else null
		icon.visible = icon.texture != null
		icon.set_meta("icon_reference", icon_reference)
		cell.set_meta("item_id", item_id)
		cell.set_meta("slot_key", slot_key)
		cell.set_meta("name", name)
		label.text = String(EQUIPMENT_SLOT_SHORT_LABELS.get(slot_key, slot_key))
		cell.tooltip_text = "%s: %s" % [String(EQUIPMENT_SLOT_LABELS.get(slot_key, slot_key)), name]
		cell.add_theme_stylebox_override("panel", _equipment_slot_style(true))

func _set_equipment_slot_empty(slot_key: String, cell: PanelContainer, icon: TextureRect, label: Label) -> void:
	icon.texture = null
	icon.visible = false
	icon.set_meta("icon_reference", "")
	cell.set_meta("item_id", "")
	cell.set_meta("slot_key", slot_key)
	cell.set_meta("name", "")
	label.text = String(EQUIPMENT_SLOT_SHORT_LABELS.get(slot_key, slot_key))
	cell.tooltip_text = "%s: 비어 있음" % String(EQUIPMENT_SLOT_LABELS.get(slot_key, slot_key))
	cell.add_theme_stylebox_override("panel", _equipment_slot_style(false))

func _equipment_slot_style(equipped: bool) -> StyleBoxFlat:
	var bg := Color(0.12, 0.085, 0.055, 0.90) if equipped else Color(0.06, 0.052, 0.042, 0.72)
	var border := Color(0.86, 0.66, 0.36, 0.92) if equipped else Color(0.33, 0.25, 0.16, 0.70)
	var style := PixelUiTheme.button_style(bg, true)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(2)
	return style

func _add_resource_icon_row(parent: Container, id: String, icon_path: String, text: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "%sDisplay" % ("Health" if id == "hp" else id.capitalize())
	_block_mouse(row)
	row.add_theme_constant_override("separation", 3)
	row.tooltip_text = "%s 상세 보기" % text
	row.gui_input.connect(func(event): _on_resource_row_gui_input(event, id, row))
	parent.add_child(row)
	var icons := HBoxContainer.new()
	icons.name = "Icons"
	_ignore_mouse(icons)
	icons.add_theme_constant_override("separation", 0)
	row.add_child(icons)
	var texture := _load_texture(icon_path)
	for index in range(RESOURCE_ICON_COUNT):
		var icon := TextureRect.new()
		icon.name = "Icon%d" % (index + 1)
		icon.custom_minimum_size = RESOURCE_ICON_SIZE
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_meta("empty_color", Color(0.20, 0.16, 0.13, 0.72))
		icon.set_meta("filled_color", color)
		_ignore_mouse(icon)
		icons.add_child(icon)
	labels["%s_icons" % id] = icons
	var value := _label(text, 8)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return value

func _build_resource_detail_panel(parent: Control) -> void:
	var panel := _panel(RESOURCE_DETAIL_PANEL_SIZE)
	panel.name = "ResourceDetailPanel"
	panel.visible = false
	_block_mouse(panel)
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			panel.accept_event()
	)
	parent.add_child(panel)
	_panels.resource_detail = panel
	_resource_detail_label = _label("", 10)
	panel.add_child(_resource_detail_label)

func _on_resource_row_gui_input(event: InputEvent, _id: String, row: Control) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if not pressed:
		return
	row.accept_event()
	var panel := _panels.get("resource_detail") as Control
	if panel == null:
		return
	if panel.visible:
		panel.visible = false
		_resource_detail_id = ""
		if _request_layout.is_valid():
			_request_layout.call()
		return
	_resource_detail_id = "all"
	panel.visible = true
	panel.move_to_front()
	if _runtime_read_model.is_valid():
		_update_resource_detail(_runtime_read_model.call())
	if _request_layout.is_valid():
		_request_layout.call()

func _update_resource_detail(model: Dictionary) -> void:
	if _resource_detail_label == null or _resource_detail_id.is_empty():
		return
	_resource_detail_label.text = "자원 상세\n체력 %d / %d\n기운 %d / %d\n心 %d / %d" % [
		int(model.hp), int(model.hp_max),
		int(model.ki), int(model.ki_max),
		int(model.kokoro), int(model.kokoro_max)
	]

func _update_resource_icons(id: String, current: int, maximum: int) -> void:
	var icons := labels.get(id) as HBoxContainer
	if icons == null:
		return
	var filled_units := clampf(float(current) / float(maximum), 0.0, 1.0) * RESOURCE_ICON_COUNT if maximum > 0 else 0.0
	for index in range(icons.get_child_count()):
		var icon := icons.get_child(index) as TextureRect
		if icon != null:
			var fill_ratio := clampf(filled_units - float(index), 0.0, 1.0)
			icon.set_meta("fill_ratio", fill_ratio)
			icon.modulate = (icon.get_meta("empty_color") as Color).lerp(icon.get_meta("filled_color") as Color, fill_ratio)

func _portrait_box(asset_id: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = PORTRAIT_BOX_SIZE
	box.add_theme_stylebox_override("panel", PixelUiTheme.button_style(Color(0.12, 0.08, 0.05, 0.86)))
	_ignore_mouse(box)
	var texture := TextureRect.new()
	texture.name = "PortraitTexture"
	texture.custom_minimum_size = PORTRAIT_BOX_SIZE - Vector2(8, 8)
	texture.texture = _load_texture(asset_id)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(texture)
	return box

func _set_label(id: String, text: String) -> void:
	var label := labels.get(id) as Label
	if label != null:
		label.text = text

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	return panel

func _label(text: String, font_size := 12) -> Label:
	var label := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _load_texture(reference: String) -> Texture2D:
	return _texture_resolver.call(reference) as Texture2D if _texture_resolver.is_valid() else null

func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _block_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
