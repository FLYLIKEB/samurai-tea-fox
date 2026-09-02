extends RefCounted
class_name MetaCodexCommandRuntime

const GameCommand = preload("res://src/core/commands/game_command.gd")

signal read_model_changed(read_model: Dictionary)
signal operation_failed(error: Dictionary)

const SNAPSHOT_SCHEMA_VERSION := 1
const TAB_QUESTS := "quests"
const TAB_TEAS := "teas"
const TAB_TEA_WARE := "tea_ware"
const TAB_YOKAI := "yokai"
const TAB_MEMORIES := "memories"
const FILTER_ALL := "all"
const FILTER_DISCOVERED := "discovered"
const FILTER_MASKED := "masked"
const TABS := [TAB_QUESTS, TAB_TEAS, TAB_TEA_WARE, TAB_YOKAI, TAB_MEMORIES]
const FILTERS := [FILTER_ALL, FILTER_DISCOVERED, FILTER_MASKED]

var data_version := ""
var catalog
var run_state_provider: Callable
var meta_state_provider: Callable
var selected_tab := TAB_QUESTS
var filter_mode := FILTER_ALL
var selected_detail_id := ""

func configure(new_catalog, new_run_state_provider := Callable(), new_meta_state_provider := Callable(), new_data_version := "") -> Dictionary:
	if new_catalog == null or not new_catalog.has_method("get_definitions") or not new_catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Meta codex runtime requires a data catalog.")
	catalog = new_catalog
	run_state_provider = new_run_state_provider
	meta_state_provider = new_meta_state_provider
	data_version = new_data_version
	selected_tab = TAB_QUESTS
	filter_mode = FILTER_ALL
	selected_detail_id = ""
	_emit_changed()
	return {"ok": true}

func read_model() -> Dictionary:
	var run_snapshot := _snapshot(run_state_provider)
	var meta_snapshot := _snapshot(meta_state_provider)
	var rows := _rows_for_tab(selected_tab, run_snapshot, meta_snapshot)
	rows = _filtered_rows(rows)
	if selected_detail_id.is_empty() or _row_by_id(rows, selected_detail_id).is_empty():
		selected_detail_id = String(rows[0].get("id", "")) if not rows.is_empty() else ""
	for row in rows:
		row["selected"] = String(row.get("id", "")) == selected_detail_id
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"data_version": data_version,
		"read_only": true,
		"selected_tab": selected_tab,
		"filter_mode": filter_mode,
		"available_tabs": TABS.duplicate(),
		"available_filters": FILTERS.duplicate(),
		"rows": rows,
		"detail": _detail_for_row(_row_by_id(rows, selected_detail_id), run_snapshot, meta_snapshot),
		"counts": _counts(run_snapshot, meta_snapshot),
		"commands": {
			"set_tab": GameCommand.Type.META_CODEX_SET_TAB,
			"set_filter": GameCommand.Type.META_CODEX_SET_FILTER,
			"select_detail": GameCommand.Type.META_CODEX_SELECT_DETAIL,
			"navigate": GameCommand.Type.META_CODEX_NAVIGATE
		}
	}

func handle_command(command) -> Dictionary:
	if not command is GameCommand:
		return _fail_and_emit(_fail("invalid_command", "Meta codex runtime requires a GameCommand."))
	match command.type:
		GameCommand.Type.META_CODEX_SET_TAB:
			return set_tab(String(command.payload.get("tab", TAB_QUESTS)))
		GameCommand.Type.META_CODEX_SET_FILTER:
			return set_filter(String(command.payload.get("filter", FILTER_ALL)))
		GameCommand.Type.META_CODEX_SELECT_DETAIL:
			return select_detail(String(command.payload.get("id", "")))
		GameCommand.Type.META_CODEX_NAVIGATE:
			return navigate(command.direction)
		_:
			return _fail_and_emit(_fail("unsupported_command", "Unsupported meta codex command."))

