extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class DropSource:
	extends Node
	signal drop_requested(event: Dictionary)

class FailureProbe:
	extends RefCounted
	var reasons := []

	func record(error: Dictionary) -> void:
		reasons.append(String(error.get("reason", "")))

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "runtime acquisition fixture loads generated definitions")
	var runtime := _configured_runtime(catalog, RunState.new())
	asserts.true_value(runtime.result.ok, "main configures acquisition against generated world data")
	asserts.equal(runtime.main.acquisition_service.gatherable_for("resource_0").definition_id, "wood", "generated resource registers with its confirmed stable item id")
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "resource_0"})
	asserts.true_value(runtime.main.submit_mobile_action_command(command), "main routes target INTERACT into acquisition")
	asserts.equal(runtime.main.inventory.get_total_quantity("wood"), 1, "live interaction grants the confirmed resource")
	asserts.true_value(runtime.main.run_state.acquisitions.gatherables[0].depleted, "live acquisition changes persist into RunState")

	var saved_state: RunState = RunState.from_dictionary(runtime.main.snapshot_run_state())
	var restored := _configured_runtime(catalog, saved_state)
	asserts.true_value(restored.result.ok, "main reloads acquisition state during world lifecycle configuration")
	asserts.true_value(restored.main.acquisition_service.gatherable_for("resource_0").depleted, "reloaded runtime preserves generated resource depletion")

	var source := DropSource.new()
	var probe := FailureProbe.new()
	restored.main.acquisition_service.operation_failed.connect(probe.record)
	asserts.true_value(restored.main._connect_acquisition_combat_source(source).ok, "main connects combat drop source")
	source.drop_requested.emit({"type": "monster_drop_requested", "combat_id": "fixture_drop", "definition_id": "unconfirmed_monster"})
	asserts.equal(probe.reasons, ["unknown_drop_definition"], "combat drop signal reaches normalized acquisition processing")
	source.free()
	runtime.main.free()
	restored.main.free()

func _configured_runtime(catalog, state: RunState) -> Dictionary:
	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = state
	var services: Dictionary = runtime._configure_run_services(catalog)
	if not services.ok:
		return {"main": runtime, "result": services}
	var world := WorldData.new(3, 1, "grass", true)
	world.reserve_entity("resource_0", Vector2i.ZERO, Vector2i.ONE, true, {"resource_id": "wood"})
	runtime.generated_world = {
		"ok": true,
		"world_data": world.to_dictionary(),
		"resource_nodes": [{"id": "resource_0", "resource_id": "wood", "position": {"x": 0, "y": 0}}]
	}
	return {"main": runtime, "result": runtime._configure_acquisition_for_generated_world()}
