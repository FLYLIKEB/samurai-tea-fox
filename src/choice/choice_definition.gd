extends RefCounted
class_name ChoiceDefinition

const REQUIRED_FIELDS := [
	"id", "name", "status", "choice_key", "run_flag", "display_text", "resolution",
	"meta_record", "target_survives", "philosophy_marks", "final_room_effect"
]

static func from_row(row: Dictionary) -> Dictionary:
	for field in REQUIRED_FIELDS:
		if not row.has(field) or row[field] == null:
			return _fail("missing_choice_field", "Choice '%s' is missing required field '%s'." % [row.get("id", ""), field])
		if typeof(row[field]) == TYPE_STRING and String(row[field]).strip_edges().is_empty():
			return _fail("missing_choice_field", "Choice '%s' is missing required field '%s'." % [row.get("id", ""), field])
	if not _matches(String(row.id), "^[a-z][a-z0-9_]*$"):
		return _fail("invalid_choice_id", "Choice id '%s' is not a stable runtime id." % row.id)
	if not _matches(String(row.choice_key), "^[A-Z][A-Z0-9_]*$"):
		return _fail("invalid_choice_key", "Choice '%s' has invalid choice_key '%s'." % [row.id, row.choice_key])
	if not _matches(String(row.run_flag), "^[a-z][a-z0-9_]*$"):
		return _fail("invalid_run_flag", "Choice '%s' has invalid run_flag '%s'." % [row.id, row.run_flag])
	if typeof(row.meta_record) != TYPE_BOOL or typeof(row.target_survives) != TYPE_BOOL:
		return _fail("invalid_choice_boolean", "Choice '%s' meta_record and target_survives must be booleans." % row.id)
	if typeof(row.philosophy_marks) != TYPE_ARRAY:
		return _fail("invalid_philosophy_marks", "Choice '%s' philosophy_marks must be an array." % row.id)
	for mark in row.philosophy_marks:
		if typeof(mark) != TYPE_STRING or String(mark).strip_edges().is_empty():
			return _fail("invalid_philosophy_marks", "Choice '%s' philosophy_marks must contain non-empty strings." % row.id)
	var conditions = row.get("conditions", [])
	if typeof(conditions) != TYPE_ARRAY:
		return _fail("invalid_choice_conditions", "Choice '%s' conditions must be an array." % row.id)
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY:
			return _fail("invalid_choice_conditions", "Choice '%s' contains a non-object condition." % row.id)
	var definition := row.duplicate(true)
	definition["conditions"] = conditions.duplicate(true)
	return {"ok": true, "definition": definition}

static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.search(value) != null

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
