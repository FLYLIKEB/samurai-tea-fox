extends Node
class_name SfxEventRouter

const SFX_BUS_NAME := "SFX"
const DEFAULT_BUS_VOLUME_DB := -6.0
const DEFAULT_STREAM_PATH := "res://assets/audio/sfx/procedural_sfx.tres"

const EVENT_STEP := "player_step"
const EVENT_UI_SELECT := "ui_select"
const EVENT_UI_MENU_OPEN := "ui_menu_open"
const EVENT_UI_MENU_CLOSE := "ui_menu_close"
const EVENT_UI_FAIL := "ui_fail"
const EVENT_GATHER_WOOD := "gather_wood"
const EVENT_GATHER_STONE := "gather_stone"
const EVENT_ITEM_PICKUP := "item_pickup"
const EVENT_ATTACK_SWING := "attack_swing"
const EVENT_COMBAT_HIT := "combat_hit"
const EVENT_PLAYER_HIT := "player_hit"
const EVENT_DODGE := "dodge"
const EVENT_INTERACT_SUCCESS := "interact_success"
const EVENT_INTERACT_FAIL := "interact_fail"

const EVENTS := {
	EVENT_STEP: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -14.0, "pitch_scale": 0.92, "cooldown_msec": 90, "frequency_hz": 180.0, "duration_sec": 0.045, "wave": "noise"},
	EVENT_UI_SELECT: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -18.0, "pitch_scale": 1.25, "cooldown_msec": 45, "frequency_hz": 880.0, "duration_sec": 0.035, "wave": "sine"},
	EVENT_UI_MENU_OPEN: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -17.0, "pitch_scale": 1.0, "cooldown_msec": 80, "frequency_hz": 620.0, "duration_sec": 0.07, "wave": "triangle"},
	EVENT_UI_MENU_CLOSE: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -17.0, "pitch_scale": 0.82, "cooldown_msec": 80, "frequency_hz": 520.0, "duration_sec": 0.06, "wave": "triangle"},
	EVENT_UI_FAIL: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -16.0, "pitch_scale": 0.65, "cooldown_msec": 120, "frequency_hz": 220.0, "duration_sec": 0.08, "wave": "square"},
	EVENT_GATHER_WOOD: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -11.0, "pitch_scale": 0.78, "cooldown_msec": 110, "frequency_hz": 150.0, "duration_sec": 0.09, "wave": "noise"},
	EVENT_GATHER_STONE: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -10.0, "pitch_scale": 0.55, "cooldown_msec": 130, "frequency_hz": 120.0, "duration_sec": 0.075, "wave": "square"},
	EVENT_ITEM_PICKUP: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -14.0, "pitch_scale": 1.45, "cooldown_msec": 80, "frequency_hz": 1040.0, "duration_sec": 0.055, "wave": "sine"},
	EVENT_ATTACK_SWING: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -12.0, "pitch_scale": 0.95, "cooldown_msec": 95, "frequency_hz": 340.0, "duration_sec": 0.07, "wave": "noise"},
	EVENT_COMBAT_HIT: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -10.0, "pitch_scale": 0.72, "cooldown_msec": 70, "frequency_hz": 170.0, "duration_sec": 0.06, "wave": "square"},
	EVENT_PLAYER_HIT: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -9.0, "pitch_scale": 0.58, "cooldown_msec": 120, "frequency_hz": 130.0, "duration_sec": 0.09, "wave": "square"},
	EVENT_DODGE: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -13.0, "pitch_scale": 1.12, "cooldown_msec": 100, "frequency_hz": 420.0, "duration_sec": 0.055, "wave": "noise"},
	EVENT_INTERACT_SUCCESS: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -15.0, "pitch_scale": 1.05, "cooldown_msec": 80, "frequency_hz": 700.0, "duration_sec": 0.045, "wave": "triangle"},
	EVENT_INTERACT_FAIL: {"stream_path": DEFAULT_STREAM_PATH, "volume_db": -15.0, "pitch_scale": 0.62, "cooldown_msec": 160, "frequency_hz": 200.0, "duration_sec": 0.08, "wave": "square"}
}
const SFX_EVENT_BY_MATERIAL_TAG := {
	"stone": EVENT_GATHER_STONE,
	"wood": EVENT_GATHER_WOOD
}
const MATERIAL_TAG_BY_ITEM_ID := {
	"branch": "wood",
	"copper_ore": "stone",
	"iron_ore": "stone",
	"ore": "stone",
	"stone": "stone",
	"timber": "wood",
	"wood": "wood"
}
const MATERIAL_TAG_BY_SOURCE_PREFIX := {
	"dungeon_iron_ore_": "stone",
	"dungeon_stone_": "stone",
	"terrain_mountain_mineral_": "stone",
	"terrain_tree_": "wood"
}

var event_counts: Dictionary = {}
var played_events: Array = []
var missing_stream_events: Array = []
var _last_frame_keys: Dictionary = {}
var _last_played_msec: Dictionary = {}

func _ready() -> void:
	_ensure_sfx_bus()

static func event_definition(event_id: String) -> Dictionary:
	return EVENTS.get(event_id, {}).duplicate(true)

static func event_ids() -> Array:
	var ids := EVENTS.keys()
	ids.sort()
	return ids

