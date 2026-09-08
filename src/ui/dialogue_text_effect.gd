extends Label
class_name DialogueTextEffect

signal text_reveal_started
signal text_reveal_completed

const REVEAL_SPEED := 0.05
const SOUND_INTERVAL := 0.08
const DEFAULT_VOICE_PITCH := 1.0

const BEEP_SAMPLE_RATE := 22050
const BEEP_FREQ_START := 800.0
const BEEP_FREQ_END := 1200.0
const BEEP_DURATION := 0.06

var _full_text: String = ""
var _reveal_progress: int = 0
var _elapsed_time: float = 0.0
var _is_revealing: bool = false
var _sound_player: AudioStreamPlayer
var _last_sound_time: float = 0.0
var _voice_pitch: float = DEFAULT_VOICE_PITCH

func _ready() -> void:
	_setup_sound_player()
	print_debug("🎭 DialogueTextEffect ready")

func _setup_sound_player() -> void:
	_sound_player = AudioStreamPlayer.new()
	_sound_player.volume_db = 0
	_sound_player.stream = _generate_beep_stream()
	add_child(_sound_player)
	print_debug("✓ Procedural beep sound generated")

func _generate_beep_stream() -> AudioStreamWAV:
	var sample_count := int(BEEP_SAMPLE_RATE * BEEP_DURATION)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	for i in range(sample_count):
		var t := float(i) / BEEP_SAMPLE_RATE
		var progress := float(i) / sample_count
		var frequency := lerpf(BEEP_FREQ_START, BEEP_FREQ_END, progress)
		var envelope := 1.0 - progress * 0.5
		if progress < 0.15:
			envelope = progress / 0.15
		var sample_value := sin(TAU * frequency * t) * envelope * 0.9
		var sample_int := int(clampf(sample_value, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = BEEP_SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream

func start_reveal(text: String, voice_pitch: float = DEFAULT_VOICE_PITCH) -> void:
	_full_text = text
	_voice_pitch = voice_pitch
	self.text = ""
	_reveal_progress = 0
	_elapsed_time = 0.0
	_last_sound_time = 0.0
	_is_revealing = true
	text_reveal_started.emit()
	print_debug("📖 Revealing text: %d characters (pitch %.2f)" % [text.length(), voice_pitch])

func skip_to_end() -> void:
	if _is_revealing:
		self.text = _full_text
		_is_revealing = false
		text_reveal_completed.emit()
		print_debug("⏭️ Text reveal skipped to end")

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
		if _sound_player != null:
			_sound_player.pitch_scale = _voice_pitch
			_sound_player.play()
			print_debug("🔊 Dialogue sound playing at %.2fs (pitch %.2f)" % [_elapsed_time, _voice_pitch])
		_last_sound_time = _elapsed_time

func is_revealing() -> bool:
	return _is_revealing
