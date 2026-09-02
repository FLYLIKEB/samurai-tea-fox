extends RefCounted
class_name BossDefinition

const SUPPORTED_RESOLUTION_TYPES := ["combat", "peaceful"]

var id: String
var name: String
var status: String
var dungeon_id: String
var max_hp: int
var phases: Array
var resolution_types: Array
var reward_item_ids: Array
var progression_unlock_ids: Array
var data_snapshot: Dictionary

func _init(values: Dictionary) -> void:
	id = String(values.id)
	name = String(values.name)
	status = String(values.status)
	dungeon_id = String(values.dungeon_id)
	max_hp = int(values.max_hp)
	phases = values.phases.duplicate(true)
	resolution_types = values.resolution_types.duplicate(true)
	reward_item_ids = _array_value(values.get("reward_item_ids", []))
	progression_unlock_ids = _array_value(values.get("progression_unlock_ids", []))
	data_snapshot = values.duplicate(true)

static func from_catalog(catalog, boss_id: String) -> Dictionary:
	var row: Dictionary = catalog.find_by_id("bosses", boss_id)
	if row.is_empty():
		return {"ok": false, "error": "Missing boss definition: %s" % boss_id}
	return from_dictionary(row)

static func from_dictionary(row: Dictionary) -> Dictionary:
	var validation := validate_row(row)
	if not validation.ok:
		return validation
	return {"ok": true, "definition": load("res://src/boss/boss_definition.gd").new(row)}

static func validate_row(row: Dictionary) -> Dictionary:
	for field in ["id", "name", "status", "dungeon_id"]:
		if String(row.get(field, "")).strip_edges().is_empty():
			return _failure("Boss definition is missing required field: %s" % field)
	var max_hp_value = row.get("max_hp")
	if not _positive_integer(max_hp_value):
		return _failure("Boss max_hp must be a positive integer: %s" % row.id)
	var resolutions = row.get("resolution_types")
	if typeof(resolutions) != TYPE_ARRAY or resolutions.is_empty() or not resolutions.has("combat"):
		return _failure("Boss resolution_types must include combat: %s" % row.id)
	for resolution_type in resolutions:
		if not SUPPORTED_RESOLUTION_TYPES.has(String(resolution_type)):
			return _failure("Boss resolution type is unsupported: %s.%s" % [row.id, resolution_type])
	var phases_value = row.get("phases")
	if typeof(phases_value) != TYPE_ARRAY or phases_value.is_empty():
		return _failure("Boss phases must be a non-empty array: %s" % row.id)
	var phase_ids := {}
	var previous_threshold := 2.0
	for phase_index in range(phases_value.size()):
		var phase = phases_value[phase_index]
		if typeof(phase) != TYPE_DICTIONARY:
			return _failure("Boss phase must be an object: %s.%d" % [row.id, phase_index])
		var phase_id := String(phase.get("id", ""))
		if phase_id.is_empty() or phase_ids.has(phase_id):
			return _failure("Boss phase ids must be non-empty and unique: %s" % row.id)
		phase_ids[phase_id] = true
		var threshold = phase.get("health_ratio_threshold")
		if not _finite_number(threshold) or float(threshold) <= 0.0 or float(threshold) > 1.0:
			return _failure("Boss phase threshold must be within (0, 1]: %s.%s" % [row.id, phase_id])
		if phase_index == 0 and not is_equal_approx(float(threshold), 1.0):
			return _failure("Boss first phase threshold must be 1.0: %s" % row.id)
		if float(threshold) >= previous_threshold:
			return _failure("Boss phase thresholds must be strictly descending: %s" % row.id)
		previous_threshold = float(threshold)
		var patterns = phase.get("patterns")
		if typeof(patterns) != TYPE_ARRAY or patterns.is_empty():
			return _failure("Boss phase patterns must be a non-empty array: %s.%s" % [row.id, phase_id])
		var pattern_ids := {}
		for pattern in patterns:
			if typeof(pattern) != TYPE_DICTIONARY:
				return _failure("Boss pattern must be an object: %s.%s" % [row.id, phase_id])
			var pattern_id := String(pattern.get("id", ""))
			if pattern_id.is_empty() or pattern_ids.has(pattern_id):
				return _failure("Boss pattern ids must be non-empty and unique per phase: %s.%s" % [row.id, phase_id])
			pattern_ids[pattern_id] = true
			var interval = pattern.get("interval_seconds")
			if not _finite_number(interval) or float(interval) <= 0.0:
				return _failure("Boss pattern interval must be positive: %s.%s" % [row.id, pattern_id])
			if typeof(pattern.get("summon_monster_ids", [])) != TYPE_ARRAY:
				return _failure("Boss summon_monster_ids must be an array: %s.%s" % [row.id, pattern_id])
	return {"ok": true}

func phase_index_for_health(current_hp: int) -> int:
	var health_ratio := float(maxi(current_hp, 0)) / float(max_hp)
	var selected_index := 0
	for index in range(phases.size()):
		if health_ratio <= float(phases[index].health_ratio_threshold):
			selected_index = index
	return selected_index

func supports_resolution(resolution_type: String) -> bool:
	return resolution_types.has(resolution_type)

func to_runtime_snapshot() -> Dictionary:
	return data_snapshot.duplicate(true)

static func _positive_integer(value) -> bool:
	return _finite_number(value) and float(value) > 0.0 and float(value) == floor(float(value))

static func _finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _array_value(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
