extends RefCounted
class_name DirectionalWalkAnimator

const DIRECTION_ROWS := {
	"south": 0,
	"west": 1,
	"east": 2,
	"north": 3
}
const EXPECTED_DIRECTION_COUNT := 4
const EXPECTED_FRAMES_PER_DIRECTION := 8
const EXPECTED_FRAME_SIZE := 32

var _sprite: Sprite2D
var _catalog
var _walk_asset_id := ""
var _walk_texture: Texture2D
var _attack_asset_id := ""
var _attack_texture: Texture2D
var _idle_asset_ids: Dictionary = {}
var _idle_textures: Dictionary = {}
var _frames_per_second := 8.0
var _attack_frames_per_second := 16.0
var _elapsed_seconds := 0.0
var _attack_elapsed_seconds := 0.0
var _current_direction := "south"
var _current_asset_id := ""
var _walking := false
var _attacking := false
var _configured := false

func configure(
	target_sprite: Sprite2D,
	asset_catalog,
	walk_asset_id: String,
	idle_asset_ids := {},
	frames_per_second := 8.0,
	attack_asset_id := "",
	attack_frames_per_second := 16.0
) -> Dictionary:
	if target_sprite == null:
		return {"ok": false, "error": "Directional walk animator requires a Sprite2D target."}
	if asset_catalog == null:
		return {"ok": false, "error": "Directional walk animator requires an asset catalog."}
	if frames_per_second <= 0.0:
		return {"ok": false, "error": "Directional walk animation speed must be positive."}
	if attack_frames_per_second <= 0.0:
		return {"ok": false, "error": "Directional attack animation speed must be positive."}
	var definition: Dictionary = asset_catalog.definition_for(walk_asset_id)
	var definition_result := validate_definition(definition)
	if not definition_result.ok:
		return definition_result
	var texture: Texture2D = asset_catalog.load_texture(walk_asset_id)
	if texture == null:
		return {"ok": false, "error": "Could not load walk texture for asset '%s'." % walk_asset_id}
	var attack_texture: Texture2D = null
	var normalized_attack_asset_id := String(attack_asset_id)
	if not normalized_attack_asset_id.is_empty():
		var attack_definition: Dictionary = asset_catalog.definition_for(normalized_attack_asset_id)
		var attack_definition_result := validate_definition(attack_definition, "Attack")
		if not attack_definition_result.ok:
			return attack_definition_result
		attack_texture = asset_catalog.load_texture(normalized_attack_asset_id)
		if attack_texture == null:
			return {"ok": false, "error": "Could not load attack texture for asset '%s'." % normalized_attack_asset_id}
	if typeof(idle_asset_ids) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Idle asset IDs must be a direction dictionary."}
	var idle_textures: Dictionary = {}
	for direction in idle_asset_ids:
		if not DIRECTION_ROWS.has(direction):
			return {"ok": false, "error": "Unsupported idle direction '%s'." % direction}
		var idle_asset_id := String(idle_asset_ids[direction])
		if idle_asset_id.is_empty() or not asset_catalog.has(idle_asset_id):
			return {"ok": false, "error": "Missing idle asset '%s' for %s." % [idle_asset_id, direction]}
		var idle_texture: Texture2D = asset_catalog.load_texture(idle_asset_id)
		if idle_texture == null:
			return {"ok": false, "error": "Could not load idle texture '%s' for %s." % [idle_asset_id, direction]}
		idle_textures[direction] = idle_texture

	_sprite = target_sprite
	_catalog = asset_catalog
	_walk_asset_id = walk_asset_id
	_walk_texture = texture
	_attack_asset_id = normalized_attack_asset_id
	_attack_texture = attack_texture
	_idle_asset_ids = idle_asset_ids.duplicate(true)
	_idle_textures = idle_textures
	_frames_per_second = frames_per_second
	_attack_frames_per_second = attack_frames_per_second
	_elapsed_seconds = 0.0
	_attack_elapsed_seconds = 0.0
	_current_direction = "south"
	_current_asset_id = ""
	_walking = false
	_attacking = false
	_configured = true
	_apply_idle_frame(_current_direction)
	return {"ok": true}

func configure_for_character(
	target_sprite: Sprite2D,
	asset_catalog,
	character_id: String,
	idle_asset_ids := {},
	frames_per_second := 8.0,
	attack_frames_per_second := 16.0
) -> Dictionary:
	if asset_catalog == null:
		return {"ok": false, "error": "Directional walk animator requires an asset catalog."}
	var walk_asset_id: String = asset_catalog.character_animation_id(character_id, "walk")
	if walk_asset_id.is_empty():
		return {"ok": false, "error": "Missing walk animation for character '%s'." % character_id}
	var attack_asset_id: String = asset_catalog.character_animation_id(character_id, "attack")
	return configure(target_sprite, asset_catalog, walk_asset_id, idle_asset_ids, frames_per_second, attack_asset_id, attack_frames_per_second)

