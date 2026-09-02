extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const BossEncounterState = preload("res://src/boss/boss_encounter_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class CatalogProgressionBoundary:
	extends RefCounted

	var biome_id: String
	var completed_biome_ids := []

	func _init(value: String) -> void:
		biome_id = value

	func current_biome_id() -> String:
		return biome_id

	func complete_dungeon(value: String) -> Dictionary:
		return complete_dungeon_transaction(value)

	func complete_dungeon_transaction(value: String, commit_hook := Callable()) -> Dictionary:
		if commit_hook.is_valid():
			var hook_result = commit_hook.call()
			if typeof(hook_result) != TYPE_DICTIONARY or not bool(hook_result.get("ok", false)):
				return hook_result
		completed_biome_ids.append(value)
		return {"ok": true}

class BossTeaCatalog:
	extends RefCounted
	var definitions: Dictionary

	func _init(value: Dictionary) -> void:
		definitions = value

	func find_by_id(dataset: String, definition_id: String) -> Dictionary:
		for row in definitions.get(dataset, []):
			if String(row.get("id", "")) == definition_id:
				return row
		return {}

func run(asserts) -> void:
	_definition_loader_and_samples(asserts)
	_tea_resolution_definition_contract(asserts)
	_catalog_bosses_complete_declared_dungeons(asserts)
	_deterministic_phases_patterns_and_summons(asserts)
	_combat_resolution_completes_dungeon_once(asserts)
	_peaceful_resolution_uses_common_contract(asserts)
	_abort_does_not_complete_dungeon(asserts)
	_summon_failure_keeps_pattern_retryable(asserts)

func _definition_loader_and_samples(asserts) -> void:
	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	asserts.true_value(loaded.ok, "boss sample data loads through the shared catalog: %s" % loaded.get("error", ""))
	var bamboo := BossDefinition.from_catalog(catalog, "sample_bamboo_guardian")
	var ash := BossDefinition.from_catalog(catalog, "sample_ash_warden")
	asserts.true_value(bamboo.ok and ash.ok, "two sample bosses load through one BossDefinition contract")
	if bamboo.ok and ash.ok:
		asserts.equal(bamboo.definition.phases.size(), 2, "peaceful sample preserves data-driven phases")
		asserts.false_value(ash.definition.supports_resolution("peaceful"), "combat-only sample preserves resolution policy")
	var invalid := _boss_row()
	invalid.phases[1].health_ratio_threshold = 1.0
	asserts.false_value(BossDefinition.from_dictionary(invalid).ok, "non-descending phase thresholds are rejected")

func _tea_resolution_definition_contract(asserts) -> void:
	var valid := _boss_row()
	valid.tea_resolution = _tea_resolution_config()
	asserts.true_value(BossDefinition.from_dictionary(valid).ok, "boss definition accepts the typed tea resolution contract")

	var bad_choice := valid.duplicate(true)
	bad_choice.tea_resolution.choice_id = "Bad Choice"
	asserts.false_value(BossDefinition.from_dictionary(bad_choice).ok, "tea resolution choice_id must be stable")
	var bad_condition := valid.duplicate(true)
	bad_condition.tea_resolution.peaceful_conditions = [{"type": "meta_flag", "id": "forbidden_meta"}]
	asserts.false_value(BossDefinition.from_dictionary(bad_condition).ok, "tea resolution rejects unsupported condition types")
	var bad_shape := valid.duplicate(true)
	bad_shape.tea_resolution.peaceful_conditions = [{"type": "run_flag", "id": "met_boss", "value": 1}]
	asserts.false_value(BossDefinition.from_dictionary(bad_shape).ok, "tea resolution rejects condition fields outside its shape")
	var bad_hook := valid.duplicate(true)
	bad_hook.tea_resolution.hooks.common.memory = ["dialogue.wrong_channel"]
	asserts.false_value(BossDefinition.from_dictionary(bad_hook).ok, "tea resolution hook keys must be stable keys for their channel")

	var catalog := BossTeaCatalog.new({
		"bosses": [valid],
		"choices": [{"id": "fixture_share_tea"}],
		"teas": [{"id": "oribe_green_matcha"}]
	})
	asserts.true_value(BossDefinition.from_catalog(catalog, "fixture_boss").ok, "BossDefinition resolves tea choice and tea catalog references")
	catalog.definitions.choices = []
	asserts.false_value(BossDefinition.from_catalog(catalog, "fixture_boss").ok, "BossDefinition rejects a missing tea choice reference")
	catalog.definitions.choices = [{"id": "fixture_share_tea"}]
	catalog.definitions.teas = []
	asserts.false_value(BossDefinition.from_catalog(catalog, "fixture_boss").ok, "BossDefinition rejects a missing required tea reference")

func _catalog_bosses_complete_declared_dungeons(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "catalog dungeon adapter fixture loads")
	for boss_id in ["sample_bamboo_guardian", "sample_ash_warden"]:
		var boss_row: Dictionary = catalog.find_by_id("bosses", boss_id)
		var dungeon_row: Dictionary = catalog.find_by_id("dungeons", String(boss_row.dungeon_id))
		asserts.false_value(dungeon_row.is_empty(), "%s resolves its canonical dungeon relation" % boss_id)
		if dungeon_row.is_empty():
			continue
		var biome_id := String(dungeon_row.get("biome_ids", [""])[0])
		asserts.equal(biome_id, String(boss_row.biome_id), "%s dungeon relation preserves the canonical biome" % boss_id)
		var progression := CatalogProgressionBoundary.new(biome_id)
		var dungeon := DungeonRuntime.new()
		asserts.true_value(dungeon.configure(
			RunState.new(),
			progression,
			func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
		).ok, "%s configures the shared dungeon adapter" % boss_id)
		asserts.true_value(dungeon.enter_dungeon(
			"%s_instance" % boss_id,
			{"id": dungeon_row.id, "biome_id": biome_id},
			WorldData.new(2, 2),
			{"biome_id": biome_id, "world_seed": 2801}
		).ok, "%s enters through its declared catalog dungeon ID" % boss_id)
		var boss := BossEncounterRuntime.new()
		asserts.true_value(boss.configure(
			BossDefinition.from_catalog(catalog, boss_id).definition,
			null,
			Callable(),
			func(event: Dictionary) -> Dictionary: return dungeon.complete_boss_encounter(event)
		).ok, "%s connects to the shared dungeon adapter" % boss_id)
		asserts.true_value(boss.start("%s_encounter" % boss_id, String(boss_row.dungeon_id)).ok, "%s starts with its declared catalog dungeon ID" % boss_id)
		asserts.true_value(boss.update_health(0).ok, "%s reaches combat resolution" % boss_id)
		var resolved := boss.handle_resolution({"type": "victory"})
		asserts.true_value(resolved.ok, "%s completes its declared catalog dungeon" % boss_id)
		if resolved.ok:
			asserts.equal(resolved.completion_result.clear_event.dungeon_id, boss_row.dungeon_id, "%s clear event preserves the catalog dungeon ID" % boss_id)
		asserts.equal(progression.completed_biome_ids, [biome_id], "%s crosses progression exactly once" % boss_id)

func _deterministic_phases_patterns_and_summons(asserts) -> void:
	var definition = BossDefinition.from_dictionary(_boss_row()).definition
	var summons := []
	var runtime := BossEncounterRuntime.new()
	asserts.true_value(runtime.configure(
		definition,
		null,
		func(event: Dictionary) -> Dictionary:
			summons.append(event)
			return {"ok": true}
	).ok, "boss runtime configures with default deterministic scheduler")
	asserts.true_value(runtime.start("encounter_1", "fixture_dungeon").ok, "boss encounter starts with matching stable ids")
	var first := runtime.tick(0.0)
	asserts.equal(first.event.pattern_id, "opening_strike", "scheduler starts with the first phase pattern")
	asserts.false_value(runtime.tick(0.5).scheduled, "pattern interval blocks an early repeat")
	var second := runtime.tick(0.5)
	asserts.equal(second.event.pattern_id, "summon_bandit", "scheduler preserves declared pattern order")
	asserts.equal(summons.size(), 1, "summon hook runs for the scheduled summon pattern")
	asserts.equal(summons[0].monster_ids, ["road_bandit"], "summon hook receives stable monster ids")
	var transition := runtime.update_health(50)
	asserts.true_value(transition.phase_changed, "health threshold deterministically changes phase")
	asserts.equal(transition.event.phase_id, "desperate", "phase transition selects the declared phase id")
	asserts.equal(runtime.tick(0.0).event.pattern_id, "rapid_strike", "new phase resets its pattern cursor")
	var snapshot := runtime.to_projection()
	snapshot.current_hp = 999
	asserts.equal(runtime.to_projection().current_hp, 50, "read-only projection is detached from encounter state")

func _combat_resolution_completes_dungeon_once(asserts) -> void:
	var context := _dungeon_context()
	var dungeon: DungeonRuntime = context.dungeon
	var rewards := {"count": 0}
	asserts.true_value(dungeon.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false)),
		func(_event: Dictionary) -> Dictionary:
			rewards.count += 1
			return {"ok": true}
	).ok, "combat dungeon boundary configures")
	asserts.true_value(dungeon.enter_dungeon("instance_combat", {"id": "fixture_dungeon", "biome_id": "common_region"}, WorldData.new(2, 2), _return_context()).ok, "combat boss dungeon enters")
	var boss := BossEncounterRuntime.new()
	asserts.true_value(boss.configure(
		BossDefinition.from_dictionary(_boss_row()).definition,
		null,
		Callable(),
		func(event: Dictionary) -> Dictionary: return dungeon.complete_boss_encounter(event)
	).ok, "combat boss connects to dungeon resolution adapter")
	asserts.true_value(boss.start("boss_combat", "fixture_dungeon").ok, "combat boss starts")
	asserts.equal(boss.handle_resolution({"type": "victory"}).reason, "victory_condition_not_met", "victory input requires defeated boss health")
	asserts.true_value(boss.update_health(0).ok, "combat state can report zero boss health")
	var resolved := boss.handle_resolution({"type": "victory"})
	asserts.true_value(resolved.ok, "victory resolves through the common boss contract")
	asserts.equal(resolved.event.resolution_type, "combat", "victory normalizes to combat resolution")
	asserts.equal(resolved.completion_result.clear_event.dungeon_id, "fixture_dungeon", "boss result reaches dungeon clear event")
	asserts.equal(rewards.count, 1, "boss victory invokes dungeon reward once")
	asserts.equal(boss.handle_resolution({"type": "victory"}).reason, "encounter_not_active", "duplicate boss completion is rejected")
	asserts.equal(rewards.count, 1, "duplicate boss completion cannot repeat reward")

