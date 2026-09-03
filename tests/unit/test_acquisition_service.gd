extends RefCounted

const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-acquisition"

	func _init(slot_count: int) -> void:
		definitions = {
			"balance": [{"id": "inventory_base_slots", "value": slot_count}],
			"items": [
				{"id": "wood", "name": "목재", "type": "재료", "max_stack": 10},
				{"id": "clay", "name": "점토", "type": "재료", "max_stack": 10},
				{"id": "fixture_ore_item", "name": "테스트 광물", "type": "재료", "max_stack": 10},
				{"id": "stone_axe", "name": "돌도끼", "type": "도구", "max_stack": 1},
				{"id": "filler", "name": "테스트 채움재", "type": "재료", "max_stack": 1}
			],
			"teas": [
				{"id": "fixture_tea_leaf_item", "name": "테스트 찻잎", "max_stack": 10}
			]
		}

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if String(definition.get("id", "")) == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_four_fixture_types_share_interact_contract(asserts)
	_assert_inventory_full_preserves_pickup(asserts)
	_assert_monster_drop_uses_stable_definition(asserts)
	_assert_run_save_round_trip_preserves_world_state(asserts)
	_assert_invalid_definitions_are_atomic(asserts)
	_assert_generated_resource_reservation_can_be_adopted(asserts)
	_assert_gatherable_can_require_a_tool_and_clear_terrain(asserts)
	_assert_interaction_kind_alone_cannot_be_adopted(asserts)
	_assert_failed_snapshot_restore_is_atomic(asserts)
	_assert_multi_grant_drop_rolls_back_on_world_failure(asserts)

func _assert_four_fixture_types_share_interact_contract(asserts) -> void:
	var runtime := _runtime(8, Vector2i(8, 2))
	var service: AcquisitionService = runtime.service
	var fixture_nodes := [
		{"node_id": "tree_01", "definition_id": "fixture_tree_common", "position": Vector2i(0, 0), "item_id": "wood"},
		{"node_id": "ore_01", "definition_id": "fixture_ore_mountain", "position": Vector2i(2, 0), "item_id": "fixture_ore_item"},
		{"node_id": "clay_01", "definition_id": "fixture_clay_common", "position": Vector2i(4, 0), "item_id": "clay"},
		{"node_id": "tea_01", "definition_id": "fixture_tea_leaf_common", "position": Vector2i(6, 0), "item_id": "fixture_tea_leaf_item"}
	]

	for fixture in fixture_nodes:
		asserts.true_value(service.register_gatherable(fixture.node_id, fixture.definition_id, fixture.position).ok, "fixture registers through common gatherable path")
		var command := GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": fixture.node_id})
		var gathered: Dictionary = service.handle_command(command)
		asserts.true_value(gathered.ok, "fixture gathers through common INTERACT command")
		asserts.true_value(service.gatherable_for(fixture.node_id).depleted, "successful gather depletes fixture node")
		var duplicate: Dictionary = service.handle_command(command)
		asserts.false_value(duplicate.ok, "depleted fixture cannot grant twice")
		asserts.equal(duplicate.reason, "depleted", "duplicate gather reports stable depleted reason")
		if gathered.delivery == AcquisitionService.POLICY_PICKUP:
			asserts.true_value(service.handle_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": gathered.pickup_id})).ok, "pickup uses the same INTERACT command boundary")
		asserts.equal(runtime.inventory.get_total_quantity(fixture.item_id), 1, "fixture stable item id reaches inventory")

func _assert_inventory_full_preserves_pickup(asserts) -> void:
	var runtime := _runtime(1, Vector2i(3, 1))
	var inventory: InventoryModel = runtime.inventory
	var service: AcquisitionService = runtime.service
	asserts.true_value(inventory.add_item("filler", 1).ok, "capacity fixture fills inventory")
	var inventory_before := inventory.to_snapshot()
	asserts.true_value(service.register_gatherable("tree_full", "fixture_tree_common", Vector2i(1, 0)).ok, "full inventory tree registers")

	var gathered: Dictionary = service.handle_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "tree_full"}))
	asserts.true_value(gathered.ok, "full inventory falls back to pickup")
	asserts.equal(gathered.delivery, AcquisitionService.POLICY_PICKUP, "capacity failure uses pickup delivery")
	asserts.equal(inventory.to_snapshot(), inventory_before, "capacity failure preserves inventory atomically")
	asserts.equal(service.pickup_for(gathered.pickup_id).item_id, "wood", "overflow item remains in world pickup")

	var failed_collect: Dictionary = service.collect_pickup(gathered.pickup_id)
	asserts.false_value(failed_collect.ok, "full inventory rejects pickup collection")
	asserts.equal(failed_collect.reason, "inventory_full", "pickup exposes inventory capacity failure")
	asserts.equal(service.pickup_for(gathered.pickup_id).quantity, 1, "failed pickup collection leaves full quantity in world")
	asserts.true_value(inventory.remove_item("filler", 1).ok, "capacity fixture frees inventory")
	asserts.true_value(service.collect_pickup(gathered.pickup_id).ok, "pickup collects after capacity becomes available")
	asserts.equal(service.pickup_for(gathered.pickup_id), {}, "pickup is removed only after successful inventory grant")
	asserts.equal(inventory.get_total_quantity("wood"), 1, "preserved pickup reaches inventory")

