extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const BossTeaResolutionRuntime = preload("res://src/boss/boss_tea_resolution_runtime.gd")
const ChoiceRuntime = preload("res://src/choice/choice_runtime.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const PlayerResources = preload("res://src/player/player_resources.gd")
const RunState = preload("res://src/save/run_state.gd")
const TeaService = preload("res://src/tea/tea_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class FakeCatalog:
	extends RefCounted
	var data_version := "boss-tea-fixture-v1"
	var definitions: Dictionary

	func _init(value: Dictionary) -> void:
		definitions = value

	func get_definitions(key: String) -> Array:
		return definitions.get(key, [])

	func find_by_id(key: String, id: String) -> Dictionary:
		for item in get_definitions(key):
			if String(item.get("id", "")) == id:
				return item
		return {}

class ProgressionBoundary:
	extends RefCounted
	var biome_id := "common_region"
	var completed := []
	var fail_completion := false

	func current_biome_id() -> String:
		return biome_id

	func complete_dungeon(value: String) -> Dictionary:
		return complete_dungeon_transaction(value)

	func complete_dungeon_transaction(value: String, commit_hook := Callable()) -> Dictionary:
		if fail_completion:
			return {"ok": false, "reason": "progression_rejected", "error": "fixture progression rejected"}
		if commit_hook.is_valid():
			var hook_result = commit_hook.call()
			if typeof(hook_result) == TYPE_DICTIONARY and not bool(hook_result.get("ok", false)):
				return hook_result
		completed.append(value)
		return {"ok": true}

class MutatingFailChoiceBoundary:
	extends RefCounted
	var delegate

	func _init(value) -> void:
		delegate = value

	func definition_for(choice_id: String) -> Dictionary:
		return delegate.definition_for(choice_id)

	func can_apply(choice_id: String, run_state, context := {}) -> Dictionary:
		return delegate.can_apply(choice_id, run_state, context)

	func apply_choice(_choice_id: String, run_state, _context := {}) -> Dictionary:
		run_state.narrative_flags.append("partial_choice_mutation")
		run_state.choice_history.append("partial_choice_mutation")
		return {"ok": false, "reason": "choice_commit_failed", "error": "fixture choice commit failed"}

class FailAfterCompleteTeaService:
	extends TeaService
	func complete_drinking(action: Dictionary, resources = null) -> Dictionary:
		var committed: Dictionary = super.complete_drinking(action, resources)
		if not committed.ok:
			return committed
		var failure := {"ok": false, "reason": "tea_commit_failed", "error": "fixture tea failed after mutation"}
		operation_failed.emit(failure.duplicate(true))
		return failure

class DictionaryResourceTeaService:
	extends TeaService
	func complete_drinking(action: Dictionary, resources = null) -> Dictionary:
		var committed: Dictionary = super.complete_drinking(action, null)
		if committed.ok and resources is Dictionary:
			resources.ki = mini(int(resources.get("ki_max", 0)), int(resources.get("ki", 0)) + int(committed.effect.ki_recovery_requested))
		return committed

class RejectDrinkCommitTeaService:
	extends TeaService
	func prepare_drink_commit(_started_action: Dictionary, _completion_result: Dictionary, _committed_snapshot: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "tea_commit_prepare_rejected", "error": "fixture tea commit prepare rejected"}

class RejectSnapshotDeltaResources:
	extends PlayerResources
	func prepare_snapshot_delta(_before: Dictionary, _after: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "resource_commit_prepare_rejected", "error": "fixture resource commit prepare rejected"}

func run(asserts) -> void:
	_asserts_pre_boss_commands_are_stable_state(asserts)
	_asserts_payload_choice_cannot_override_definition(asserts)
	_asserts_drink_tea_requires_prepared_availability(asserts)
	_asserts_failed_conditions_do_not_consume_tea(asserts)
	_asserts_malformed_conditions_are_rejected_without_consumption(asserts)
	_asserts_complete_drinking_failure_is_atomic(asserts)
	_asserts_apply_choice_failure_is_atomic(asserts)
	_asserts_tea_commit_prepare_failure_is_atomic(asserts)
	_asserts_resource_commit_prepare_failure_is_atomic(asserts)
	_asserts_resolution_failure_is_atomic(asserts)
	_asserts_dictionary_resources_restore_without_signal_contract(asserts)
	_asserts_successful_tea_resolution_commits_common_boss_contract(asserts)
	_asserts_existing_signal_block_state_is_preserved(asserts)
	_asserts_combat_start_branches_converge_once_through_common_victory(asserts)

func _asserts_pre_boss_commands_are_stable_state(asserts) -> void:
	var fixture := _fixture(asserts)
	var runtime: BossTeaResolutionRuntime = fixture.tea_resolution
	asserts.equal(runtime.start("Bad ID").reason, "invalid_pre_boss_id", "pre-boss runtime rejects malformed stable ids")
	asserts.true_value(runtime.start("pre_boss_refuse").ok, "pre-boss runtime starts from a stable id")
	var refused: Dictionary = runtime.handle_command(BossTeaResolutionRuntime.COMMAND_REFUSE)
	asserts.true_value(refused.ok, "refuse command is accepted")
	asserts.equal(refused.outcome_type, BossTeaResolutionRuntime.OUTCOME_COMBAT_STARTED, "refuse starts combat without resolving the boss")
	asserts.false_value(refused.consumed, "refuse does not consume prepared tea")
	asserts.equal(refused.projection.lifecycle_state, BossTeaResolutionRuntime.STATE_COMBAT_STARTED, "refuse owns explicit state outside UI")
	asserts.false_value(refused.event.final_resolution, "pre-boss event is explicitly non-final")
	asserts.true_value(refused.projection.boss_resolution_pending, "projection keeps final boss resolution pending")
	asserts.equal(refused.projection.resolution_event, {}, "pre-boss combat transition has no final resolution event")
	asserts.equal(runtime.handle_command(BossTeaResolutionRuntime.COMMAND_ATTACK_FIRST).reason, "pre_boss_resolution_not_active", "duplicate pre-boss command is guarded")

func _asserts_payload_choice_cannot_override_definition(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "choice identity fixture tea prepares")
	fixture.tea_resolution.start("pre_boss_choice_identity")
	var before := _state_snapshots(fixture)
	var result: Dictionary = fixture.tea_resolution.handle_command(
		BossTeaResolutionRuntime.COMMAND_DRINK_TEA,
		{"slot": 0, "choice_id": "payload_override"},
		fixture.run_state
	)
	asserts.false_value(result.ok, "payload cannot replace the configured peaceful choice")
	asserts.equal(result.reason, "peaceful_choice_mismatch", "choice mismatch exposes a stable rejection reason")
	_assert_snapshots_equal(asserts, fixture, before, "choice identity rejection")

func _asserts_drink_tea_requires_prepared_availability(asserts) -> void:
	var fixture := _fixture(asserts)
	var runtime: BossTeaResolutionRuntime = fixture.tea_resolution
	runtime.start("pre_boss_missing_tea")
	var result: Dictionary = runtime.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.false_value(result.ok, "drink tea command requires an occupied prepared slot")
	asserts.equal(result.reason, "missing_prepared_tea", "missing tea exposes a stable reason")

func _asserts_failed_conditions_do_not_consume_tea(asserts) -> void:
	var fixture := _fixture(asserts, [{"type": "run_flag", "id": "met_boss"}])
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "fixture tea can be prepared")
	fixture.tea_resolution.start("pre_boss_condition_false")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.true_value(result.ok, "unmet peaceful condition produces a mixed branch result")
	asserts.equal(result.outcome_type, BossTeaResolutionRuntime.OUTCOME_MIXED, "condition failure reports mixed outcome")
	asserts.false_value(result.consumed, "failed peaceful conditions do not consume tea")
	asserts.true_value(fixture.tea_service.has_prepared_tea(0), "prepared tea remains available after condition failure")

func _asserts_malformed_conditions_are_rejected_without_consumption(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.definition.data_snapshot.tea_resolution.peaceful_conditions = [{"type": "unknown_condition", "id": "broken"}]
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "fixture tea can be prepared for malformed condition")
	fixture.tea_resolution.start("pre_boss_malformed")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.false_value(result.ok, "malformed peaceful condition is rejected")
	asserts.equal(result.reason, "unknown_condition_type", "malformed condition preserves resolver reason")
	asserts.true_value(fixture.tea_service.has_prepared_tea(0), "malformed condition does not consume tea")

func _asserts_complete_drinking_failure_is_atomic(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.tea_service = _failing_tea_service(asserts)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var hooks := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(_event: Dictionary) -> Dictionary:
			hooks.count += 1
			return {"ok": true}
	)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "drink failure fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	fixture.tea_resolution.start("pre_boss_drink_failure")
	var before := _state_snapshots(fixture)
	var resources_before := resources.to_dictionary()
	var result: Dictionary = fixture.tea_resolution.handle_command(
		BossTeaResolutionRuntime.COMMAND_DRINK_TEA,
		{"slot": 0, "resources": resources},
		fixture.run_state
	)
	asserts.false_value(result.ok, "complete_drinking failure rejects peaceful commit")
	asserts.equal(result.reason, "tea_commit_failed", "tea failure reason is preserved")
	asserts.true_value(result.rolled_back, "tea failure reports explicit snapshot rollback")
	_assert_snapshots_equal(asserts, fixture, before, "complete_drinking failure")
	asserts.equal(resources.to_dictionary(), resources_before, "complete_drinking failure restores player resources exactly")
	_assert_no_committed_signals(asserts, signals, "complete_drinking failure")
	asserts.false_value(fixture.tea_service.is_blocking_signals(), "complete_drinking failure restores tea signal blocking state")
	asserts.false_value(resources.is_blocking_signals(), "complete_drinking failure restores resource signal blocking state")
	asserts.equal(hooks.count, 0, "tea failure cannot invoke post-commit hooks")

func _asserts_apply_choice_failure_is_atomic(asserts) -> void:
	var fixture := _fixture(asserts)
	var failing_choice := MutatingFailChoiceBoundary.new(fixture.choice_runtime)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var hooks := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		failing_choice,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(_event: Dictionary) -> Dictionary:
			hooks.count += 1
			return {"ok": true}
	)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "choice failure fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	var evaluations := []
	fixture.tea_resolution.peaceful_condition_evaluated.connect(func(event: Dictionary) -> void: evaluations.append(event))
	fixture.tea_resolution.start("pre_boss_choice_failure")
	var before := _state_snapshots(fixture)
	var resources_before := resources.to_dictionary()
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.false_value(result.ok, "apply_choice failure rejects peaceful commit")
	asserts.equal(result.reason, "choice_commit_failed", "choice failure reason is preserved")
	asserts.true_value(result.rolled_back, "choice failure reports explicit snapshot rollback")
	_assert_snapshots_equal(asserts, fixture, before, "apply_choice failure")
	asserts.equal(resources.to_dictionary(), resources_before, "apply_choice failure restores player resources exactly")
	_assert_no_committed_signals(asserts, signals, "apply_choice failure")
	asserts.equal(evaluations.size(), 1, "choice failure retains one distinct preflight evaluation signal")
	asserts.equal(evaluations[0].signal_phase, "preflight", "evaluation signal is explicitly preflight rather than committed")
	asserts.equal(hooks.count, 0, "choice failure cannot invoke post-commit hooks")

