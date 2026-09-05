extends RefCounted
class_name GameHudReadModelProvider

const WorldData = preload("res://src/world/data/world_data.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")

signal changed(read_model: Dictionary)

const BALANCE_ABILITY_SLOTS_ID := "ability_equip_slots"

var player
var world: Dictionary = {}
var render_result: Dictionary = {}
var catalog
var inventory
var inventory_command_runtime
var map_read_model_builder
var world_data
var world_origin := Vector2.ZERO
var combat_target
var run_state
var tea_service
var tea_brewing_command_runtime
var meta_codex_command_runtime
var crafting_service
var crafting_context: Dictionary = {}
var biome_progression_state
var cheat_mode := false
var biome_map_previews: Dictionary = {}
var time_state

func configure(player_node, generated_world: Dictionary, generated_render_result: Dictionary, runtime_context := {}) -> void:
	_unbind_runtime_signals()
	player = player_node
	world = generated_world.duplicate(true)
	render_result = generated_render_result.duplicate(true)
	if typeof(runtime_context) == TYPE_DICTIONARY:
		catalog = runtime_context.get("catalog", null)
		inventory = runtime_context.get("inventory", null)
		inventory_command_runtime = runtime_context.get("inventory_command_runtime", null)
		map_read_model_builder = runtime_context.get("map_read_model_builder", null)
		world_data = runtime_context.get("world_data", null)
		world_origin = runtime_context.get("world_origin", Vector2.ZERO)
		combat_target = runtime_context.get("combat_target", null)
		run_state = runtime_context.get("run_state", null)
		tea_service = runtime_context.get("tea_service", null)
		tea_brewing_command_runtime = runtime_context.get("tea_brewing_command_runtime", null)
		meta_codex_command_runtime = runtime_context.get("meta_codex_command_runtime", null)
		crafting_service = runtime_context.get("crafting_service", null)
		crafting_context = _dictionary_value(runtime_context.get("crafting_context", {}))
		biome_progression_state = runtime_context.get("biome_progression_state", null)
		cheat_mode = bool(runtime_context.get("cheat_mode", false))
		biome_map_previews = _dictionary_value(runtime_context.get("biome_map_previews", {}))
		time_state = runtime_context.get("time_state", null)
	_bind_runtime_signals()

func read_model() -> Dictionary:
	var resources = _object_property(player, "resources")
	var phase_name := String(_object_property(time_state, "phase", "day"))
	var model := {
		"hp": int(_object_property(resources, "hp", 0)),
		"hp_max": int(_object_property(resources, "hp_max", 0)),
		"ki": int(_object_property(resources, "ki", 0)),
		"ki_max": int(_object_property(resources, "ki_max", 0)),
		"kokoro": int(_object_property(resources, "kokoro", 0)),
		"kokoro_max": int(_object_property(resources, "kokoro_max", 0)),
		"inventory_slot_count": inventory_slot_count(),
		"inventory_used_slots": inventory_used_slots(),
		"tea_quickslot_count": tea_quickslot_count(),
		"tea_ready_slots": tea_ready_slots(),
		"consumable_ready": consumable_ready(),
		"ability_slot_count": balance_integer(BALANCE_ABILITY_SLOTS_ID),
		"time_visible": time_state != null,
		"time_phase": phase_name,
		"time_phase_label": time_phase_label(phase_name),
		"time_progress_percent": time_progress_percent(),
		"combat_target": combat_target_read_model(),
		"equipment": equipment_read_model(),
		"biome_label": biome_label(current_biome_id()),
		"terrain_count": render_count("terrain"),
		"object_count": render_count("entities") + render_count("Landmarks"),
		"minimap": minimap_read_model()
	}
	return model.duplicate(true)

func inventory_read_model() -> Dictionary:
	if inventory_command_runtime == null or not inventory_command_runtime.has_method("read_model"):
		return {}
	return _dictionary_value(inventory_command_runtime.read_model())

func tea_brewing_read_model() -> Dictionary:
	if tea_brewing_command_runtime == null or not tea_brewing_command_runtime.has_method("read_model"):
		return {}
	return _dictionary_value(tea_brewing_command_runtime.read_model())