func _assert_monster_drop_uses_stable_definition(asserts) -> void:
	var runtime := _runtime(4, Vector2i(4, 2))
	var service: AcquisitionService = runtime.service
	var event := {
		"type": "monster_drop_requested",
		"combat_id": "combat_road_bandit_01",
		"definition_id": "road_bandit",
		"display_drop": "이 문자열은 런타임에서 해석하지 않는다",
		"position": {"x": 1, "y": 1}
	}
	var dropped: Dictionary = service.process_drop_request(event)
	asserts.true_value(dropped.ok, "monster drop request resolves through stable definition id")
	asserts.equal(dropped.grants[0].item_id, "clay", "drop ignores display string and uses normalized item id")
	asserts.equal(dropped.grants[0].delivery, AcquisitionService.POLICY_PICKUP, "drop definition controls pickup policy")
	var pickup_id := String(dropped.grants[0].pickup_id)
	asserts.equal(service.pickup_for(pickup_id).source.source_id, "road_bandit", "pickup retains stable monster source id")
	var duplicate: Dictionary = service.process_drop_request(event)
	asserts.false_value(duplicate.ok, "duplicate monster drop request is rejected")
	asserts.equal(duplicate.reason, "drop_already_processed", "duplicate drop uses stable reason")

func _assert_run_save_round_trip_preserves_world_state(asserts) -> void:
	var first := _runtime(1, Vector2i(4, 2))
	asserts.true_value(first.inventory.add_item("filler", 1).ok, "save fixture fills inventory")
	asserts.true_value(first.service.register_gatherable("clay_save", "fixture_clay_common", Vector2i(1, 0)).ok, "save fixture gatherable registers")
	var gathered: Dictionary = first.service.gather("clay_save")
	asserts.true_value(gathered.ok, "save fixture gather creates persistent pickup")

	var run_state := RunState.new()
	run_state.acquisitions = first.service.to_snapshot()
	var decoded: Dictionary = SaveCodec.decode_run(SaveCodec.encode_run(run_state.to_dictionary()))
	asserts.true_value(decoded.ok, "run save containing acquisition state decodes")
	asserts.equal(decoded.run_state.acquisitions, run_state.acquisitions, "hydrated RunState preserves acquisition snapshot")

	var restored := _runtime(1, Vector2i(4, 2))
	asserts.true_value(restored.inventory.add_item("filler", 1).ok, "restored inventory mirrors saved capacity")
	asserts.true_value(restored.service.load_snapshot(decoded.run_state.acquisitions).ok, "acquisition snapshot reloads into fresh runtime")
	asserts.true_value(restored.service.gatherable_for("clay_save").depleted, "depletion survives save round-trip")
	asserts.equal(restored.service.pickup_for(gathered.pickup_id).item_id, "clay", "remaining pickup survives save round-trip")
	asserts.true_value(restored.world.get_interactables(_position(restored.service.pickup_for(gathered.pickup_id).position)).has(gathered.pickup_id), "restored pickup is reserved through WorldData")
	asserts.equal(RunState.new().acquisitions, {}, "new run starts without prior gatherable or pickup state")