func _asserts_tea_commit_prepare_failure_is_atomic(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.tea_service = _rejecting_commit_tea_service(asserts)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var hooks := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(_event: Dictionary) -> Dictionary:
			hooks.count += 1
			return {"ok": true}
	)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "tea prepare rejection fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	fixture.tea_resolution.start("pre_boss_tea_commit_prepare_failure")
	var before := _state_snapshots(fixture)
	var resources_before := resources.to_dictionary()
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.equal(result.reason, "tea_commit_prepare_rejected", "tea commit prepare rejection is preserved")
	asserts.true_value(result.rolled_back, "tea commit prepare rejection reports rollback")
	_assert_snapshots_equal(asserts, fixture, before, "tea commit prepare failure")
	asserts.equal(resources.to_dictionary(), resources_before, "tea commit prepare failure restores player resources exactly")
	_assert_no_committed_signals(asserts, signals, "tea commit prepare failure")
	asserts.equal(hooks.count, 0, "tea commit prepare failure cannot invoke post-commit hooks")

func _asserts_resource_commit_prepare_failure_is_atomic(asserts) -> void:
	var fixture := _fixture(asserts)
	var resources := RejectSnapshotDeltaResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var hooks := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(_event: Dictionary) -> Dictionary:
			hooks.count += 1
			return {"ok": true}
	)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "resource prepare rejection fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	fixture.tea_service.set_block_signals(true)
	resources.set_block_signals(true)
	fixture.tea_resolution.start("pre_boss_resource_commit_prepare_failure")
	var before := _state_snapshots(fixture)
	var resources_before := resources.to_dictionary()
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.equal(result.reason, "resource_commit_prepare_rejected", "resource commit prepare rejection is preserved")
	asserts.true_value(result.rolled_back, "resource commit prepare rejection reports rollback")
	_assert_snapshots_equal(asserts, fixture, before, "resource commit prepare failure")
	asserts.equal(resources.to_dictionary(), resources_before, "resource commit prepare failure restores player resources exactly")
	_assert_no_committed_signals(asserts, signals, "resource commit prepare failure")
	asserts.true_value(fixture.tea_service.is_blocking_signals(), "failed rollback preserves pre-blocked tea signal state")
	asserts.true_value(resources.is_blocking_signals(), "failed rollback preserves pre-blocked resource signal state")
	asserts.equal(hooks.count, 0, "resource commit prepare failure cannot invoke post-commit hooks")

