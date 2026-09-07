extends RefCounted
class_name DungeonDefinitionResolver

func current_biome_dungeon_definition(catalog, run_state) -> Dictionary:
	if catalog == null or run_state == null:
		return {}
	var current_biome_id := String(run_state.current_biome_id)
	for definition in catalog.get_definitions("dungeons"):
		var biome_ids: Array = definition.get("biome_ids", [])
		if biome_ids.has(current_biome_id):
			return definition.duplicate(true)
	return {
		"id": "%s_core_dungeon" % current_biome_id,
		"name": "%s 핵심 던전" % current_biome_id,
		"biome_ids": [current_biome_id],
		"phase_count": 1,
		"pattern_count": 1,
		"peaceful_resolution": false,
		"reward_item_ids": []
	}

func current_biome_boss_definition(catalog, biome_id: String, dungeon_id: String) -> Dictionary:
	if catalog == null:
		return {}
	for definition in catalog.get_definitions("bosses"):
		if String(definition.get("biome_id", "")) == biome_id and String(definition.get("dungeon_id", "")) == dungeon_id:
			return definition.duplicate(true)
	return {}

func pre_boss_dialogue_event_id_for(catalog, narrative_runtime, dungeon_definition: Dictionary, boss_definition := {}) -> String:
	var explicit_event_id := String(dungeon_definition.get("pre_boss_dialogue_event_id", ""))
	if explicit_event_id.is_empty() and typeof(boss_definition) == TYPE_DICTIONARY:
		explicit_event_id = String(boss_definition.get("pre_boss_dialogue_event_id", ""))
	if not explicit_event_id.is_empty():
		return explicit_event_id if narrative_event_exists(catalog, narrative_runtime, explicit_event_id) else ""
	return ""

func narrative_event_exists(catalog, narrative_runtime, event_id: String) -> bool:
	if event_id.is_empty() or catalog == null:
		return false
	if narrative_runtime != null and narrative_runtime.event_definitions.has(event_id):
		return true
	return not catalog.find_by_id("events", event_id).is_empty()

func dungeon_entry_definition(catalog, narrative_runtime, run_state) -> Dictionary:
	var definition := current_biome_dungeon_definition(catalog, run_state)
	if definition.is_empty():
		return {}
	var biome_id := String(run_state.current_biome_id)
	definition["biome_id"] = biome_id
	var boss_definition := current_biome_boss_definition(catalog, biome_id, String(definition.get("id", "")))
	if not boss_definition.is_empty():
		definition["boss_id"] = String(boss_definition.get("id", ""))
	var event_id := pre_boss_dialogue_event_id_for(catalog, narrative_runtime, definition, boss_definition)
	if not event_id.is_empty():
		definition["pre_boss_dialogue_event_id"] = event_id
	return definition