func meta_codex_read_model() -> Dictionary:
	if meta_codex_command_runtime == null or not meta_codex_command_runtime.has_method("read_model"):
		return {}
	return _dictionary_value(meta_codex_command_runtime.read_model())

func crafting_read_model(filter: String, selected_recipe_id: String) -> Dictionary:
	if crafting_service == null or not crafting_service.has_method("read_model"):
		return {}
	return _dictionary_value(crafting_service.read_model(inventory, crafting_context, {
		"category": filter,
		"selected_recipe_id": selected_recipe_id
	}))

func facility_nodes() -> Array:
	return _array_value(world.get("facility_nodes", []))

func map_read_model(options := {}, selected_biome_id := "") -> Dictionary:
	var selected_id := selected_biome_id if not selected_biome_id.is_empty() else current_biome_id()
	var map_source = world_data
	var selected_run_state = run_state
	var selected_options: Dictionary = _dictionary_value(options)
	var uses_selected_preview := false
	if selected_id != current_biome_id():
		if not biome_map_previews.has(selected_id):
			return {"ok": false, "reason": "missing_biome_map_preview", "biome_id": selected_id}
		map_source = WorldData.from_dictionary(biome_map_previews[selected_id].get("world_data", {}))
		selected_run_state = _read_state_for_selected_biome(selected_id)
		if not bool(selected_options.get("reveal_all", false)):
			selected_options["discovery_radius"] = -1
		uses_selected_preview = true
	var model := _map_read_model(selected_options, map_source, selected_run_state)
	if uses_selected_preview:
		model = _without_current_player_marker(model)
	return model

func current_biome_id() -> String:
	var biome_id := String(world.get("biome_id", ""))
	if biome_id.is_empty() and run_state != null:
		biome_id = String(_object_property(run_state, "current_biome_id", ""))
	return biome_id if not biome_id.is_empty() else "common_region"

func dungeon_cleared_for_current_biome() -> bool:
	var biome_id := current_biome_id()
	var cleared := cheat_mode or (run_state != null and _array_property(run_state, "completed_dungeon_ids").has(biome_id))
	if run_state != null:
		var teleport_states: Dictionary = _object_property(run_state, "teleport_states", {})
		cleared = cleared or String(teleport_states.get(biome_id, "")) in ["repairable", "repaired"]
		cleared = cleared or _array_property(run_state, "crafting_unlocks").has(biome_id)
	return cleared

func repaired_ruin_biome_ids() -> Array:
	if run_state == null:
		return []
	return _array_property(run_state, "completed_dungeon_ids")

func biome_progression_projection() -> Dictionary:
	if biome_progression_state == null or not biome_progression_state.has_method("to_projection"):
		return {}
	return _dictionary_value(biome_progression_state.to_projection())

func ordered_biome_definitions() -> Array:
	if catalog == null or not catalog.has_method("get_definitions"):
		return []
	var definitions: Array = _array_value(catalog.get_definitions("biomes"))
	definitions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_order = left.get("progression_order", 999)
		var right_order = right.get("progression_order", 999)
		var left_value: int = 999 if left_order == null else int(left_order)
		var right_value: int = 999 if right_order == null else int(right_order)
		return left_value < right_value
	)
	return definitions

func biome_definition(biome_id: String) -> Dictionary:
	for definition in ordered_biome_definitions():
		if String(definition.get("id", "")) == biome_id:
			return _dictionary_value(definition)
	return {}

func is_biome_map_accessible(biome_id: String) -> bool:
	if cheat_mode:
		return true
	var current_id := current_biome_id()
	if biome_id == current_id:
		return true
	if run_state != null and _array_property(run_state, "crafting_unlocks").has(biome_id):
		return true
	if biome_progression_state != null and biome_progression_state.has_method("teleport_state_for"):
		return String(biome_progression_state.teleport_state_for(biome_id)) == "repaired"
	return false

func catalog_definition(dataset: String, stable_id: String) -> Dictionary:
	if catalog != null and catalog.has_method("find_by_id"):
		return _dictionary_value(catalog.find_by_id(dataset, stable_id))
	return {}

func inventory_definition(item_id: String) -> Dictionary:
	if inventory != null and inventory.has_method("definition_for"):
		return _dictionary_value(inventory.definition_for(item_id))
	if catalog != null and catalog.has_method("find_by_id"):
		return _dictionary_value(catalog.find_by_id("items", item_id))
	return {"id": item_id, "name": item_id}

