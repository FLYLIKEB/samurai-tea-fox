extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const BossTeaResolutionRuntime = preload("res://src/boss/boss_tea_resolution_runtime.gd")
const ChoiceRuntime = preload("res://src/choice/choice_runtime.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
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

	func current_biome_id() -> String:
		return biome_id

	func complete_dungeon(value: String) -> Dictionary:
		return complete_dungeon_transaction(value)

	func complete_dungeon_transaction(value: String, commit_hook := Callable()) -> Dictionary:
		if commit_hook.is_valid():
			var hook_result = commit_hook.call()
			if typeof(hook_result) == TYPE_DICTIONARY and not bool(hook_result.get("ok", false)):
				return hook_result
		completed.append(value)
		return {"ok": true}

func run(asserts) -> void:
	_asserts_pre_boss_commands_are_stable_state(asserts)
	_asserts_drink_tea_requires_prepared_availability(asserts)
	_asserts_failed_conditions_do_not_consume_tea(asserts)
	_asserts_malformed_conditions_are_rejected_without_consumption(asserts)
	_asserts_successful_tea_resolution_commits_common_boss_contract(asserts)
	_asserts_resolution_hook_failure_is_retryable_and_does_not_consume(asserts)
	_asserts_equal_progression_rewards_across_resolution_modes(asserts)

func _asserts_pre_boss_commands_are_stable_state(asserts) -> void:
	var fixture := _fixture(asserts)
	var runtime: BossTeaResolutionRuntime = fixture.tea_resolution
	asserts.true_value(runtime.start("pre_boss_refuse").ok, "pre-boss runtime starts from a stable id")
	var refused: Dictionary = runtime.handle_command(BossTeaResolutionRuntime.COMMAND_REFUSE)
	asserts.true_value(refused.ok, "refuse command is accepted")
	asserts.equal(refused.outcome_type, BossTeaResolutionRuntime.OUTCOME_COMBAT, "refuse transitions into combat branch")
	asserts.false_value(refused.consumed, "refuse does not consume prepared tea")
	asserts.equal(refused.projection.lifecycle_state, BossTeaResolutionRuntime.STATE_COMBAT_STARTED, "refuse owns explicit state outside UI")
	asserts.equal(runtime.handle_command(BossTeaResolutionRuntime.COMMAND_ATTACK_FIRST).reason, "pre_boss_resolution_not_active", "duplicate pre-boss command is guarded")

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
	var fixture := _fixture(asserts, [{"type": "unknown_condition", "id": "broken"}])
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "fixture tea can be prepared for malformed condition")
	fixture.tea_resolution.start("pre_boss_malformed")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.false_value(result.ok, "malformed peaceful condition is rejected")
	asserts.equal(result.reason, "unknown_condition_type", "malformed condition preserves resolver reason")
	asserts.true_value(fixture.tea_service.has_prepared_tea(0), "malformed condition does not consume tea")

func _asserts_successful_tea_resolution_commits_common_boss_contract(asserts) -> void:
	var fixture := _fixture(asserts)
	var hooks := {"memory": [], "weakness": [], "dialogue": []}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary: return fixture.boss.handle_resolution(event),
		func(event: Dictionary) -> Dictionary:
			hooks.memory.append(event)
			return {"ok": true},
		func(event: Dictionary) -> Dictionary:
			hooks.weakness.append(event)
			return {"ok": true},
		func(event: Dictionary) -> Dictionary:
			hooks.dialogue.append(event)
			return {"ok": true}
	)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "fixture tea can be prepared")
	fixture.tea_resolution.start("pre_boss_success")
	var result: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.true_value(result.ok, "successful tea command resolves through boss runtime")
	asserts.equal(result.event.event_type, BossEncounterRuntime.EVENT_RESOLVED, "tea ceremony emits common DEV-28 boss event")
	asserts.equal(result.event.resolution_type, "peaceful", "tea ceremony maps to peaceful common resolution type")
	asserts.equal(result.event.tea_resolution_outcome, BossTeaResolutionRuntime.OUTCOME_PEACEFUL_TEA_CEREMONY, "specific tea outcome remains a stable flag")
	asserts.equal(result.resolution_result.completion_result.clear_event.dungeon_id, "fixture_dungeon", "boss event clears the active dungeon")
	asserts.equal(result.resolution_result.completion_result.clear_event.reward_item_ids, ["humble_clay_bowl"], "progression reward payload crosses dungeon completion")
	asserts.true_value(result.consumed, "successful commit consumes the prepared tea")
	asserts.false_value(fixture.tea_service.has_prepared_tea(0), "tea is consumed only after successful commit")
	asserts.true_value(fixture.run_state.narrative_flags.has("fixture_shared_tea"), "choice run flag is recorded after successful resolution")
	asserts.equal(hooks.memory[0].memory_hook_keys, ["memory.fixture_boss.met", "memory.fixture_boss.shared_tea"], "memory hooks expose stable keys without dialogue text")
	asserts.equal(hooks.weakness[0].weakness_hook_keys, ["weakness.fixture_boss.calm"], "weakness hooks expose stable keys")
	asserts.equal(hooks.dialogue[0].dialogue_hook_keys, ["dialogue.fixture_boss.pre_boss", "dialogue.fixture_boss.peaceful"], "dialogue hooks expose stable keys")
	asserts.equal(fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state).reason, "pre_boss_resolution_not_active", "duplicate peaceful resolution is guarded")

