extends RefCounted
class_name PlayerRuntimeCoordinator

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const RunState = preload("res://src/save/run_state.gd")

class Ports:
	var get_player: Callable
	var get_inventory: Callable
	var get_equipment: Callable
	var get_game_hud: Callable
	var get_tea_service: Callable
	var get_consumable_service: Callable
	var get_time_state: Callable
	var get_facility_placement_service: Callable
	var get_world_data: Callable
	var get_run_state: Callable
	var set_run_state: Callable
	var get_save_store: Callable
	var get_inventory_command_runtime: Callable
	var get_tea_brewing_command_runtime: Callable
	var get_meta_codex_command_runtime: Callable
	var get_map_read_model_builder: Callable
	var get_memory_tea_cutscene_runtime: Callable
	var get_generated_world: Callable
	var get_run_runtime_state_binder: Callable
	var get_acquisition_service: Callable
	var get_in_dungeon_map: Callable
	var world_cell_from_world_position: Callable
	var save_current_run: Callable
	var configure_game_hud: Callable
	var start_consumable_use: Callable
	var sync_runtime_state: Callable
	var store_current_biome_runtime_aliases: Callable
	var available_facility_item_ids: Callable
	var unlocked_biome_ids: Callable

var _ports: Ports
var _player_item_actions
var _narrative_session
var _run_state_snapshot_coordinator

func _init(ports: Ports, player_item_actions, narrative_session, run_state_snapshot_coordinator) -> void:
	_ports = ports
	_player_item_actions = player_item_actions
	_narrative_session = narrative_session
	_run_state_snapshot_coordinator = run_state_snapshot_coordinator

func handle_tea_command(command: GameCommand) -> bool:
	var player = _call_value(_ports.get_player)
	return _player_item_actions.start_tea(command, _call_value(_ports.get_tea_service), player.get("resources") if player != null else null)

func is_tea_drink_active() -> bool:
	return _player_item_actions.is_tea_drink_active()

func tick_tea_runtime(delta_seconds: float) -> Dictionary:
	var player = _call_value(_ports.get_player)
	return _player_item_actions.tick_tea(delta_seconds, _call_value(_ports.get_tea_service), player.get("resources") if player != null else null)

func is_consumable_use_active() -> bool:
	return _player_item_actions.is_consumable_use_active(_call_value(_ports.get_consumable_service))

func tick_consumable_runtime(delta_seconds: float) -> Dictionary:
	var player = _call_value(_ports.get_player)
	return _player_item_actions.tick_consumable(
		delta_seconds,
		_call_value(_ports.get_consumable_service),
		_call_value(_ports.get_inventory),
		player.get("resources") if player != null else null
	)

func interrupt_consumable_use(reason := "hit") -> Dictionary:
	return _player_item_actions.interrupt_consumable(_call_value(_ports.get_consumable_service), reason)

func handle_consumable_command(command: GameCommand) -> bool:
	var consumable_service = _call_value(_ports.get_consumable_service)
	var inventory = _call_value(_ports.get_inventory)
	var player = _call_value(_ports.get_player)
	if consumable_service == null or inventory == null or player == null or player.resources == null:
		return false
	var item_id := consumable_item_id_for_command(command)
	if item_id.is_empty():
		return false
	var start: Dictionary = start_consumable_use(item_id, {"command_slot": command.slot, "source": "quickslot"})
	var game_hud = _call_value(_ports.get_game_hud)
	if game_hud != null:
		game_hud.show_command_feedback(
			"소모품 사용 중: %s" % item_id
			if start.ok
			else "소모품 실패: %s" % String(start.get("reason", "unknown"))
		)
	return bool(start.ok)

func start_consumable_use(item_id: String, context := {}) -> Dictionary:
	return _player_item_actions.start_consumable(item_id, context, _call_value(_ports.get_consumable_service), _call_value(_ports.get_inventory))

