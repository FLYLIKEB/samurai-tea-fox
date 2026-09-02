extends RefCounted
class_name FinalRoomStateBuilder

const SNAPSHOT_SCHEMA_VERSION := 1
const EMPTY_KEY := "none"

var data_version := ""
var choices_by_id := {}
var items_by_id := {}
var characters_by_target_id := {}

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Final room state builder requires catalog definitions.")
	var builder: FinalRoomStateBuilder = load("res://src/meta/final_room_state_builder.gd").new()
	builder.data_version = String(catalog.get("data_version")) if catalog.has_method("get") else ""
	builder.choices_by_id = _definitions_by_id(catalog.get_definitions("choices"))
	builder.items_by_id = _definitions_by_id(catalog.get_definitions("items"))
	builder.characters_by_target_id = _characters_by_target_id(catalog.get_definitions("characters"))
	return {"ok": true, "builder": builder}

func build(run_state) -> Dictionary:
	var snapshot := _run_snapshot(run_state)
	var choice_traces := _choice_traces(snapshot)
	var survival := _survival_projection(snapshot)
	var tea_ware := _tea_ware_placements(snapshot)
	var philosophy := _philosophy_projection(snapshot)
	return {"ok": true, "state": {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"read_only": true,
		"choice_traces": choice_traces,
		"surviving_characters": survival.surviving_characters,
		"relics": survival.relics,
		"tea_ware_placements": tea_ware,
		"philosophy_marks": philosophy.marks,
		"philosophy_combination_key": philosophy.combination_key,
		"space_state_keys": _space_state_keys(choice_traces, survival, tea_ware, philosophy)
	}}

func _choice_traces(snapshot: Dictionary) -> Array:
	var result := []
	var effects_by_choice := {}
	for effect in _array_value(snapshot.get("final_room_effects", [])):
		if typeof(effect) == TYPE_DICTIONARY:
			effects_by_choice[String(effect.get("choice_id", ""))] = String(effect.get("effect", ""))
	for choice_id_value in _array_value(snapshot.get("choice_history", [])):
		var choice_id := String(choice_id_value)
		var definition: Dictionary = choices_by_id.get(choice_id, {})
		result.append({
			"choice_id": choice_id,
			"choice_key": String(definition.get("choice_key", choice_id)),
			"resolution": String(definition.get("resolution", "unknown")),
			"display_text": String(definition.get("display_text", choice_id)),
			"final_room_effect": String(effects_by_choice.get(choice_id, definition.get("final_room_effect", ""))),
			"placement_key": "choice_trace_%s" % choice_id
		})
	return result

func _survival_projection(snapshot: Dictionary) -> Dictionary:
	var surviving := []
	var relics := []
	var survival: Dictionary = _dictionary_value(snapshot.get("target_survival", {}))
	var targets := survival.keys()
	targets.sort()
	for target in targets:
		var target_id := String(target)
		var character: Dictionary = characters_by_target_id.get(target_id, {})
		var entry := {
			"target_id": target_id,
			"character_id": String(character.get("id", target_id)),
			"name": String(character.get("name", target_id))
		}
		if bool(survival[target]):
			entry["placement_key"] = "character_%s_present" % target_id
			surviving.append(entry)
		else:
			entry["placement_key"] = "relic_%s_absent" % target_id
			relics.append(entry)
	return {"surviving_characters": surviving, "relics": relics}

func _tea_ware_placements(snapshot: Dictionary) -> Array:
	var collection: Dictionary = _dictionary_value(snapshot.get("core_tea_ware_collection", {}))
	var ids: Array = _array_value(collection.get("collected_ids", []))
	var result := []
	for item_id_value in ids:
		var item_id := String(item_id_value)
		var definition: Dictionary = items_by_id.get(item_id, {})
		result.append({
			"item_id": item_id,
			"name": String(definition.get("name", item_id)),
			"core_tea_ware_order": int(definition.get("core_tea_ware_order", 0)),
			"placement_key": "tea_ware_%s_display" % item_id
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_order := int(left.get("core_tea_ware_order", 0))
		var right_order := int(right.get("core_tea_ware_order", 0))
		if left_order == right_order:
			return String(left.item_id) < String(right.item_id)
		return left_order < right_order
	)
	return result

func _philosophy_projection(snapshot: Dictionary) -> Dictionary:
	var unique := []
	for mark_value in _array_value(snapshot.get("philosophy_marks", [])):
		var mark := String(mark_value)
		if not mark.is_empty() and not unique.has(mark):
			unique.append(mark)
	var key_parts := unique.duplicate()
	key_parts.sort()
	return {"marks": unique, "combination_key": _safe_join_key(key_parts)}

func _space_state_keys(choice_traces: Array, survival: Dictionary, tea_ware: Array, philosophy: Dictionary) -> Array:
	var keys := []
	keys.append("choice_traces_%d" % choice_traces.size())
	keys.append("survivors_%d" % survival.surviving_characters.size())
	keys.append("relics_%d" % survival.relics.size())
	keys.append("core_tea_ware_%d" % tea_ware.size())
	keys.append("philosophy_%s" % String(philosophy.combination_key))
	keys.sort()
	return keys

func _run_snapshot(run_state) -> Dictionary:
	if run_state == null:
		return {}
	if run_state is Dictionary:
		return run_state.duplicate(true)
	if run_state.has_method("to_dictionary"):
		return run_state.to_dictionary()
	return {}

static func _definitions_by_id(rows: Array) -> Dictionary:
	var by_id := {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			var id := String(row.get("id", ""))
			if not id.is_empty():
				by_id[id] = row.duplicate(true)
	return by_id

static func _characters_by_target_id(rows: Array) -> Dictionary:
	var by_target := {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id := String(row.get("id", ""))
		if id.is_empty():
			continue
		by_target[id] = row.duplicate(true)
		var target_ids = row.get("final_room_target_ids", [])
		if typeof(target_ids) == TYPE_ARRAY:
			for target_id_value in target_ids:
				var target_id := String(target_id_value)
				if not target_id.is_empty():
					by_target[target_id] = row.duplicate(true)
	return by_target

static func _safe_join_key(parts: Array) -> String:
	if parts.is_empty():
		return EMPTY_KEY
	var safe_parts := []
	for part_value in parts:
		var part := String(part_value)
		var safe := "u"
		for index in range(part.length()):
			var code := part.unicode_at(index)
			if index > 0:
				safe += "_"
			safe += str(code)
		safe_parts.append(safe)
	return "__".join(safe_parts)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