func _asserts_resolution_failure_is_atomic(asserts) -> void:
	var fixture := _fixture(asserts)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	var hooks := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(_event: Dictionary) -> Dictionary:
			hooks.count += 1
			return {"ok": true}
	)
	fixture.progression.fail_completion = true
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "resolution failure fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	fixture.tea_resolution.start("pre_boss_resolution_failure")
	var before := _state_snapshots(fixture)
	var resources_before := resources.to_dictionary()
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.false_value(result.ok, "DEV-28 resolution failure rejects peaceful commit")
	asserts.equal(result.reason, "progression_rejected", "resolution failure reason is preserved")
	asserts.true_value(result.rolled_back, "resolution failure reports explicit snapshot rollback")
	_assert_snapshots_equal(asserts, fixture, before, "resolution failure")
	asserts.equal(resources.to_dictionary(), resources_before, "resolution failure restores player resources exactly")
	_assert_no_committed_signals(asserts, signals, "resolution failure")
	asserts.equal(hooks.count, 0, "resolution failure cannot invoke post-commit hooks")
	fixture.progression.fail_completion = false
	var retry: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.true_value(retry.ok, "fully rolled back peaceful resolution can retry")

func _asserts_dictionary_resources_restore_without_signal_contract(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.tea_service = _dictionary_resource_tea_service(asserts)
	var failing_choice := MutatingFailChoiceBoundary.new(fixture.choice_runtime)
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		failing_choice,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event)
	)
	var resources := {"hp": 80, "hp_max": 100, "ki": 50, "ki_max": 100, "kokoro": 70, "kokoro_max": 100}
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "dictionary resource fixture tea prepares")
	fixture.tea_resolution.start("pre_boss_dictionary_resource_failure")
	var resources_before := resources.duplicate(true)
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.false_value(result.ok, "dictionary resource choice failure rejects commit")
	asserts.equal(resources, resources_before, "dictionary resources restore exactly without a signal contract")

