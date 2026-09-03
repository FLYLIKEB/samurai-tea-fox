extends RefCounted
class_name RuntimeConstants

const PATH := "res://data/runtime_constants.json"
const REQUIRED_IDS := [
	"world.overworld_width", "world.overworld_height", "world.chunk_width", "world.chunk_height",
	"world.generation_retry_limit", "world.tile_size_pixels", "world.default_seed", "game.turn_seconds",
	"input.pointer_stop_distance_pixels", "camera.discovery_radius", "camera.minimap_width", "camera.minimap_height",
	"camera.zoom", "placement.search_radius", "placement.use_distance",
	"player.movement_speed_pixels_per_second", "combat.attack_range_pixels", "combat.hit_flash_seconds",
	"combat.damage_popup_seconds", "combat.damage_popup_rise_pixels", "combat.grid_step_tween_seconds",
	"audio.feedback_mix_rate", "audio.feedback_beep_seconds", "audio.feedback_beep_frequency",
	"narrative.the_end_duration_seconds"
]

static var _values: Dictionary = _load_values()

static func int_value(id: String) -> int:
	var value = _required(id)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		push_error("Runtime constant must be numeric: %s" % id)
		return 0
	return int(value)

static func float_value(id: String) -> float:
	var value = _required(id)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		push_error("Runtime constant must be numeric: %s" % id)
		return 0.0
	return float(value)

static func _required(id: String):
	if not _values.has(id):
		push_error("Missing required runtime constant: %s" % id)
		return 0
	return _values[id]

static func _load_values() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("Missing runtime constants file: %s" % PATH)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schema_version", 0)) != 1:
		push_error("Invalid runtime constants file: %s" % PATH)
		return {}
	var values = parsed.get("values", {})
	if typeof(values) != TYPE_DICTIONARY:
		push_error("Runtime constants values must be a dictionary: %s" % PATH)
		return {}
	for id in REQUIRED_IDS:
		if not values.has(id):
			push_error("Missing required runtime constant: %s" % id)
			return {}
	return values
