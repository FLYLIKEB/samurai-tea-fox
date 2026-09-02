extends RefCounted
class_name CoreTeaWareCollection

const SNAPSHOT_SCHEMA_VERSION := 1
const EVENT_BOSS_RESOLVED := "boss_encounter_resolved"
const EVENT_DUNGEON_CLEARED := "dungeon_cleared"
const EVENT_BOSS_TEA_COMMITTED := "boss_tea_resolution_committed"
const RESOLUTION_COMBAT := "combat"
const RESOLUTION_PEACEFUL := "peaceful"
const DISCOVERY_PREFIX := "core_tea_ware_"

var data_version := ""
var required_definitions: Array = []
var required_by_id := {}
var required_order := []

static func from_catalog(catalog) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Core tea ware collection requires catalog definitions.")
	var definitions_result := _required_definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result
	var service: CoreTeaWareCollection = load("res://src/dungeon/core_tea_ware_collection.gd").new()
	var version = catalog.get("data_version") if catalog.has_method("get") else ""
	var configured := service.configure(definitions_result.definitions, String(version))
	if not configured.ok:
		return configured
	var coverage := _validate_reward_coverage(catalog, service.required_order)
	if not coverage.ok:
		return coverage
	return {"ok": true, "collection": service}

func configure(new_required_definitions: Array, new_data_version := "") -> Dictionary:
	var normalized_result := _normalize_required_definitions(new_required_definitions)
	if not normalized_result.ok:
		return normalized_result
	data_version = new_data_version
	required_definitions = normalized_result.definitions
	required_by_id = {}
	required_order = []
	for definition in required_definitions:
		required_by_id[String(definition.id)] = definition.duplicate(true)
		required_order.append(String(definition.id))
	return {"ok": true, "required_ids": required_order.duplicate()}

func record_boss_resolution_rewards(resolution_event: Dictionary, run_state) -> Dictionary:
	var preflight := validate_boss_resolution_rewards(resolution_event, run_state)
	if not preflight.ok:
		return preflight
	var reward_ids: Array = resolution_event.get("reward_item_ids", [])
	var collected := []
	var ignored := []
	var meta_events := []
	for reward_id_value in reward_ids:
		var reward_id := String(reward_id_value)
		if not required_by_id.has(reward_id):
			ignored.append(reward_id)
			continue
		var collect_result := collect_core_tea_ware(reward_id, run_state, {
			"source_event_type": String(resolution_event.event_type),
			"resolution_type": String(resolution_event.resolution_type),
			"boss_id": String(resolution_event.get("boss_id", "")),
			"dungeon_id": String(resolution_event.get("dungeon_id", "")),
			"choice_key": String(resolution_event.get("choice_key", "")),
			"run_flag": String(resolution_event.get("run_flag", ""))
		})
		if not collect_result.ok:
			return collect_result
		collected.append(reward_id)
		meta_events.append_array(collect_result.meta_events)
	return {
		"ok": true,
		"collected": collected,
		"ignored_reward_item_ids": ignored,
		"meta_events": meta_events,
		"gate": final_room_gate_query(run_state)
	}

func validate_boss_resolution_rewards(resolution_event: Dictionary, run_state) -> Dictionary:
	var event_result := _validate_resolution_event(resolution_event)
	if not event_result.ok:
		return event_result
	var reward_ids: Array = resolution_event.get("reward_item_ids", [])
	return _preflight_core_rewards(reward_ids, run_state)

func _preflight_core_rewards(reward_ids: Array, run_state) -> Dictionary:
	var state := _collection_state(run_state)
	var seen := {}
	for reward_id_value in reward_ids:
		var reward_id := String(reward_id_value)
		if not required_by_id.has(reward_id):
			continue
		if seen.has(reward_id) or state.collected_ids.has(reward_id):
			return _fail("duplicate_core_tea_ware", "Core tea ware was already collected this run: %s" % reward_id)
		seen[reward_id] = true
	return {"ok": true}

