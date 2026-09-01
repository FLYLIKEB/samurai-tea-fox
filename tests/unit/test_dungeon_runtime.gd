extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class IncompleteProgressionBoundary:
	extends RefCounted

	func complete_dungeon(_biome_id: String) -> Dictionary:
		return {"ok": true}

func run(asserts) -> void:
	_lifecycle_clear_and_duplicate_guards(asserts)
	_save_round_trip_resumes_active_instance(asserts)
	_invalid_saved_return_context_is_rejected(asserts)
	_invalid_entry_boundaries(asserts)
	_incomplete_progression_boundary_is_rejected(asserts)

func _lifecycle_clear_and_duplicate_guards(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	var run_state: RunState = context.run_state
	var reward_calls := {"count": 0}
	var clear_events := []
	runtime.dungeon_cleared.connect(func(event: Dictionary) -> void: clear_events.append(event))
	asserts.true_value(runtime.configure(
		run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)),
		func(_event: Dictionary) -> Dictionary:
			reward_calls.count += 1
			return {"ok": true}
	).ok, "dungeon runtime configures with injected boundaries")

	var world := WorldData.new(3, 3, "fixture_floor", true)
	var entered := runtime.enter_dungeon("fixture_instance_1", _fixture_definition(), world, _return_context())
	asserts.true_value(entered.ok, "dungeon entry accepts injected WorldData")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_ACTIVE, "entry reaches active state")
	asserts.equal(runtime.to_projection().world_data.bounds, {"width": 3, "height": 3}, "runtime stores fixed layout snapshot")
	world.setup(1, 1, "mutated", true)
	asserts.equal(runtime.to_projection().world_data.bounds, {"width": 3, "height": 3}, "layout snapshot is detached from injected WorldData")

	var early_return := runtime.begin_return()
	asserts.false_value(early_return.ok, "return before completion is rejected")
	asserts.equal(early_return.reason, "invalid_return_transition", "early return exposes stable reason")
	var rejected := runtime.complete_dungeon({"objective_complete": false})
	asserts.false_value(rejected.ok, "resolver can reject incomplete objective")
	asserts.equal(rejected.reason, "completion_condition_not_met", "resolver rejection exposes stable reason")

	var completed := runtime.complete_dungeon({
		"objective_complete": true,
		"resolution_type": "tea_ceremony",
		"choice_key": "FIXTURE_CHOICE",
		"run_flag": "fixture_flag",
		"reward_item_ids": ["fixture_reward"],
		"progression_unlock_ids": ["common_region"]
	})
	asserts.true_value(completed.ok, "valid objective completes dungeon")
	asserts.equal(completed.clear_event.event_type, DungeonRuntime.CLEAR_EVENT_TYPE, "completion emits common clear event type")
	asserts.equal(completed.clear_event.dungeon_id, "fixture_dungeon", "clear event uses stable dungeon id")
	asserts.equal(clear_events.size(), 1, "clear signal emits exactly once")
	asserts.equal(reward_calls.count, 1, "reward hook runs exactly once")
	asserts.equal(run_state.completed_runtime_dungeon_ids, ["fixture_dungeon"], "canonical dungeon completion is recorded")
	asserts.equal(run_state.completed_dungeon_ids, ["common_region"], "clear event crosses biome progression boundary")
	asserts.equal(context.progression.teleport_state_for("common_region"), BiomeProgressionState.TELEPORT_REPAIRABLE, "clear makes biome teleport repairable")

	var duplicate := runtime.complete_dungeon({"objective_complete": true})
	asserts.false_value(duplicate.ok, "duplicate completion is rejected")
	asserts.equal(duplicate.reason, "invalid_completion_transition", "duplicate completion cannot leave completed state")
	asserts.equal(reward_calls.count, 1, "duplicate completion does not rerun reward hook")
	asserts.equal(clear_events.size(), 1, "duplicate completion does not re-emit clear signal")

	var returning := runtime.begin_return()
	asserts.true_value(returning.ok, "completed dungeon can begin return")
	asserts.equal(returning.return_context, _return_context(), "return exposes original world context")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_RETURNING, "return uses explicit returning state")
	asserts.true_value(runtime.finish_return().ok, "returning dungeon can finish return")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_RETURNED, "return finishes in returned state")
	var reenter := runtime.enter_dungeon("fixture_instance_2", _fixture_definition(), WorldData.new(2, 2), _return_context())
	asserts.false_value(reenter.ok, "completed canonical dungeon cannot be entered for another reward")
	asserts.equal(reenter.reason, "duplicate_dungeon_completion", "canonical duplicate exposes stable reason")