func _assert_invalid_definitions_are_atomic(asserts) -> void:
	var inventory := _inventory(2)
	var before := inventory.to_snapshot()
	var service := AcquisitionService.new()
	var result: Dictionary = service.configure(inventory, WorldData.new(2, 2), [
		{"id": "bad_resource", "item_id": "unconfirmed_production_id", "quantity": 1, "policy": "direct"}
	], [])
	asserts.false_value(result.ok, "unknown content id is rejected during definition configuration")
	asserts.equal(result.reason, "unknown_item", "unknown content id reports stable reason")
	asserts.equal(inventory.to_snapshot(), before, "invalid definition does not mutate inventory")

func _assert_generated_resource_reservation_can_be_adopted(asserts) -> void:
	var runtime := _runtime(2, Vector2i(2, 1))
	asserts.true_value(runtime.world.reserve_entity("resource_0", Vector2i.ZERO, Vector2i.ONE, true, {"resource_id": "wood"}).ok, "generator-style resource reserves WorldData first")
	var registered: Dictionary = runtime.service.register_gatherable("resource_0", "fixture_tree_common", Vector2i.ZERO)
	asserts.true_value(registered.ok, "acquisition adopts matching generated resource reservation")
	asserts.true_value(runtime.service.gather("resource_0").ok, "adopted generated resource gathers normally")
	asserts.equal(runtime.inventory.get_total_quantity("wood"), 1, "adopted resource grants stable item id")

func _assert_gatherable_can_require_a_tool_and_clear_terrain(asserts) -> void:
	var runtime := _runtime(3, Vector2i(2, 1))
	runtime.world.set_terrain(Vector2i.ZERO, "common_forest", false, "terrain_tree_broadleaf_32x32")
	asserts.true_value(runtime.service.register_gatherable("terrain_tree_0_0", "fixture_tree_requires_axe", Vector2i.ZERO).ok, "tool-gated tree registers")
	var missing_tool: Dictionary = runtime.service.gather("terrain_tree_0_0")
	asserts.false_value(missing_tool.ok, "tree harvest is rejected without the required axe")
	asserts.equal(missing_tool.reason, "missing_required_tool", "missing axe reports a stable reason")
	asserts.false_value(runtime.world.is_walkable(Vector2i.ZERO), "failed tree harvest keeps the blocking tree terrain")
	asserts.true_value(runtime.inventory.add_item("stone_axe", 1).ok, "fixture creates required axe")
	var harvested: Dictionary = runtime.service.gather("terrain_tree_0_0")
	asserts.true_value(harvested.ok, "tree harvest succeeds once the axe exists")
	asserts.equal(harvested.required_tool_item_id, "stone_axe", "harvest result records the required tool")
	asserts.equal(runtime.inventory.get_total_quantity("wood"), 1, "tree harvest grants wood")
	asserts.true_value(runtime.world.is_walkable(Vector2i.ZERO), "successful tree harvest clears the blocking tree terrain")

func _assert_interaction_kind_alone_cannot_be_adopted(asserts) -> void:
	var runtime := _runtime(2, Vector2i(2, 1))
	asserts.true_value(runtime.world.reserve_entity("resource_kind_only", Vector2i.ZERO, Vector2i.ONE, true, {"interaction_kind": "gatherable"}).ok, "kind-only fixture reserves the cell")
	var registered: Dictionary = runtime.service.register_gatherable("resource_kind_only", "fixture_tree_common", Vector2i.ZERO)
	asserts.false_value(registered.ok, "interaction kind alone cannot adopt a resource reservation")
	asserts.equal(registered.reason, "world_owner_already_reserved", "kind-only reservation retains the world failure reason")

