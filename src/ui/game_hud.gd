extends CanvasLayer
class_name GameHud

const ICON_HP := "res://assets/ui/icons/hp_heart_32.png"
const ICON_KI := "res://assets/ui/icons/tea_cup_32.png"
const ICON_KOKORO := "res://assets/ui/icons/tea_leaf_32.png"
const ICON_COIN := "res://assets/ui/icons/coin_32.png"
const ICON_MAP := "res://assets/ui/icons/map_pin_32.png"

var player
var world: Dictionary = {}
var render_result: Dictionary = {}
var _labels: Dictionary = {}
var _built := false

func _ready() -> void:
	_build()

func configure(player_node, generated_world: Dictionary, generated_render_result: Dictionary) -> void:
	player = player_node
	world = generated_world.duplicate(true)
	render_result = generated_render_result.duplicate(true)
	_build()
	_update()

func _process(_delta: float) -> void:
	_update()

func _build() -> void:
	if _built:
		return
	_built = true

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_left := _panel(Vector2(16, 16), Vector2(250, 132))
	top_left.name = "StatusPanel"
	root.add_child(top_left)
	var status_rows := VBoxContainer.new()
	status_rows.add_theme_constant_override("separation", 6)
	top_left.add_child(status_rows)
	_labels.hp = _add_icon_row(status_rows, ICON_HP, "HP")
	_labels.ki = _add_icon_row(status_rows, ICON_KI, "KI")
	_labels.kokoro = _add_icon_row(status_rows, ICON_KOKORO, "KOKORO")
	_labels.currency = _add_icon_row(status_rows, ICON_COIN, "0")

	var top_right := _panel(Vector2(-276, 16), Vector2(260, 96), true)
	top_right.name = "MapPanel"
	root.add_child(top_right)
	var map_rows := VBoxContainer.new()
	map_rows.add_theme_constant_override("separation", 8)
	top_right.add_child(map_rows)
	_labels.map_title = _add_icon_row(map_rows, ICON_MAP, "초록 평원")
	_labels.map_stats = _label("tiles 0 / objects 0")
	map_rows.add_child(_labels.map_stats)

	var bottom := _panel(Vector2(16, -96), Vector2(420, 80), false, true)
	bottom.name = "QuickSlotPanel"
	root.add_child(bottom)
	var quick_rows := HBoxContainer.new()
	quick_rows.add_theme_constant_override("separation", 10)
	bottom.add_child(quick_rows)
	_add_icon_row(quick_rows, ICON_KOKORO, "찻잎")
	_add_icon_row(quick_rows, ICON_KI, "차")
	_add_icon_row(quick_rows, "res://assets/ui/icons/scroll_32.png", "기록")
	_add_icon_row(quick_rows, "res://assets/ui/icons/key_32.png", "상호작용")

func _update() -> void:
	if not _built:
		return
	if player != null and player.get("resources") != null:
		var resources = player.resources
		_set_label("hp", "%d / %d" % [resources.hp, resources.hp_max])
		_set_label("ki", "%d / %d" % [resources.ki, resources.ki_max])
		_set_label("kokoro", "%d / %d" % [resources.kokoro, resources.kokoro_max])
	else:
		_set_label("hp", "-- / --")
		_set_label("ki", "-- / --")
		_set_label("kokoro", "-- / --")
	_set_label("currency", "0")

	var biome := String(world.get("biome_id", "common_region"))
	_set_label("map_title", _biome_label(biome))
	var counts: Dictionary = render_result.get("counts", {})
	_set_label(
		"map_stats",
		"tiles %d / objects %d" % [
			int(counts.get("terrain", 0)),
			int(counts.get("entities", 0)) + int(counts.get("Landmarks", 0))
		]
	)

func _panel(offset: Vector2, size: Vector2, from_right := false, from_bottom := false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	if from_right:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
	if from_bottom:
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
	panel.offset_left = offset.x
	panel.offset_top = offset.y
	panel.offset_right = offset.x + size.x
	panel.offset_bottom = offset.y + size.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.049, 0.038, 0.86)
	style.border_color = Color(0.73, 0.55, 0.31, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _add_icon_row(parent: Container, icon_path: String, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(icon_path)
	row.add_child(icon)
	var value := _label(text)
	row.add_child(value)
	return value

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.93, 0.83, 0.63, 1.0))
	return label

func _set_label(id: String, text: String) -> void:
	var label := _labels.get(id) as Label
	if label != null:
		label.text = text

func _biome_label(id: String) -> String:
	match id:
		"common_region":
			return "초록 평원"
		"mountain_region":
			return "산악 지대"
		"snowfield":
			return "설원"
		"rainforest":
			return "열대 우림"
		"wasteland":
			return "황무지"
		_:
			return id

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