func speaker_label(speaker_id: String) -> String:
	if catalog != null and catalog.has_method("find_character_by_id"):
		var character: Dictionary = _dictionary_value(catalog.find_character_by_id(speaker_id))
		if not character.is_empty():
			return String(character.get("name", speaker_id))
	return speaker_id

func balance_integer(id: String) -> int:
	if catalog == null or not catalog.has_method("find_by_id"):
		return 0
	var definition: Dictionary = _dictionary_value(catalog.find_by_id("balance", id))
	return int(definition.get("value", 0))

func inventory_slot_count() -> int:
	return int(_object_property(inventory, "slot_count", 0))

func inventory_used_slots() -> int:
	var slots = _object_property(inventory, "slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return 0
	var count := 0
	for slot in slots:
		if typeof(slot) == TYPE_DICTIONARY and not slot.is_empty():
			count += 1
	return count

func tea_quickslot_count() -> int:
	return int(_object_property(tea_service, "quickslot_count", 0))

func tea_ready_slots() -> int:
	var slots = _object_property(tea_service, "quick_slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return 0
	var count := 0
	for slot in slots:
		if typeof(slot) == TYPE_DICTIONARY and not slot.is_empty():
			count += 1
	return count

func consumable_ready() -> bool:
	var slots = _object_property(inventory, "slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return false
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY or int(slot.get("quantity", 0)) <= 0:
			continue
		var item_id := String(slot.get("item_id", ""))
		var definition := inventory_definition(item_id)
		if String(definition.get("type", "")) == "소모품":
			return true
	return false

func time_progress_percent() -> int:
	if time_state == null:
		return 0
	var phase := StringName(_object_property(time_state, "phase", "day"))
	var elapsed := float(_object_property(time_state, "phase_elapsed_seconds", 0.0))
	var config = _object_property(time_state, "config")
	if config == null or not config.has_method("phase_duration_seconds"):
		return 0
	var duration := float(config.phase_duration_seconds(phase))
	if duration <= 0.0:
		return 0
	return clampi(int(round((elapsed / duration) * 100.0)), 0, 100)

func time_phase_label(id: String) -> String:
	match id:
		"day":
			return "낮"
		"dusk":
			return "해질녘"
		"night":
			return "밤"
		"late_night":
			return "깊은 밤"
		_:
			return id

func biome_label(id: String) -> String:
	match id:
		"common_region":
			return "초록 평원"
		"mountain_region":
			return "산악 지대"
		"snowfield":
			return "설원"
		"rainforest":
			return "열대 우림"
		"wasteland":
			return "황무지"
		_:
			return id

func render_count(key: String) -> int:
	var counts: Dictionary = render_result.get("counts", {})
	return int(counts.get(key, 0))

func equipment_read_model() -> Dictionary:
	var model := inventory_read_model()
	return _dictionary_value(model.get("equipment", {}))

func minimap_read_model() -> Dictionary:
	var model := _map_read_model({"minimap_width": 11, "minimap_height": 7})
	if not bool(model.get("ok", false)):
		return model
	return {
		"ok": true,
		"discovered_count": int(model.discovered_count),
		"marker_count": _array_value(model.get("markers", [])).size(),
		"minimap": model.minimap
	}

func combat_target_read_model() -> Dictionary:
	var combatant = _object_property(combat_target, "combatant")
	if combatant == null:
		return {"visible": false}
	var hp := int(_object_property(combatant, "hp", 0))
	var hp_max := int(_object_property(combatant, "hp_max", 0))
	if hp_max <= 0:
		return {"visible": false}
	var definition_id := String(_object_property(combatant, "definition_id", _object_property(combat_target, "monster_id", "")))
	var definition := catalog_definition("monsters", definition_id) if not definition_id.is_empty() else {}
	return {
		"visible": hp > 0,
		"id": definition_id,
		"name": String(definition.get("name", definition_id if not definition_id.is_empty() else "적")),
		"hp": hp,
		"hp_max": hp_max,
		"attack": int(_object_property(combatant, "attack", 0))
	}

func _map_read_model(options := {}, source_world_data = null, source_run_state = null) -> Dictionary:
	if map_read_model_builder == null or not map_read_model_builder.has_method("build"):
		return {"ok": false, "reason": "missing_map_read_model_builder"}
	var selected_source = source_world_data if source_world_data != null else (world_data if world_data != null else world)
	var selected_run_state = source_run_state if source_run_state != null else run_state
	return _dictionary_value(map_read_model_builder.build(selected_source, selected_run_state, _player_cell(), options))

func _read_state_for_selected_biome(biome_id: String) -> Dictionary:
	var state := {
		"current_biome_id": biome_id,
		"completed_dungeon_ids": [],
		"teleport_states": {},
		"crafting_unlocks": [],
		"map_discovery": {}
	}
	if run_state == null:
		return state
	state["completed_dungeon_ids"] = _array_property(run_state, "completed_dungeon_ids")
	state["teleport_states"] = _object_property(run_state, "teleport_states", {})
	state["crafting_unlocks"] = _array_property(run_state, "crafting_unlocks")
	var discovery_by_biome: Dictionary = _object_property(run_state, "map_discovery_by_biome", {})
	if discovery_by_biome.has(biome_id):
		state["map_discovery"] = _dictionary_value(discovery_by_biome[biome_id])
	return state

func _without_current_player_marker(model: Dictionary) -> Dictionary:
	var result := _dictionary_value(model)
	var markers := []
	for raw_marker in _array_value(result.get("markers", [])):
		var marker: Dictionary = raw_marker
		if String(marker.get("marker_type", "")) == MapReadModelBuilder.MARKER_PLAYER:
			continue
		markers.append(marker)
	result["markers"] = markers
	result["player"] = {}
	if result.has("minimap"):
		var minimap: Dictionary = _dictionary_value(result.minimap)
		var minimap_markers := []
		for raw_marker in _array_value(minimap.get("markers", [])):
			var marker: Dictionary = raw_marker
			if String(marker.get("marker_type", "")) == MapReadModelBuilder.MARKER_PLAYER:
				continue
			minimap_markers.append(marker)
		minimap["markers"] = minimap_markers
		result["minimap"] = minimap
	return result

func _player_cell() -> Vector2i:
	var position := Vector2.ZERO
	if player != null and player.has_method("get"):
		position = player.get("global_position")
	var tile_size := 32
	if world_data != null and world_data.has_method("get"):
		tile_size = max(1, int(world_data.get("tile_size")))
	var local_position := position - world_origin
	return Vector2i(int(floor(local_position.x / float(tile_size))), int(floor(local_position.y / float(tile_size))))

func _bind_runtime_signals() -> void:
	var resources = _object_property(player, "resources")
	_connect_runtime_signal(resources, &"hp_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(resources, &"ki_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(resources, &"kokoro_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(inventory, &"changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(inventory_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(combat_target, &"damaged", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(combat_target, &"defeated", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(tea_service, &"changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(tea_brewing_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(meta_codex_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_connect_runtime_signal(time_state, &"phase_changed", Callable(self, "_on_runtime_changed"))

func _unbind_runtime_signals() -> void:
	var resources = _object_property(player, "resources")
	_disconnect_runtime_signal(resources, &"hp_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(resources, &"ki_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(resources, &"kokoro_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(inventory, &"changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(inventory_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(combat_target, &"damaged", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(combat_target, &"defeated", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(tea_service, &"changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(tea_brewing_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(meta_codex_command_runtime, &"read_model_changed", Callable(self, "_on_runtime_changed"))
	_disconnect_runtime_signal(time_state, &"phase_changed", Callable(self, "_on_runtime_changed"))

func _connect_runtime_signal(source, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _disconnect_runtime_signal(source, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)

func _on_runtime_changed(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
	changed.emit(read_model())

func _object_property(object, property: String, fallback = null):
	if typeof(object) == TYPE_DICTIONARY:
		var dictionary: Dictionary = object
		return dictionary.get(property, fallback)
	if object == null or not object.has_method("get"):
		return fallback
	var value = object.get(property)
	return fallback if value == null else value

func _array_property(object, property: String) -> Array:
	return _array_value(_object_property(object, property, []))

func _array_value(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

func _dictionary_value(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
