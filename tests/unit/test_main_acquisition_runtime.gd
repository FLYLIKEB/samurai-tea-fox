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
	asserts.true_value(runtime.result.ok, "main configures acquisition against generated world data: %s" % runtime.result.get("error", ""))
	if not runtime.result.ok:
		runtime.main.free()
		return
	asserts.equal(runtime.main.acquisition_service.gatherable_for("resource_0").definition_id, "wood", "generated resource registers with its confirmed stable item id")
	var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "resource_0"})
	asserts.true_value(runtime.main.submit_mobile_action_command(command), "main routes target INTERACT into acquisition")
	asserts.equal(runtime.main.inventory.get_total_quantity("wood"), 1, "live interaction grants the confirmed resource")
	asserts.true_value(runtime.main.run_state.acquisitions.gatherables[0].depleted, "live acquisition changes persist into RunState")

	var desktop_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(desktop_runtime.result.ok, "desktop interaction fixture configures")
	asserts.true_value(desktop_runtime.main.submit_desktop_action_command("interact", Vector2i.RIGHT), "desktop interact resolves the forward world target")
	asserts.equal(desktop_runtime.main.inventory.get_total_quantity("wood"), 1, "desktop interact grants through the shared acquisition command")

	var mobile_button_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(mobile_button_runtime.result.ok, "mobile button interaction fixture configures")
	asserts.true_value(mobile_button_runtime.main.submit_mobile_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.RIGHT)), "mobile interact without target resolves through the shared nearby target path")
	asserts.equal(mobile_button_runtime.main.inventory.get_total_quantity("wood"), 1, "mobile interact without target grants through the shared acquisition command")

	var pointer_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.ZERO)
	asserts.true_value(pointer_runtime.result.ok, "pointer interaction fixture configures")
	var pointer_position: Vector2 = pointer_runtime.main.world_position_for_cell_center(Vector2i.ZERO)
	asserts.true_value(pointer_runtime.main.submit_pointer_interaction(pointer_position), "pointer click resolves the clicked interactable cell")
	asserts.equal(pointer_runtime.main.inventory.get_total_quantity("wood"), 1, "pointer click grants through the shared acquisition command")

	var near_pointer_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.RIGHT)
	asserts.true_value(near_pointer_runtime.result.ok, "nearby pointer interaction fixture configures")
	var near_pointer_position: Vector2 = near_pointer_runtime.main.world_position_for_cell_center(Vector2i.ZERO)
	asserts.true_value(near_pointer_runtime.main.submit_pointer_interaction(near_pointer_position), "pointer click tolerates one-cell sprite edge misses")
	asserts.equal(near_pointer_runtime.main.inventory.get_total_quantity("wood"), 1, "nearby pointer click grants through the shared acquisition command")

	var empty_click_runtime := _configured_runtime(catalog, RunState.new(), Vector2i.ZERO)
	asserts.true_value(empty_click_runtime.result.ok, "empty pointer fixture configures")
	var inventory_before_empty_click: Dictionary = empty_click_runtime.main.inventory.to_snapshot()
	asserts.false_value(empty_click_runtime.main.submit_pointer_interaction(empty_click_runtime.main.world_position_for_cell_center(Vector2i(2, 0))), "empty pointer click is ignored")
	asserts.equal(empty_click_runtime.main.inventory.to_snapshot(), inventory_before_empty_click, "empty pointer click does not mutate inventory")

	var tea_runtime := _configured_runtime(catalog, RunState.new())
	asserts.true_value(tea_runtime.result.ok, "tea command fixture configures")
	asserts.true_value(tea_runtime.main.inventory.add_item("tea_8", 1).ok, "generated tea leaf can be stocked for command routing")
	asserts.true_value(tea_runtime.main.inventory.add_item("humble_clay_bowl", 1).ok, "generated tea vessel can be stocked for command routing")
	asserts.true_value(tea_runtime.main.tea_service.brew("tea_8", "humble_clay_bowl", tea_runtime.main.inventory, 0).ok, "prepared tea can occupy quickslot 0")
	asserts.true_value(tea_runtime.main.submit_desktop_action_command("drink_tea", Vector2i.ZERO, 0), "desktop tea command routes into TeaService")
	asserts.false_value(tea_runtime.main.tea_service.has_prepared_tea(0), "routed tea command consumes the prepared quickslot use")

	var saved_state: RunState = RunState.from_dictionary(runtime.main.snapshot_run_state())
	var restored := _configured_runtime(catalog, saved_state)
	asserts.true_value(restored.result.ok, "main reloads acquisition state during world lifecycle configuration")
	asserts.equal(restored.main.inventory.get_total_quantity("wood"), 1, "reloaded runtime preserves inventory granted through live INTERACT")
	asserts.true_value(restored.main.acquisition_service.gatherable_for("resource_0").depleted, "reloaded runtime preserves generated resource depletion")

	var source := DropSource.new()
	var probe := FailureProbe.new()
	restored.main.acquisition_service.operation_failed.connect(probe.record)
	asserts.true_value(restored.main._connect_acquisition_combat_source(source).ok, "main connects combat drop source")
	source.drop_requested.emit({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.equal(restored.main.inventory.get_total_quantity("item_33"), 1, "generated road_bandit drop grants the exact related coin stable ID")
	var duplicate_result: Dictionary = restored.main.acquisition_service.process_drop_request({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.false_value(duplicate_result.ok, "duplicate generated drop request is rejected")
	asserts.equal(restored.main.inventory.get_total_quantity("item_33"), 1, "duplicate generated drop request does not grant twice")

	var dropped_state: RunState = RunState.from_dictionary(restored.main.snapshot_run_state())
	var drop_restored := _configured_runtime(catalog, dropped_state)
	asserts.true_value(drop_restored.result.ok, "fresh runtime restores generated drop acquisition state")
	asserts.equal(drop_restored.main.inventory.get_total_quantity("item_33"), 1, "generated road_bandit grant persists with inventory round-trip")
	asserts.true_value(drop_restored.main.acquisition_service.to_snapshot().processed_drop_request_ids.has("road_bandit_1"), "generated drop duplicate guard persists round-trip")
	var restored_probe := FailureProbe.new()
	drop_restored.main.acquisition_service.operation_failed.connect(restored_probe.record)
	var restored_duplicate: Dictionary = drop_restored.main.acquisition_service.process_drop_request({"type": "monster_drop_requested", "combat_id": "road_bandit_1", "definition_id": "road_bandit"})
	asserts.false_value(restored_duplicate.ok, "restored runtime rejects the persisted duplicate request")
	asserts.equal(drop_restored.main.inventory.get_total_quantity("item_33"), 1, "round-tripped duplicate guard prevents another grant")
	asserts.equal(restored_probe.reasons, ["drop_already_processed"], "round-tripped duplicate request remains rejected")
	asserts.equal(probe.reasons, ["drop_already_processed"], "duplicate drop failure is observable without mutating inventory")
	source.free()
	runtime.main.free()
	desktop_runtime.main.free()
	mobile_button_runtime.main.free()
	pointer_runtime.main.free()
	near_pointer_runtime.main.free()
	empty_click_runtime.main.free()
	tea_runtime.main.free()
	restored.main.free()
	drop_restored.main.free()

func _configured_runtime(catalog, state: RunState, resource_position := Vector2i.ZERO) -> Dictionary:
	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = state
	var services: Dictionary = runtime._configure_run_services(catalog)
	if not services.ok:
		return {"main": runtime, "result": services}
	var world := WorldData.new(3, 1, "grass", true)
	world.reserve_entity("resource_0", resource_position, Vector2i.ONE, true, {"resource_id": "wood"})
	runtime.generated_world = {
		"ok": true,
		"world_data": world.to_dictionary(),
		"resource_nodes": [{"id": "resource_0", "resource_id": "wood", "position": {"x": resource_position.x, "y": resource_position.y}}]
	}
	return {"main": runtime, "result": runtime._configure_acquisition_for_generated_world()}
