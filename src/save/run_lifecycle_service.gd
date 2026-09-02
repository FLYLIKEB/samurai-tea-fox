extends RefCounted
class_name RunLifecycleService

const RunState = preload("res://src/save/run_state.gd")

const EFFECT_RESURRECTION := "resurrection"
const RAW_EFFECT_RESURRECTION := "부활"
const BALANCE_REVIVE_HP_RATIO_ID := "balance_24"
const BALANCE_INVULNERABILITY_SECONDS_ID := "balance_25"
const BALANCE_MAX_OWNED_ID := "balance_26"

var data_version := ""
var revive_hp_ratio := 0.0
var revive_invulnerability_seconds := 0.0
var max_resurrection_owned := 0
var resurrection_item_ids: Array[String] = []
var death_pending := false
var death_confirmed := false

static func from_catalog(catalog) -> Dictionary:
	var ratio_result := _required_positive_number_balance(catalog, BALANCE_REVIVE_HP_RATIO_ID)
	if not ratio_result.ok:
		return ratio_result
	var invulnerability_result := _required_non_negative_number_balance(catalog, BALANCE_INVULNERABILITY_SECONDS_ID)
	if not invulnerability_result.ok:
		return invulnerability_result
	var max_owned_result := _required_positive_integer_balance(catalog, BALANCE_MAX_OWNED_ID)
	if not max_owned_result.ok:
		return max_owned_result
	var item_ids := _resurrection_item_ids_from_catalog(catalog)
	if item_ids.is_empty():
		return _fail("missing_resurrection_item", "No data-defined resurrection item was found.")

	var service: RunLifecycleService = load("res://src/save/run_lifecycle_service.gd").new()
	service.data_version = _catalog_data_version(catalog)
	service.revive_hp_ratio = float(ratio_result.value)
	service.revive_invulnerability_seconds = float(invulnerability_result.value)
	service.max_resurrection_owned = int(max_owned_result.value)
	service.resurrection_item_ids = item_ids
	return {"ok": true, "run_lifecycle_service": service}

func resolve_lethal_hp(resources, inventory, combat_state = null, combat_id := "player") -> Dictionary:
	if resources == null or not resources.has_method("heal_hp"):
		return _fail("invalid_resources", "Run lifecycle requires player resources.")
	if int(resources.hp) > 0:
		death_pending = false
		return {"ok": true, "state": "alive", "death_pending": false}

	death_pending = true
	death_confirmed = false
	var item_id := _first_available_resurrection_item(inventory)
	if item_id.is_empty():
		return {"ok": true, "state": "death_pending", "death_pending": true, "resurrected": false}

	var remove_result: Dictionary = inventory.remove_item(item_id, 1)
	if not remove_result.ok:
		return remove_result
	var revive_hp := maxi(1, int(ceil(float(resources.hp_max) * revive_hp_ratio)))
	var healed := int(resources.heal_hp(revive_hp))
	if combat_state != null and combat_state.has_method("set_hit_invulnerable"):
		combat_state.set_hit_invulnerable(combat_id, revive_invulnerability_seconds)
	death_pending = false
	return {
		"ok": true,
		"state": "resurrected",
		"death_pending": false,
		"resurrected": true,
		"item_id": item_id,
		"consumed": true,
		"revive_hp": int(resources.hp),
		"hp_healed": healed,
		"invulnerability_seconds": revive_invulnerability_seconds
	}

