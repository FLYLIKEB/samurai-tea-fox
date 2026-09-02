extends RefCounted

const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const RunState = preload("res://src/save/run_state.gd")
const TradeService = preload("res://src/economy/trade_service.gd")

func run(asserts) -> void:
	_assert_buy_and_sell(asserts)
	_assert_failures_are_atomic(asserts)
	_assert_data_policies_and_deterministic_sell(asserts)
	_assert_definition_validation(asserts)
	_assert_run_state_round_trip(asserts)

func _assert_buy_and_sell(asserts) -> void:
	var service := _service()
	var inventory := _inventory(3)
	var state := RunState.new()
	state.currency = 30
	asserts.true_value(service.set_context("merchant", 0).ok, "trade context configures")
	var bought := service.buy("shop_bandage_early", 2, state, inventory)
	asserts.true_value(bought.ok, "normal purchase succeeds")
	asserts.equal(state.currency, 14, "purchase subtracts exact price")
	asserts.equal(inventory.get_total_quantity("bandage"), 2, "purchase grants exact quantity")
	asserts.equal(service.remaining_stock("shop_bandage_early", state), 3, "purchase persists stock delta")
	var sold := service.sell("bandage", 1, state, inventory)
	asserts.true_value(sold.ok, "normal sale succeeds")
	asserts.equal(state.currency, 18, "sale grants explicit sell price")
	asserts.equal(inventory.get_total_quantity("bandage"), 1, "sale removes exact quantity")

func _assert_failures_are_atomic(asserts) -> void:
	var service := _service()
	asserts.true_value(service.set_context("merchant", 0).ok, "failure fixture context configures")
	var inventory := _inventory(1)
	var state := RunState.new()
	state.currency = 7
	var before := inventory.to_snapshot()
	asserts.equal(service.buy("shop_bandage_early", 1, state, inventory).reason, "insufficient_currency", "insufficient balance blocks purchase")
	asserts.equal(state.currency, 7, "insufficient balance preserves currency")
	asserts.equal(inventory.to_snapshot(), before, "insufficient balance preserves inventory")
	state.currency = 100
	asserts.equal(service.buy("shop_bandage_early", 6, state, inventory).reason, "insufficient_stock", "insufficient stock blocks purchase")
	asserts.equal(service.remaining_stock("shop_bandage_early", state), 5, "stock failure preserves stock")
	asserts.true_value(inventory.add_item("stone", 1).ok, "fills only inventory slot")
	before = inventory.to_snapshot()
	var full := service.buy("shop_bandage_early", 1, state, inventory)
	asserts.equal(full.reason, "inventory_full", "full inventory blocks purchase")
	asserts.equal(state.currency, 100, "full inventory preserves currency")
	asserts.equal(inventory.to_snapshot(), before, "full inventory preserves contents")
	asserts.equal(service.remaining_stock("shop_bandage_early", state), 5, "full inventory preserves stock")
	asserts.equal(service.sell("bandage", 1, state, inventory).reason, "insufficient_quantity", "missing owned quantity blocks sale")
	asserts.equal(state.currency, 100, "failed sale preserves currency")

func _assert_data_policies_and_deterministic_sell(asserts) -> void:
	var service := _service()
	var inventory := _inventory(4)
	var state := RunState.new()
	state.currency = 0
	asserts.true_value(inventory.add_item("bandage", 3).ok, "sell fixture inventory populated")
	asserts.true_value(inventory.add_item("core_bowl", 1).ok, "policy fixture item populated")
	asserts.true_value(service.set_context("merchant", 0).ok, "early context configures")
	asserts.equal(service.sell("core_bowl", 1, state, inventory).reason, "not_sellable", "can_sell false blocks sale")
	asserts.equal(service.buy("shop_core", 1, state, inventory).reason, "not_buyable", "data-driven progression policy blocks purchase")
	asserts.equal(service.sell("stone", 1, state, inventory).reason, "not_sellable", "missing sale definition blocks sale")
	asserts.equal(service.buy("shop_bandage_late", 1, state, inventory).reason, "progress_locked", "minimum progress blocks purchase")
	asserts.true_value(service.set_context("merchant", 3).ok, "late context configures")
	var sold := service.sell("bandage", 1, state, inventory)
	asserts.equal(sold.definition_id, "shop_bandage_late", "highest eligible progress row deterministically sets sale definition")
	asserts.equal(state.currency, 5, "deterministic later row supplies explicit later sell price")
	state.currency = 998
	var before := inventory.to_snapshot()
	asserts.equal(service.sell("bandage", 1, state, inventory).reason, "currency_overflow", "currency cap blocks overflow")
	asserts.equal(state.currency, 998, "overflow preserves currency")
	asserts.equal(inventory.to_snapshot(), before, "overflow preserves inventory")

