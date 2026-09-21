extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")
const UiContentBounds = preload("res://src/ui/ui_content_bounds.gd")

const ICON_SCROLL := "asset_assets_ui_icons_atlas_scroll_rolled_png"
const MAP_PANEL_SIZE := Vector2(140, 126)
const MAP_PANEL_TIME_HEIGHT := 126.0
const FULL_MAP_CELL_SIZE := Vector2(6, 6)
const COMPACT_MAP_CELL_SIZE := Vector2(4, 4)
const TIME_DIAL_SIZE := Vector2(28, 28)

class TimeDial:
	extends Control
	var phase := "day"
	var progress_percent := 0
	func set_time(value_phase: String, value_progress_percent: int) -> void:
		phase = value_phase
		progress_percent = clampi(value_progress_percent, 0, 100)
		queue_redraw()
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		var track_color := Color(0.29, 0.25, 0.22, 0.92)
		var progress_color := _phase_color()
		draw_circle(center, radius, Color(0.055, 0.049, 0.038, 0.96))
		draw_arc(center, radius, 0.0, TAU, 16, track_color, 2.0, false)
		var filled_segments := int(ceil(float(progress_percent) / 100.0 * 12.0))
		for segment in range(filled_segments):
			var start_angle := -PI * 0.5 + TAU * float(segment) / 12.0
			var end_angle := start_angle + TAU / 12.0 - 0.07
			draw_arc(center, radius, start_angle, end_angle, 2, progress_color, 2.0, false)
		_draw_phase_mark(center, progress_color)

	func _draw_phase_mark(center: Vector2, color: Color) -> void:
		if phase == "night":
			draw_circle(center - Vector2(1.0, 0.0), 4.0, color)
			draw_circle(center + Vector2(1.0, -1.0), 4.0, Color(0.055, 0.049, 0.038, 1.0))
			return
		draw_circle(center, 3.0, color)
		for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(center + direction * 5.0, center + direction * 7.0, color, 1.0, false)

	func _phase_color() -> Color:
		match phase:
			"night":
				return Color(0.37, 0.53, 0.69, 1.0)
			"dusk":
				return Color(0.83, 0.50, 0.18, 1.0)
			_:
				return Color(0.84, 0.65, 0.36, 1.0)

var labels := {}
var _panels := {}
var _minimap_grid: GridContainer
var _time_dial: TimeDial
var _selected_map_biome_id := ""
var _texture_resolver: Callable
var _press_mobile_button: Callable
var _show_detail_popup: Callable
var _request_map_refresh: Callable
var _emit_command: Callable

func build(parent: Control, deps: Dictionary) -> Dictionary:
	_texture_resolver = deps.get("texture_resolver", Callable())
	_press_mobile_button = deps.get("press_mobile_button", Callable())
	_show_detail_popup = deps.get("show_detail_popup", Callable())
	_request_map_refresh = deps.get("request_map_refresh", Callable())
	_emit_command = deps.get("emit_command", Callable())
	var map_panel := _panel(MAP_PANEL_SIZE)
	map_panel.name = "MapPanel"
	map_panel.clip_contents = true
	map_panel.add_theme_stylebox_override("panel", PixelUiTheme.hud_minimap_style())
	parent.add_child(map_panel)
	_panels.map = map_panel
	var map_rows := VBoxContainer.new()
	map_rows.name = "MapRows"
	_ignore_mouse(map_rows)
	map_rows.add_theme_constant_override("separation", 3)
	map_panel.add_child(map_rows)
	labels.map_title = _label("초록 평원", 9)
	labels.map_title.custom_minimum_size = Vector2(0, 14)
	labels.map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.map_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	labels.map_title.add_theme_color_override("font_color", PixelUiTheme.INK_COLOR)
	map_rows.add_child(labels.map_title)
	_build_time_dial_row(map_rows)
	labels.map_stats = _label("타일 0 · 사물 0", 11)
	labels.map_stats.visible = false
	map_rows.add_child(labels.map_stats)
	_minimap_grid = GridContainer.new()
	_minimap_grid.name = "MinimapGrid"
	_minimap_grid.columns = 11
	_minimap_grid.add_theme_constant_override("h_separation", 1)
	_minimap_grid.add_theme_constant_override("v_separation", 1)
	_ignore_mouse(_minimap_grid)
	map_rows.add_child(_minimap_grid)
	var map_open_button := _button()
	map_open_button.name = "MapOpenButton"
	map_open_button.flat = true
	map_open_button.tooltip_text = "지도 열기"
	map_open_button.focus_mode = Control.FOCUS_NONE
	map_open_button.mouse_filter = Control.MOUSE_FILTER_STOP
	map_open_button.pressed.connect(func():
		if _press_mobile_button.is_valid():
			_press_mobile_button.call("open_map")
	)
	map_panel.add_child(map_open_button)
	return _panels.duplicate()

