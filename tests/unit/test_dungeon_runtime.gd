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
	_reward_failure_keeps_dungeon_retryable(asserts)
	_progression_failure_does_not_grant_reward(asserts)
	_boss_precombat_gate_blocks_resolution_until_dialogue_complete(asserts)
	_boss_gate_save_round_trip_preserves_pending_active_and_combat(asserts)
	_invalid_saved_boss_gate_is_rejected(asserts)

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

func _reward_failure_keeps_dungeon_retryable(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	var reward_calls := {"attempts": 0, "grants": 0}
	var clear_events := []
	runtime.dungeon_cleared.connect(func(event: Dictionary) -> void: clear_events.append(event))
	asserts.true_value(runtime.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)),
		func(_event: Dictionary) -> Dictionary:
			reward_calls.attempts += 1
			if reward_calls.attempts == 1:
				return {"ok": false, "reason": "inventory_full", "error": "fixture reward rejected"}
			reward_calls.grants += 1
			return {"ok": true}
	).ok, "reward failure fixture configures")
	asserts.true_value(runtime.enter_dungeon("reward_retry_instance", _fixture_definition(), WorldData.new(2, 2), _return_context()).ok, "reward retry fixture enters")

	var rejected := runtime.complete_dungeon({"objective_complete": true, "reward_item_ids": ["fixture_reward"]})
	asserts.false_value(rejected.ok, "reward hook failure rejects top-level completion")
	asserts.equal(rejected.reason, "reward_hook_rejected", "reward failure exposes stable retry reason")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_ACTIVE, "reward failure leaves dungeon active for retry")
	asserts.false_value(context.run_state.completed_runtime_dungeon_ids.has("fixture_dungeon"), "reward failure does not record canonical completion")
	asserts.equal(context.run_state.completed_dungeon_ids, [], "reward failure does not advance biome progression")
	asserts.equal(clear_events.size(), 0, "reward failure does not emit a clear event")
	asserts.equal(reward_calls.attempts, 1, "failed reward hook runs once")
	asserts.equal(reward_calls.grants, 0, "failed reward hook does not grant a reward")

	var completed := runtime.complete_dungeon({"objective_complete": true, "reward_item_ids": ["fixture_reward"]})
	asserts.true_value(completed.ok, "retry completes after reward boundary succeeds")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_COMPLETED, "successful retry records terminal completion")
	asserts.equal(reward_calls.attempts, 2, "retry invokes reward exactly once more")
	asserts.equal(reward_calls.grants, 1, "retry grants the reward exactly once")
	asserts.equal(clear_events.size(), 1, "successful retry emits one clear event")
	asserts.equal(runtime.complete_dungeon({"objective_complete": true}).reason, "invalid_completion_transition", "completed dungeon cannot duplicate reward")
	asserts.equal(reward_calls.attempts, 2, "duplicate guard prevents a third reward attempt")
	asserts.equal(reward_calls.grants, 1, "duplicate guard prevents a duplicate reward grant")
	asserts.equal(clear_events.size(), 1, "duplicate guard prevents a duplicate clear event")

func _progression_failure_does_not_grant_reward(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	var reward_calls := {"count": 0}
	asserts.true_value(runtime.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)),
		func(_event: Dictionary) -> Dictionary:
			reward_calls.count += 1
			return {"ok": true}
	).ok, "progression failure fixture configures")
	asserts.true_value(runtime.enter_dungeon("progression_reject_instance", _fixture_definition(), WorldData.new(2, 2), _return_context()).ok, "progression failure fixture enters")
	context.run_state.teleport_states["common_region"] = BiomeProgressionState.TELEPORT_REPAIRED

	var rejected := runtime.complete_dungeon({"objective_complete": true, "reward_item_ids": ["fixture_reward"]})
	asserts.false_value(rejected.ok, "progression rejection prevents completion")
	asserts.equal(rejected.reason, "invalid_teleport_state", "progression rejection preserves its stable reason")
	asserts.equal(reward_calls.count, 0, "progression validation runs before the side-effecting reward hook")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_ACTIVE, "progression rejection leaves the dungeon retryable")
	asserts.false_value(context.run_state.completed_runtime_dungeon_ids.has("fixture_dungeon"), "progression rejection does not record canonical completion")