func consumable_item_id_for_command(command: GameCommand) -> String:
	return _player_item_actions.consumable_item_id_for_command(command, _call_value(_ports.get_consumable_service), _call_value(_ports.get_inventory))

func handle_sleep_command() -> bool:
	var time_state = _call_value(_ports.get_time_state)
	var player = _call_value(_ports.get_player)
	if time_state == null or player == null or player.resources == null:
		return false
	var facility_result := sleep_facility_interaction_at_player()
	var game_hud = _call_value(_ports.get_game_hud)
	if not facility_result.ok:
		if game_hud != null:
			game_hud.show_command_feedback(sleep_facility_failure_message(String(facility_result.get("reason", "sleep_facility_unavailable"))))
		return false
	var result: Dictionary = time_state.sleep_until_morning(player.resources)
	if game_hud != null:
		game_hud.show_command_feedback("수면 완료: HP +%d / 心 +%d" % [
			int(result.get("hp_healed", 0)),
			int(result.get("kokoro_restored", 0))
		])
	_call_dictionary(_ports.save_current_run)
	_call_void(_ports.configure_game_hud)
	return true

func sleep_facility_interaction_at_player() -> Dictionary:
	var facility_placement_service = _call_value(_ports.get_facility_placement_service)
	var world_data = _call_value(_ports.get_world_data)
	if facility_placement_service == null or world_data == null:
		return {"ok": false, "reason": "missing_facility_capability"}
	return facility_placement_service.facility_interaction_at(world_data, player_world_cell(), "sleep")

func sleep_facility_failure_message(reason: String) -> String:
	match reason:
		"interaction_tile_blocked":
			return "수면 불가: 시설 앞이 막혀 있습니다."
		"facility_interaction_out_of_position":
			return "수면 불가: 시설 정면에서만 가능합니다."
		"interaction_tile_out_of_bounds":
			return "수면 불가: 시설 정면 타일이 맵 밖입니다."
		_:
			return "수면 불가: 잘 수 있는 시설이 필요합니다."

func handle_tea_brewing_command(command: GameCommand) -> bool:
	var tea_brewing_command_runtime = _call_value(_ports.get_tea_brewing_command_runtime)
	if tea_brewing_command_runtime == null:
		return false
	var result: Dictionary = tea_brewing_command_runtime.handle_command(command)
	var game_hud = _call_value(_ports.get_game_hud)
	if game_hud != null:
		game_hud.show_command_feedback(
			"차 우리기 완료"
			if result.ok and command.type == GameCommand.Type.BREW_TEA
			else "차 우리기 갱신"
			if result.ok
			else "차 우리기 실패: %s" % String(result.get("reason", "unknown"))
		)
	if not result.ok:
		return false
	_call_void(_ports.sync_runtime_state)
	if game_hud != null:
		game_hud.show_tea_brewing_menu()
	return true

func handle_meta_codex_command(command: GameCommand) -> bool:
	var meta_codex_command_runtime = _call_value(_ports.get_meta_codex_command_runtime)
	if meta_codex_command_runtime == null:
		return false
	var result: Dictionary = meta_codex_command_runtime.handle_command(command)
	var game_hud = _call_value(_ports.get_game_hud)
	if game_hud != null:
		game_hud.show_command_feedback("도감 갱신" if result.ok else "도감 실패: %s" % String(result.get("reason", "unknown")))
	if not result.ok:
		return false
	if game_hud != null:
		game_hud.show_meta_codex_menu()
	return true