func _asserts_successful_tea_resolution_commits_common_boss_contract(asserts) -> void:
	var fixture := _fixture(asserts)
	var hooks := {"memory": [], "weakness": [], "dialogue": []}
	var hook_states := []
	var sequence := []
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(event: Dictionary) -> Dictionary:
			hooks.memory.append(event)
			hook_states.append(_state_snapshots(fixture))
			sequence.append("hook")
			return {"ok": true},
		func(event: Dictionary) -> Dictionary:
			hooks.weakness.append(event)
			return {"ok": true},
		func(event: Dictionary) -> Dictionary:
			hooks.dialogue.append(event)
			return {"ok": true}
	)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "fixture tea can be prepared")
	fixture.boss.encounter_resolved.connect(func(_event: Dictionary) -> void: sequence.append("boss_resolved"))
	var signals := _committed_signal_counts(fixture.tea_service, resources, sequence)
	fixture.tea_resolution.start("pre_boss_success")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.true_value(result.ok, "successful tea command resolves through boss runtime")
	asserts.equal(result.event.event_type, BossEncounterRuntime.EVENT_RESOLVED, "tea ceremony emits common DEV-28 boss event")
	asserts.equal(result.event.resolution_type, "peaceful", "tea ceremony maps to peaceful common resolution type")
	asserts.equal(result.event.tea_resolution_outcome, BossTeaResolutionRuntime.OUTCOME_PEACEFUL_TEA_CEREMONY, "specific tea outcome remains a stable flag")
	asserts.equal(result.resolution_result.completion_result.clear_event.dungeon_id, "fixture_dungeon", "boss event clears the active dungeon")
	asserts.equal(result.resolution_result.completion_result.clear_event.reward_item_ids, ["humble_clay_bowl"], "progression reward payload crosses dungeon completion")
	asserts.true_value(result.consumed, "successful commit consumes the prepared tea")
	asserts.false_value(fixture.tea_service.has_prepared_tea(0), "tea is consumed only after successful commit")
	asserts.equal(resources.ki, 62, "successful commit preserves the tea resource effect")
	asserts.true_value(fixture.run_state.narrative_flags.has("fixture_shared_tea"), "choice run flag is recorded after successful resolution")
	asserts.equal(signals.drink_started, 1, "successful commit publishes drink_started exactly once")
	asserts.equal(signals.drink_completed, 1, "successful commit publishes drink_completed exactly once")
	asserts.equal(signals.changed, 1, "successful commit publishes tea changed exactly once")
	asserts.equal(signals.operation_failed, 0, "successful commit does not publish operation_failed")
	asserts.equal(signals.ki_changed, 1, "successful commit publishes resource delta exactly once")
	asserts.equal(signals.ki_events, [[50, 62, 100]], "published resource delta preserves the committed before and after values")
	asserts.equal(sequence, ["boss_resolved", "tea_started", "tea_completed", "tea_changed", "ki_changed", "hook"], "commit signals and hooks publish only after the common boss resolution succeeds")
	asserts.false_value(result.has("tea_publish_result"), "successful result does not hide a fallible post-resolution tea publish result")
	asserts.false_value(result.has("resource_publish_result"), "successful result does not hide a fallible post-resolution resource publish result")
	asserts.equal(hooks.memory[0].memory_hook_keys, ["memory.fixture_boss.met", "memory.fixture_boss.shared_tea"], "memory hooks expose stable keys without dialogue text")
	asserts.equal(hooks.weakness[0].weakness_hook_keys, ["weakness.fixture_boss.calm"], "weakness hooks expose stable keys")
	asserts.equal(hooks.dialogue[0].dialogue_hook_keys, ["dialogue.fixture_boss.pre_boss", "dialogue.fixture_boss.peaceful"], "dialogue hooks expose stable keys")
	asserts.equal(hook_states[0].boss.lifecycle_state, "resolved", "hooks run after boss resolution commits")
	asserts.equal(hook_states[0].dungeon.lifecycle_state, "completed", "hooks run after dungeon completion commits")
	asserts.equal(hook_states[0].tea.quick_slots[0], {}, "hooks run after tea consumption commits")
	asserts.true_value(hook_states[0].run.narrative_flags.has("fixture_shared_tea"), "hooks run after choice state commits")
	asserts.equal(fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state).reason, "pre_boss_resolution_not_active", "duplicate peaceful resolution is guarded")