func validate_definition(definition: Dictionary, label := "Walk") -> Dictionary:
	if definition.is_empty():
		return {"ok": false, "error": "%s asset definition is missing." % label}
	if int(definition.get("direction_count", 0)) != EXPECTED_DIRECTION_COUNT:
		return {"ok": false, "error": "%s asset must contain four directions." % label}
	if int(definition.get("frame_count", 0)) != EXPECTED_DIRECTION_COUNT * EXPECTED_FRAMES_PER_DIRECTION:
		return {"ok": false, "error": "%s asset must contain eight frames per direction." % label}
	var grid = definition.get("frame_grid", {})
	if typeof(grid) != TYPE_DICTIONARY:
		return {"ok": false, "error": "%s asset frame grid is missing." % label}
	if (
		int(grid.get("columns", 0)) != EXPECTED_FRAMES_PER_DIRECTION
		or int(grid.get("rows", 0)) != EXPECTED_DIRECTION_COUNT
		or int(grid.get("frame_width", 0)) != EXPECTED_FRAME_SIZE
		or int(grid.get("frame_height", 0)) != EXPECTED_FRAME_SIZE
	):
		return {"ok": false, "error": "%s asset frame grid must be 8x4 with 32x32 cells." % label}
	if int(definition.get("width", 0)) != EXPECTED_FRAME_SIZE * EXPECTED_FRAMES_PER_DIRECTION:
		return {"ok": false, "error": "%s asset width must be 256 pixels." % label}
	if int(definition.get("height", 0)) != EXPECTED_FRAME_SIZE * EXPECTED_DIRECTION_COUNT:
		return {"ok": false, "error": "%s asset height must be 128 pixels." % label}
	var direction_rows = definition.get("direction_rows", {})
	if typeof(direction_rows) != TYPE_DICTIONARY or direction_rows.size() != DIRECTION_ROWS.size():
		return {"ok": false, "error": "%s asset rows must be south, west, east, north." % label}
	for direction in DIRECTION_ROWS:
		if not direction_rows.has(direction) or int(direction_rows[direction]) != int(DIRECTION_ROWS[direction]):
			return {"ok": false, "error": "%s asset rows must be south, west, east, north." % label}
	return {"ok": true}

func update(delta: float, direction: String, moving: bool) -> bool:
	if not _configured or not DIRECTION_ROWS.has(direction):
		return false
	if _attacking:
		_attack_elapsed_seconds += maxf(delta, 0.0)
		var attack_frame_index := int(floor(_attack_elapsed_seconds * _attack_frames_per_second))
		if attack_frame_index < EXPECTED_FRAMES_PER_DIRECTION:
			_current_direction = direction
			_apply_attack_frame(direction, attack_frame_index)
			return true
		_attacking = false
		_attack_elapsed_seconds = 0.0
	if moving:
		if not _walking or direction != _current_direction:
			_elapsed_seconds = 0.0
		else:
			_elapsed_seconds += maxf(delta, 0.0)
		_current_direction = direction
		_walking = true
		var frame_index := int(floor(_elapsed_seconds * _frames_per_second)) % EXPECTED_FRAMES_PER_DIRECTION
		_apply_walk_frame(direction, frame_index)
		return true

	var direction_changed := direction != _current_direction
	_current_direction = direction
	if _walking or direction_changed or _current_asset_id == _walk_asset_id or _current_asset_id == _attack_asset_id:
		_elapsed_seconds = 0.0
		_walking = false
		_apply_idle_frame(direction)
	return true

func current_asset_id() -> String:
	return _current_asset_id

func current_direction() -> String:
	return _current_direction

func is_walking() -> bool:
	return _walking

func is_attacking() -> bool:
	return _attacking

func play_attack(direction: String) -> bool:
	if not _configured or not DIRECTION_ROWS.has(direction) or _attack_texture == null:
		return false
	_current_direction = direction
	_attacking = true
	_walking = false
	_attack_elapsed_seconds = 0.0
	_apply_attack_frame(direction, 0)
	return true

func _apply_walk_frame(direction: String, frame_index: int) -> void:
	_sprite.texture = _walk_texture
	_sprite.hframes = EXPECTED_FRAMES_PER_DIRECTION
	_sprite.vframes = EXPECTED_DIRECTION_COUNT
	_sprite.frame_coords = Vector2i(frame_index, int(DIRECTION_ROWS[direction]))
	_current_asset_id = _walk_asset_id

func _apply_attack_frame(direction: String, frame_index: int) -> void:
	_sprite.texture = _attack_texture
	_sprite.hframes = EXPECTED_FRAMES_PER_DIRECTION
	_sprite.vframes = EXPECTED_DIRECTION_COUNT
	_sprite.frame_coords = Vector2i(frame_index, int(DIRECTION_ROWS[direction]))
	_current_asset_id = _attack_asset_id

func _apply_idle_frame(direction: String) -> void:
	var idle_asset_id := String(_idle_asset_ids.get(direction, ""))
	if idle_asset_id.is_empty():
		_apply_walk_frame(direction, 0)
		return
	var idle_texture: Texture2D = _idle_textures.get(direction)
	if idle_texture == null:
		push_error("Configured idle texture is unavailable for %s." % direction)
		_apply_walk_frame(direction, 0)
		return
	_sprite.texture = idle_texture
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.frame = 0
	_current_asset_id = idle_asset_id