func _peaceful_resolution_uses_common_contract(asserts) -> void:
	var context := _dungeon_context()
	var dungeon: DungeonRuntime = context.dungeon
	asserts.true_value(dungeon.configure(
		context.run_state,
		context.progression,
		func(payload: Dictionary, _projection: Dictionary) -> bool: return bool(payload.get("objective_complete", false))
	).ok, "peaceful dungeon boundary configures")
	asserts.true_value(dungeon.enter_dungeon("instance_peaceful", {"id": "fixture_dungeon", "biome_id": "common_region"}, WorldData.new(2, 2), _return_context()).ok, "peaceful boss dungeon enters")
	var boss := BossEncounterRuntime.new()
	boss.configure(
		BossDefinition.from_dictionary(_boss_row()).definition,
		null,
		Callable(),
		func(event: Dictionary) -> Dictionary: return dungeon.complete_boss_encounter(event)
	)
	boss.start("boss_peaceful", "fixture_dungeon")
	asserts.equal(boss.handle_resolution({"type": "peaceful"}).reason, "missing_peaceful_choice", "peaceful result requires a stable choice key")
	var resolved := boss.handle_resolution({"type": "peaceful", "choice_key": "FIXTURE_MERCY", "run_flag": "fixture_mercy"})
	asserts.true_value(resolved.ok, "peaceful input clears through the same dungeon adapter")
	asserts.equal(resolved.completion_result.clear_event.choice_key, "FIXTURE_MERCY", "peaceful choice crosses the common clear event")
	asserts.equal(resolved.completion_result.clear_event.run_flag, "fixture_mercy", "peaceful run flag crosses the common clear event")

