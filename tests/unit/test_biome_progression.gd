extends RefCounted

const BiomeProgressionState = preload("res://src/world/biome/biome_progression_state.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	_progression_commands_and_order(asserts)
	_run_reset_clears_progression(asserts)
	_invalid_definition_order_is_rejected(asserts)

func _progression_commands_and_order(asserts) -> void:
	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "biome progression loads generated definitions")
	var run_state := RunState.new()
	var result: Dictionary = BiomeProgressionState.from_catalog(catalog, run_state)
	asserts.true_value(result.ok, "biome progression configures from catalog")
	if not result.ok:
		return
	var progression: BiomeProgressionState = result.progression_state

	asserts.equal(progression.current_biome_id(), "common_region", "lowest progression order starts the run")
	asserts.equal(progression.teleport_state_for("common_region"), BiomeProgressionState.TELEPORT_BROKEN, "current biome teleport starts broken")
	asserts.equal(progression.teleport_state_for("mountain_region"), BiomeProgressionState.TELEPORT_UNDISCOVERED, "future biome teleport starts undiscovered")

	var early_repair := progression.apply_command(GameCommand.new(GameCommand.Type.REPAIR_TELEPORT, Vector2i.ZERO, -1, {"biome_id": "common_region"}))
	asserts.false_value(early_repair.ok, "repair before dungeon completion is rejected")
	asserts.equal(early_repair.reason, "dungeon_incomplete", "early repair reports dungeon prerequisite")
	var early_advance := progression.advance_biome("common_region")
	asserts.false_value(early_advance.ok, "advance before teleport repair is rejected")
	asserts.equal(early_advance.reason, "teleport_not_repaired", "early advance reports teleport prerequisite")

	var wrong_order := progression.complete_dungeon("mountain_region")
	asserts.false_value(wrong_order.ok, "future biome completion is rejected")
	asserts.equal(wrong_order.reason, "invalid_biome_order", "future biome event reports invalid order")

	var completed := progression.apply_command(GameCommand.new(GameCommand.Type.COMPLETE_DUNGEON, Vector2i.ZERO, -1, {"biome_id": "common_region"}))
	asserts.true_value(completed.ok, "dungeon completion command is accepted")
	asserts.equal(progression.teleport_state_for("common_region"), BiomeProgressionState.TELEPORT_REPAIRABLE, "dungeon completion makes teleport repairable")
	asserts.equal(progression.crafting_context().unlocked_biome_ids, ["common_region"], "dungeon completion grants current-run crafting unlock")
	asserts.false_value(progression.complete_dungeon("common_region").ok, "duplicate dungeon completion is rejected")

	asserts.true_value(progression.apply_command(GameCommand.new(GameCommand.Type.REPAIR_TELEPORT, Vector2i.ZERO, -1, {"biome_id": "common_region"})).ok, "repair after completion is accepted")
	asserts.equal(progression.teleport_state_for("common_region"), BiomeProgressionState.TELEPORT_REPAIRED, "successful repair records repaired state")
	asserts.true_value(progression.can_advance_biome(), "repaired current teleport satisfies next-biome condition")
	var duplicate_repair := progression.repair_teleport("common_region")
	asserts.false_value(duplicate_repair.ok, "duplicate teleport repair is rejected")
	asserts.equal(duplicate_repair.reason, "duplicate_repair", "duplicate repair has stable reason")

	asserts.true_value(progression.apply_command(GameCommand.new(GameCommand.Type.ADVANCE_BIOME, Vector2i.ZERO, -1, {"biome_id": "common_region"})).ok, "advance command enters next ordered biome")
	asserts.equal(progression.current_biome_id(), "mountain_region", "advance uses definition progression order")
	asserts.equal(progression.teleport_state_for("mountain_region"), BiomeProgressionState.TELEPORT_BROKEN, "new current biome teleport is discovered broken")
	asserts.false_value(progression.advance_biome("common_region").ok, "advancing an old biome is rejected")

func _run_reset_clears_progression(asserts) -> void:
	var run_state := RunState.new()
	var progression := BiomeProgressionState.new()
	asserts.true_value(progression.configure(_fixture_biomes(), run_state).ok, "fixture progression configures")
	progression.complete_dungeon("first")
	progression.repair_teleport("first")
	progression.advance_biome("first")
	progression.reset_run()

	asserts.equal(run_state.current_biome_id, "first", "run reset returns to first ordered biome")
	asserts.equal(run_state.completed_dungeon_ids, [], "run reset clears dungeon completion")
	asserts.equal(run_state.repaired_teleports, [], "run reset clears repaired teleports")
	asserts.equal(run_state.crafting_unlocks, [], "run reset clears crafting unlocks")
	asserts.equal(run_state.teleport_states, {"first": "broken", "second": "undiscovered"}, "run reset restores initial teleport states")

func _invalid_definition_order_is_rejected(asserts) -> void:
	var progression := BiomeProgressionState.new()
	var duplicate_order := progression.configure([
		{"id": "first", "progression_order": 1},
		{"id": "second", "progression_order": 1}
	])
	asserts.false_value(duplicate_order.ok, "duplicate biome progression order is rejected")
	asserts.equal(duplicate_order.reason, "duplicate_progression_order", "duplicate definition order has stable reason")

func _fixture_biomes() -> Array:
	return [
		{"id": "second", "progression_order": 2},
		{"id": "first", "progression_order": 1}
	]
