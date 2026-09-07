extends Label
class_name DialogueTextEffect

signal text_reveal_started
signal text_reveal_completed

const REVEAL_SPEED := 0.05
const SOUND_INTERVAL := 0.08
const REVEAL_SOUND_PATH := "res://assets/sounds/ui/dialogue_text_reveal.wav"

var _full_text: String = ""
var _reveal_progress: int = 0
var _elapsed_time: float = 0.0
var _is_revealing: bool = false
var _sound_player: AudioStreamPlayer
var _last_sound_time: float = 0.0

func _ready() -> void:
	_setup_sound_player()

func _setup_sound_player() -> void:
	_sound_player = AudioStreamPlayer.new()
	_sound_player.bus = &"Master"
	var sound := load(REVEAL_SOUND_PATH) as AudioStream
	if sound != null:
		_sound_player.stream = sound
	add_child(_sound_player)

func start_reveal(text: String) -> void:
	_full_text = text
	self.text = ""
	_reveal_progress = 0
	_elapsed_time = 0.0
	_last_sound_time = 0.0
	_is_revealing = true
	text_reveal_started.emit()

func skip_to_end() -> void:
	if _is_revealing:
		self.text = _full_text
		_is_revealing = false
		text_reveal_completed.emit()

func _process(delta: float) -> void:
	if not _is_revealing or _full_text.is_empty():
		return

	_elapsed_time += delta
	var char_count := int(_elapsed_time / REVEAL_SPEED)
	var max_chars := _full_text.length()

	if char_count > max_chars:
		char_count = max_chars
		_is_revealing = false
		text_reveal_completed.emit()

	if char_count > _reveal_progress:
		_play_reveal_sound()

	_reveal_progress = char_count
	self.text = _full_text.substr(0, char_count)

func _play_reveal_sound() -> void:
	if _elapsed_time - _last_sound_time >= SOUND_INTERVAL:
		if _sound_player != null and _sound_player.stream != null:
			_sound_player.stop()
			_sound_player.play()
		_last_sound_time = _elapsed_time

func is_revealing() -> bool:
	return _is_revealing