func _asserts_resolution_hook_failure_is_retryable_and_does_not_consume(asserts) -> void:
	var fixture := _fixture(asserts)
	fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(fixture, "oribe_green_matcha"), "retry tea can be prepared")
	var calls := {"count": 0}
	fixture.tea_resolution = _tea_resolution_runtime(
		asserts,
		fixture.definition,
		fixture.tea_service,
		fixture.choice_runtime,
		func(event: Dictionary) -> Dictionary:
			calls.count += 1
			if calls.count == 1:
				return {"ok": false, "reason": "dungeon_busy", "error": "fixture hook rejected"}
			return fixture.boss.handle_resolution(event)
	)
	fixture.tea_resolution.start("pre_boss_retry")
	var rejected: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.false_value(rejected.ok, "resolution hook failure rejects commit")
	asserts.equal(rejected.reason, "dungeon_busy", "resolution hook reason is preserved")
	asserts.true_value(fixture.tea_service.has_prepared_tea(0), "hook failure does not consume prepared tea")
	asserts.false_value(fixture.run_state.narrative_flags.has("fixture_shared_tea"), "hook failure does not apply choice state")
	var retried: Dictionary = fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, fixture.run_state)
	asserts.true_value(retried.ok, "same pre-boss command can retry after failed hook")
	asserts.false_value(fixture.tea_service.has_prepared_tea(0), "successful retry consumes tea")
	asserts.equal(calls.count, 2, "retry invokes resolution hook exactly once more")

func _asserts_equal_progression_rewards_across_resolution_modes(asserts) -> void:
	var peaceful_fixture := _fixture(asserts)
	peaceful_fixture.run_state.narrative_flags.append("met_boss")
	asserts.true_value(_prepare_fixture_tea(peaceful_fixture, "oribe_green_matcha"), "peaceful reward fixture tea prepares")
	peaceful_fixture.tea_resolution.start("pre_boss_reward")
	var peaceful: Dictionary = peaceful_fixture.tea_resolution.handle_command(BossTeaResolutionRuntime.COMMAND_DRINK_TEA, {"slot": 0}, peaceful_fixture.run_state)

	var combat_fixture := _fixture(asserts)
	asserts.true_value(combat_fixture.boss.update_health(0).ok, "combat reward fixture boss can be defeated")
	var combat: Dictionary = combat_fixture.boss.handle_resolution({"type": "victory"})

	asserts.true_value(peaceful.ok and combat.ok, "both permitted resolution modes complete")
	asserts.equal(peaceful.event.reward_item_ids, combat.event.reward_item_ids, "peaceful and combat modes grant the same item rewards")
	asserts.equal(peaceful.event.progression_unlock_ids, combat.event.progression_unlock_ids, "peaceful and combat modes grant the same progression unlocks")

func _fixture(asserts, conditions := [{"type": "run_flag", "id": "met_boss"}]) -> Dictionary:
	var definition: BossDefinition = BossDefinition.from_dictionary(_boss_row(conditions)).definition
	var run_state := RunState.new()
	run_state.current_biome_id = "common_region"
	var progression := ProgressionBoundary.new()
	var dungeon := DungeonRuntime.new()
	asserts.true_value(dungeon.configure(
		run_state,
		progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "fixture dungeon configures")
	asserts.true_value(dungeon.enter_dungeon("fixture_instance", {"id": "fixture_dungeon", "biome_id": "common_region"}, WorldData.new(2, 2), {"biome_id": "common_region", "world_seed": 2901}).ok, "fixture dungeon enters")
	var boss := BossEncounterRuntime.new()
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
		"dungeon": dungeon,
		"boss": boss,
		"tea_service": tea_service,
		"inventory": inventory,
		"choice_runtime": choice_runtime,
		"tea_resolution": tea_resolution
	}

func _tea_resolution_runtime(
	asserts,
	definition: BossDefinition,
	tea_service: TeaService,
	choice_runtime: ChoiceRuntime,
	resolution_hook: Callable,
	memory_hook := Callable(),
	weakness_hook := Callable(),
	dialogue_hook := Callable()
) -> BossTeaResolutionRuntime:
	var runtime := BossTeaResolutionRuntime.new()
	var configured := runtime.configure(definition, tea_service, resolution_hook, choice_runtime, memory_hook, weakness_hook, dialogue_hook)
	asserts.true_value(configured.ok, "boss tea resolution runtime configures")
	return runtime

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