func update(model: Dictionary) -> bool:
	_set_label("map_title", String(model.get("biome_label", "")))
	_set_label("time_phase", String(model.get("time_phase_label", "")))
	_set_label("time_progress", "%d%%" % int(model.get("time_progress_percent", 0)))
	if _time_dial != null:
		_time_dial.set_time(String(model.get("time_phase", "")), int(model.get("time_progress_percent", 0)))
	var time_row := (labels.get("time_phase") as Label).get_parent().get_parent() as Control if labels.get("time_phase") is Label else null
	if time_row != null:
		time_row.visible = bool(model.get("time_visible", false))
	var map_panel := _panels.get("map") as Control
	var map_height := MAP_PANEL_TIME_HEIGHT if bool(model.get("time_visible", false)) else MAP_PANEL_SIZE.y
	var layout_changed := false
	if map_panel != null and not is_equal_approx(map_panel.custom_minimum_size.y, map_height):
		map_panel.custom_minimum_size.y = map_height
		layout_changed = true
	var minimap: Dictionary = model.get("minimap", {})
	_set_label("map_stats", "발견 %d · 표식 %d" % [int(minimap.get("discovered_count", 0)), int(minimap.get("marker_count", 0))] if bool(minimap.get("ok", false)) else "타일 %d · 사물 %d" % [int(model.get("terrain_count", 0)), int(model.get("object_count", 0))])
	_render_minimap_grid(_minimap_grid, minimap.get("minimap", {}) if bool(minimap.get("ok", false)) else {}, Vector2(3, 3))
	return layout_changed

func reset_selection(current_biome_id: String) -> void:
	_selected_map_biome_id = current_biome_id

func selected_biome_id(current_biome_id: String) -> String:
	return _selected_map_biome_id if not _selected_map_biome_id.is_empty() else current_biome_id

func map_rows(context: Dictionary) -> Array:
	var rows: Array = []
	var current_biome_id := String(context.get("current_biome_id", ""))
	var selected_id := String(context.get("selected_biome_id", selected_biome_id(current_biome_id)))
	var model: Dictionary = context.get("map_model", {})
	if not bool(model.get("ok", false)):
		rows.append(_label("지도 read model 없음", 11))
		return rows
	rows.append(_icon_text_row(ICON_SCROLL, "전체 지도 · 접근 가능한 지역", 11))
	rows.append(_biome_map_selector(context))
	var selected := _definition_by_id(context.get("biome_definitions", []), selected_id)
	rows.append(_label("현재 보기: %s%s" % [String(selected.get("name", selected_id)), " · 현재 위치" if selected_id == current_biome_id else ""], 12))
	var accessible_ids: Array = context.get("accessible_ids", [])
	if selected_id != current_biome_id and not accessible_ids.has(selected_id):
		rows.append(_label("이 지역은 아직 잠겨 있습니다. 해금 후 상세 지도가 표시됩니다.", 10))
		return rows
	var bounds: Dictionary = model.get("bounds", {})
	rows.append(_label("%s · %dx%d · 발견 %d · 안개 %d · 던전 %s" % [
		"씨앗 %d" % int(model.get("seed", 0)),
		int(bounds.get("width", 0)),
		int(bounds.get("height", 0)),
		int(model.get("discovered_count", 0)),
		int(model.get("fog_count", 0)),
		"완료" if bool(context.get("dungeon_cleared_current", false)) else "미완료"
	], 10))
	var compact := bool(context.get("compact", false))
	var cell_size := COMPACT_MAP_CELL_SIZE if compact else FULL_MAP_CELL_SIZE
	var map_canvas := CenterContainer.new()
	map_canvas.name = "MapCanvas"
	map_canvas.custom_minimum_size = Vector2(240, 140) if compact else Vector2(340, 196)
	map_canvas.add_child(_map_color_grid(model.get("minimap", {}), cell_size))
	var map_frame := _card_frame(map_canvas)
	map_frame.name = "MapFrame"
	rows.append(map_frame)
	var markers: Array = model.get("markers", [])
	rows.append(_label("표식 %d개 · 선택하면 위치와 설명을 볼 수 있습니다" % markers.size(), 10))
	rows.append(_map_marker_grid(markers, compact))
	return rows

