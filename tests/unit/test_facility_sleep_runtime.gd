extends RefCounted

const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const TimeConfig = preload("res://src/time/time_config.gd")
const TimeState = preload("res://src/time/time_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class TestPlayer:
	extends Node2D

	var resources

class TestSaveStore:
	extends RefCounted

	func save_run(_state) -> Dictionary:
		return {"ok": true}

func run(asserts) -> void:
	_assert_sleep_interaction_tile_uses_facility_definition(asserts)
	_assert_sleep_command_accepts_adjacent_tiles(asserts)

func _assert_sleep_interaction_tile_uses_facility_definition(asserts) -> void:
	var placement := FacilityPlacementService.new()
	asserts.true_value(placement.configure(_item_definitions()).ok, "sleep facility placement configures")
	var world := WorldData.new(7, 7, "grass", true)
	asserts.true_value(placement.place_facility("portable_brazier", world, Vector2i(3, 3)).ok, "sleep facility installs")
	var reservation: Dictionary = world.to_dictionary().get("reservations", [])[0]
	asserts.equal(reservation.metadata.get("facility_name"), "휴대 화로", "placed facility exposes its display name to shared presentation")
	asserts.equal(reservation.metadata.get("facility_capabilities"), ["sleep"], "placed facility exposes reusable interaction capabilities")

	var front := placement.facility_interaction_at(world, Vector2i(3, 4), "sleep")
	asserts.true_value(front.ok, "sleep facility accepts its defined south-front tile")
	asserts.equal(front.facility_item_id, "portable_brazier", "sleep interaction reports the facility item id")
	asserts.equal(front.interaction_cell, {"x": 3, "y": 4}, "sleep interaction reports the exact interaction cell")
	asserts.true_value(placement.facility_interaction_at(world, Vector2i(4, 3), "sleep").ok, "sleep facility accepts side tiles")
	asserts.true_value(placement.facility_interaction_at(world, Vector2i(3, 2), "sleep").ok, "sleep facility accepts back tiles")

	var rotated_world := WorldData.new(7, 7, "grass", true)
	asserts.true_value(placement.place_facility("portable_brazier", rotated_world, Vector2i(3, 3), {"rotation_quarter_turns": 1}).ok, "rotated sleep facility installs")
	asserts.true_value(placement.facility_interaction_at(rotated_world, Vector2i(2, 3), "sleep").ok, "rotation turns the front interaction tile with the facility")
	asserts.true_value(placement.facility_interaction_at(rotated_world, Vector2i(3, 4), "sleep").ok, "rotated facility still accepts another adjacent tile")

	var workbench_world := WorldData.new(7, 7, "grass", true)
	asserts.true_value(placement.place_facility("wooden_workbench", workbench_world, Vector2i(3, 3)).ok, "non-sleep facility installs")
	asserts.false_value(placement.facility_interaction_at(workbench_world, Vector2i(3, 4), "sleep").ok, "non-sleep facility does not satisfy sleep capability")

	var blocked_world := WorldData.new(7, 7, "grass", true)
	asserts.true_value(placement.place_facility("portable_brazier", blocked_world, Vector2i(3, 3)).ok, "blocked-front sleep facility installs")
	asserts.true_value(blocked_world.reserve_entity("front_blocker", Vector2i(3, 4)).ok, "front blocker occupies the interaction tile")
	var blocked := placement.facility_interaction_at(blocked_world, Vector2i(3, 4), "sleep")
	asserts.false_value(blocked.ok, "blocked front tile rejects sleep interaction")
	asserts.equal(blocked.reason, "interaction_tile_blocked", "blocked front tile reports a stable reason")

func _assert_sleep_command_accepts_adjacent_tiles(asserts) -> void:
	_assert_sleep_command_rejects_cell(asserts, {}, Vector2i(3, 4), "sleep command rejects no facility")
	_assert_sleep_command_rejects_cell(asserts, {"facility_item_id": "wooden_workbench", "origin": Vector2i(3, 3)}, Vector2i(3, 4), "sleep command rejects non-sleep facility")
	_assert_sleep_command_rejects_cell(asserts, {"facility_item_id": "portable_brazier", "origin": Vector2i(3, 3)}, Vector2i(6, 6), "sleep command rejects distant tile")
	_assert_sleep_command_rejects_cell(asserts, {"facility_item_id": "portable_brazier", "origin": Vector2i(3, 3), "block_front": true}, Vector2i(3, 4), "sleep command rejects blocked front tile")
	_assert_sleep_command_accepts_cell(asserts, Vector2i(4, 3), "sleep command accepts side tile")
	_assert_sleep_command_accepts_cell(asserts, Vector2i(3, 2), "sleep command accepts back tile")

	_assert_sleep_command_accepts_cell(asserts, Vector2i(3, 4), "sleep command accepts defined front tile")

func _assert_sleep_command_accepts_cell(asserts, player_cell: Vector2i, message: String) -> void:
	var runtime := _runtime_with_world()
	asserts.true_value(runtime.facility_placement_service.place_facility("portable_brazier", runtime.world_data, Vector2i(3, 3)).ok, "%s fixture installs" % message)
	runtime.player.global_position = runtime.world_position_for_cell_center(player_cell)
	var phase_changes := []
	runtime.time_state.phase_changed.connect(func(previous, current): phase_changes.append({"previous": previous, "current": current}))
	var accepted := runtime.submit_action_command(GameCommand.new(GameCommand.Type.SLEEP))
	asserts.true_value(accepted, message)
	asserts.equal(String(runtime.time_state.phase), "day", "sleep command advances time to morning")
	asserts.equal(runtime.time_state.phase_elapsed_seconds, 0.0, "sleep command resets phase elapsed time")
	asserts.equal(runtime.player.resources.kokoro, runtime.player.resources.kokoro_max, "sleep command restores kokoro")
	asserts.equal(runtime.player.resources.hp, 70, "sleep command heals HP by configured ratio without exceeding max")
	asserts.equal(phase_changes.size(), 1, "one sleep command invokes the sleep transition once")
	runtime.player.free()
	runtime.free()

func _assert_sleep_command_rejects_cell(asserts, setup: Dictionary, player_cell: Vector2i, message: String) -> void:
	var runtime := _runtime_with_world()
	var facility_item_id := String(setup.get("facility_item_id", ""))
	if not facility_item_id.is_empty():
		asserts.true_value(runtime.facility_placement_service.place_facility(facility_item_id, runtime.world_data, setup.origin).ok, "%s fixture facility installs" % message)
	if bool(setup.get("block_front", false)):
		asserts.true_value(runtime.world_data.reserve_entity("front_blocker", Vector2i(3, 4)).ok, "%s fixture front blocker installs" % message)
	runtime.player.global_position = runtime.world_position_for_cell_center(player_cell)
	var snapshot := _sleep_state_snapshot(runtime)
	asserts.false_value(runtime.submit_action_command(GameCommand.new(GameCommand.Type.SLEEP)), message)
	asserts.equal(_sleep_state_snapshot(runtime), snapshot, "%s leaves time/resources unchanged" % message)
	runtime.player.free()
	runtime.free()

func _runtime_with_world() -> Main:
	var runtime := Main.new()
	var placement := FacilityPlacementService.new()
	placement.configure(_item_definitions())
	runtime.facility_placement_service = placement
	runtime.world_data = WorldData.new(7, 7, "grass", true)
	runtime.run_state = RunState.new()
	runtime.generated_world = {
		"biome_id": "common_region",
		"renderer_input": {"bounds": {"width": 7, "height": 7}, "tile_size": 32}
	}
	var player := TestPlayer.new()
	player.resources = PlayerResources.new(100, 100, 100, 30)
	player.resources.apply_damage(50)
	player.resources.reduce_kokoro(40)
	runtime.player = player
	runtime.save_store = TestSaveStore.new()
	runtime.time_state = TimeState.new(_test_time_config())
	runtime.time_state.phase = TimeState.NIGHT
	runtime.time_state.phase_elapsed_seconds = 5.0
	return runtime

func _sleep_state_snapshot(runtime: Main) -> Dictionary:
	return {
		"phase": String(runtime.time_state.phase),
		"phase_elapsed_seconds": runtime.time_state.phase_elapsed_seconds,
		"resources": runtime.player.resources.to_dictionary()
	}

func _test_time_config() -> TimeConfig:
	return TimeConfig.new({
		"day_phase_duration_seconds": 10.0,
		"dusk_phase_duration_seconds": 10.0,
		"night_phase_duration_seconds": 10.0,
		"late_night_phase_duration_seconds": 10.0,
		"dusk_kokoro_decay_per_second": 0.1,
		"night_kokoro_decay_per_second": 0.2,
		"late_night_kokoro_decay_per_second": 0.3,
		"low_kokoro_ability_cost_increase_percent": 25.0,
		"sleep_heal_ratio": 0.2
	})

func _item_definitions() -> Dictionary:
	return {
		"portable_brazier": {
			"id": "portable_brazier",
			"name": "휴대 화로",
			"type": "도구",
			"max_stack": 1,
			"footprint_size": Vector2i.ONE,
			"facility_capabilities": ["sleep"],
			"facility_interactions": {
				"sleep": {
					"front_direction": "south",
					"tile_index": 0
				}
			}
		},
		"wooden_workbench": {
			"id": "wooden_workbench",
			"name": "목재 작업대",
			"type": "도구",
			"max_stack": 1,
			"footprint_size": Vector2i.ONE
		}
	}
