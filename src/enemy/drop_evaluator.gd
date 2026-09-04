extends RefCounted
class_name DropEvaluator

const TimeState = preload("res://src/time/time_state.gd")

const CONDITION_ALWAYS := "항상"
const CONDITION_DAY := "낮"
const CONDITION_NIGHT := "밤"
const SUPPORTED_CONDITIONS := [CONDITION_ALWAYS, CONDITION_DAY, CONDITION_NIGHT]

static func evaluate(grant: Dictionary, context: Dictionary) -> Dictionary:
	var condition := String(grant.get("condition", ""))
	if not SUPPORTED_CONDITIONS.has(condition):
		return {
			"ok": false,
			"reason": "unsupported_drop_condition",
			"error": "Unsupported drop condition: %s" % condition
		}
	if not _condition_matches(condition, String(context.get("time_phase", ""))):
		return {"ok": true, "included": false}

	var request_key := "%s|%s" % [
		String(context.get("request_id", "")),
		String(grant.get("drop_id", ""))
	]
	var run_seed := int(context.get("run_seed", 0))
	# Zero is the legacy fresh-run seed, so keep its existing replay key stable.
	var roll_key := request_key if run_seed == 0 else "%d|%s" % [run_seed, request_key]
	if _stable_unit_interval(roll_key + "|chance") >= float(grant.get("chance", 0.0)):
		return {"ok": true, "included": false}

	var minimum := int(grant.get("min_quantity", 0))
	var maximum := int(grant.get("max_quantity", 0))
	var quantity := minimum
	var quantity_span := maximum - minimum + 1
	if quantity_span > 1:
		quantity += int(floor(_stable_unit_interval(roll_key + "|quantity") * quantity_span))
	return {
		"ok": true,
		"included": true,
		"grant": {
			"item_id": String(grant.get("item_id", "")),
			"quantity": quantity,
			"policy": String(grant.get("policy", ""))
		}
	}

static func _condition_matches(condition: String, time_phase: String) -> bool:
	match condition:
		CONDITION_ALWAYS:
			return true
		CONDITION_DAY:
			return time_phase == String(TimeState.DAY)
		CONDITION_NIGHT:
			return time_phase in [String(TimeState.NIGHT), String(TimeState.LATE_NIGHT)]
	return false

static func _stable_unit_interval(key: String) -> float:
	var hash_value := 2166136261
	for byte in key.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * 16777619) & 0x7fffffff
	return float(hash_value % 1000000) / 1000000.0