func set_tab(tab: String) -> Dictionary:
	if not TABS.has(tab):
		return _fail_and_emit(_fail("invalid_tab", "Unknown meta codex tab: %s" % tab))
	selected_tab = tab
	selected_detail_id = ""
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func set_filter(new_filter: String) -> Dictionary:
	if not FILTERS.has(new_filter):
		return _fail_and_emit(_fail("invalid_filter", "Unknown meta codex filter: %s" % new_filter))
	filter_mode = new_filter
	selected_detail_id = ""
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func select_detail(id: String) -> Dictionary:
	var rows := _filtered_rows(_rows_for_tab(selected_tab, _snapshot(run_state_provider), _snapshot(meta_state_provider)))
	if _row_by_id(rows, id).is_empty():
		return _fail_and_emit(_fail("unknown_detail", "Meta codex detail is not in the current read model: %s" % id))
	selected_detail_id = id
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func navigate(direction: Vector2i) -> Dictionary:
	var rows := _filtered_rows(_rows_for_tab(selected_tab, _snapshot(run_state_provider), _snapshot(meta_state_provider)))
	if rows.is_empty():
		selected_detail_id = ""
		_emit_changed()
		return {"ok": true, "read_model": read_model()}
	var offset := 1
	if direction.x < 0 or direction.y < 0:
		offset = -1
	var index := 0
	for row_index in range(rows.size()):
		if String(rows[row_index].get("id", "")) == selected_detail_id:
			index = row_index
			break
	selected_detail_id = String(rows[(index + offset + rows.size()) % rows.size()].get("id", ""))
	_emit_changed()
	return {"ok": true, "read_model": read_model()}