func handle_inventory_command(command: GameCommand) -> bool:
	var inventory_command_runtime = _call_value(_ports.get_inventory_command_runtime)
	if inventory_command_runtime == null:
		return false
	var result: Dictionary = inventory_command_runtime.handle_command(command)
	var started_consumable := false
	if result.ok and command.type == GameCommand.Type.USE_INVENTORY_SLOT and result.has("use_intent"):
		var intent: Dictionary = result.get("use_intent", {})
		var start_result: Dictionary = start_consumable_use(String(intent.get("item_id", "")), {
			"inventory_slot_index": int(intent.get("inventory_slot_index", command.slot)),
			"command_slot": command.slot,
			"source": "inventory"
		})
		if not start_result.ok:
			result = start_result
		else:
			started_consumable = true
	var game_hud = _call_value(_ports.get_game_hud)
	if game_hud != null:
		game_hud.show_command_feedback(
			"인벤토리 갱신"
			if result.ok
			else "인벤토리 명령 실패: %s" % String(result.get("reason", "unknown"))
		)
	if not result.ok:
		return false
	if not started_consumable:
		_call_void(_ports.sync_runtime_state)
		if game_hud != null:
			game_hud.show_inventory_menu()
		_call_dictionary(_ports.save_current_run)
	return true

func inventory_read_model() -> Dictionary:
	var inventory_command_runtime = _call_value(_ports.get_inventory_command_runtime)
	if inventory_command_runtime == null:
		return {"ok": false, "reason": "missing_inventory_command_runtime", "error": "Inventory command runtime is not configured."}
	var model: Dictionary = inventory_command_runtime.read_model()
	model["ok"] = true
	return model

func map_read_model(options := {}) -> Dictionary:
	var map_read_model_builder = _call_value(_ports.get_map_read_model_builder)
	var world_data = _call_value(_ports.get_world_data)
	var run_state = _call_value(_ports.get_run_state)
	if map_read_model_builder == null:
		return {"ok": false, "reason": "missing_map_read_model_builder", "error": "Map read model builder is not configured."}
	if world_data == null:
		return {"ok": false, "reason": "missing_world_data", "error": "Map read model requires current world data."}
	if run_state == null:
		run_state = RunState.new()
		_call_void(_ports.set_run_state, [run_state])
	return map_read_model_builder.build(world_data, run_state, player_world_cell(), options)

func selected_inventory_slot_index() -> int:
	var inventory_command_runtime = _call_value(_ports.get_inventory_command_runtime)
	if inventory_command_runtime == null:
		return -1
	return int(inventory_command_runtime.read_model().get("selected_slot_index", -1))

func sync_run_runtime_state() -> Dictionary:
	var result: Dictionary = _run_state_snapshot_coordinator.sync_runtime_state(
		_call_value(_ports.get_run_state),
		_call_value(_ports.get_run_runtime_state_binder),
		run_runtime_state_entries()
	)
	if result.ok:
		_call_void(_ports.set_run_state, [result.run_state])
	return result

func tea_brewing_read_model() -> Dictionary:
	var tea_brewing_command_runtime = _call_value(_ports.get_tea_brewing_command_runtime)
	if tea_brewing_command_runtime == null:
		return {"ok": false, "reason": "missing_tea_brewing_command_runtime", "error": "Tea brewing command runtime is not configured."}
	var model: Dictionary = tea_brewing_command_runtime.read_model()
	model["ok"] = true
	return model

func run_runtime_state_entries() -> Array:
	return [
		{"field": "inventory", "runtime": _call_value(_ports.get_inventory)},
		{"field": "equipment", "runtime": _call_value(_ports.get_equipment)},
		{"field": "tea", "runtime": _call_value(_ports.get_tea_service)},
		{"field": "consumables", "runtime": _call_value(_ports.get_consumable_service), "clear_when_empty_key": "active_action"},
		{"field": "time", "runtime": _call_value(_ports.get_time_state)},
		{"field": "acquisitions", "runtime": _call_value(_ports.get_acquisition_service), "active": not bool(_call_value(_ports.get_in_dungeon_map, [], false))},
		{"field": "memory_tea_cutscene", "runtime": _call_value(_ports.get_memory_tea_cutscene_runtime)}
	]

