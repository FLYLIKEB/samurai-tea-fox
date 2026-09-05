extends RefCounted
## 차·소모품의 진행 상태와 완료 효과 순서를 조정한다.
## 서비스와 자원은 매 호출에 전달하여 새 런/저장 복원 후에도 현재 객체를 사용한다.

const GameCommand = preload("res://src/core/commands/game_command.gd")

var active_tea_drink_action: Dictionary = {}
var _snapshot: Callable
var _save: Callable
var _refresh_hud: Callable
var _advance_turn: Callable
var _queue_enemy_turn: Callable

func _init(snapshot: Callable, save: Callable, refresh_hud: Callable, advance_turn: Callable, queue_enemy_turn: Callable) -> void:
	_snapshot = snapshot
	_save = save
	_refresh_hud = refresh_hud
	_advance_turn = advance_turn
	_queue_enemy_turn = queue_enemy_turn

func start_tea(command: GameCommand, tea_service, player_resources) -> bool:
	if tea_service == null or not active_tea_drink_action.is_empty():
		return false
	var conditions := {}
	if player_resources != null:
		conditions["low_kokoro"] = player_resources.is_kokoro_low()
	var start_result: Dictionary = tea_service.start_drinking(maxi(command.slot, 0), {"conditions": conditions})
	if not start_result.ok:
		return false
	active_tea_drink_action = start_result.action
	return true

func is_tea_drink_active() -> bool:
	return not active_tea_drink_action.is_empty()

func tick_tea(delta_seconds: float, tea_service, resources) -> Dictionary:
	if tea_service == null:
		return {"ok": true, "changed": false}
	var effect_tick: Dictionary = tea_service.tick_effects(delta_seconds, resources)
	if not effect_tick.ok:
		return effect_tick
	var changed := bool(effect_tick.get("changed", false))
	var drink_completed := false
	if not active_tea_drink_action.is_empty():
		var drink_tick: Dictionary = tea_service.tick_drinking(active_tea_drink_action, delta_seconds, resources)
		if not drink_tick.ok:
			return drink_tick
		if bool(drink_tick.get("consumed", false)):
			active_tea_drink_action = {}
			changed = true
			drink_completed = true
		else:
			active_tea_drink_action = drink_tick.action
	if changed:
		_snapshot.call()
	if drink_completed:
		_save.call()
		_refresh_hud.call()
	return {"ok": true, "changed": changed, "active": is_tea_drink_active()}

func is_consumable_use_active(consumable_service) -> bool:
	return consumable_service != null \
		and consumable_service.has_method("has_active_use") \
		and consumable_service.has_active_use()

func tick_consumable(delta_seconds: float, consumable_service, inventory, resources) -> Dictionary:
	if consumable_service == null or not is_consumable_use_active(consumable_service):
		return {"ok": true, "changed": false, "active": false}
	if inventory == null or resources == null:
		return {"ok": false, "reason": "consumable_runtime_unavailable", "error": "Consumable use requires inventory and player resources."}
	var result: Dictionary = consumable_service.tick_use(delta_seconds, inventory, resources)
	if not result.ok:
		if String(result.get("reason", "")) != "invalid_delta":
			var interrupt_result: Dictionary = interrupt_consumable(consumable_service, "failed_%s" % String(result.get("reason", "unknown")))
			result["interrupted"] = bool(interrupt_result.get("interrupted", false))
		return result
	if bool(result.get("consumed", false)):
		_advance_turn.call()
		_queue_enemy_turn.call()
		_refresh_hud.call()
		_save.call()
	return {
		"ok": true,
		"changed": true,
		"active": is_consumable_use_active(consumable_service),
		"completed": bool(result.get("consumed", false)),
		"result": result
	}

func interrupt_consumable(consumable_service, reason := "hit") -> Dictionary:
	if consumable_service == null or not is_consumable_use_active(consumable_service):
		return {"ok": true, "interrupted": false}
	var result: Dictionary = consumable_service.interrupt_use(reason)
	if not result.ok:
		return result
	_snapshot.call()
	_save.call()
	_refresh_hud.call()
	return {"ok": true, "interrupted": true, "result": result}

func start_consumable(item_id: String, context: Dictionary, consumable_service, inventory) -> Dictionary:
	if consumable_service == null or inventory == null:
		return {"ok": false, "reason": "missing_consumable_runtime", "error": "Consumable runtime is not configured."}
	var start: Dictionary = consumable_service.start_use(item_id, inventory, context)
	if not start.ok:
		return start
	_snapshot.call()
	_save.call()
	_refresh_hud.call()
	return start

func consumable_item_id_for_command(command: GameCommand, consumable_service, inventory) -> String:
	var requested := String(command.payload.get("item_id", ""))
	if not requested.is_empty():
		return requested if consumable_service.has_definition(requested) and inventory.get_total_quantity(requested) > 0 else ""
	var slots = inventory.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		return ""
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var item_id := String(slot.get("item_id", ""))
		if not item_id.is_empty() and int(slot.get("quantity", 0)) > 0 and consumable_service.has_definition(item_id):
			return item_id
	return ""