func ruin_travel_rows(context: Dictionary) -> Array:
	var rows: Array = [_label("수리된 다른 유적을 선택하세요", 11)]
	var current_id := String(context.get("current_biome_id", ""))
	var repaired_ids: Array = context.get("repaired_ruin_biome_ids", [])
	for definition in context.get("biome_definitions", []):
		var destination_id := String(definition.get("id", ""))
		if destination_id.is_empty() or destination_id == current_id or not repaired_ids.has(destination_id):
			continue
		var button := _button()
		button.text = "이동 · %s" % String(definition.get("name", destination_id))
		button.custom_minimum_size = Vector2(220, 34)
		button.pressed.connect(func():
			if _emit_command.is_valid():
				_emit_command.call(GameCommand.new(GameCommand.Type.TRAVEL_TO_BIOME, Vector2i.ZERO, -1, {"biome_id": destination_id, "travel_mode": "ruin"}))
		)
		rows.append(button)
	if rows.size() == 1:
		rows.append(_label("이동할 수리 완료 유적이 없습니다", 11))
	rows.append(_label("텔레포트는 별도로 수리·관리됩니다", 10))
	return rows

func teleport_travel_rows(context: Dictionary) -> Array:
	var rows: Array = [_label("수리된 텔레포트 · 연결된 일반 지역을 선택하세요", 11)]
	var projection: Dictionary = context.get("projection", {})
	if projection.is_empty():
		rows.append(_label("바이옴 연결 정보 없음", 11))
		return rows
	var order: Array = projection.get("biome_order", [])
	var current_id := String(context.get("current_biome_id", ""))
	var current_index := order.find(current_id)
	var destinations: Array = []
	for index in [current_index - 1, current_index + 1]:
		if index < 0 or index >= order.size():
			continue
		var destination_id := String(order[index])
		if index > current_index and String(projection.get("next_biome_id", "")) != destination_id:
			continue
		if index > current_index and not bool(projection.get("can_advance_biome", false)):
			continue
		destinations.append(destination_id)
	for destination_id in destinations:
		var definition := _definition_by_id(context.get("biome_definitions", []), destination_id)
		var button := _button()
		button.text = "이동 · %s" % String(definition.get("name", destination_id))
		button.custom_minimum_size = Vector2(220, 34)
		button.pressed.connect(func():
			if _emit_command.is_valid():
				_emit_command.call(GameCommand.new(GameCommand.Type.TRAVEL_TO_BIOME, Vector2i.ZERO, -1, {"biome_id": destination_id, "travel_mode": "teleport"}))
		)
		rows.append(button)
	if destinations.is_empty():
		rows.append(_label("현재 연결된 다른 일반 지역이 없습니다", 11))
	return rows

func _biome_map_selector(context: Dictionary) -> Control:
	var strip := GridContainer.new()
	strip.name = "BiomeMapSelector"
	var definitions: Array = context.get("biome_definitions", [])
	strip.columns = maxi(1, ceili(definitions.size() / 2.0))
	strip.add_theme_constant_override("separation", 4)
	for definition in definitions:
		var biome_id := String(definition.get("id", ""))
		var button := _button()
		button.name = "BiomeMap_%s" % biome_id
		button.text = String(definition.get("name", biome_id))
		button.tooltip_text = "선택하여 지역 지도 보기"
		button.custom_minimum_size = Vector2(86, 30)
		button.disabled = biome_id == String(context.get("current_biome_id", "")) and _selected_map_biome_id == biome_id
		button.pressed.connect(func():
			_selected_map_biome_id = biome_id
			if _request_map_refresh.is_valid():
				_request_map_refresh.call()
		)
		strip.add_child(button)
	if strip.get_child_count() == 0:
		strip.add_child(_label("지역 데이터 없음", 10))
	return strip

func _map_marker_grid(markers: Array, compact: bool) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "MapMarkerGrid"
	grid.columns = 2 if compact else 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var totals := {}
	for marker in markers:
		var name := String(marker.get("display_name", _marker_label(String(marker.get("marker_type", "")))))
		totals[name] = int(totals.get(name, 0)) + 1
	var seen := {}
	for marker in markers:
		var name := String(marker.get("display_name", _marker_label(String(marker.get("marker_type", "")))))
		seen[name] = int(seen.get(name, 0)) + 1
		grid.add_child(_map_marker_button(marker, "%s %d" % [name, seen[name]] if int(totals[name]) > 1 else name))
	return grid