func confirm_death(save_store = null, current_run_state = null) -> Dictionary:
	if not death_pending:
		return _fail("death_not_pending", "Death cannot be confirmed before a pending lethal state.")
	var invalidation := {"ok": true, "invalidated_lifecycle_epoch": 0}
	if save_store != null:
		if not save_store.has_method("invalidate_run"):
			return _fail("invalid_save_store", "Run lifecycle requires a save store with invalidate_run.")
		invalidation = save_store.invalidate_run(current_run_state)
		if not invalidation.ok:
			return invalidation
		if bool(invalidation.get("preserved_newer_run", false)):
			death_pending = false
			death_confirmed = false
			return {
				"ok": true,
				"state": "newer_run_preserved",
				"death_pending": false,
				"death_confirmed": false,
				"preserved_newer_run": true,
				"invalidated_lifecycle_epoch": int(invalidation.get("invalidated_lifecycle_epoch", 0)),
				"current_lifecycle_epoch": int(invalidation.get("current_lifecycle_epoch", 0)),
				"current_run_snapshot": invalidation.get("current_run_snapshot", {}),
				"current_run_state": invalidation.get("current_run_state")
			}
	death_pending = false
	death_confirmed = true
	return {
		"ok": true,
		"state": "death_confirmed",
		"death_pending": false,
		"death_confirmed": true,
		"invalidated_lifecycle_epoch": int(invalidation.get("invalidated_lifecycle_epoch", 0))
	}

func create_fresh_run_after_confirmed_death(invalidated_lifecycle_epoch: int, seed := 0) -> RunState:
	var state := RunState.new()
	state.data_version = data_version
	state.lifecycle_epoch = invalidated_lifecycle_epoch + 1
	state.seed = seed
	return state

func reset_for_new_run() -> void:
	death_pending = false
	death_confirmed = false

func _first_available_resurrection_item(inventory) -> String:
	if inventory == null or not inventory.has_method("get_total_quantity"):
		return ""
	for item_id in resurrection_item_ids:
		if int(inventory.get_total_quantity(item_id)) > 0:
			return item_id
	return ""

static func _resurrection_item_ids_from_catalog(catalog) -> Array[String]:
	var ids: Array[String] = []
	for row in _catalog_definitions(catalog, "items"):
		if _normalized_effect_type(row) == EFFECT_RESURRECTION:
			ids.append(String(row.get("id", "")))
	ids.sort()
	return ids

static func _normalized_effect_type(row: Dictionary) -> String:
	var raw := String(row.get("effect_type", row.get("effect", ""))).strip_edges()
	match raw:
		RAW_EFFECT_RESURRECTION, EFFECT_RESURRECTION:
			return EFFECT_RESURRECTION
		_:
			return raw

static func _required_positive_number_balance(catalog, id: String) -> Dictionary:
	var value_result := _required_number_balance(catalog, id)
	if not value_result.ok:
		return value_result
	if float(value_result.value) <= 0.0:
		return _fail("invalid_balance", "Run lifecycle balance must be positive: %s" % id)
	return value_result

static func _required_non_negative_number_balance(catalog, id: String) -> Dictionary:
	var value_result := _required_number_balance(catalog, id)
	if not value_result.ok:
		return value_result
	if float(value_result.value) < 0.0:
		return _fail("invalid_balance", "Run lifecycle balance must be non-negative: %s" % id)
	return value_result

static func _required_positive_integer_balance(catalog, id: String) -> Dictionary:
	var value_result := _required_positive_number_balance(catalog, id)
	if not value_result.ok:
		return value_result
	if float(value_result.value) != floor(float(value_result.value)):
		return _fail("invalid_balance", "Run lifecycle balance must be an integer: %s" % id)
	return {"ok": true, "value": int(value_result.value)}

static func _required_number_balance(catalog, id: String) -> Dictionary:
	if not catalog.has_method("find_by_id"):
		return _fail("invalid_catalog", "Catalog cannot look up balance values.")
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return _fail("missing_balance", "Missing required run lifecycle balance value: %s" % id)
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_balance", "Run lifecycle balance must be numeric: %s" % id)
	return {"ok": true, "value": float(value)}

static func _catalog_definitions(catalog, dataset: String) -> Array:
	if catalog.has_method("get_definitions"):
		return catalog.get_definitions(dataset)
	var raw_definitions = catalog.get("definitions") if catalog.has_method("get") else {}
	if typeof(raw_definitions) == TYPE_DICTIONARY:
		return raw_definitions.get(dataset, [])
	return []

static func _catalog_data_version(catalog) -> String:
	var value = catalog.get("data_version") if catalog.has_method("get") else ""
	return "" if value == null else String(value)

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
