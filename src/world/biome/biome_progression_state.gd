extends RefCounted
class_name BiomeProgressionState

const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")

const TELEPORT_UNDISCOVERED := "undiscovered"
const TELEPORT_BROKEN := "broken"
const TELEPORT_REPAIRABLE := "repairable"
const TELEPORT_REPAIRED := "repaired"

const BIOME_SOURCE := "biomes"

var _biome_ids: Array = []
var _run_state: RunState

static func from_catalog(catalog, run_state: Variant = null) -> Dictionary:
	if catalog == null or not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Catalog cannot provide biome definitions.")
	var state: BiomeProgressionState = load("res://src/world/biome/biome_progression_state.gd").new()
	var configure_result: Dictionary = state.configure(catalog.get_definitions(BIOME_SOURCE), run_state)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "progression_state": state}

func configure(biome_definitions: Array, run_state: Variant = null) -> Dictionary:
	var ordered: Array = []
	var seen_ids := {}
	var seen_orders := {}
	for definition in biome_definitions:
		if typeof(definition) != TYPE_DICTIONARY:
			continue
		var raw_order = definition.get("progression_order")
		if raw_order == null:
			continue
		if typeof(raw_order) not in [TYPE_INT, TYPE_FLOAT] or float(raw_order) != floor(float(raw_order)) or int(raw_order) <= 0:
			return _fail("invalid_progression_order", "Biome progression_order must be a positive integer.")
		var biome_id := String(definition.get("id", ""))
		var order := int(raw_order)
		if biome_id.is_empty():
			return _fail("missing_biome_id", "Progression biome is missing a stable id.")
		if seen_ids.has(biome_id):
			return _fail("duplicate_biome_id", "Duplicate progression biome id: %s" % biome_id)
		if seen_orders.has(order):
			return _fail("duplicate_progression_order", "Duplicate biome progression order: %d" % order)
		seen_ids[biome_id] = true
		seen_orders[order] = true
		ordered.append({"id": biome_id, "order": order})
	if ordered.is_empty():
		return _fail("missing_biome_definitions", "Biome progression requires at least one ordered biome.")
	ordered.sort_custom(func(a, b) -> bool: return int(a.order) < int(b.order))
	_biome_ids.clear()
	for definition in ordered:
		_biome_ids.append(String(definition.id))

	_run_state = run_state if run_state is RunState else RunState.new()
	if _run_state.current_biome_id.is_empty():
		reset_run()
	else:
		var hydration_result := _hydrate_progression_state()
		if not hydration_result.ok:
			return hydration_result
	return {"ok": true}

func apply_command(command) -> Dictionary:
	if not command is GameCommand:
		return _fail("invalid_command", "Biome progression requires a GameCommand.")
	var biome_id := String(command.payload.get("biome_id", current_biome_id()))
	match command.type:
		GameCommand.Type.COMPLETE_DUNGEON:
			return complete_dungeon(biome_id)
		GameCommand.Type.REPAIR_TELEPORT:
			return repair_teleport(biome_id)
		GameCommand.Type.ADVANCE_BIOME:
			return advance_biome(biome_id)
		_:
			return _fail("unsupported_command", "Command is not handled by biome progression.")

func complete_dungeon(biome_id: String) -> Dictionary:
	var order_result := _validate_current_biome(biome_id)
	if not order_result.ok:
		return order_result
	if _run_state.completed_dungeon_ids.has(biome_id):
		return _fail("duplicate_dungeon_completion", "Dungeon completion was already recorded.")
	if teleport_state_for(biome_id) != TELEPORT_BROKEN:
		return _fail("invalid_teleport_state", "Dungeon completion requires a broken teleport.")
	_run_state.completed_dungeon_ids.append(biome_id)
	_run_state.crafting_unlocks.append(biome_id)
	_run_state.teleport_states[biome_id] = TELEPORT_REPAIRABLE
	return _success_projection()

