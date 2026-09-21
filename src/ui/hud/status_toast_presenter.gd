extends RefCounted

const PixelUiTheme = preload("res://src/ui/pixel_ui_theme.gd")

const STATUS_TOAST_DURATION := 0.9
const STATUS_TOAST_MAX_VISIBLE_QUEUE := 4
const STATUS_TOAST_ICON_SIZE := Vector2(18, 18)
const STATUS_TOAST_PANEL_SIZE := Vector2(300, 32)

var _toast_queue: Array[Dictionary] = []
var _active_toast: Dictionary = {}
var _toast_label: Label
var _toast_icon: TextureRect
var _toast_panel: PanelContainer
var _toast_remaining := 0.0
var _texture_resolver: Callable
var _presented: Callable

func build(parent: Control, deps: Dictionary) -> Dictionary:
	_texture_resolver = deps.get("texture_resolver", Callable())
	_presented = deps.get("presented", Callable())
	_toast_panel = _panel(STATUS_TOAST_PANEL_SIZE)
	_toast_panel.name = "StatusToastPanel"
	_toast_panel.z_index = 100
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	parent.add_child(_toast_panel)
	var toast_row := HBoxContainer.new()
	toast_row.name = "StatusToastRow"
	toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_row.add_theme_constant_override("separation", 5)
	_ignore_mouse(toast_row)
	_toast_panel.add_child(toast_row)
	_toast_icon = TextureRect.new()
	_toast_icon.name = "StatusToastIcon"
	_toast_icon.custom_minimum_size = STATUS_TOAST_ICON_SIZE
	_toast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_toast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_toast_icon.visible = false
	_ignore_mouse(_toast_icon)
	toast_row.add_child(_toast_icon)
	_toast_label = _label("")
	_toast_label.name = "StatusToastLabel"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.clip_text = true
	_toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	toast_row.add_child(_toast_label)
	return {"toast": _toast_panel}

func enqueue(model: Dictionary) -> bool:
	var message := String(model.get("message", ""))
	if message.is_empty():
		return false
	var event_key := String(model.get("event_key", message))
	if event_key == _active_toast_key():
		return false
	for pending in _toast_queue:
		if String(pending.get("event_key", "")) == event_key:
			return false
	if _active_toast.is_empty() and _toast_queue.size() >= STATUS_TOAST_MAX_VISIBLE_QUEUE:
		_toast_queue.pop_front()
	elif not _active_toast.is_empty() and _toast_queue.size() >= STATUS_TOAST_MAX_VISIBLE_QUEUE - 1:
		_toast_queue.pop_front()
	var normalized := model.duplicate(true)
	normalized["event_key"] = event_key
	_toast_queue.append(normalized)
	if _toast_label != null and _toast_remaining <= 0.0:
		_advance()
	return true

func tick(delta: float) -> void:
	if _active_toast.is_empty():
		return
	_toast_remaining -= maxf(delta, 0.0)
	if _toast_remaining <= 0.0:
		_advance()

func debug_snapshot() -> Dictionary:
	return {
		"active": _active_toast.duplicate(true),
		"queue": _toast_queue.duplicate(true),
		"remaining": _toast_remaining,
		"panel_visible": _toast_panel.visible if _toast_panel != null else false,
		"label_text": _toast_label.text if _toast_label != null else "",
		"icon_visible": _toast_icon.visible if _toast_icon != null else false,
		"icon_has_texture": _toast_icon.texture != null if _toast_icon != null else false
	}

func panel() -> Control:
	return _toast_panel

func _advance() -> void:
	if _toast_label == null or _toast_queue.is_empty():
		_active_toast.clear()
		if _toast_label != null:
			_toast_label.visible = false
		if _toast_icon != null:
			_toast_icon.visible = false
			_toast_icon.texture = null
		if _toast_panel != null:
			_toast_panel.visible = false
		_toast_remaining = 0.0
		return
	_active_toast = _toast_queue.pop_front()
	_apply(_active_toast)

func _apply(model: Dictionary) -> void:
	var message := String(model.get("message", ""))
	_toast_label.text = message
	_toast_label.visible = not message.is_empty()
	var icon_reference := String(model.get("icon_reference", ""))
	var texture := _load_texture(icon_reference) if not icon_reference.is_empty() else null
	_toast_icon.texture = texture
	_toast_icon.visible = texture != null
	_toast_panel.visible = true
	_toast_remaining = STATUS_TOAST_DURATION
	if _presented.is_valid():
		_presented.call(String(model.get("kind", "")), String(model.get("event_key", message)))

func _active_toast_key() -> String:
	return String(_active_toast.get("event_key", "")) if not _active_toast.is_empty() else ""

func _load_texture(reference: String) -> Texture2D:
	if reference.is_empty() or not _texture_resolver.is_valid():
		return null
	return _texture_resolver.call(reference) as Texture2D

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = size
	panel.custom_minimum_size = size
	_ignore_mouse(panel)
	panel.add_theme_stylebox_override("panel", PixelUiTheme.panel_style())
	return panel

func _label(text: String, font_size := 12) -> Label:
	var label := Label.new()
	_ignore_mouse(label)
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)