func _asserts_existing_signal_block_state_is_preserved(asserts) -> void:
	var fixture := _fixture(asserts)
	var resources := PlayerResources.new(100, 100, 100, 20)
	resources.spend_ki(50)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "blocked signal fixture tea prepares")
	var signals := _committed_signal_counts(fixture.tea_service, resources)
	fixture.tea_service.set_block_signals(true)
	resources.set_block_signals(true)
	fixture.tea_resolution.start("pre_boss_blocked_signals")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0, "resources": resources}, fixture.run_state)
	asserts.true_value(result.ok, "transaction succeeds while observers are already blocked")
	asserts.true_value(fixture.tea_service.is_blocking_signals(), "successful transaction preserves tea signal blocking state")
	asserts.true_value(resources.is_blocking_signals(), "successful transaction preserves resource signal blocking state")
	_assert_no_committed_signals(asserts, signals, "pre-blocked successful transaction")

func _asserts_combat_start_branches_converge_once_through_common_victory(asserts) -> void:
	for command_id in [BossTeaResolutionRuntime.COMMAND_REFUSE, BossTeaResolutionRuntime.COMMAND_ATTACK_FIRST, BossTeaResolutionRuntime.COMMAND_DRINK_TEA]:
		var fixture := _fixture(asserts)
		if command_id == BossTeaResolutionRuntime.COMMAND_DRINK_TEA:
			asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "mixed branch fixture tea prepares")
		fixture.tea_resolution.start("pre_boss_%s" % command_id)
		var result: Dictionary = fixture.tea_resolution.handle_command(command_id, {"slot": 0}, fixture.run_state)
		asserts.true_value(result.ok and result.combat_started, "%s starts pre-boss combat" % command_id)
		asserts.equal(result.event.event_type, BossTeaResolutionRuntime.EVENT_PRE_BOSS_COMBAT_STARTED, "%s emits a pre-boss combat transition event" % command_id)
		asserts.false_value(result.event.final_resolution, "%s transition is not a final boss resolution" % command_id)
		asserts.true_value(result.event.requires_boss_victory, "%s requires later boss victory" % command_id)
		asserts.equal(fixture.boss_events.size(), 0, "%s does not emit the common boss result early" % command_id)
		asserts.equal(fixture.dungeon_events.size(), 0, "%s does not clear the dungeon early" % command_id)
		asserts.equal(fixture.progression.completed, [], "%s does not advance progression early" % command_id)

		asserts.true_value(fixture.boss.update_health(0).ok, "%s combat can defeat the boss" % command_id)
		var victory: Dictionary = fixture.boss.handle_resolution({"type": "victory"})
		asserts.true_value(victory.ok, "%s converges through DEV-28 victory" % command_id)
		asserts.equal(fixture.boss_events.size(), 1, "%s emits exactly one common boss event" % command_id)
		asserts.equal(fixture.boss_events[0].event_type, BossEncounterRuntime.EVENT_RESOLVED, "%s uses the DEV-28 common event" % command_id)
		asserts.equal(fixture.boss_events[0].resolution_type, "combat", "%s final result is combat victory" % command_id)
		asserts.equal(fixture.dungeon_events.size(), 1, "%s reaches DungeonRuntime exactly once" % command_id)
		asserts.equal(fixture.progression.completed, ["common_region"], "%s advances progression exactly once" % command_id)
		asserts.equal(victory.event.reward_item_ids, ["humble_clay_bowl"], "%s preserves declared rewards" % command_id)
		asserts.equal(victory.event.progression_unlock_ids, ["common_region"], "%s preserves declared progression unlocks" % command_id)
		asserts.equal(fixture.boss.handle_resolution({"type": "victory"}).reason, "encounter_not_active", "%s duplicate victory is rejected" % command_id)
		asserts.equal(fixture.boss_events.size(), 1, "%s duplicate victory cannot emit again" % command_id)
		asserts.equal(fixture.dungeon_events.size(), 1, "%s duplicate victory cannot clear again" % command_id)