static func event_id_for_acquisition(result: Dictionary) -> String:
	var kind := String(result.get("kind", ""))
	if kind == "pickup":
		return EVENT_ITEM_PICKUP
	var material := _material_tag_for_acquisition(result)
	return String(SFX_EVENT_BY_MATERIAL_TAG.get(material, EVENT_INTERACT_SUCCESS))

static func _material_tag_for_acquisition(result: Dictionary) -> String:
	var explicit := String(result.get("material_tag", result.get("interaction_tag", "")))
	if SFX_EVENT_BY_MATERIAL_TAG.has(explicit):
		return explicit
	var item_id := String(result.get("item_id", ""))
	var item_tag := String(MATERIAL_TAG_BY_ITEM_ID.get(item_id, ""))
	if not item_tag.is_empty():
		return item_tag
	var source_id := String(result.get("source_id", result.get("node_id", "")))
	for prefix in MATERIAL_TAG_BY_SOURCE_PREFIX:
		if source_id.begins_with(String(prefix)):
			return String(MATERIAL_TAG_BY_SOURCE_PREFIX[prefix])
	return ""

func play_event(event_id: String, payload := {}, dedupe_key := "", now_msec := -1) -> Dictionary:
	var definition := event_definition(event_id)
	if definition.is_empty():
		return {"ok": false, "reason": "unknown_sfx_event", "event_id": event_id}
	var resolved_now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var resolved_key := event_id if dedupe_key.is_empty() else dedupe_key
	var frame := Engine.get_process_frames()
	var frame_key := "%s:%s" % [event_id, resolved_key]
	if int(_last_frame_keys.get(frame_key, -1)) == frame:
		return {"ok": false, "reason": "duplicate_frame", "event_id": event_id}
	var cooldown := int(definition.get("cooldown_msec", 0))
	var last_played := int(_last_played_msec.get(frame_key, -1000000000))
	if cooldown > 0 and resolved_now - last_played < cooldown:
		return {"ok": false, "reason": "cooldown", "event_id": event_id}
	_last_frame_keys[frame_key] = frame
	_last_played_msec[frame_key] = resolved_now
	event_counts[event_id] = int(event_counts.get(event_id, 0)) + 1
	played_events.append({"event_id": event_id, "payload": payload.duplicate(true) if payload is Dictionary else {}, "time_msec": resolved_now})
	var stream_path := String(definition.get("stream_path", ""))
	if stream_path.is_empty() or not ResourceLoader.exists(stream_path):
		missing_stream_events.append({"event_id": event_id, "stream_path": stream_path})
		return {"ok": false, "reason": "missing_stream", "event_id": event_id, "stream_path": stream_path}
	var stream := ResourceLoader.load(stream_path)
	if not stream is AudioStream:
		missing_stream_events.append({"event_id": event_id, "stream_path": stream_path})
		return {"ok": false, "reason": "invalid_stream", "event_id": event_id, "stream_path": stream_path}
	_play_stream(stream, definition)
	return {"ok": true, "event_id": event_id}

func count_for(event_id: String) -> int:
	return int(event_counts.get(event_id, 0))

func registered_stream_paths() -> Array:
	var paths := []
	for event_id in event_ids():
		var path := String(EVENTS[event_id].get("stream_path", ""))
		if not paths.has(path):
			paths.append(path)
	paths.sort()
	return paths

func _play_stream(stream: AudioStream, definition: Dictionary) -> void:
	if not is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS_NAME
	player.volume_db = float(definition.get("volume_db", -12.0))
	player.pitch_scale = float(definition.get("pitch_scale", 1.0))
	add_child(player)
	player.play()
	if stream is AudioStreamGenerator:
		var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback != null:
			_push_generated_tone(playback, stream, definition)
	if stream is AudioStreamGenerator:
		var lifetime := float(definition.get("duration_sec", 0.05)) + 0.05
		get_tree().create_timer(lifetime).timeout.connect(player.queue_free)
	else:
		player.finished.connect(player.queue_free)

func _push_generated_tone(playback: AudioStreamGeneratorPlayback, stream: AudioStreamGenerator, definition: Dictionary) -> void:
	var mix_rate := maxf(float(stream.mix_rate), 1.0)
	var frame_count := mini(int(mix_rate * float(definition.get("duration_sec", 0.05))), playback.get_frames_available())
	var frequency := float(definition.get("frequency_hz", 440.0)) * float(definition.get("pitch_scale", 1.0))
	var wave := String(definition.get("wave", "sine"))
	var amplitude := db_to_linear(float(definition.get("volume_db", -12.0))) * 0.36
	for index in range(frame_count):
		var ratio := float(index) / maxf(float(frame_count), 1.0)
		var t := float(index) / mix_rate
		var sample := _sample_wave(wave, frequency, t, index) * amplitude * (1.0 - ratio)
		playback.push_frame(Vector2(sample, sample))

func _sample_wave(wave: String, frequency: float, t: float, index: int) -> float:
	match wave:
		"square":
			return 1.0 if sin(TAU * frequency * t) >= 0.0 else -1.0
		"triangle":
			return asin(sin(TAU * frequency * t)) * (2.0 / PI)
		"noise":
			var value := int((index * 1103515245 + int(frequency) * 12345) & 0x7fffffff)
			return (float(value % 2000) / 1000.0) - 1.0
		_:
			return sin(TAU * frequency * t)

func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS_NAME) >= 0:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, SFX_BUS_NAME)
	AudioServer.set_bus_volume_db(index, DEFAULT_BUS_VOLUME_DB)