func _rows_for_tab(tab: String, run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Array:
	match tab:
		TAB_TEAS:
			return _catalog_rows("teas", run_snapshot, meta_snapshot, "tea")
		TAB_TEA_WARE:
			return _tea_ware_rows(run_snapshot, meta_snapshot)
		TAB_YOKAI:
			return _yokai_rows(run_snapshot, meta_snapshot)
		TAB_MEMORIES:
			return _memory_rows(run_snapshot, meta_snapshot)
		_:
			return _quest_rows(run_snapshot, meta_snapshot)

func _quest_rows(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Array:
	var rows := []
	rows.append(_visible_row("quest_current_biome", "현재 바이옴", String(run_snapshot.get("current_biome_id", "미정")), true, "quest", {"biome_id": String(run_snapshot.get("current_biome_id", ""))}))
	for dungeon_id in _array_value(run_snapshot.get("completed_runtime_dungeon_ids", [])):
		rows.append(_visible_row("quest_dungeon_%s" % String(dungeon_id), "완료 던전", String(dungeon_id), true, "quest", {"dungeon_id": String(dungeon_id)}))
	for ending in _array_value(meta_snapshot.get("ending_records", [])):
		var ending_id := String(_dictionary_value(ending).get("primary_ending_id", _dictionary_value(ending).get("ending_id", "")))
		if not ending_id.is_empty():
			rows.append(_visible_row("quest_ending_%s" % ending_id, "기록된 엔딩", ending_id, true, "quest", {"ending_id": ending_id}))
	if rows.is_empty():
		rows.append(_visible_row("quest_none", "현재 목표", "기록 없음", true, "quest", {}))
	return rows

func _catalog_rows(dataset: String, run_snapshot: Dictionary, meta_snapshot: Dictionary, kind: String) -> Array:
	var rows := []
	for definition_value in catalog.get_definitions(dataset):
		var definition := _dictionary_value(definition_value)
		var id := String(definition.get("id", ""))
		if id.is_empty():
			continue
		var discovered := _is_discovered(id, dataset, run_snapshot, meta_snapshot)
		rows.append(_masked_or_visible_row(id, String(definition.get("name", id)), discovered, kind, definition))
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if bool(left.discovered) == bool(right.discovered):
			return String(left.id) < String(right.id)
		return bool(left.discovered) and not bool(right.discovered)
	)
	return rows

func _tea_ware_rows(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Array:
	var rows := []
	for definition_value in catalog.get_definitions("items"):
		var definition := _dictionary_value(definition_value)
		if String(definition.get("type", "")) != "다구":
			continue
		var id := String(definition.get("id", ""))
		var discovered := _is_discovered(id, "items", run_snapshot, meta_snapshot)
		rows.append(_masked_or_visible_row(id, String(definition.get("name", id)), discovered, "tea_ware", definition))
	return rows

func _yokai_rows(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Array:
	var rows := []
	for definition_value in catalog.get_definitions("monsters"):
		var definition := _dictionary_value(definition_value)
		if String(definition.get("kind", "")) != "요괴":
			continue
		var id := String(definition.get("id", ""))
		var discovered := _is_discovered(id, "monsters", run_snapshot, meta_snapshot)
		rows.append(_masked_or_visible_row(id, String(definition.get("name", id)), discovered, "yokai", definition))
	return rows

func _memory_rows(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Array:
	var rows := []
	for definition_value in catalog.get_definitions("teas"):
		var definition := _dictionary_value(definition_value)
		if not bool(definition.get("memory", false)):
			continue
		var id := String(definition.get("id", ""))
		var memory_id := String(definition.get("memory_event_id", "memory_tea_%s" % id))
		var discovered := _is_discovered(id, "teas", run_snapshot, meta_snapshot) or _records(run_snapshot, meta_snapshot).has(memory_id) or int(_dictionary_value(run_snapshot.get("narrative_event_counts", {})).get(memory_id, 0)) > 0
		rows.append(_masked_or_visible_row(memory_id, String(definition.get("name", id)), discovered, "memory", definition))
	for record_id in _records(run_snapshot, meta_snapshot).keys():
		if String(record_id).begins_with("memory") and _row_by_id(rows, String(record_id)).is_empty():
			rows.append(_visible_row(String(record_id), "기억 기록", String(record_id), true, "memory", {"record_id": String(record_id)}))
	return rows

func _masked_or_visible_row(id: String, name: String, discovered: bool, kind: String, definition: Dictionary) -> Dictionary:
	if discovered:
		return _visible_row(id, name, _summary_for(definition), true, kind, definition)
	return {
		"id": id,
		"name": "미발견",
		"summary": "아직 발견하지 못한 기록",
		"kind": kind,
		"discovered": false,
		"masked": true,
		"selected": false,
		"detail": {"masked": true, "spoiler": false}
	}

func _visible_row(id: String, name: String, summary: String, discovered: bool, kind: String, definition: Dictionary) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"summary": summary,
		"kind": kind,
		"discovered": discovered,
		"masked": false,
		"selected": false,
		"detail": _safe_detail(definition)
	}

func _safe_detail(definition: Dictionary) -> Dictionary:
	var detail := {}
	for key in ["id", "name", "status", "type", "tea_type", "origin", "grade", "reward_type", "condition_type", "reward_kind", "memory", "memory_event_id", "meta_memory", "dungeon_id", "biome", "biome_id", "kind"]:
		if definition.has(key):
			detail[key] = definition[key]
	return detail

func _detail_for_row(row: Dictionary, run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Dictionary:
	if row.is_empty():
		return {}
	var detail: Dictionary = _dictionary_value(row.get("detail", {}))
	detail["id"] = String(row.get("id", ""))
	detail["name"] = String(row.get("name", ""))
	detail["masked"] = bool(row.get("masked", false))
	detail["related"] = _related_for_row(row, run_snapshot, meta_snapshot)
	return detail

func _related_for_row(row: Dictionary, _run_snapshot: Dictionary, _meta_snapshot: Dictionary) -> Dictionary:
	if bool(row.get("masked", false)):
		return {}
	var related := {"characters": [], "memories": []}
	var row_id := String(row.get("id", ""))
	var detail := _dictionary_value(row.get("detail", {}))
	var event_ids := [row_id]
	var memory_event_id := String(detail.get("memory_event_id", ""))
	if not memory_event_id.is_empty() and not event_ids.has(memory_event_id):
		event_ids.append(memory_event_id)
	for event_value in catalog.get_definitions("events"):
		var event := _dictionary_value(event_value)
		if event_ids.has(String(event.get("id", ""))) or String(event.get("ending_key", "")) == row_id:
			for node in _array_value(event.get("nodes", [])):
				var speaker_id := String(_dictionary_value(node).get("speaker_id", ""))
				if not speaker_id.is_empty() and not _related_has_id(related.characters, speaker_id):
					var character: Dictionary = catalog.find_character_by_id(speaker_id) if catalog.has_method("find_character_by_id") else catalog.find_by_id("characters", speaker_id)
					related.characters.append({
						"id": speaker_id,
						"name": String(character.get("name", speaker_id)),
						"meta_memory": bool(character.get("meta_memory", false))
					})
	for tea_value in catalog.get_definitions("teas"):
		var tea := _dictionary_value(tea_value)
		if String(tea.get("memory_event_id", "memory_tea_%s" % String(tea.get("id", "")))) == row_id:
			related.memories.append({
				"id": String(tea.get("id", "")),
				"name": String(tea.get("name", tea.get("id", "")))
			})
	return related

func _related_has_id(rows: Array, id: String) -> bool:
	for row in rows:
		if String(_dictionary_value(row).get("id", "")) == id:
			return true
	return false

func _filtered_rows(rows: Array) -> Array:
	var filtered := []
	for row in rows:
		var discovered := bool(_dictionary_value(row).get("discovered", false))
		if filter_mode == FILTER_DISCOVERED and not discovered:
			continue
		if filter_mode == FILTER_MASKED and discovered:
			continue
		filtered.append(_dictionary_value(row))
	return filtered

func _row_by_id(rows: Array, id: String) -> Dictionary:
	for row_value in rows:
		var row := _dictionary_value(row_value)
		if String(row.get("id", "")) == id:
			return row
	return {}

func _is_discovered(id: String, dataset: String, run_snapshot: Dictionary, meta_snapshot: Dictionary) -> bool:
	var records := _records(run_snapshot, meta_snapshot)
	if records.has(id) or records.has("%s:%s" % [dataset, id]):
		return true
	if _array_value(run_snapshot.get("discovered_records", [])).has(id):
		return true
	if dataset == "teas" and _inventory_item_ids(run_snapshot).has(id):
		return true
	if dataset == "items" and (_inventory_item_ids(run_snapshot).has(id) or _array_value(_dictionary_value(run_snapshot.get("core_tea_ware_collection", {})).get("collected_ids", [])).has(id)):
		return true
	if dataset == "monsters" and _array_value(meta_snapshot.get("reached_place_ids", [])).has(id):
		return true
	if dataset == "bosses" and (_array_value(run_snapshot.get("completed_runtime_dungeon_ids", [])).has(String(catalog.find_by_id("bosses", id).get("dungeon_id", ""))) or _array_value(meta_snapshot.get("reached_place_ids", [])).has(id)):
		return true
	return false

func _inventory_item_ids(run_snapshot: Dictionary) -> Dictionary:
	var ids := {}
	var inventory := _dictionary_value(run_snapshot.get("inventory", {}))
	for slot_value in _array_value(inventory.get("slots", [])):
		var id := String(_dictionary_value(slot_value).get("item_id", ""))
		if not id.is_empty():
			ids[id] = true
	return ids

func _records(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Dictionary:
	var records := {}
	for field_source in [run_snapshot, meta_snapshot]:
		for record_id in _array_value(field_source.get("discovered_records", [])):
			records[String(record_id)] = true
	for choice_id in _array_value(run_snapshot.get("choice_history", [])) + _array_value(meta_snapshot.get("past_choice_ids", [])):
		records[String(choice_id)] = true
	return records

func _counts(run_snapshot: Dictionary, meta_snapshot: Dictionary) -> Dictionary:
	return {
		"discovered_records": _records(run_snapshot, meta_snapshot).size(),
		"choices": _array_value(run_snapshot.get("choice_history", [])).size() + _array_value(meta_snapshot.get("past_choice_ids", [])).size(),
		"endings": _array_value(meta_snapshot.get("ending_records", [])).size()
	}

func _summary_for(definition: Dictionary) -> String:
	for key in ["summary", "description", "origin", "name", "id"]:
		var value := String(definition.get(key, ""))
		if not value.is_empty():
			return value
	return ""

func _snapshot(provider: Callable) -> Dictionary:
	if not provider.is_valid():
		return {}
	var value = provider.call()
	if typeof(value) == TYPE_OBJECT and value != null and value.has_method("to_dictionary"):
		return value.to_dictionary()
	return _dictionary_value(value)

func _emit_changed() -> void:
	read_model_changed.emit(read_model())

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error.duplicate(true))
	return error

static func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

static func _fail(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
