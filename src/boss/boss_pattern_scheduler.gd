extends RefCounted
class_name BossPatternScheduler

func select_pattern(phase: Dictionary, cursor: int) -> Dictionary:
	var patterns = phase.get("patterns", [])
	if typeof(patterns) != TYPE_ARRAY or patterns.is_empty():
		return {"ok": false, "reason": "missing_phase_patterns", "error": "Boss phase has no schedulable patterns."}
	var normalized_cursor := posmod(cursor, patterns.size())
	return {
		"ok": true,
		"pattern": patterns[normalized_cursor].duplicate(true),
		"next_cursor": normalized_cursor + 1
	}