func _map_marker_button(marker: Dictionary, display_name := "") -> Button:
	var button := _button()
	button.name = "MapMarker_%s" % String(marker.get("id", "unknown"))
	button.text = "%s%s" % [display_name, " ?" if not bool(marker.get("discovered", true)) else ""]
	button.tooltip_text = String(marker.get("description", "상세 정보를 봅니다."))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(104, 26)
	button.pressed.connect(func(): _show_map_marker_info(marker))
	return button

func _show_map_marker_info(marker: Dictionary) -> void:
	if not _show_detail_popup.is_valid():
		return
	var position: Dictionary = marker.get("position", {})
	var marker_type := String(marker.get("marker_type", ""))
	var status := "확인됨" if bool(marker.get("discovered", true)) else "미발견"
	var info := "%s\n종류: %s\n좌표: (%d, %d)\n상태: %s" % [
		String(marker.get("description", "지도에 표시된 중요한 장소입니다.")),
		_marker_label(marker_type),
		int(position.get("x", 0)),
		int(position.get("y", 0)),
		status
	]
	var card := _detail_card("위치 정보")
	var rows := card.get_node("Rows") as VBoxContainer
	rows.add_child(_wrapped_label(info, 11))
	_show_detail_popup.call(String(marker.get("display_name", "중요 지점")), card)

func _map_color_grid(minimap: Dictionary, cell_size: Vector2) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "MapColorGrid"
	_ignore_mouse(grid)
	var size: Dictionary = minimap.get("size", {})
	grid.columns = maxi(1, int(size.get("width", 1)))
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	_render_minimap_grid(grid, minimap, cell_size)
	return grid

func _render_minimap_grid(grid: GridContainer, minimap: Dictionary, cell_size: Vector2) -> void:
	if grid == null:
		return
	_clear_container_children(grid)
	var size: Dictionary = minimap.get("size", {})
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0 or height <= 0:
		return
	grid.columns = width
	var marker_data_by_position := {}
	for marker in _array_value(minimap.get("markers", [])):
		var marker_position: Dictionary = marker.get("position", {})
		marker_data_by_position["%d,%d" % [int(marker_position.get("x", 0)), int(marker_position.get("y", 0))]] = marker
	var cell_by_position := {}
	for cell in _array_value(minimap.get("cells", [])):
		var cell_position: Dictionary = cell.get("position", {})
		cell_by_position["%d,%d" % [int(cell_position.get("x", 0)), int(cell_position.get("y", 0))]] = cell
	var origin: Dictionary = minimap.get("origin", {})
	for y in range(int(origin.get("y", 0)), int(origin.get("y", 0)) + height):
		for x in range(int(origin.get("x", 0)), int(origin.get("x", 0)) + width):
			var key := "%d,%d" % [x, y]
			var tile: Control
			if marker_data_by_position.has(key):
				var marker: Dictionary = marker_data_by_position[key]
				var marker_button := _button()
				var marker_color := _minimap_marker_color(String(marker.get("marker_type", "")))
				marker_button.text = ""
				marker_button.custom_minimum_size = cell_size
				marker_button.add_theme_stylebox_override("normal", PixelUiTheme.button_style(marker_color))
				marker_button.add_theme_stylebox_override("hover", PixelUiTheme.button_style(marker_color.lightened(0.16)))
				marker_button.add_theme_stylebox_override("pressed", PixelUiTheme.button_style(marker_color.darkened(0.16)))
				marker_button.name = "MapMarker_%s" % String(marker.get("id", "unknown"))
				marker_button.tooltip_text = "%s: %s" % [String(marker.get("display_name", "중요 지점")), String(marker.get("description", "상세 정보를 봅니다."))]
				marker_button.pressed.connect(func(): _show_map_marker_info(marker))
				tile = marker_button
			else:
				var color_tile := ColorRect.new()
				color_tile.custom_minimum_size = cell_size
				color_tile.color = _minimap_cell_color(cell_by_position.get(key, {}))
				tile = color_tile
				_ignore_mouse(tile)
			grid.add_child(tile)

