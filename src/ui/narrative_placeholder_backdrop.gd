extends Control
class_name NarrativePlaceholderBackdrop

const INK := Color("2a271f")
const CHARCOAL := Color("4a4038")
const PAPER := Color("fff7e7")
const CLAY := Color("a88b62")
const TEA_LEAF := Color("979a47")
const MOSS := Color("3f5f4a")
const FOX_RUSSET := Color("d3802f")
const CREAM := Color("e6cfa4")
const STEAM := Color("c9d7c0")
const RIVER := Color("5f879b")
const NIGHT := Color("2f3e5c")
const CINNABAR := Color("a95f23")
const GOLD := Color("d6a75d")
const VIOLET := Color("7a668e")

const PROLOGUE_BACKDROPS := {
	"story_pro_01::dlg_pro_000": {"variant": 0, "sky": CREAM, "ground": CLAY, "accent": FOX_RUSSET},
	"story_pro_01::dlg_pro_001": {"variant": 1, "sky": PAPER, "ground": TEA_LEAF, "accent": CINNABAR},
	"story_pro_02::dlg_pro_002": {"variant": 2, "sky": STEAM, "ground": MOSS, "accent": GOLD},
	"story_pro_03::dlg_1": {"variant": 3, "sky": RIVER, "ground": CLAY, "accent": CREAM},
	"story_pro_04::dlg_pro_004": {"variant": 4, "sky": NIGHT, "ground": CHARCOAL, "accent": GOLD},
	"story_pro_05::dlg_pro_005a": {"variant": 5, "sky": VIOLET, "ground": NIGHT, "accent": STEAM},
	"story_pro_05::dlg_pro_005b": {"variant": 6, "sky": NIGHT, "ground": MOSS, "accent": CINNABAR},
	"story_pro_06::dlg_pro_006": {"variant": 7, "sky": CLAY, "ground": CHARCOAL, "accent": FOX_RUSSET},
	"story_pro_07::dlg_4": {"variant": 8, "sky": STEAM, "ground": TEA_LEAF, "accent": RIVER},
	"story_pro_07::dlg_pro_007b": {"variant": 9, "sky": VIOLET, "ground": CHARCOAL, "accent": GOLD},
	"story_pro_08::dlg_pro_008": {"variant": 10, "sky": NIGHT, "ground": INK, "accent": PAPER}
}

var _key := ""
var _backdrop := {}

func _ready() -> void:
	name = "NarrativePlaceholderBackdrop"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_for(read_model: Dictionary) -> void:
	_key = "%s::%s" % [read_model.get("event_id", ""), read_model.get("node_id", "")]
	_backdrop = PROLOGUE_BACKDROPS.get(_key, _fallback_backdrop(_key)).duplicate(true)
	visible = true
	queue_redraw()

func hide_backdrop() -> void:
	visible = false
	_key = ""
	_backdrop.clear()
	queue_redraw()

func debug_signature() -> Dictionary:
	return {
		"key": _key,
		"variant": int(_backdrop.get("variant", -1)),
		"opaque": not _key.is_empty() and float((_backdrop.get("sky", Color.TRANSPARENT) as Color).a) >= 1.0
	}

func _draw() -> void:
	if _key.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var sky: Color = _backdrop.get("sky", NIGHT)
	var ground: Color = _backdrop.get("ground", INK)
	var accent: Color = _backdrop.get("accent", GOLD)
	var variant := int(_backdrop.get("variant", 0))
	var horizon := snappedf(size.y * (0.52 + float(variant % 3) * 0.06), 4.0)
	draw_rect(Rect2(Vector2.ZERO, size), sky)
	draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), ground)
	_draw_horizon(variant, horizon, accent)
	_draw_identity_marks(variant, horizon, accent)

func _draw_horizon(variant: int, horizon: float, accent: Color) -> void:
	match variant:
		0, 1:
			_draw_teahouse(horizon, accent, variant == 1)
		2, 8:
			_draw_forest(horizon, accent, variant == 8)
		3:
			_draw_shore(horizon, accent)
		4, 9:
			_draw_mountains(horizon, accent, variant == 9)
		5, 6:
			_draw_cave(horizon, accent, variant == 6)
		7:
			_draw_gate(horizon, accent)
		10:
			_draw_distant_light(horizon, accent)

func _draw_teahouse(horizon: float, accent: Color, late_light: bool) -> void:
	var center := size.x * 0.5
	var house_width := minf(size.x * 0.34, 280.0)
	var wall_top := horizon - 72.0
	draw_rect(Rect2(center - house_width * 0.5, wall_top, house_width, 72.0), CREAM if not late_light else CLAY)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center - house_width * 0.62, wall_top), Vector2(center, wall_top - 48.0),
		Vector2(center + house_width * 0.62, wall_top), Vector2(center + house_width * 0.52, wall_top + 12.0),
		Vector2(center - house_width * 0.52, wall_top + 12.0)
	]), INK)
	draw_rect(Rect2(center - 18.0, horizon - 50.0, 36.0, 50.0), CHARCOAL)
	draw_rect(Rect2(center - house_width * 0.35, horizon - 46.0, 32.0, 24.0), accent)
	draw_rect(Rect2(center + house_width * 0.35 - 32.0, horizon - 46.0, 32.0, 24.0), accent)

