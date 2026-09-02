extends RefCounted
class_name BossDefinition

const SUPPORTED_RESOLUTION_TYPES := ["combat", "peaceful"]
const TEA_CONDITION_TYPES := ["always", "prepared_tea", "run_flag", "run_not_flag", "current_biome", "has_item"]
const TEA_HOOK_GROUPS := ["common", "peaceful_tea_ceremony", "mixed", "combat_started"]
const TEA_HOOK_CHANNELS := ["memory", "weakness", "dialogue"]

var id: String
var name: String
var status: String
var dungeon_id: String
var max_hp: int
var phases: Array
var resolution_types: Array
var reward_item_ids: Array
var progression_unlock_ids: Array
var tea_resolution: Dictionary
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
	tea_resolution = _dictionary_value(values.get("tea_resolution", {}))
	data_snapshot = values.duplicate(true)

static func from_catalog(catalog, boss_id: String) -> Dictionary:
	var row: Dictionary = catalog.find_by_id("bosses", boss_id)
	if row.is_empty():
		return {"ok": false, "error": "Missing boss definition: %s" % boss_id}
	var result := from_dictionary(row)
	if not result.ok:
		return result
	var references := _validate_catalog_references(catalog, result.definition.tea_resolution, boss_id)
	if not references.ok:
		return references
	return result

static func from_dictionary(row: Dictionary) -> Dictionary:
	var validation := validate_row(row)
	if not validation.ok:
		return validation
	return {"ok": true, "definition": load("res://src/boss/boss_definition.gd").new(row)}

static func validate_row(row: Dictionary) -> Dictionary:
	for field in ["id", "name", "status", "dungeon_id"]:
		if String(row.get(field, "")).strip_edges().is_empty():
			return _failure("Boss definition is missing required field: %s" % field)
	if not _is_stable_id(String(row.id)):
		return _failure("Boss definition id must be a stable id: %s" % row.id)
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
	var tea_resolution_value = row.get("tea_resolution", {})
	if tea_resolution_value != null and typeof(tea_resolution_value) != TYPE_DICTIONARY:
		return _failure("Boss tea_resolution must be an object: %s" % row.id)
	if typeof(tea_resolution_value) == TYPE_DICTIONARY and not tea_resolution_value.is_empty():
		if not resolutions.has("peaceful"):
			return _failure("Boss tea_resolution requires peaceful resolution support: %s" % row.id)
		var choice_id := String(tea_resolution_value.get("choice_id", ""))
		if not _is_stable_id(choice_id):
			return _failure("Boss tea_resolution.choice_id must be a stable id: %s" % row.id)
		var required_tea_ids = tea_resolution_value.get("required_tea_ids", [])
		if typeof(required_tea_ids) != TYPE_ARRAY:
			return _failure("Boss tea_resolution.required_tea_ids must be an array: %s" % row.id)
		for tea_id in required_tea_ids:
			if typeof(tea_id) != TYPE_STRING or not _is_stable_id(String(tea_id)):
				return _failure("Boss tea_resolution.required_tea_ids must contain stable ids: %s" % row.id)
		var peaceful_conditions = tea_resolution_value.get("peaceful_conditions", [])
		if typeof(peaceful_conditions) != TYPE_ARRAY:
			return _failure("Boss tea_resolution.peaceful_conditions must be an array: %s" % row.id)
		for condition in peaceful_conditions:
			var condition_result := _validate_tea_condition(condition, String(row.id))
			if not condition_result.ok:
				return condition_result
		var hooks_result := _validate_tea_hooks(tea_resolution_value.get("hooks", {}), String(row.id))
		if not hooks_result.ok:
			return hooks_result
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

static func _dictionary_value(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

static func _validate_catalog_references(catalog, config: Dictionary, boss_id: String) -> Dictionary:
	if config.is_empty():
		return {"ok": true}
	if catalog == null or not catalog.has_method("find_by_id"):
		return _failure("Boss tea resolution references require a catalog: %s" % boss_id)
	var choice_id := String(config.get("choice_id", ""))
	if catalog.find_by_id("choices", choice_id).is_empty():
		return _failure("Boss tea_resolution.choice_id targets missing choice: %s.%s" % [boss_id, choice_id])
	var tea_ids := _array_value(config.get("required_tea_ids", []))
	for condition in _array_value(config.get("peaceful_conditions", [])):
		if typeof(condition) == TYPE_DICTIONARY and String(condition.get("type", "")) == "prepared_tea":
			var condition_tea_id := String(condition.get("id", ""))
			if not tea_ids.has(condition_tea_id):
				tea_ids.append(condition_tea_id)
	for tea_id in tea_ids:
		if catalog.find_by_id("teas", String(tea_id)).is_empty():
			return _failure("Boss tea_resolution references missing tea: %s.%s" % [boss_id, tea_id])
	return {"ok": true}

static func _validate_tea_condition(condition, boss_id: String) -> Dictionary:
	if typeof(condition) != TYPE_DICTIONARY:
		return _failure("Boss tea_resolution.peaceful_conditions must contain objects: %s" % boss_id)
	var condition_type := String(condition.get("type", ""))
	if not TEA_CONDITION_TYPES.has(condition_type):
		return _failure("Boss tea_resolution has unsupported condition type: %s.%s" % [boss_id, condition_type])
	var allowed_fields := ["type"] if condition_type == "always" else ["type", "id"]
	for field in condition:
		if not allowed_fields.has(String(field)):
			return _failure("Boss tea_resolution condition has unsupported field: %s.%s" % [boss_id, field])
	if condition_type != "always" and (typeof(condition.get("id")) != TYPE_STRING or not _is_stable_id(String(condition.get("id", "")))):
		return _failure("Boss tea_resolution condition id must be stable: %s.%s" % [boss_id, condition_type])
	return {"ok": true}

static func _validate_tea_hooks(hooks, boss_id: String) -> Dictionary:
	if typeof(hooks) != TYPE_DICTIONARY:
		return _failure("Boss tea_resolution.hooks must be an object: %s" % boss_id)
	for group in hooks:
		if not TEA_HOOK_GROUPS.has(String(group)):
			return _failure("Boss tea_resolution.hooks has unsupported group: %s.%s" % [boss_id, group])
		var channels = hooks[group]
		if typeof(channels) != TYPE_DICTIONARY:
			return _failure("Boss tea_resolution hook group must be an object: %s.%s" % [boss_id, group])
		for channel in channels:
			if not TEA_HOOK_CHANNELS.has(String(channel)):
				return _failure("Boss tea_resolution hook channel is unsupported: %s.%s" % [boss_id, channel])
			var keys = channels[channel]
			if typeof(keys) != TYPE_ARRAY:
				return _failure("Boss tea_resolution hook keys must be an array: %s.%s" % [boss_id, channel])
			for key in keys:
				if typeof(key) != TYPE_STRING or not _is_stable_hook_key(String(key)) or not String(key).begins_with("%s." % channel):
					return _failure("Boss tea_resolution hook keys must be stable channel keys: %s.%s" % [boss_id, key])
	return {"ok": true}

static func _is_stable_id(value: String) -> bool:
	return _matches(value, "^[a-z][a-z0-9_]*$")

static func _is_stable_hook_key(value: String) -> bool:
	return _matches(value, "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$")

static func _matches(value: String, expression: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile(expression)
	return pattern.search(value) != null

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
