extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const FacilityBiomeCoordinator = preload("res://src/main/facility_biome_coordinator.gd")
const FacilityPlacementSession = preload("res://src/main/facility_placement_session.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")

class ProgressionStub:
	extends RefCounted

	var applied_commands := []

	func to_projection() -> Dictionary:
		return {"biome_order": ["common_region", "mountain_region", "snowfield"]}

	func teleport_state_for(_biome_id: String) -> String:
		return BiomeProgressionState.TELEPORT_REPAIRED

	func apply_command(command) -> Dictionary:
		applied_commands.append(command)
		return {"ok": true}

class CraftingStub:
	extends RefCounted

	func recipe_for(recipe_id: String) -> Dictionary:
		return {"id": recipe_id, "result_item_id": "tea_bowl"}

	func is_facility_item(_item_id: String) -> bool:
		return false

	func craft(recipe_id: String, _inventory, _context: Dictionary, _options := {}) -> Dictionary:
		return {"ok": true, "recipe_id": recipe_id, "result_item_id": "tea_bowl", "result_quantity": 1}

class HudStub:
	extends RefCounted

	var feedback := []
	var events := []

	func show_command_feedback(message: String) -> void:
		feedback.append(message)

	func show_status_event(event: Dictionary) -> void:
		events.append(event.duplicate(true))

var run_state: RunState
var progression_state := ProgressionStub.new()
var hud := HudStub.new()
var calls := []

func run(asserts) -> void:
	_assert_connected_biome_requires_repaired_current_gate(asserts)
	_assert_craft_command_syncs_saves_and_reports_event(asserts)

func _assert_connected_biome_requires_repaired_current_gate(asserts) -> void:
	_reset_state()
	run_state.teleport_states["common_region"] = BiomeProgressionState.TELEPORT_REPAIRED
	var coordinator := _coordinator()

	asserts.true_value(coordinator.is_connected_biome("common_region", "mountain_region"), "repaired current biome opens the next biome")
	asserts.false_value(coordinator.is_connected_biome("common_region", "snowfield"), "non-adjacent biome remains locked")

	run_state.teleport_states["common_region"] = BiomeProgressionState.TELEPORT_REPAIRABLE
	asserts.false_value(coordinator.is_connected_biome("common_region", "mountain_region"), "unrepaired current biome cannot travel")

func _assert_craft_command_syncs_saves_and_reports_event(asserts) -> void:
	_reset_state()
	var coordinator := _coordinator()
	var accepted := coordinator.handle_craft_recipe_command(GameCommand.new(GameCommand.Type.CRAFT_RECIPE, Vector2i.ZERO, -1, {"recipe_id": "tea_bowl_recipe"}))

	asserts.true_value(accepted, "non-facility crafting remains accepted")
	asserts.equal(calls, ["sync", "save", "hud"], "craft command preserves sync, save, HUD refresh order")
	asserts.equal(hud.feedback, ["제작 완료: tea_bowl"], "craft command keeps existing feedback text")
	asserts.equal(hud.events[0].type, "craft_completed", "craft command emits completion status event")

func _coordinator() -> FacilityBiomeCoordinator:
	var ports := FacilityBiomeCoordinator.Ports.new()
	ports.is_in_dungeon_map = func(): return false
	ports.get_dungeon_runtime = func(): return null
	ports.combat_targets = func(): return []
	ports.dungeon_boss_combat_available = func(): return false
	ports.return_from_dungeon_map = func(): calls.append("return")
	ports.save_current_run = func():
		calls.append("save")
		return {"ok": true}
	ports.configure_game_hud = func(): calls.append("hud")
	ports.get_game_hud = func(): return hud
	ports.get_run_state = func(): return run_state
	ports.set_run_state = func(value): run_state = value
	ports.is_core_dungeon_target = func(_target_id): return false
	ports.handle_complete_dungeon_command = func(_command): return true
	ports.ensure_biome_progression_state = func(): return {"ok": true}
	ports.get_biome_progression_state = func(): return progression_state
	ports.set_biome_progression_state = func(value): progression_state = value
	ports.get_generated_world = func(): return {"biome_id": "common_region"}
	ports.set_generated_world = func(_value): pass
	ports.store_current_biome_runtime_aliases = func(_biome_id := ""): calls.append("store")
	ports.restore_run_state_from_snapshot = func(_snapshot): pass
	ports.configure_world_for_current_run = func(): return {"ok": true}
	ports.create_loading_overlay = func(): pass
	ports.set_loading_status = func(_message): pass
	ports.clear_loading_overlay = func(): pass
	ports.loading_biome_label = func(): return "테스트"
	ports.debug = func(_message): pass
	ports.get_crafting_service = func(): return CraftingStub.new()
	ports.get_inventory = func(): return {}
	ports.get_facility_placement_service = func(): return null
	ports.get_world_data = func(): return null
	ports.get_player = func(): return null
	ports.player_world_cell = func(): return Vector2i.ZERO
	ports.player_facility_metadata = func(_facility_item_id): return {}
	ports.crafting_context = func(): return {}
	ports.clear_pointer_movement = func(): pass
	ports.clear_facility_placement_preview = func(): pass
	ports.update_facility_placement_preview = func(_validation): pass
	ports.sync_runtime_world_render = func(): pass
	ports.sync_run_runtime_state = func(): calls.append("sync")
	ports.advance_time_for_turn = func(): calls.append("time")
	ports.play_feedback_beep = func(): calls.append("beep")
	ports.queue_enemy_turn_after_player_action = func(): calls.append("enemy")
	ports.content_image_asset_id = func(_dataset, _content_id): return ""
	ports.get_start_mode = func(): return "resume"
	ports.get_catalog = func(): return null
	return FacilityBiomeCoordinator.new(FacilityPlacementSession.new(), ports)

func _reset_state() -> void:
	run_state = RunState.new()
	run_state.current_biome_id = "common_region"
	progression_state = ProgressionStub.new()
	hud = HudStub.new()
	calls = []