func _save_round_trip_resumes_active_instance(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	asserts.true_value(runtime.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "save fixture runtime configures")
	asserts.true_value(runtime.enter_dungeon("fixture_saved_instance", _fixture_definition(), WorldData.new(4, 2), _return_context()).ok, "active save fixture enters")

	var encoded := SaveCodec.encode_run(context.run_state.to_dictionary())
	var decoded := SaveCodec.decode_run(encoded)
	asserts.true_value(decoded.ok, "run save with dungeon state decodes")
	asserts.equal(decoded.run_state.dungeon_runtime_state.lifecycle_state, DungeonInstanceState.STATE_ACTIVE, "run save preserves active lifecycle")
	encoded.run.dungeon_runtime_state.return_context.biome_id = "mutated"
	asserts.equal(decoded.run_state.dungeon_runtime_state.return_context.biome_id, "common_region", "decoded dungeon state is detached from save payload")

	var resumed_progression := BiomeProgressionState.new()
	asserts.true_value(resumed_progression.configure(_fixture_biomes(), decoded.run_state).ok, "decoded run resumes biome progression")
	var resumed := DungeonRuntime.new()
	asserts.true_value(resumed.configure(
		decoded.run_state,
		resumed_progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "decoded run resumes dungeon runtime")
	asserts.equal(resumed.to_projection().instance_id, "fixture_saved_instance", "resumed runtime preserves instance identity")
	asserts.equal(resumed.to_projection().world_data.bounds, {"width": 4, "height": 2}, "resumed runtime preserves fixed layout")

func _invalid_saved_return_context_is_rejected(asserts) -> void:
	var mismatched_context := _runtime_context()
	mismatched_context.run_state.dungeon_runtime_state = _saved_instance({"biome_id": "mountain_region", "world_seed": 11037})
	var mismatched_result: Dictionary = mismatched_context.runtime.configure(
		mismatched_context.run_state,
		mismatched_context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.false_value(mismatched_result.ok, "saved return context rejects a mismatched biome")
	asserts.equal(mismatched_result.reason, "invalid_saved_dungeon_state", "saved biome mismatch exposes stable reason")

	var malformed_context := _runtime_context()
	malformed_context.run_state.dungeon_runtime_state = _saved_instance({"biome_id": "common_region", "world_seed": null})
	var malformed_result: Dictionary = malformed_context.runtime.configure(
		malformed_context.run_state,
		malformed_context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.false_value(malformed_result.ok, "saved return context rejects malformed world identity")
	asserts.equal(malformed_result.reason, "invalid_saved_dungeon_state", "saved world identity failure exposes stable reason")

	var stale_biome_context := _runtime_context()
	stale_biome_context.run_state.dungeon_runtime_state = _saved_instance({"biome_id": "mountain_region", "world_seed": 11037})
	stale_biome_context.run_state.dungeon_runtime_state.biome_id = "mountain_region"
	var stale_biome_result: Dictionary = stale_biome_context.runtime.configure(
		stale_biome_context.run_state,
		stale_biome_context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.false_value(stale_biome_result.ok, "saved active dungeon rejects a stale progression biome")
	asserts.equal(stale_biome_result.reason, "invalid_saved_dungeon_state", "saved progression mismatch exposes stable reason")

func _invalid_entry_boundaries(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	asserts.true_value(runtime.configure(
		context.run_state,
		context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	).ok, "invalid entry fixture configures")
	asserts.equal(runtime.enter_dungeon("", _fixture_definition(), WorldData.new(2, 2), _return_context()).reason, "missing_stable_id", "entry rejects missing instance id")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), null, _return_context()).reason, "invalid_world_data", "entry rejects missing layout")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region"}).reason, "invalid_return_context", "entry rejects missing world identity")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "mountain_region", "world_seed": 11037}).reason, "invalid_return_context", "entry rejects return context for another biome")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_id": null}).reason, "invalid_return_context", "entry rejects null world identity")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_id": {"id": "not_stable"}}).reason, "invalid_return_context", "entry rejects malformed world id")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_id": "   "}).reason, "invalid_return_context", "entry rejects blank world id")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_seed": null}).reason, "invalid_return_context", "entry rejects null world seed")
	asserts.equal(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_seed": 11037.5}).reason, "invalid_return_context", "entry rejects a fractional numeric world seed")
	var wrong_biome := _fixture_definition()
	wrong_biome.biome_id = "mountain_region"
	asserts.equal(runtime.enter_dungeon("fixture_instance", wrong_biome, WorldData.new(2, 2), _return_context()).reason, "invalid_biome", "entry rejects non-current biome")
	asserts.true_value(runtime.enter_dungeon("fixture_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_id": "stable_world"}).ok, "entry accepts a non-empty stable world id")

	var string_seed_context := _runtime_context()
	asserts.true_value(string_seed_context.runtime.configure(
		string_seed_context.run_state,
		string_seed_context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	).ok, "string seed fixture configures")
	asserts.true_value(string_seed_context.runtime.enter_dungeon("string_seed_instance", _fixture_definition(), WorldData.new(2, 2), {"biome_id": "common_region", "world_seed": "11037"}).ok, "entry accepts a non-empty string world seed")

func _incomplete_progression_boundary_is_rejected(asserts) -> void:
	var runtime := DungeonRuntime.new()
	var result := runtime.configure(
		RunState.new(),
		IncompleteProgressionBoundary.new(),
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.false_value(result.ok, "configure rejects an incomplete progression boundary")
	asserts.equal(result.reason, "invalid_progression_state", "incomplete progression boundary exposes stable reason")

func _runtime_context() -> Dictionary:
	var run_state := RunState.new()
	var progression := BiomeProgressionState.new()
	progression.configure(_fixture_biomes(), run_state)
	return {"run_state": run_state, "progression": progression, "runtime": DungeonRuntime.new()}

func _fixture_definition() -> Dictionary:
	return {"id": "fixture_dungeon", "biome_id": "common_region"}

func _return_context() -> Dictionary:
	return {"biome_id": "common_region", "world_seed": 11037, "landmark_id": "fixture_entry"}

func _saved_instance(return_context: Dictionary) -> Dictionary:
	return {
		"schema_version": 1,
		"instance_id": "saved_instance",
		"dungeon_id": "fixture_dungeon",
		"biome_id": "common_region",
		"lifecycle_state": DungeonInstanceState.STATE_ACTIVE,
		"world_data": WorldData.new(2, 2).to_dictionary(),
		"return_context": return_context
	}

func _fixture_biomes() -> Array:
	return [
		{"id": "common_region", "progression_order": 1},
		{"id": "mountain_region", "progression_order": 2}
	]