func _minimap_cell_color(cell: Dictionary) -> Color:
	if cell.is_empty() or bool(cell.get("fog", true)):
		return Color(0.05, 0.05, 0.05, 0.88)
	var terrain_id := String(cell.get("terrain_id", ""))
	if "water" in terrain_id or "river" in terrain_id or "ice" in terrain_id:
		return Color(0.18, 0.43, 0.68, 0.95)
	if "forest" in terrain_id or "tree" in terrain_id or "jungle" in terrain_id or "pine" in terrain_id:
		return Color(0.16, 0.45, 0.22, 0.95)
	if "mountain" in terrain_id or "rock" in terrain_id or "cliff" in terrain_id:
		return Color(0.42, 0.42, 0.36, 0.95)
	if "path" in terrain_id or "road" in terrain_id:
		return Color(0.63, 0.53, 0.33, 0.95)
	if "snow" in terrain_id:
		return Color(0.78, 0.84, 0.88, 0.95)
	return Color(0.43, 0.57, 0.28, 0.95)

func _minimap_marker_color(marker_type: String) -> Color:
	match marker_type:
		"player":
			return Color(1.0, 0.95, 0.48, 1.0)
		"dungeon":
			return Color(0.76, 0.28, 0.22, 1.0)
		"teleport":
			return Color(0.56, 0.38, 0.92, 1.0)
		_:
			return Color(0.95, 0.72, 0.32, 1.0)

func _marker_label(marker_type: String) -> String:
	match marker_type:
		"player":
			return "플레이어"
		"dungeon":
			return "던전"
		"ruin":
			return "유적"
		"teleport":
			return "텔레포트"
		_:
			return "표식"

func _build_time_dial_row(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "TimeDialRow"
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	_time_dial = TimeDial.new()
	_time_dial.name = "TimeDial"
	_time_dial.custom_minimum_size = TIME_DIAL_SIZE
	_ignore_mouse(_time_dial)
	row.add_child(_time_dial)
	var time_labels := VBoxContainer.new()
	time_labels.name = "TimeLabels"
	_ignore_mouse(time_labels)
	time_labels.add_theme_constant_override("separation", -2)
	row.add_child(time_labels)
	labels.time_phase = _label("낮", 10)
	time_labels.add_child(labels.time_phase)
	labels.time_progress = _label("0%", 9)
	labels.time_progress.modulate = Color(0.84, 0.65, 0.36, 1.0)
	time_labels.add_child(labels.time_progress)

func _definition_by_id(definitions: Array, id: String) -> Dictionary:
	for definition in definitions:
		if String(definition.get("id", "")) == id:
			return definition
	return {}

func _icon_text_row(icon_reference: String, text: String, font_size := 11) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "IconTextRow"
	_ignore_mouse(row)
	row.add_theme_constant_override("separation", 6)
	row.add_child(_item_icon_rect(icon_reference, Vector2(24, 24)))
	var label := _label(text, font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

func _item_icon_rect(icon_reference: String, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(icon_reference)
	_ignore_mouse(icon)
	return icon

func _detail_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "DetailCard"
	card.custom_minimum_size = Vector2(288, 42)
	_ignore_mouse(card)
	var card_style := PixelUiTheme.parchment_card_style(false)
	card_style.content_margin_left += 6.0
	card_style.content_margin_top += 4.0
	card_style.content_margin_right += 6.0
	card_style.content_margin_bottom += 4.0
	card.add_theme_stylebox_override("panel", card_style)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	_ignore_mouse(rows)
	rows.add_theme_constant_override("separation", 3)
	card.add_child(rows)
	rows.add_child(_wrapped_label(title, 11))
	return card

func _wrapped_label(text: String, font_size := 12) -> Label:
	var label := _label(text, font_size)
	UiContentBounds.fit_label(label, true, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _card_frame(content: Control, selected := false) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = content.custom_minimum_size + Vector2(6, 6)
	_ignore_mouse(frame)
	frame.add_theme_stylebox_override("panel", PixelUiTheme.parchment_card_style(selected))
	frame.add_child(content)
	return frame

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	return panel

func _button() -> Button:
	return UiContentBounds.fit_button(Button.new())

func _label(text: String, font_size := 12) -> Label:
	var label := UiContentBounds.fit_label(Label.new())
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _set_label(id: String, text: String) -> void:
	var label := labels.get(id) as Label
	if label != null:
		label.text = text

func _load_texture(reference: String) -> Texture2D:
	return _texture_resolver.call(reference) as Texture2D if _texture_resolver.is_valid() else null

func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

func _clear_container_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