func meta_codex_read_model() -> Dictionary:
	var meta_codex_command_runtime = _call_value(_ports.get_meta_codex_command_runtime)
	if meta_codex_command_runtime == null:
		return {"ok": false, "reason": "missing_meta_codex_runtime", "error": "Meta codex runtime is not configured."}
	var model: Dictionary = meta_codex_command_runtime.read_model()
	model["ok"] = true
	return model

func current_run_state_snapshot() -> Dictionary:
	var run_state = _call_value(_ports.get_run_state)
	return run_state.to_dictionary() if run_state != null else {}

func current_meta_state_snapshot() -> Dictionary:
	var save_store = _call_value(_ports.get_save_store)
	var loaded: Dictionary = save_store.load_meta() if save_store != null else {}
	if bool(loaded.get("ok", false)):
		return loaded.meta_state.to_dictionary()
	return {}

func tea_brewing_context() -> Dictionary:
	var context := crafting_context()
	context["has_brewing_location"] = has_brewing_location(context)
	return context

func has_brewing_location(context: Dictionary) -> bool:
	var facility_ids: Array = context.get("available_facility_item_ids", [])
	var explicit_ids: Array = context.get("brewing_location_ids", [])
	return not facility_ids.is_empty() or not explicit_ids.is_empty()

func player_world_cell() -> Vector2i:
	var player = _call_value(_ports.get_player)
	if player == null:
		return Vector2i.ZERO
	return _call_value(_ports.world_cell_from_world_position, [player.global_position], Vector2i.ZERO)

func record_current_map_discovery() -> void:
	var map_read_model_builder = _call_value(_ports.get_map_read_model_builder)
	var world_data = _call_value(_ports.get_world_data)
	var run_state = _call_value(_ports.get_run_state)
	if map_read_model_builder == null or world_data == null:
		return
	if run_state == null:
		run_state = RunState.new()
		_call_void(_ports.set_run_state, [run_state])
	var current_cell := player_world_cell()
	if not world_data.contains(current_cell):
		return
	run_state.map_discovery = MapReadModelBuilder.discover_cells(run_state.map_discovery, current_cell)
	_call_void(_ports.store_current_biome_runtime_aliases)

func crafting_context() -> Dictionary:
	return {
		"available_facility_item_ids": _call_array(_ports.available_facility_item_ids),
		"unlocked_biome_ids": _call_array(_ports.unlocked_biome_ids),
		"current_biome_id": String(_call_dictionary(_ports.get_generated_world).get("biome_id", ""))
	}

func on_tea_drink_completed(result: Dictionary) -> void:
	var equipment = _call_value(_ports.get_equipment)
	var inventory = _call_value(_ports.get_inventory)
	if equipment == null:
		return
	var accounting_result: Dictionary = equipment.record_tea_ware_use_completion(result, inventory)
	if not accounting_result.ok:
		push_error(accounting_result.error)
	var memory_tea_cutscene_runtime = _call_value(_ports.get_memory_tea_cutscene_runtime)
	if memory_tea_cutscene_runtime != null:
		var memory_result: Dictionary = _narrative_session.start_memory_tea_cutscene(memory_tea_cutscene_runtime, result, _call_value(_ports.get_run_state))
		if not memory_result.ok:
			push_error(memory_result.error)

func complete_memory_tea_cutscene() -> Dictionary:
	return _narrative_session.complete_memory_tea_cutscene(_call_value(_ports.get_memory_tea_cutscene_runtime), _call_value(_ports.get_run_state))

func skip_memory_tea_cutscene() -> Dictionary:
	return _narrative_session.skip_memory_tea_cutscene(_call_value(_ports.get_memory_tea_cutscene_runtime), _call_value(_ports.get_run_state))

func _call_value(callback: Callable, arguments := [], default_value = null):
	if not callback.is_valid():
		return default_value
	return callback.callv(arguments)

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	var value = _call_value(callback, arguments, {})
	return value if value is Dictionary else {}

func _call_array(callback: Callable, arguments := []) -> Array:
	var value = _call_value(callback, arguments, [])
	return value if value is Array else []

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)