func _assert_definition_validation(asserts) -> void:
	var service := TradeService.new()
	for field in ["buy_price", "sell_price", "stock_quantity", "min_progress_stage"]:
		var row: Dictionary = _rows()[0].duplicate(true)
		row[field] = 1.5
		asserts.false_value(service.configure([row], 999).ok, "fractional %s is rejected" % field)
	var malformed: Dictionary = _rows()[0].duplicate(true)
	malformed.erase("buy_price")
	asserts.false_value(service.configure([malformed], 999).ok, "missing price is rejected")
	for invalid_price in [0, -1]:
		var row: Dictionary = _rows()[0].duplicate(true)
		row.buy_price = invalid_price
		asserts.false_value(service.configure([row], 999).ok, "non-positive buy price is rejected")
	var ambiguous: Dictionary = _rows()[0].duplicate(true)
	ambiguous.tea_id = "tea_8"
	asserts.equal(service.configure([ambiguous], 999).reason, "invalid_subject", "ambiguous subject is rejected")
	var missing_subject: Dictionary = _rows()[0].duplicate(true)
	missing_subject.erase("item_id")
	asserts.equal(service.configure([missing_subject], 999).reason, "invalid_subject", "missing subject is rejected")

func _assert_run_state_round_trip(asserts) -> void:
	var state := RunState.new()
	state.trade_stock = {"shop_bandage_early": 2}
	var loaded: RunState = RunState.from_dictionary(state.to_dictionary())
	asserts.equal(loaded.trade_stock, state.trade_stock, "RunState round trip preserves trade stock")
	asserts.equal(RunState.new().trade_stock, {}, "new run resets trade stock")

func _service() -> TradeService:
	var service := TradeService.new()
	var result := service.configure(_rows(), 999)
	assert(result.ok)
	return service

func _inventory(slot_count: int) -> InventoryModel:
	var inventory := InventoryModel.new()
	var result := inventory.configure(slot_count, {
		"bandage": {"id": "bandage", "name": "천 붕대", "kind": "소모품", "max_stack": 5, "requires_instance": false},
		"stone": {"id": "stone", "name": "돌", "kind": "재료", "max_stack": 1, "requires_instance": false},
		"core_bowl": {"id": "core_bowl", "name": "핵심 다구", "kind": "다구", "max_stack": 1, "requires_instance": false}
	})
	assert(result.ok)
	return inventory

func _rows() -> Array:
	return [
		{"id": "shop_bandage_early", "name": "초기 붕대", "status": "테스트", "seller_id": "merchant", "item_id": "bandage", "buy_price": 8, "can_sell": true, "sell_price": 4, "stock_quantity": 5, "min_progress_stage": 0, "unlock_condition": "start"},
		{"id": "shop_bandage_late", "name": "후기 붕대", "status": "테스트", "seller_id": "merchant", "item_id": "bandage", "buy_price": 10, "can_sell": true, "sell_price": 5, "stock_quantity": 6, "min_progress_stage": 3, "unlock_condition": "stage3"},
		{"id": "shop_core", "name": "핵심 진행 아이템", "status": "테스트", "seller_id": "merchant", "item_id": "core_bowl", "buy_price": 50, "can_buy": false, "can_sell": false, "sell_price": 25, "stock_quantity": 1, "min_progress_stage": 0, "unlock_condition": "never"}
	]