func collect_core_tea_ware(item_id: String, run_state, context := {}) -> Dictionary:
	if not required_by_id.has(item_id):
		return _fail("unknown_core_tea_ware", "Item is not required core tea ware: %s" % item_id)
	var state := _collection_state(run_state)
	var collected_ids: Array = state.collected_ids
	if collected_ids.has(item_id):
		return _fail("duplicate_core_tea_ware", "Core tea ware was already collected this run: %s" % item_id)
	collected_ids.append(item_id)
	collected_ids = _sort_required_ids(collected_ids)
	state.collected_ids = collected_ids
	var collected_by_id: Dictionary = state.collected_by_id
	collected_by_id[item_id] = _collection_record(item_id, context)
	state.collected_by_id = collected_by_id
	_write_collection_state(run_state, state)
	var record_id := discovery_record_id(item_id)
	_append_run_discovery(run_state, record_id)
	return {
		"ok": true,
		"item_id": item_id,
		"collection_state": state.duplicate(true),
		"meta_events": [{"type": "discovery", "target": record_id, "item_id": item_id}]
	}

func final_room_gate_query(run_state) -> Dictionary:
	var state := _collection_state(run_state)
	var collected_ids: Array = _sort_required_ids(state.collected_ids)
	var missing_ids := []
	for item_id in required_order:
		if not collected_ids.has(item_id):
			missing_ids.append(item_id)
	return {
		"ok": true,
		"can_enter_final_room": missing_ids.is_empty() and not required_order.is_empty(),
		"required_ids": required_order.duplicate(),
		"collected_ids": collected_ids,
		"missing_ids": missing_ids,
		"required_count": required_order.size(),
		"collected_count": collected_ids.size()
	}

func reset_run_collection(run_state) -> void:
	_write_collection_state(run_state, _empty_state())

func discovery_record_id(item_id: String) -> String:
	return "%s%s" % [DISCOVERY_PREFIX, item_id]

func _collection_record(item_id: String, context: Dictionary) -> Dictionary:
	return {
		"item_id": item_id,
		"core_tea_ware_order": int(required_by_id[item_id].core_tea_ware_order),
		"source_event_type": String(context.get("source_event_type", "")),
		"resolution_type": String(context.get("resolution_type", "")),
		"boss_id": String(context.get("boss_id", "")),
		"dungeon_id": String(context.get("dungeon_id", "")),
		"choice_key": String(context.get("choice_key", "")),
		"run_flag": String(context.get("run_flag", ""))
	}

func _validate_resolution_event(event: Dictionary) -> Dictionary:
	var event_type := String(event.get("event_type", ""))
	if not [EVENT_BOSS_RESOLVED, EVENT_DUNGEON_CLEARED, EVENT_BOSS_TEA_COMMITTED].has(event_type):
		return _fail("invalid_resolution_event", "Core tea ware rewards require a boss or dungeon resolution event.")
	var resolution_type := String(event.get("resolution_type", ""))
	if not [RESOLUTION_COMBAT, RESOLUTION_PEACEFUL].has(resolution_type):
		return _fail("invalid_resolution_type", "Core tea ware rewards require combat or peaceful resolution.")
	if typeof(event.get("reward_item_ids", [])) != TYPE_ARRAY:
		return _fail("invalid_reward_items", "Core tea ware reward item ids must be an array.")
	return {"ok": true}

func _collection_state(run_state) -> Dictionary:
	var raw: Dictionary = {}
	if run_state is Dictionary:
		raw = run_state.get("core_tea_ware_collection", {})
	elif run_state != null and run_state.has_method("get"):
		raw = run_state.get("core_tea_ware_collection")
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return _empty_state()
	var state: Dictionary = raw.duplicate(true)
	if int(state.get("schema_version", 0)) != SNAPSHOT_SCHEMA_VERSION:
		return _empty_state()
	if typeof(state.get("collected_ids", [])) != TYPE_ARRAY:
		state.collected_ids = []
	if typeof(state.get("collected_by_id", {})) != TYPE_DICTIONARY:
		state.collected_by_id = {}
	state.collected_ids = _sort_required_ids(state.collected_ids)
	return state

func _write_collection_state(run_state, state: Dictionary) -> void:
	if run_state == null:
		return
	if run_state is Dictionary:
		run_state["core_tea_ware_collection"] = state.duplicate(true)
	else:
		run_state.set("core_tea_ware_collection", state.duplicate(true))

