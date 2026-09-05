extends RefCounted

const ActionCommandResultEffects = preload("res://src/main/action_command_result_effects.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

var calls := []

func run(asserts) -> void:
	_assert_applies_effects_in_command_result_order(asserts)
	_assert_rejected_interact_keeps_failure_sfx_evidence(asserts)

func _assert_applies_effects_in_command_result_order(asserts) -> void:
	calls.clear()
	var effects := ActionCommandResultEffects.new(
		Callable(self, "_sync"),
		Callable(self, "_advance"),
		Callable(self, "_beep"),
		Callable(self, "_queue"),
		Callable(self, "_sfx")
	)

	effects.apply({
		"accepted": true,
		"sync_tea_runtime": true,
		"consumes_turn": true,
		"feedback_beep": true,
		"queues_enemy_turn": true,
		"command": GameCommand.new(GameCommand.Type.CAST_ABILITY)
	})

	asserts.equal(calls, ["sync", "advance", "beep", "queue"], "command effects preserve Main's result application order")

func _assert_rejected_interact_keeps_failure_sfx_evidence(asserts) -> void:
	calls.clear()
	var effects := ActionCommandResultEffects.new(
		Callable(self, "_sync"),
		Callable(self, "_advance"),
		Callable(self, "_beep"),
		Callable(self, "_queue"),
		Callable(self, "_sfx")
	)

	effects.apply({
		"accepted": false,
		"interact_failure_sfx": true,
		"command": GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": "missing_resource"})
	})

	asserts.equal(calls, [{
		"event_id": SfxEventRouter.EVENT_INTERACT_FAIL,
		"payload": {"target_id": "missing_resource"},
		"dedupe_key": "interact_failed:missing_resource"
	}], "rejected interactions still route failure SFX before returning")

func _sync() -> void:
	calls.append("sync")

func _advance() -> void:
	calls.append("advance")

func _beep() -> void:
	calls.append("beep")

func _queue() -> void:
	calls.append("queue")

func _sfx(event_id: String, payload := {}, dedupe_key := "") -> void:
	calls.append({
		"event_id": event_id,
		"payload": payload.duplicate(true),
		"dedupe_key": dedupe_key
	})
