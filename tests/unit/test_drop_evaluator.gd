extends RefCounted

const DropEvaluator = preload("res://src/enemy/drop_evaluator.gd")

func run(asserts) -> void:
	_assert_time_conditions(asserts)
	_assert_seed_reproducibility_and_quantity_bounds(asserts)
	_assert_probability_edges(asserts)

func _assert_time_conditions(asserts) -> void:
	var always := _grant({"condition": DropEvaluator.CONDITION_ALWAYS})
	asserts.true_value(DropEvaluator.evaluate(always, _context(1, "always", "dusk")).included, "always drops ignore the current time phase")

	var day := _grant({"condition": DropEvaluator.CONDITION_DAY})
	asserts.true_value(DropEvaluator.evaluate(day, _context(1, "day", "day")).included, "day drops match the day phase")
	asserts.false_value(DropEvaluator.evaluate(day, _context(1, "dusk", "dusk")).included, "day drops do not match dusk")
	asserts.false_value(DropEvaluator.evaluate(day, _context(1, "night", "night")).included, "day drops do not match night")

	var night := _grant({"condition": DropEvaluator.CONDITION_NIGHT})
	asserts.true_value(DropEvaluator.evaluate(night, _context(1, "night", "night")).included, "night drops match the night phase")
	asserts.true_value(DropEvaluator.evaluate(night, _context(1, "late", "late_night")).included, "night drops match late night")
	asserts.false_value(DropEvaluator.evaluate(night, _context(1, "day", "day")).included, "night drops do not match day")

	var unsupported := _grant({"condition": "비"})
	var rejected: Dictionary = DropEvaluator.evaluate(unsupported, _context(1, "rain", "day"))
	asserts.false_value(rejected.ok, "unknown drop conditions are rejected")
	asserts.equal(rejected.reason, "unsupported_drop_condition", "unknown conditions expose a stable reason")

func _assert_seed_reproducibility_and_quantity_bounds(asserts) -> void:
	var grant := _grant({"min_quantity": 2, "max_quantity": 6, "chance": 0.65})
	var context := _context(9173, "enemy_0042", "day")
	var first: Dictionary = DropEvaluator.evaluate(grant, context)
	var replay: Dictionary = DropEvaluator.evaluate(grant, context)
	asserts.equal(replay, first, "same run seed and request identity reproduce the complete drop result")

	for seed in range(1, 129):
		var result: Dictionary = DropEvaluator.evaluate(grant, _context(seed, "enemy_0042", "day"))
		asserts.true_value(result.ok, "seeded drop evaluation succeeds")
		if result.included:
			asserts.true_value(int(result.grant.quantity) >= 2 and int(result.grant.quantity) <= 6, "seeded quantity remains inside the definition range")

func _assert_probability_edges(asserts) -> void:
	var never := _grant({"chance": 0.0})
	asserts.false_value(DropEvaluator.evaluate(never, _context(3, "never", "day")).included, "zero chance never grants")
	var always := _grant({"chance": 1.0})
	asserts.true_value(DropEvaluator.evaluate(always, _context(3, "always", "day")).included, "unit chance always grants")

func _grant(overrides := {}) -> Dictionary:
	var grant := {
		"drop_id": "drop_fixture",
		"item_id": "item_fixture",
		"min_quantity": 1,
		"max_quantity": 1,
		"chance": 1.0,
		"condition": DropEvaluator.CONDITION_ALWAYS,
		"policy": "direct"
	}
	for key in overrides:
		grant[key] = overrides[key]
	return grant

func _context(run_seed: int, request_id: String, time_phase: String) -> Dictionary:
	return {"run_seed": run_seed, "request_id": request_id, "time_phase": time_phase}