func _abort_does_not_complete_dungeon(asserts) -> void:
	var completion_calls := {"count": 0}
	var boss := BossEncounterRuntime.new()
	boss.configure(
		BossDefinition.from_dictionary(_boss_row()).definition,
		null,
		Callable(),
		func(_event: Dictionary) -> Dictionary:
			completion_calls.count += 1
			return {"ok": true}
	)
	boss.start("boss_abort", "fixture_dungeon")
	var aborted := boss.handle_resolution({"type": "abort"})
	asserts.true_value(aborted.ok, "abort is accepted as an explicit encounter input")
	asserts.equal(aborted.projection.lifecycle_state, BossEncounterState.STATE_ABORTED, "abort leaves an explicit terminal state")
	asserts.equal(completion_calls.count, 0, "abort does not invoke dungeon completion")
	asserts.equal(boss.tick(1.0).reason, "encounter_not_active", "aborted encounter stops scheduling patterns")

func _summon_failure_keeps_pattern_retryable(asserts) -> void:
	var definition = BossDefinition.from_dictionary(_boss_row()).definition
	var calls := {"count": 0}
	var summons := []
	var runtime := BossEncounterRuntime.new()
	asserts.true_value(runtime.configure(
		definition,
		null,
		func(event: Dictionary) -> Dictionary:
			calls.count += 1
			summons.append(event.duplicate(true))
			if calls.count == 1:
				return {"ok": false, "reason": "spawn_capacity_full", "error": "fixture summon rejected"}
			return {"ok": true}
	).ok, "summon retry fixture configures")
	asserts.true_value(runtime.start("encounter_retry", "fixture_dungeon").ok, "summon retry boss starts")
	asserts.equal(runtime.tick(0.0).event.pattern_id, "opening_strike", "first non-summon pattern schedules")

	var rejected := runtime.tick(1.0)
	asserts.false_value(rejected.ok, "summon hook failure rejects the top-level tick")
	asserts.equal(rejected.reason, "summon_hook_rejected", "summon failure exposes stable reason")
	asserts.equal(rejected.pattern_id, "summon_bandit", "failure reports the rejected pattern")
	asserts.equal(runtime.to_projection().pattern_cursor, 1, "summon failure does not advance the pattern cursor")
	asserts.equal(runtime.to_projection().pattern_cooldown_remaining, 0.0, "summon failure does not commit cooldown")
	asserts.equal(calls.count, 1, "failed summon hook is attempted once")

	var retried := runtime.tick(0.0)
	asserts.true_value(retried.ok, "summon retry succeeds")
	asserts.equal(retried.event.pattern_id, "summon_bandit", "retry preserves deterministic pattern order")
	asserts.equal(runtime.to_projection().pattern_cursor, 2, "successful retry advances cursor exactly once")
	asserts.equal(calls.count, 2, "successful retry invokes summon once more")
	asserts.equal(summons.size(), 2, "only failed attempt and successful retry request summons")