func repair_teleport(biome_id: String) -> Dictionary:
	var order_result := _validate_current_biome(biome_id)
	if not order_result.ok:
		return order_result
	var state := teleport_state_for(biome_id)
	if state == TELEPORT_REPAIRED or _run_state.repaired_teleports.has(biome_id):
		return _fail("duplicate_repair", "Teleport was already repaired.")
	if not _run_state.completed_dungeon_ids.has(biome_id):
		return _fail("dungeon_incomplete", "Teleport repair requires dungeon completion.")
	if state != TELEPORT_REPAIRABLE:
		return _fail("teleport_not_repairable", "Teleport is not repairable in its current state.")
	_run_state.teleport_states[biome_id] = TELEPORT_REPAIRED
	_run_state.repaired_teleports.append(biome_id)
	return _success_projection()

func advance_biome(biome_id: String) -> Dictionary:
	var order_result := _validate_current_biome(biome_id)
	if not order_result.ok:
		return order_result
	if teleport_state_for(biome_id) != TELEPORT_REPAIRED:
		return _fail("teleport_not_repaired", "Advancing requires the current biome teleport to be repaired.")
	var next_id := next_biome_id()
	if next_id.is_empty():
		return _fail("no_next_biome", "The current biome is the final progression biome.")
	if teleport_state_for(next_id) != TELEPORT_UNDISCOVERED:
		return _fail("invalid_biome_order", "Next biome was already discovered out of order.")
	_run_state.current_biome_id = next_id
	_run_state.teleport_states[next_id] = TELEPORT_BROKEN
	return _success_projection()

func reset_run() -> void:
	_run_state.reset_biome_progression()
	for biome_id in _biome_ids:
		_run_state.teleport_states[biome_id] = TELEPORT_UNDISCOVERED
	_run_state.current_biome_id = String(_biome_ids[0])
	_run_state.teleport_states[_run_state.current_biome_id] = TELEPORT_BROKEN

func current_biome_id() -> String:
	return _run_state.current_biome_id

func next_biome_id() -> String:
	var current_index := _biome_ids.find(current_biome_id())
	if current_index < 0 or current_index + 1 >= _biome_ids.size():
		return ""
	return String(_biome_ids[current_index + 1])

func teleport_state_for(biome_id: String) -> String:
	return String(_run_state.teleport_states.get(biome_id, TELEPORT_UNDISCOVERED))

func can_advance_biome() -> bool:
	return not next_biome_id().is_empty() and teleport_state_for(current_biome_id()) == TELEPORT_REPAIRED

func crafting_context() -> Dictionary:
	return {
		"current_biome_id": current_biome_id(),
		"unlocked_biome_ids": _run_state.crafting_unlocks.duplicate(true)
	}

func to_projection() -> Dictionary:
	return {
		"schema_version": 1,
		"read_only": true,
		"current_biome_id": current_biome_id(),
		"biome_order": _biome_ids.duplicate(true),
		"teleport_states": _run_state.teleport_states.duplicate(true),
		"completed_dungeon_ids": _run_state.completed_dungeon_ids.duplicate(true),
		"crafting_unlocks": _run_state.crafting_unlocks.duplicate(true),
		"next_biome_id": next_biome_id(),
		"can_advance_biome": can_advance_biome()
	}

func _hydrate_progression_state() -> Dictionary:
	if not _biome_ids.has(_run_state.current_biome_id):
		return _fail("unknown_current_biome", "Run state current biome is not in progression definitions.")
	for biome_id in _biome_ids:
		if not _run_state.teleport_states.has(biome_id):
			_run_state.teleport_states[biome_id] = TELEPORT_UNDISCOVERED
	return {"ok": true}

func _validate_current_biome(biome_id: String) -> Dictionary:
	if biome_id.is_empty() or not _biome_ids.has(biome_id):
		return _fail("unknown_biome", "Biome id is not in progression definitions.")
	if biome_id != current_biome_id():
		return _fail("invalid_biome_order", "Progression event must target the current biome.")
	return {"ok": true}

func _success_projection() -> Dictionary:
	return {"ok": true, "projection": to_projection()}

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
