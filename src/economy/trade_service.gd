extends RefCounted
class_name TradeService

const CURRENCY_MAX_STACK_ID := "currency_max_stack"

var definitions: Dictionary = {}
var sell_definitions: Dictionary = {}
var currency_max := 0
var seller_id := ""
var progress_stage := 0

static func from_catalog(catalog) -> Dictionary:
	var service: TradeService = load("res://src/economy/trade_service.gd").new()
	var result := service.configure(catalog.get_definitions("shops"), int(catalog.find_balance_value(CURRENCY_MAX_STACK_ID, 0)))
	if not result.ok:
		return result
	return {"ok": true, "service": service}

func configure(rows: Array, maximum_currency: int) -> Dictionary:
	if maximum_currency <= 0:
		return _failure("invalid_currency_limit", "Currency maximum must be a positive integer.")
	var normalized: Dictionary = {}
	for row in rows:
		var result := _validate_definition(row)
		if not result.ok:
			return result
		if normalized.has(row.id):
			return _failure("duplicate_definition", "Duplicate trade definition: %s" % row.id)
		normalized[row.id] = row.duplicate(true)
	definitions = normalized
	currency_max = maximum_currency
	_rebuild_sell_definitions()
	return {"ok": true}

func set_context(new_seller_id: String, new_progress_stage: int) -> Dictionary:
	if new_seller_id.is_empty() or new_progress_stage < 0:
		return _failure("invalid_context", "Trade context requires a seller and non-negative progress stage.")
	seller_id = new_seller_id
	progress_stage = new_progress_stage
	_rebuild_sell_definitions()
	return {"ok": true}

func buy(definition_id: String, quantity: int, run_state, inventory) -> Dictionary:
	var currency_result := _validate_currency(run_state)
	if not currency_result.ok:
		return currency_result
	if quantity <= 0:
		return _failure("invalid_quantity", "Quantity must be positive.")
	if not definitions.has(definition_id):
		return _failure("unknown_definition", "Unknown trade definition: %s" % definition_id)
	var definition: Dictionary = definitions[definition_id]
	if not bool(definition.get("can_buy", true)):
		return _failure("not_buyable", "Trade definition cannot be purchased.")
	var policy := _check_context(definition)
	if not policy.ok:
		return policy
	var total := int(definition.buy_price) * quantity
	if int(run_state.currency) < total:
		return _failure("insufficient_currency", "Not enough currency.")
	var remaining := _remaining_stock(definition, run_state)
	if remaining < quantity:
		return _failure("insufficient_stock", "Not enough shop stock.")
	var added: Dictionary = inventory.add_item(_subject_id(definition), quantity)
	if not added.ok:
		return added
	run_state.currency = int(run_state.currency) - total
	run_state.trade_stock[definition_id] = remaining - quantity
	return {"ok": true, "definition_id": definition_id, "quantity": quantity, "currency_delta": -total}

func sell(subject_id: String, quantity: int, run_state, inventory) -> Dictionary:
	var currency_result := _validate_currency(run_state)
	if not currency_result.ok:
		return currency_result
	if quantity <= 0:
		return _failure("invalid_quantity", "Quantity must be positive.")
	var definition := _sell_definition_for(subject_id)
	if definition.is_empty():
		return _failure("not_sellable", "No sellable trade definition for subject: %s" % subject_id)
	if inventory.get_total_quantity(subject_id) < quantity:
		return _failure("insufficient_quantity", "Not enough inventory quantity.")
	var total := int(definition.sell_price) * quantity
	if int(run_state.currency) + total > currency_max:
		return _failure("currency_overflow", "Currency maximum would be exceeded.")
	var removed: Dictionary = inventory.remove_item(subject_id, quantity)
	if not removed.ok:
		return removed
	run_state.currency = int(run_state.currency) + total
	return {"ok": true, "definition_id": definition.id, "quantity": quantity, "currency_delta": total}

func remaining_stock(definition_id: String, run_state) -> int:
	if not definitions.has(definition_id):
		return -1
	return _remaining_stock(definitions[definition_id], run_state)

func _validate_definition(row) -> Dictionary:
	if typeof(row) != TYPE_DICTIONARY:
		return _failure("invalid_definition", "Trade definition must be a dictionary.")
	for field in ["id", "seller_id", "buy_price", "can_sell", "sell_price", "stock_quantity", "min_progress_stage", "unlock_condition", "status"]:
		if not row.has(field) or row[field] == null:
			return _failure("invalid_definition", "Trade definition '%s' is missing '%s'." % [row.get("id", ""), field])
	var has_item := not String(row.get("item_id", "")).is_empty()
	var has_tea := not String(row.get("tea_id", "")).is_empty()
	if has_item == has_tea:
		return _failure("invalid_subject", "Trade definition requires exactly one item or tea subject.")
	if typeof(row.can_sell) != TYPE_BOOL:
		return _failure("invalid_can_sell", "can_sell must be a boolean.")
	for field in ["buy_price", "sell_price", "stock_quantity", "min_progress_stage"]:
		var value = row[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)):
			return _failure("invalid_number", "Trade field '%s' must be an integer." % field)
	if int(row.buy_price) <= 0 or int(row.sell_price) <= 0 or int(row.stock_quantity) < 0 or int(row.min_progress_stage) < 0:
		return _failure("invalid_number", "Trade prices must be positive and stock/progress non-negative.")
	return {"ok": true}

func _check_context(definition: Dictionary) -> Dictionary:
	if not seller_id.is_empty() and definition.seller_id != seller_id:
		return _failure("wrong_seller", "Trade definition belongs to another seller.")
	if progress_stage < int(definition.min_progress_stage):
		return _failure("progress_locked", "Trade definition is not unlocked at this progress stage.")
	return {"ok": true}

func _remaining_stock(definition: Dictionary, run_state) -> int:
	return int(run_state.trade_stock.get(definition.id, definition.stock_quantity))

func _validate_currency(run_state) -> Dictionary:
	var current := int(run_state.currency)
	if current < 0 or current > currency_max:
		return _failure("invalid_currency", "Currency is outside the configured range.")
	return {"ok": true}

func _rebuild_sell_definitions() -> void:
	sell_definitions.clear()
	for definition in definitions.values():
		if not bool(definition.can_sell):
			continue
		if not seller_id.is_empty() and definition.seller_id != seller_id:
			continue
		if int(definition.min_progress_stage) > progress_stage:
			continue
		var subject_id := _subject_id(definition)
		var current: Dictionary = sell_definitions.get(subject_id, {})
		if current.is_empty() or int(definition.min_progress_stage) > int(current.min_progress_stage) or (int(definition.min_progress_stage) == int(current.min_progress_stage) and String(definition.id) < String(current.id)):
			sell_definitions[subject_id] = definition

func _sell_definition_for(subject_id: String) -> Dictionary:
	return sell_definitions.get(subject_id, {})

func _subject_id(definition: Dictionary) -> String:
	return String(definition.get("item_id", definition.get("tea_id", "")))

func _failure(reason: String, error: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}
