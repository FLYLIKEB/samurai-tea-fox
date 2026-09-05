extends RefCounted
class_name NarrativeSession

const GameCommand = preload("res://src/core/commands/game_command.gd")
const NarrativeRuntime = preload("res://src/narrative/narrative_runtime.gd")
const RunState = preload("res://src/save/run_state.gd")

const FIRST_RUN_PROLOGUE_EVENT_ID := "first_run_prologue"

var active_event_id := ""
var active_node_id := ""

func reset() -> void:
	active_event_id = ""
	active_node_id = ""

func first_run_prologue_read_model(narrative_runtime, run_state, meta_state = null, force_first_run := false) -> Dictionary:
	if narrative_runtime == null:
		return {"ok": false, "reason": "missing_narrative_runtime", "error": "Narrative runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	var meta = meta_state if meta_state != null else {}
	if not force_first_run and int(meta.get("run_count", 0)) != 0:
		return {"ok": false, "reason": "not_first_run", "error": "First-run prologue only opens before any completed run."}
	return narrative_runtime.read_model_for_event(FIRST_RUN_PROLOGUE_EVENT_ID, run_state, meta)

func start_run_event_read_model(narrative_runtime, run_start_event_selector, run_state, meta_state = null, force_first_run := false) -> Dictionary:
	if narrative_runtime == null or run_start_event_selector == null:
		return {"ok": false, "reason": "missing_narrative_runtime", "error": "Run-start narrative runtime is not configured."}
	if run_state == null:
		run_state = RunState.new()
	var meta = meta_state if meta_state != null else {}
	var selected: Dictionary = run_start_event_selector.select_event(run_state, meta, force_first_run)
	if not selected.ok:
		return selected
	var model_result: Dictionary = narrative_runtime.read_model_for_event(String(selected.event_id), run_state, meta)
	if not model_result.ok:
		return model_result
	model_result.read_model["presentation_kind"] = String(selected.get("presentation_kind", "dialogue"))
	model_result.read_model["father_physical_actor"] = bool(selected.get("father_physical_actor", false))
	model_result.read_model["meta_run_count"] = int(selected.get("meta_run_count", 0))
	return model_result

func begin_read_model(read_model: Dictionary) -> void:
	active_event_id = String(read_model.get("event_id", ""))
	active_node_id = String(read_model.get("node_id", ""))

func select_option(command: GameCommand, narrative_runtime, run_state, meta_state = null) -> Dictionary:
	if narrative_runtime == null or run_state == null:
		return {"ok": false, "handled": false, "reason": "missing_narrative_runtime"}
	var event_id := String(command.payload.get("event_id", active_event_id))
	var node_id := String(command.payload.get("node_id", active_node_id))
	var option_id := String(command.payload.get("option_id", ""))
	if event_id.is_empty() or node_id.is_empty() or option_id.is_empty():
		return {"ok": false, "handled": false, "reason": "missing_narrative_option"}
	var result: Dictionary = narrative_runtime.select_option(event_id, node_id, option_id, run_state, meta_state)
	if not result.ok:
		return {"ok": false, "handled": false, "reason": String(result.get("reason", "narrative_selection_failed")), "result": result}
	apply_result_commands(result.get("commands", []), run_state)
	result["ok"] = true
	result["handled"] = true
	result["event_id"] = event_id
	return result

func apply_result_commands(commands: Array, run_state) -> void:
	if run_state == null:
		return
	for command in commands:
		if not command is GameCommand or command.type != GameCommand.Type.NARRATIVE_RESULT:
			continue
		var result: Dictionary = command.payload.get("result", {})
		if String(result.get("type", "")) == NarrativeRuntime.RESULT_SET_RUN_FLAG:
			var flag_id := String(result.get("id", ""))
			if not flag_id.is_empty() and not run_state.narrative_flags.has(flag_id):
				run_state.narrative_flags.append(flag_id)

func start_memory_tea_cutscene(memory_tea_cutscene_runtime, drink_result: Dictionary, run_state, meta_state = null) -> Dictionary:
	if memory_tea_cutscene_runtime == null:
		return {"ok": false, "reason": "missing_memory_cutscene_runtime", "error": "Memory tea cutscene runtime is not configured."}
	var result: Dictionary = memory_tea_cutscene_runtime.start_from_drink_completion(drink_result, run_state, meta_state)
	if result.ok and bool(result.get("started", false)):
		_sync_memory_snapshot(memory_tea_cutscene_runtime, result, run_state)
	return result

func complete_memory_tea_cutscene(memory_tea_cutscene_runtime, run_state, meta_state = null) -> Dictionary:
	if memory_tea_cutscene_runtime == null:
		return {"ok": false, "reason": "missing_memory_cutscene_runtime", "error": "Memory tea cutscene runtime is not configured."}
	var result: Dictionary = memory_tea_cutscene_runtime.complete_current(run_state, meta_state)
	_sync_memory_snapshot(memory_tea_cutscene_runtime, result, run_state)
	return result

func skip_memory_tea_cutscene(memory_tea_cutscene_runtime, run_state, meta_state = null) -> Dictionary:
	if memory_tea_cutscene_runtime == null:
		return {"ok": false, "reason": "missing_memory_cutscene_runtime", "error": "Memory tea cutscene runtime is not configured."}
	var result: Dictionary = memory_tea_cutscene_runtime.skip_current(run_state, meta_state)
	_sync_memory_snapshot(memory_tea_cutscene_runtime, result, run_state)
	return result

func _sync_memory_snapshot(memory_tea_cutscene_runtime, result: Dictionary, run_state) -> void:
	if result.ok and run_state != null:
		run_state.memory_tea_cutscene = memory_tea_cutscene_runtime.to_snapshot()
