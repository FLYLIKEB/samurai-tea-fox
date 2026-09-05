extends RefCounted
class_name DungeonCommandCoordinator

const DungeonInstanceState = preload("res://src/dungeon/dungeon_instance_state.gd")

var _debug: Callable
var _ensure_playable_runtime: Callable
var _ensure_current_entered: Callable
var _runtime_is_active: Callable
var _restore_map_from_runtime: Callable
var _completion_objective_met: Callable
var _sync_runtime_save_state: Callable
var _return_from_map: Callable
var _save_current_run: Callable
var _configure_game_hud: Callable

func _init(
		debug: Callable,
		ensure_playable_runtime: Callable,
		ensure_current_entered: Callable,
		runtime_is_active: Callable,
		restore_map_from_runtime: Callable,
		completion_objective_met: Callable,
		sync_runtime_save_state: Callable,
		return_from_map: Callable,
		save_current_run: Callable,
		configure_game_hud: Callable
) -> void:
	_debug = debug
	_ensure_playable_runtime = ensure_playable_runtime
	_ensure_current_entered = ensure_current_entered
	_runtime_is_active = runtime_is_active
	_restore_map_from_runtime = restore_map_from_runtime
	_completion_objective_met = completion_objective_met
	_sync_runtime_save_state = sync_runtime_save_state
	_return_from_map = return_from_map
	_save_current_run = save_current_run
	_configure_game_hud = configure_game_hud

func handle_complete_dungeon_command(command, dungeon_runtime, run_state, in_dungeon_map: bool, game_hud) -> bool:
	_log("던전 입장 명령 시작")
	var runtime_result: Dictionary = _call_dictionary(_ensure_playable_runtime)
	_log("런타임 준비 결과: ok=%s reason=%s" % [runtime_result.get("ok", false), runtime_result.get("reason", "")])
	if not runtime_result.ok:
		_log("던전 런타임 준비 실패: %s" % runtime_result)
		return false
	var previous_projection: Dictionary = dungeon_runtime.to_projection()
	var entered_result: Dictionary = _call_dictionary(_ensure_current_entered)
	_log("입장 시도 결과: ok=%s reason=%s in_dungeon=%s" % [entered_result.get("ok", false), entered_result.get("reason", ""), in_dungeon_map])
	if not entered_result.ok and String(entered_result.get("reason", "")) != "dungeon_already_active":
		_log("던전 입장 실패: %s" % entered_result)
		return false
	if bool(_call_value(_runtime_is_active, false)) and not in_dungeon_map:
		_log("활성 던전 화면 복원: runtime=active map=false")
		_call_void(_restore_map_from_runtime)
	if bool(command.payload.get("entry_only", false)):
		_save_and_refresh()
		_show_dungeon_entered(game_hud, dungeon_runtime, run_state)
		_log("입구 상호작용은 입장만 처리: in_dungeon=%s" % in_dungeon_map)
		return true
	if String(previous_projection.get("lifecycle_state", DungeonInstanceState.STATE_OUTSIDE)) in [DungeonInstanceState.STATE_OUTSIDE, DungeonInstanceState.STATE_RETURNED] \
			and not bool(_call_value(_completion_objective_met, false, [command.payload])):
		_log("입장만 처리(완료 조건 미충족)")
		_save_and_refresh()
		if game_hud != null:
			game_hud.show_command_feedback("던전 입장")
		_show_dungeon_entered(game_hud, dungeon_runtime, run_state)
		return true

	var payload: Dictionary = command.payload.duplicate(true)
	_apply_default_completion_payload(payload, run_state)
	_call_void(_sync_runtime_save_state)
	var completed: Dictionary = dungeon_runtime.complete_dungeon(payload)
	if not completed.ok:
		return false
	dungeon_runtime.begin_return()
	dungeon_runtime.finish_return()
	_call_void(_return_from_map)
	_save_and_refresh()
	return true

func _apply_default_completion_payload(payload: Dictionary, run_state) -> void:
	if String(payload.get("resolution_type", "")).is_empty():
		payload["resolution_type"] = "combat"
	if String(payload.get("choice_key", "")).is_empty():
		payload["choice_key"] = "dev17_minimal_clear"
	if String(payload.get("run_flag", "")).is_empty():
		payload["run_flag"] = "dev17_common_dungeon_clear"
	if not payload.has("reward_item_ids"):
		payload["reward_item_ids"] = []
	if not payload.has("progression_unlock_ids"):
		payload["progression_unlock_ids"] = [String(run_state.current_biome_id)]

func _show_dungeon_entered(game_hud, dungeon_runtime, run_state) -> void:
	if game_hud == null:
		return
	game_hud.show_status_event({
		"type": "dungeon_entered",
		"ok": true,
		"dungeon_id": String(dungeon_runtime.to_projection().get("dungeon_id", "")),
		"event_id": "entry:%s" % String(run_state.current_biome_id)
	})

func _save_and_refresh() -> void:
	_call_void(_save_current_run)
	_call_void(_configure_game_hud)

func _log(message: String) -> void:
	_call_void(_debug, [message])

func _call_dictionary(callback: Callable, arguments := []) -> Dictionary:
	var result = _call_value(callback, {}, arguments)
	return result if typeof(result) == TYPE_DICTIONARY else {}

func _call_void(callback: Callable, arguments := []) -> void:
	if callback.is_valid():
		callback.callv(arguments)

func _call_value(callback: Callable, default_value = null, arguments := []):
	if not callback.is_valid():
		return default_value
	return callback.callv(arguments)