func _boss_precombat_gate_blocks_resolution_until_dialogue_complete(asserts) -> void:
	var context := _runtime_context()
	var runtime: DungeonRuntime = context.runtime
	var clear_events := []
	asserts.true_value(runtime.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "boss gate fixture configures")
	runtime.dungeon_cleared.connect(func(event: Dictionary) -> void: clear_events.append(event))
	asserts.true_value(runtime.enter_dungeon("boss_gate_instance", _fixture_boss_definition(), WorldData.new(4, 4), _return_context()).ok, "boss gate entry accepts stable boss dialogue definition")
	asserts.equal(runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_PENDING, "entry records pre-boss dialogue pending state")
	asserts.false_value(runtime.boss_combat_available(), "boss combat is unavailable before the dialogue starts")

	var premature_resolution := runtime.complete_boss_encounter(_fixture_boss_resolution())
	asserts.false_value(premature_resolution.ok, "boss resolution is blocked before dialogue completion")
	asserts.equal(premature_resolution.reason, "invalid_boss_gate_transition", "premature boss resolution exposes stable reason")
	asserts.equal(clear_events.size(), 0, "premature boss resolution does not clear the dungeon")

	var begun := runtime.begin_boss_precombat_dialogue()
	asserts.true_value(begun.ok, "pending boss gate can begin pre-combat dialogue")
	asserts.equal(begun.event_id, "fixture_boss_precombat", "runtime exposes the stable dialogue event id")
	asserts.equal(runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE, "dialogue start is saved as its own state")
	var wrong_dialogue := runtime.complete_boss_precombat_dialogue("other_event")
	asserts.false_value(wrong_dialogue.ok, "wrong dialogue event cannot unlock boss combat")
	asserts.equal(wrong_dialogue.reason, "invalid_pre_boss_dialogue", "wrong dialogue completion exposes stable reason")

	var dialogue_done := runtime.complete_boss_precombat_dialogue("fixture_boss_precombat")
	asserts.true_value(dialogue_done.ok, "matching dialogue completion unlocks boss combat")
	asserts.equal(runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_COMBAT_ACTIVE, "dialogue completion persists boss combat state")
	asserts.true_value(runtime.to_projection().pre_boss_dialogue_completed, "dialogue completion is persisted")
	asserts.true_value(runtime.boss_combat_available(), "boss combat is available after the dialogue")

	var completed := runtime.complete_boss_encounter(_fixture_boss_resolution())
	asserts.true_value(completed.ok, "common boss resolution clears the dungeon after the gate opens")
	asserts.equal(runtime.to_projection().lifecycle_state, DungeonInstanceState.STATE_COMPLETED, "boss defeat completes the dungeon lifecycle")
	asserts.equal(runtime.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_RESOLVED, "boss resolution is persisted separately")
	asserts.equal(clear_events.size(), 1, "boss victory emits clear exactly once")
	asserts.equal(context.run_state.completed_runtime_dungeon_ids, ["fixture_dungeon"], "boss victory records canonical dungeon completion once")
	asserts.equal(runtime.complete_boss_encounter(_fixture_boss_resolution()).reason, "invalid_boss_gate_transition", "duplicate boss clear cannot run after dungeon completion")
	asserts.equal(clear_events.size(), 1, "duplicate boss clear does not re-emit clear")