func _empty_state() -> Dictionary:
	return {"schema_version": SNAPSHOT_SCHEMA_VERSION, "collected_ids": [], "collected_by_id": {}}

func _sort_required_ids(ids: Array) -> Array:
	var result := []
	for required_id in required_order:
		if ids.has(required_id) and not result.has(required_id):
			result.append(required_id)
	return result

func _append_run_discovery(run_state, record_id: String) -> void:
	if run_state == null:
		return
	var records := []
	if run_state is Dictionary:
		var raw = run_state.get("discovered_records", [])
		records = raw.duplicate(true) if typeof(raw) == TYPE_ARRAY else []
		if not records.has(record_id):
			records.append(record_id)
		run_state["discovered_records"] = records
	else:
		var raw = run_state.get("discovered_records") if run_state.has_method("get") else []
		records = raw.duplicate(true) if typeof(raw) == TYPE_ARRAY else []
		if not records.has(record_id):
			records.append(record_id)
		run_state.set("discovered_records", records)

static func _required_definitions_from_catalog(catalog) -> Dictionary:
	var definitions := []
	for row in catalog.get_definitions("items"):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not _checkbox_value(row.get("core_tea_ware", false)):
			continue
		if String(row.get("status", "")) == "폐기" or String(row.get("type", "")) != "다구":
			continue
		definitions.append(row.duplicate(true))
	return {"ok": true, "definitions": definitions}

static func _validate_reward_coverage(catalog, required_ids: Array) -> Dictionary:
	var reward_sources := []
	reward_sources.append_array(_catalog_definitions(catalog, "bosses"))
	reward_sources.append_array(_catalog_definitions(catalog, "dungeons"))
	if reward_sources.is_empty():
		return {"ok": true}
	var rewarded := {}
	for source in reward_sources:
		if typeof(source) != TYPE_DICTIONARY:
			continue
		var reward_ids = source.get("reward_item_ids", [])
		if typeof(reward_ids) != TYPE_ARRAY:
			continue
		for reward_id in reward_ids:
			rewarded[String(reward_id)] = true
	var missing := []
	for required_id in required_ids:
		if not rewarded.has(String(required_id)):
			missing.append(String(required_id))
	if not missing.is_empty():
		return _fail("missing_core_tea_ware_reward_source", "Core tea ware reward sources are missing required ids: %s" % ", ".join(missing))
	return {"ok": true}

static func _catalog_definitions(catalog, dataset: String) -> Array:
	if catalog != null and catalog.has_method("get_definitions"):
		return catalog.get_definitions(dataset)
	return []

static func _normalize_required_definitions(definitions: Array) -> Dictionary:
	if definitions.is_empty():
		return _fail("missing_core_tea_ware", "At least one core tea ware definition is required.")
	var by_order := {}
	var by_id := {}
	for raw in definitions:
		if typeof(raw) != TYPE_DICTIONARY:
			return _fail("invalid_core_tea_ware", "Core tea ware definition must be a dictionary.")
		var item_id := String(raw.get("id", ""))
		if not _is_stable_id(item_id):
			return _fail("invalid_core_tea_ware_id", "Core tea ware id must be stable: %s" % item_id)
		if by_id.has(item_id):
			return _fail("duplicate_core_tea_ware_id", "Core tea ware id is duplicated: %s" % item_id)
		var order := int(raw.get("core_tea_ware_order", 0))
		if order <= 0:
			return _fail("invalid_core_tea_ware_order", "Core tea ware order must be positive: %s" % item_id)
		if by_order.has(order):
			return _fail("duplicate_core_tea_ware_order", "Core tea ware order is duplicated: %d" % order)
		by_id[item_id] = true
		by_order[order] = raw.duplicate(true)
	var normalized := []
	for order in range(1, by_order.size() + 1):
		if not by_order.has(order):
			return _fail("missing_core_tea_ware_order", "Core tea ware orders must be contiguous from 1.")
		normalized.append(by_order[order])
	return {"ok": true, "definitions": normalized}

static func _is_stable_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45
		if not allowed:
			return false
	return true

static func _checkbox_value(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_STRING:
		var normalized := String(value).strip_edges().to_lower()
		return value == "__YES__" or normalized in ["true", "yes", "1", "y"]
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value) != 0.0
	return value != null

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