func _boss_row() -> Dictionary:
	return {
		"id": "fixture_boss",
		"name": "Fixture Boss",
		"status": "테스트",
		"dungeon_id": "fixture_dungeon",
		"max_hp": 100,
		"phases": [
			{"id": "opening", "health_ratio_threshold": 1.0, "patterns": [
				{"id": "opening_strike", "interval_seconds": 1.0, "summon_monster_ids": []},
				{"id": "summon_bandit", "interval_seconds": 2.0, "summon_monster_ids": ["road_bandit"]}
			]},
			{"id": "desperate", "health_ratio_threshold": 0.5, "patterns": [
				{"id": "rapid_strike", "interval_seconds": 0.5, "summon_monster_ids": []}
			]}
		],
		"resolution_types": ["combat", "peaceful"],
		"reward_item_ids": ["humble_clay_bowl"],
		"progression_unlock_ids": ["common_region"]
	}

func _tea_resolution_config() -> Dictionary:
	return {
		"choice_id": "fixture_share_tea",
		"required_tea_ids": ["oribe_green_matcha"],
		"peaceful_conditions": [
			{"type": "prepared_tea", "id": "oribe_green_matcha"},
			{"type": "run_flag", "id": "met_boss"}
		],
		"hooks": {
			"common": {"memory": ["memory.fixture_boss.met"]},
			"combat_started": {"dialogue": ["dialogue.fixture_boss.combat_started"]}
		}
	}

func _dungeon_context() -> Dictionary:
	var run_state := RunState.new()
	var progression := BiomeProgressionState.new()
	progression.configure([
		{"id": "common_region", "progression_order": 1},
		{"id": "mountain_region", "progression_order": 2}
	], run_state)
	return {"run_state": run_state, "progression": progression, "dungeon": DungeonRuntime.new()}

func _return_context() -> Dictionary:
	return {"biome_id": "common_region", "world_seed": 11037}