func _boss_gate_save_round_trip_preserves_pending_active_and_combat(asserts) -> void:
	var pending_context := _runtime_context()
	var pending_runtime: DungeonRuntime = pending_context.runtime
	asserts.true_value(pending_runtime.configure(pending_context.run_state, pending_context.progression, func(_payload: Dictionary, _projection: Dictionary) -> bool: return true).ok, "pending gate fixture configures")
	asserts.true_value(pending_runtime.enter_dungeon("pending_boss_gate", _fixture_boss_definition(), WorldData.new(3, 3), _return_context()).ok, "pending gate fixture enters")
	var pending_resumed := _resume_runtime_from_encoded_run(pending_context.run_state)
	asserts.equal(pending_resumed.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_PENDING, "save resume preserves pre-dialogue pending state")
	asserts.false_value(pending_resumed.boss_combat_available(), "pending save resume keeps boss combat locked")

	var active_context := _runtime_context()
	var active_runtime: DungeonRuntime = active_context.runtime
	asserts.true_value(active_runtime.configure(active_context.run_state, active_context.progression, func(_payload: Dictionary, _projection: Dictionary) -> bool: return true).ok, "active dialogue fixture configures")
	asserts.true_value(active_runtime.enter_dungeon("active_boss_gate", _fixture_boss_definition(), WorldData.new(3, 3), _return_context()).ok, "active dialogue fixture enters")
	asserts.true_value(active_runtime.begin_boss_precombat_dialogue().ok, "active dialogue fixture starts dialogue")
	var active_resumed := _resume_runtime_from_encoded_run(active_context.run_state)
	asserts.equal(active_resumed.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE, "save resume preserves active pre-dialogue state")
	asserts.false_value(active_resumed.boss_combat_available(), "active dialogue save resume keeps boss combat locked")

	var combat_context := _runtime_context()
	var combat_runtime: DungeonRuntime = combat_context.runtime
	asserts.true_value(combat_runtime.configure(combat_context.run_state, combat_context.progression, func(_payload: Dictionary, _projection: Dictionary) -> bool: return true).ok, "boss combat fixture configures")
	asserts.true_value(combat_runtime.enter_dungeon("combat_boss_gate", _fixture_boss_definition(), WorldData.new(3, 3), _return_context()).ok, "boss combat fixture enters")
	asserts.true_value(combat_runtime.begin_boss_precombat_dialogue().ok, "boss combat fixture starts dialogue")
	asserts.true_value(combat_runtime.complete_boss_precombat_dialogue("fixture_boss_precombat").ok, "boss combat fixture completes dialogue")
	var combat_resumed := _resume_runtime_from_encoded_run(combat_context.run_state)
	asserts.equal(combat_resumed.to_projection().boss_flow_state, DungeonInstanceState.BOSS_FLOW_COMBAT_ACTIVE, "save resume preserves boss combat state")
	asserts.true_value(combat_resumed.boss_combat_available(), "boss combat save resume keeps boss available")

func _invalid_saved_boss_gate_is_rejected(asserts) -> void:
	var context := _runtime_context()
	context.run_state.dungeon_runtime_state = _saved_instance(_return_context())
	context.run_state.dungeon_runtime_state["boss_flow_state"] = DungeonInstanceState.BOSS_FLOW_PRE_DIALOGUE_ACTIVE
	context.run_state.dungeon_runtime_state["boss_id"] = "fixture_boss"
	context.run_state.dungeon_runtime_state["boss_encounter_id"] = "saved_instance_fixture_boss"
	var result: Dictionary = context.runtime.configure(
		context.run_state,
		context.progression,
		func(_payload: Dictionary, _projection: Dictionary) -> bool: return true
	)
	asserts.false_value(result.ok, "saved boss gate without dialogue id is rejected")
	asserts.equal(result.reason, "invalid_saved_dungeon_state", "invalid saved boss gate exposes stable reason")

func _runtime_context() -> Dictionary:
	var run_state := RunState.new()
	var progression := BiomeProgressionState.new()
	progression.configure(_fixture_biomes(), run_state)
	return {"run_state": run_state, "progression": progression, "runtime": DungeonRuntime.new()}

func _fixture_definition() -> Dictionary:
	return {"id": "fixture_dungeon", "biome_id": "common_region"}

func _fixture_boss_definition() -> Dictionary:
	return {
		"id": "fixture_dungeon",
		"biome_id": "common_region",
		"boss_id": "fixture_boss",
		"pre_boss_dialogue_event_id": "fixture_boss_precombat"
	}

func _fixture_boss_resolution() -> Dictionary:
	return {
		"event_type": "boss_encounter_resolved",
		"boss_id": "fixture_boss",
		"encounter_id": "boss_gate_instance_fixture_boss",
		"dungeon_id": "fixture_dungeon",
		"biome_id": "common_region",
		"resolution_type": "combat",
		"choice_key": "fixture_boss_defeated",
		"run_flag": "fixture_boss_defeated",
		"reward_item_ids": [],
		"progression_unlock_ids": ["common_region"]
	}

func _resume_runtime_from_encoded_run(source_run_state: RunState) -> DungeonRuntime:
	var decoded := SaveCodec.decode_run(SaveCodec.encode_run(source_run_state.to_dictionary()))
	var progression := BiomeProgressionState.new()
	progression.configure(_fixture_biomes(), decoded.run_state)
	var resumed := DungeonRuntime.new()
	resumed.configure(decoded.run_state, progression, func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)))
	return resumed

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