func _draw_forest(horizon: float, accent: Color, pale_trunks: bool) -> void:
	var trunk_color := CREAM if pale_trunks else CHARCOAL
	for index in range(7):
		var x := size.x * (0.08 + float(index) * 0.14)
		var height := 64.0 + float((index * 19) % 52)
		draw_rect(Rect2(x - 7.0, horizon - height, 14.0, height), trunk_color)
		draw_circle(Vector2(x, horizon - height), 27.0 + float(index % 3) * 6.0, accent)

func _draw_shore(horizon: float, accent: Color) -> void:
	for index in range(5):
		var y := horizon + 18.0 + float(index) * 18.0
		var offset := 24.0 if index % 2 == 0 else 64.0
		for x in range(int(offset), int(size.x), 112):
			draw_rect(Rect2(float(x), y, 64.0, 5.0), accent)
	var sun_position := Vector2(size.x * 0.72, horizon * 0.36)
	draw_circle(sun_position, 30.0, CREAM)

func _draw_mountains(horizon: float, accent: Color, moonlit: bool) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, horizon), Vector2(size.x * 0.24, horizon - 136.0),
		Vector2(size.x * 0.46, horizon), Vector2(size.x * 0.68, horizon - 184.0),
		Vector2(size.x, horizon), Vector2(size.x, horizon + 1.0), Vector2(0.0, horizon + 1.0)
	]), CHARCOAL if not moonlit else VIOLET)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.53, horizon - 58.0), Vector2(size.x * 0.68, horizon - 184.0),
		Vector2(size.x * 0.77, horizon - 72.0), Vector2(size.x * 0.68, horizon - 104.0)
	]), accent)
	if moonlit:
		draw_circle(Vector2(size.x * 0.22, horizon * 0.28), 28.0, CREAM)

func _draw_cave(horizon: float, accent: Color, crystals: bool) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x, horizon * 0.38),
		Vector2(size.x * 0.78, horizon * 0.26), Vector2(size.x * 0.62, horizon * 0.44),
		Vector2(size.x * 0.42, horizon * 0.22), Vector2(size.x * 0.24, horizon * 0.42),
		Vector2(0.0, horizon * 0.30)
	]), INK)
	for index in range(5):
		var x := size.x * (0.18 + float(index) * 0.16)
		var height := 28.0 + float((index * 13) % 38)
		var color := accent if crystals or index % 2 == 0 else CHARCOAL
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 12.0, horizon), Vector2(x, horizon - height), Vector2(x + 12.0, horizon)
		]), color)

func _draw_gate(horizon: float, accent: Color) -> void:
	var center := size.x * 0.5
	draw_rect(Rect2(center - 112.0, horizon - 112.0, 18.0, 112.0), CINNABAR)
	draw_rect(Rect2(center + 94.0, horizon - 112.0, 18.0, 112.0), CINNABAR)
	draw_rect(Rect2(center - 142.0, horizon - 126.0, 284.0, 18.0), accent)
	draw_rect(Rect2(center - 118.0, horizon - 98.0, 236.0, 12.0), CINNABAR)

func _draw_distant_light(horizon: float, accent: Color) -> void:
	var center := Vector2(size.x * 0.5, horizon * 0.46)
	for radius in [72.0, 48.0, 24.0]:
		draw_circle(center, radius, accent if radius == 24.0 else (VIOLET if radius == 48.0 else CHARCOAL))
	for index in range(9):
		var x := size.x * float(index + 1) / 10.0
		draw_rect(Rect2(x - 3.0, horizon + float(index % 3) * 12.0, 6.0, size.y - horizon), accent)

func _draw_identity_marks(variant: int, horizon: float, accent: Color) -> void:
	var mark_size := maxf(6.0, floorf(minf(size.x, size.y) / 72.0) * 2.0)
	var start := Vector2(mark_size * 2.0, minf(horizon - mark_size * 3.0, size.y * 0.12))
	for bit in range(4):
		if (variant + 1) & (1 << bit):
			draw_rect(Rect2(start.x + float(bit) * mark_size * 2.0, start.y, mark_size, mark_size * 2.0), accent)

func _fallback_backdrop(key: String) -> Dictionary:
	var variant := absi(key.hash()) % 11
	return {"variant": variant, "sky": NIGHT, "ground": INK, "accent": GOLD}