func _assert_failed_snapshot_restore_is_atomic(asserts) -> void:
	var runtime := _runtime(3, Vector2i(3, 1))
	asserts.true_value(runtime.service.register_gatherable("tree_existing", "fixture_tree_common", Vector2i.ZERO).ok, "atomic fixture registers prior gatherable")
	asserts.true_value(runtime.world.reserve_entity("unrelated_blocker", Vector2i(2, 0)).ok, "atomic fixture reserves unrelated world state")
	var service_before: Dictionary = runtime.service.to_snapshot()
	var world_before: Dictionary = runtime.world.to_dictionary()
	var failed: Dictionary = runtime.service.load_snapshot({
		"schema_version": AcquisitionService.SNAPSHOT_SCHEMA_VERSION,
		"next_pickup_id": 2,
		"gatherables": [],
		"pickups": [{
			"pickup_id": "pickup_000001",
			"item_id": "wood",
			"quantity": 1,
			"position": {"x": 2, "y": 0},
			"source": {}
		}],
		"processed_drop_request_ids": []
	})
	asserts.false_value(failed.ok, "snapshot restore rejects a conflicting reservation")
	asserts.equal(runtime.service.to_snapshot(), service_before, "failed snapshot restore preserves prior service state")
	asserts.equal(runtime.world.to_dictionary(), world_before, "failed snapshot restore preserves prior world state")

func _assert_multi_grant_drop_rolls_back_on_world_failure(asserts) -> void:
	var runtime := _runtime(2, Vector2i(1, 1))
	asserts.true_value(runtime.world.reserve_entity("blocker", Vector2i.ZERO).ok, "drop rollback fixture blocks all pickup positions")
	var before: Dictionary = runtime.inventory.to_snapshot()
	var failed: Dictionary = runtime.service.process_drop_request({
		"type": "monster_drop_requested",
		"combat_id": "combat_multi_01",
		"definition_id": "multi_drop"
	}, Vector2i.ZERO)
	asserts.false_value(failed.ok, "later pickup placement failure rejects multi-grant drop")
	asserts.equal(failed.reason, "no_pickup_space", "world placement failure has stable reason")
	asserts.equal(runtime.inventory.to_snapshot(), before, "failed multi-grant drop rolls back earlier direct grants")
	asserts.equal(runtime.service.to_snapshot().pickups, [], "failed multi-grant drop rolls back spawned pickups")

func _runtime(slot_count: int, world_size: Vector2i) -> Dictionary:
	var inventory := _inventory(slot_count)
	var world := WorldData.new(world_size.x, world_size.y, "grass", true)
	var service := AcquisitionService.new()
	var configured: Dictionary = service.configure(inventory, world, _gatherable_definitions(), _drop_definitions())
	if not configured.ok:
		push_error(configured.error)
	return {"inventory": inventory, "world": world, "service": service}

func _inventory(slot_count: int) -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new(slot_count))
	return result.inventory

func _gatherable_definitions() -> Array:
	return [
		{"id": "fixture_tree_common", "item_id": "wood", "quantity": 1, "policy": "direct"},
		{"id": "fixture_tree_requires_axe", "item_id": "wood", "quantity": 1, "policy": "direct", "required_tool_item_id": "stone_axe", "depleted_terrain": {"id": "common_grass", "render_id": "terrain_plains_grass_ground_01", "walkable": true}},
		{"id": "fixture_ore_mountain", "item_id": "fixture_ore_item", "quantity": 1, "policy": "direct"},
		{"id": "fixture_clay_common", "item_id": "clay", "quantity": 1, "policy": "pickup"},
		{"id": "fixture_tea_leaf_common", "item_id": "fixture_tea_leaf_item", "quantity": 1, "policy": "direct"}
	]

func _drop_definitions() -> Array:
	return [
		{"monster_id": "road_bandit", "grants": [
			{"item_id": "clay", "quantity": 1, "policy": "pickup"}
		]},
		{"monster_id": "multi_drop", "grants": [
			{"item_id": "wood", "quantity": 1, "policy": "direct"},
			{"item_id": "clay", "quantity": 1, "policy": "pickup"}
		]}
	]

func _position(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.x), int(data.y))
