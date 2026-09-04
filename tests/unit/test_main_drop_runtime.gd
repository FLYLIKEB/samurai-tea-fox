extends RefCounted

const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const TimeState = preload("res://src/time/time_state.gd")

class AcquisitionProbe:
	extends RefCounted
	var event: Dictionary = {}
	var context: Dictionary = {}

	func process_drop_request(next_event: Dictionary, _position := Vector2i.ZERO, next_context := {}) -> Dictionary:
		event = next_event.duplicate(true)
		context = next_context.duplicate(true)
		return {"ok": true, "grants": []}

class CatalogProbe:
	extends RefCounted
	var drops: Array

	func _init(next_drops: Array) -> void:
		drops = next_drops

	func get_definitions(dataset: String) -> Array:
		return drops if dataset == "drops" else []

class TimePhaseProbe:
	extends RefCounted
	var phase: StringName

	func _init(next_phase: StringName) -> void:
		phase = next_phase

class DropSourceProbe:
	extends Node2D
	signal drop_requested(event: Dictionary)

func run(asserts) -> void:
	_assert_main_observes_seed_and_time_state(asserts)
	_assert_combat_source_supplies_drop_position(asserts)
	_assert_generated_rows_group_by_stable_monster_id(asserts)

func _assert_main_observes_seed_and_time_state(asserts) -> void:
	var main := Main.new()
	var state := RunState.new()
	state.seed = 70159
	var acquisition := AcquisitionProbe.new()
	main.run_state = state
	main.time_state = TimePhaseProbe.new(TimeState.LATE_NIGHT)
	main.acquisition_service = acquisition
	main._in_dungeon_map = true
	main._on_combat_drop_requested({
		"type": "monster_drop_requested",
		"combat_id": "foxfire_7",
		"definition_id": "foxfire",
		"position": {"x": 2, "y": 3}
	})
	asserts.equal(acquisition.context.run_seed, 70159, "main passes the current run seed into drop evaluation")
	asserts.equal(acquisition.context.time_phase, "late_night", "main observes the current time phase for conditional drops")
	asserts.equal(acquisition.event.definition_id, "foxfire", "main preserves the monster stable definition id")
	asserts.equal(acquisition.event.position, {"x": 2, "y": 3}, "dungeon monster drops use the shared acquisition path")
	main.free()

func _assert_combat_source_supplies_drop_position(asserts) -> void:
	var main := Main.new()
	var acquisition := AcquisitionProbe.new()
	var source := DropSourceProbe.new()
	main.acquisition_service = acquisition
	main.add_child(source)
	source.position = main.world_position_for_cell_center(Vector2i(5, 6))
	asserts.true_value(main._connect_acquisition_combat_source(source).ok, "main connects each monster drop source")
	source.drop_requested.emit({
		"type": "monster_drop_requested",
		"combat_id": "wild_dog_12",
		"definition_id": "wild_dog"
	})
	asserts.equal(acquisition.event.position, {"x": 5, "y": 6}, "drop position comes from the monster that emitted the event")
	main.free()

func _assert_generated_rows_group_by_stable_monster_id(asserts) -> void:
	var main := Main.new()
	main.catalog = CatalogProbe.new([
		{"id": "drop_3", "monster_id": "wild_dog", "tea_id": "tea_8", "condition": "낮", "min_quantity": 1, "max_quantity": 1, "chance": 0.08},
		{"id": "drop_4", "monster_id": "foxfire", "tea_id": "tea_15", "condition": "밤", "min_quantity": 1, "max_quantity": 1, "chance": 0.12},
		{"id": "drop_5", "monster_id": "wild_dog", "item_id": "item_32", "condition": "항상", "min_quantity": 1, "max_quantity": 2, "chance": 0.4}
	])
	var definitions: Array = main._generated_drop_definitions()
	asserts.equal(definitions.size(), 2, "all generated rows group into their stable monster definitions")
	asserts.equal(definitions[0].monster_id, "foxfire", "generated monster groups are deterministic by stable id")
	asserts.equal(definitions[0].grants[0].item_id, "tea_15", "tea relations normalize into the shared acquisition item id")
	asserts.equal(definitions[1].monster_id, "wild_dog", "second generated monster group retains its stable id")
	asserts.equal(definitions[1].grants.size(), 2, "all generated rows for one monster are retained")
	asserts.equal(definitions[1].grants[0].condition, "낮", "generated day condition reaches the evaluator unchanged")
	asserts.equal(definitions[1].grants[1].max_quantity, 2, "generated quantity range reaches the evaluator unchanged")
	main.free()
