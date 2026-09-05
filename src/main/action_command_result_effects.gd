extends RefCounted
class_name ActionCommandResultEffects

const GameCommand = preload("res://src/core/commands/game_command.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

var _sync_runtime_state: Callable
var _advance_time_for_turn: Callable
var _play_feedback_beep: Callable
var _queue_enemy_turn: Callable
var _play_sfx_event: Callable

func _init(sync_runtime_state: Callable, advance_time_for_turn: Callable, play_feedback_beep: Callable, queue_enemy_turn: Callable, play_sfx_event: Callable) -> void:
	_sync_runtime_state = sync_runtime_state
	_advance_time_for_turn = advance_time_for_turn
	_play_feedback_beep = play_feedback_beep
	_queue_enemy_turn = queue_enemy_turn
	_play_sfx_event = play_sfx_event

func apply(result: Dictionary) -> void:
	if result.is_empty():
		return
	var command = result.get("command")
	if bool(result.get("interact_failure_sfx", false)) and command is GameCommand:
		var target_id := String(command.payload.get("target_id", ""))
		_call(_play_sfx_event, [SfxEventRouter.EVENT_INTERACT_FAIL, {"target_id": target_id}, "interact_failed:%s" % target_id])
	if not bool(result.get("accepted", false)):
		return
	if bool(result.get("sync_tea_runtime", false)):
		_call(_sync_runtime_state)
	if bool(result.get("consumes_turn", false)):
		_call(_advance_time_for_turn)
	if bool(result.get("feedback_beep", false)):
		_call(_play_feedback_beep)
	if bool(result.get("queues_enemy_turn", false)):
		_call(_queue_enemy_turn)

func _call(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)
