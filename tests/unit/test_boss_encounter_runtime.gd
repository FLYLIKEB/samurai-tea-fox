extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const BossDefinition = preload("res://src/boss/boss_definition.gd")
const BossEncounterRuntime = preload("res://src/boss/boss_encounter_runtime.gd")
const BossEncounterState = preload("res://src/boss/boss_encounter_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const DungeonRuntime = preload("res://src/dungeon/dungeon_runtime.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	_definition_loader_and_samples(asserts)
	_deterministic_phases_patterns_and_summons(asserts)
	_combat_resolution_completes_dungeon_once(asserts)
	_peaceful_resolution_uses_common_contract(asserts)
	_abort_does_not_complete_dungeon(asserts)

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