func _fixture(asserts, conditions := [{"type": "run_flag", "id": "met_boss"}]) -> Dictionary:
	var definition: BossDefinition = BossDefinition.from_dictionary(_boss_row(conditions)).definition
	var run_state := RunState.new()
	run_state.current_biome_id = "common_region"
	var progression := ProgressionBoundary.new()
	var dungeon := DungeonRuntime.new()
	var dungeon_events := []
	dungeon.dungeon_cleared.connect(func(event: Dictionary) -> void: dungeon_events.append(event))
	asserts.true_value(dungeon.configure(
		run_state,
		progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "fixture dungeon configures")
	asserts.true_value(dungeon.enter_dungeon("fixture_instance", {"id": "fixture_dungeon", "biome_id": "common_region"}, WorldData.new(2, 2), {"biome_id": "common_region", "world_seed": 2901}).ok, "fixture dungeon enters")
	var boss := BossEncounterRuntime.new()
	var boss_events := []
	boss.encounter_resolved.connect(func(event: Dictionary) -> void: boss_events.append(event))
	asserts.true_value(boss.configure(
		definition,
		null,
		Callable(),
		func(event: Dictionary) -> Dictionary: return dungeon.complete_boss_encounter(event)
	).ok, "fixture boss configures")
	asserts.true_value(boss.start("fixture_encounter", "fixture_dungeon").ok, "fixture boss starts")
	var tea_service := _tea_service(asserts)
	var inventory := _inventory(asserts)
	var choice_runtime := _choice_runtime(asserts)
	var tea_resolution := _tea_resolution_runtime(
		asserts,
		definition,
		tea_service,
		choice_runtime,
		func(event: Dictionary) -> Dictionary: return boss.handle_resolution(event)
	)
	return {
		"definition": definition,
		"run_state": run_state,
		"progression": progression,
		"dungeon": dungeon,
		"dungeon_events": dungeon_events,
		"boss": boss,
		"boss_events": boss_events,
		"tea_service": tea_service,
		"inventory": inventory,
		"choice_runtime": choice_runtime,
		"tea_resolution": tea_resolution
	}

func _tea_resolution_runtime(
	asserts,
	definition: BossDefinition,
	tea_service,
	choice_runtime,
	resolution_hook: Callable,
	memory_hook := Callable(),
	weakness_hook := Callable(),
	dialogue_hook := Callable()
) -> BossTeaResolutionRuntime:
	var runtime := BossTeaResolutionRuntime.new()
	var configured := runtime.configure(definition, tea_service, resolution_hook, choice_runtime, memory_hook, weakness_hook, dialogue_hook)
	asserts.true_value(configured.ok, "boss tea resolution runtime configures")
	return runtime

func _state_snapshots(fixture: Dictionary) -> Dictionary:
	return {
		"boss": fixture.boss.to_projection(),
		"dungeon": fixture.dungeon.to_projection(),
		"tea": fixture.tea_service.to_snapshot(),
		"run": fixture.run_state.to_dictionary(),
		"progression": fixture.progression.completed.duplicate(true)
	}

func _assert_snapshots_equal(asserts, fixture: Dictionary, before: Dictionary, label: String) -> void:
	var after := _state_snapshots(fixture)
	asserts.equal(after.boss, before.boss, "%s restores boss state" % label)
	asserts.equal(after.dungeon, before.dungeon, "%s restores dungeon state" % label)
	asserts.equal(after.tea, before.tea, "%s restores tea state" % label)
	asserts.equal(after.run, before.run, "%s restores run state" % label)
	asserts.equal(after.progression, before.progression, "%s preserves progression state" % label)

func _committed_signal_counts(tea_service, resources = null, sequence = null) -> Dictionary:
	var counts := {
		"drink_started": 0,
		"drink_completed": 0,
		"changed": 0,
		"operation_failed": 0,
		"ki_changed": 0,
		"ki_events": []
	}
	tea_service.drink_started.connect(func(_event: Dictionary) -> void:
		counts.drink_started += 1
		if sequence is Array:
			sequence.append("tea_started")
	)
	tea_service.drink_completed.connect(func(_event: Dictionary) -> void:
		counts.drink_completed += 1
		if sequence is Array:
			sequence.append("tea_completed")
	)
	tea_service.changed.connect(func(_snapshot: Dictionary) -> void:
		counts.changed += 1
		if sequence is Array:
			sequence.append("tea_changed")
	)
	tea_service.operation_failed.connect(func(_failure: Dictionary) -> void:
		counts.operation_failed += 1
		if sequence is Array:
			sequence.append("tea_failed")
	)
	if resources != null and not resources is Dictionary:
		resources.ki_changed.connect(func(previous: int, current: int, maximum: int) -> void:
			counts.ki_changed += 1
			counts.ki_events.append([previous, current, maximum])
			if sequence is Array:
				sequence.append("ki_changed")
		)
	return counts

func _assert_no_committed_signals(asserts, signals: Dictionary, label: String) -> void:
	asserts.equal(signals.drink_started, 0, "%s emits no drink_started signal" % label)
	asserts.equal(signals.drink_completed, 0, "%s emits no drink_completed signal" % label)
	asserts.equal(signals.changed, 0, "%s emits no tea changed signal" % label)
	asserts.equal(signals.operation_failed, 0, "%s emits no operation_failed signal" % label)
	asserts.equal(signals.ki_changed, 0, "%s emits no resource delta signal" % label)

func _prepare_fixture_tea(fixture: Dictionary, tea_id: String) -> bool:
	var inventory: InventoryModel = fixture.inventory
	inventory.add_item(tea_id, 1)
	inventory.add_item("plain_bowl", 1)
	return bool(fixture.tea_service.brew(tea_id, "plain_bowl", inventory, 0).get("ok", false))

func _tea_service(asserts) -> TeaService:
	var result: Dictionary = TeaService.from_catalog(FakeCatalog.new({
		"balance": _balance_rows(),
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	asserts.true_value(result.ok, "fixture tea service loads")
	return result.tea_service

func _failing_tea_service(asserts) -> TeaService:
	return _configured_tea_subclass(asserts, FailAfterCompleteTeaService.new())

func _dictionary_resource_tea_service(asserts) -> TeaService:
	return _configured_tea_subclass(asserts, DictionaryResourceTeaService.new())

func _rejecting_commit_tea_service(asserts) -> TeaService:
	return _configured_tea_subclass(asserts, RejectDrinkCommitTeaService.new())

func _configured_tea_subclass(asserts, service: TeaService) -> TeaService:
	var base := _tea_service(asserts)
	var configured: Dictionary = service.configure(
		base.quickslot_count,
		base.drink_base_seconds,
		base.tea_definitions,
		base.vessel_definitions,
		base.data_version
	)
	asserts.true_value(configured.ok, "tea service test subclass configures")
	return service

func _inventory(asserts) -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": 8}],
		"items": _item_rows(),
		"teas": _tea_rows()
	}))
	asserts.true_value(result.ok, "fixture inventory loads")
	return result.inventory

func _choice_runtime(asserts) -> ChoiceRuntime:
	var result: Dictionary = ChoiceRuntime.new().from_catalog(FakeCatalog.new({"choices": [_choice_row()]}))
	asserts.true_value(result.ok, "fixture choice runtime loads")
	return result.runtime

func _boss_row(conditions: Array) -> Dictionary:
	return {
		"id": "fixture_boss",
		"name": "Fixture Boss",
		"status": "테스트",
		"dungeon_id": "fixture_dungeon",
		"biome_id": "common_region",
		"max_hp": 100,
		"phases": [
			{"id": "opening", "health_ratio_threshold": 1.0, "patterns": [
				{"id": "opening_strike", "interval_seconds": 1.0, "summon_monster_ids": []}
			]}
		],
		"resolution_types": ["combat", "peaceful"],
		"reward_item_ids": ["humble_clay_bowl"],
		"progression_unlock_ids": ["common_region"],
		"summon_monster_ids": [],
		"tea_resolution": {
			"choice_id": "fixture_share_tea",
			"required_tea_ids": ["oribe_green_matcha"],
			"peaceful_conditions": conditions,
			"hooks": {
				"common": {
					"memory": ["memory.fixture_boss.met"],
					"dialogue": ["dialogue.fixture_boss.pre_boss"]
				},
				"peaceful_tea_ceremony": {
					"memory": ["memory.fixture_boss.shared_tea"],
					"weakness": ["weakness.fixture_boss.calm"],
					"dialogue": ["dialogue.fixture_boss.peaceful"]
				},
				"mixed": {
					"dialogue": ["dialogue.fixture_boss.mixed"]
				}
			}
		}
	}

func _choice_row() -> Dictionary:
	return {
		"id": "fixture_share_tea",
		"name": "Fixture Share Tea",
		"status": "테스트",
		"choice_key": "FIXTURE_SHARE_TEA",
		"run_flag": "fixture_shared_tea",
		"display_text": "Share tea",
		"resolution": "다도",
		"meta_record": true,
		"target_survives": true,
		"philosophy_marks": ["和·공존"],
		"final_room_effect": "fixture final effect"
	}

func _balance_rows() -> Array:
	return [
		{"id": "tea_quickslot_count", "name": "차 퀵슬롯 수", "status": "테스트", "value": 2},
		{"id": "tea_drink_base_seconds", "name": "차 마시기 기본 시간", "status": "테스트", "value": 1.0}
	]

func _item_rows() -> Array:
	return [
		{"id": "plain_bowl", "name": "소박한 사발", "status": "테스트", "type": "다구"},
		{"id": "humble_clay_bowl", "name": "소박한 흙사발", "status": "테스트", "type": "다구"}
	]

func _tea_rows() -> Array:
	return [
		{"id": "oribe_green_matcha", "name": "오리베의 청말", "status": "테스트", "ki_recovery": 12, "max_stack": 4},
		{"id": "wrong_tea", "name": "다른 차", "status": "테스트", "ki_recovery": 6, "max_stack": 4}
	]
