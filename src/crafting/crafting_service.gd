extends RefCounted
class_name CraftingService

signal operation_failed(error: Dictionary)
signal craft_completed(result: Dictionary)

const RECIPE_SOURCE := "recipes"
const ITEM_SOURCE := "items"
const TEA_SOURCE := "teas"
const HANDCRAFT_LABELS := {
	"": true,
	"손제작": true,
	"handcraft": true
}

var data_version := ""
var recipe_definitions: Dictionary = {}
var item_definitions: Dictionary = {}
var item_name_to_id: Dictionary = {}

static func from_catalog(catalog) -> Dictionary:
	var definitions_result := _definitions_from_catalog(catalog)
	if not definitions_result.ok:
		return definitions_result
	var service: CraftingService = load("res://src/crafting/crafting_service.gd").new()
	var configure_result := service.configure(
		definitions_result.recipes,
		definitions_result.items,
		definitions_result.item_name_to_id,
		_catalog_data_version(catalog)
	)
	if not configure_result.ok:
		return configure_result
	return {"ok": true, "crafting_service": service}

func configure(
	new_recipe_definitions: Dictionary,
	new_item_definitions: Dictionary,
	new_item_name_to_id := {},
	new_data_version := ""
) -> Dictionary:
	if new_recipe_definitions.is_empty():
		return _fail("missing_recipe_definitions", "Crafting recipes must not be empty.")
	if new_item_definitions.is_empty():
		return _fail("missing_item_definitions", "Crafting item definitions must not be empty.")
	recipe_definitions = _duplicate_dictionary(new_recipe_definitions)
	item_definitions = _duplicate_dictionary(new_item_definitions)
	item_name_to_id = _duplicate_dictionary(new_item_name_to_id)
	data_version = new_data_version
	return {"ok": true}

func has_recipe(recipe_id: String) -> bool:
	return recipe_definitions.has(recipe_id)

func recipe_for(recipe_id: String) -> Dictionary:
	return _duplicate_dictionary(recipe_definitions.get(recipe_id, {}))

func can_craft(recipe_id: String, inventory, context := {}) -> Dictionary:
	var validation := _validate_craft(recipe_id, inventory, context)
	validation["craftable"] = bool(validation.ok)
	return validation

func craft(recipe_id: String, inventory, context := {}) -> Dictionary:
	var validation := can_craft(recipe_id, inventory, context)
	if not validation.ok:
		return _fail_and_emit(validation)
	if inventory == null or not inventory.has_method("to_snapshot") or not inventory.has_method("load_snapshot"):
		return _fail_and_emit(_fail("invalid_inventory", "Crafting requires snapshot-capable inventory."))

	var snapshot: Dictionary = inventory.to_snapshot()
	var recipe: Dictionary = recipe_definitions[recipe_id]
	for material in recipe.materials:
		var remove_result: Dictionary = inventory.remove_item(String(material.item_id), int(material.quantity))
		if not remove_result.ok:
			inventory.load_snapshot(snapshot)
			return _fail_and_emit(remove_result)

	var add_result: Dictionary = inventory.add_item(String(recipe.result_item_id), int(recipe.result_quantity))
	if not add_result.ok:
		inventory.load_snapshot(snapshot)
		return _fail_and_emit(add_result)

	var result := {
		"ok": true,
		"recipe_id": recipe_id,
		"result_item_id": String(recipe.result_item_id),
		"result_quantity": int(recipe.result_quantity),
		"materials": _duplicate_array(recipe.materials),
		"facility_item_ids": _duplicate_array(recipe.facility_item_ids)
	}
	craft_completed.emit(_duplicate_dictionary(result))
	return result

func required_facility_item_ids(recipe_id: String) -> Array:
	if not recipe_definitions.has(recipe_id):
		return []
	return _duplicate_array(recipe_definitions[recipe_id].facility_item_ids)

func is_handcraft(recipe_id: String) -> bool:
	return required_facility_item_ids(recipe_id).is_empty()

func _validate_craft(recipe_id: String, inventory, context) -> Dictionary:
	if not recipe_definitions.has(recipe_id):
		return _fail("unknown_recipe", "Unknown crafting recipe: %s" % recipe_id)
	var recipe: Dictionary = recipe_definitions[recipe_id]
	var definition_errors: Array = recipe.get("definition_errors", [])
	if not definition_errors.is_empty():
		return {
			"ok": false,
			"reason": "invalid_recipe_definition",
			"errors": _duplicate_array(definition_errors),
			"recipe": _duplicate_dictionary(recipe)
		}
	if inventory == null or not inventory.has_method("get_total_quantity") or not inventory.has_method("remove_item") or not inventory.has_method("add_item"):
		return _fail("invalid_inventory", "Crafting requires an inventory model.")

	var errors: Array = []
	var missing_materials: Array = []
	for material in recipe.materials:
		var item_id := String(material.item_id)
		var required := int(material.quantity)
		var available := int(inventory.get_total_quantity(item_id))
		if available < required:
			missing_materials.append({
				"item_id": item_id,
				"required": required,
				"available": available
			})
	if not missing_materials.is_empty():
		errors.append({"reason": "missing_materials", "materials": missing_materials})

	var missing_facilities := _missing_facility_item_ids(recipe.facility_item_ids, context)
	if not missing_facilities.is_empty():
		errors.append({"reason": "missing_facilities", "facility_item_ids": missing_facilities})

	if not _unlock_context_allows(recipe, context):
		errors.append({"reason": "locked", "unlock_biome_id": String(recipe.get("unlock_biome_id", ""))})

	return {
		"ok": errors.is_empty(),
		"reason": "" if errors.is_empty() else String(errors[0].reason),
		"errors": errors,
		"missing_materials": missing_materials,
		"missing_facility_item_ids": missing_facilities,
		"recipe": _duplicate_dictionary(recipe)
	}

func _missing_facility_item_ids(required_facilities: Array, context) -> Array:
	if required_facilities.is_empty():
		return []
	var available := _available_facility_item_ids(context)
	var missing: Array = []
	for facility_id in required_facilities:
		if not available.has(String(facility_id)):
			missing.append(String(facility_id))
	return missing

func _available_facility_item_ids(context) -> Dictionary:
	var available := {}
	if typeof(context) != TYPE_DICTIONARY:
		return available
	var single_id := String(context.get("facility_item_id", ""))
	if not single_id.is_empty():
		available[single_id] = true
	var raw_many = context.get("available_facility_item_ids", [])
	if typeof(raw_many) == TYPE_DICTIONARY:
		for key in raw_many:
			if bool(raw_many[key]):
				available[String(key)] = true
	elif typeof(raw_many) == TYPE_ARRAY:
		for value in raw_many:
			available[String(value)] = true
	return available

func _unlock_context_allows(recipe: Dictionary, context) -> bool:
	var unlock_biome_id := String(recipe.get("unlock_biome_id", ""))
	if unlock_biome_id.is_empty():
		return true
	if typeof(context) != TYPE_DICTIONARY:
		return false
	if String(context.get("current_biome_id", "")) == unlock_biome_id:
		return true
	var unlocked = context.get("unlocked_biome_ids", [])
	if typeof(unlocked) == TYPE_DICTIONARY:
		return bool(unlocked.get(unlock_biome_id, false))
	if typeof(unlocked) == TYPE_ARRAY:
		return unlocked.has(unlock_biome_id)
	return false

static func _definitions_from_catalog(catalog) -> Dictionary:
	if not catalog.has_method("get_definitions"):
		return _fail("invalid_catalog", "Catalog cannot provide crafting definitions.")

	var item_result := _items_from_catalog(catalog)
	if not item_result.ok:
		return item_result

	var recipes: Dictionary = {}
	for row in _catalog_definitions(catalog, RECIPE_SOURCE):
		var recipe_result := _recipe_definition_from_row(row, item_result.items, item_result.item_name_to_id)
		if not recipe_result.ok:
			return recipe_result
		recipes[recipe_result.definition.id] = recipe_result.definition
	return {"ok": true, "recipes": recipes, "items": item_result.items, "item_name_to_id": item_result.item_name_to_id}

static func _items_from_catalog(catalog) -> Dictionary:
	var items: Dictionary = {}
	var names: Dictionary = {}
	for dataset in [ITEM_SOURCE, TEA_SOURCE]:
		for row in _catalog_definitions(catalog, dataset):
			var id := String(row.get("id", ""))
			if id.is_empty():
				return _fail("missing_item_id", "Crafting item definition is missing a stable id.")
			if items.has(id):
				return _fail("duplicate_item_id", "Duplicate crafting item id: %s" % id)
			var definition := _duplicate_dictionary(row)
			definition["id"] = id
			items[id] = definition
			var name := String(row.get("name", ""))
			if not name.is_empty():
				names[name] = id
	return {"ok": true, "items": items, "item_name_to_id": names}

static func _recipe_definition_from_row(row: Dictionary, items: Dictionary, names: Dictionary) -> Dictionary:
	var id := String(row.get("id", ""))
	if id.is_empty():
		return _fail("missing_recipe_id", "Crafting recipe is missing a stable id.")
	var errors: Array = []

	var result_item_id := String(row.get("result_item_id", ""))
	if result_item_id.is_empty():
		result_item_id = id
	if not items.has(result_item_id):
		errors.append({"reason": "unknown_result_item", "item_id": result_item_id})

	var quantity_result := _optional_positive_integer(row, "result_quantity", 1)
	if not quantity_result.ok:
		errors.append(quantity_result)

	var material_result := _materials_from_row(row, names)
	if material_result.ok:
		for material in material_result.materials:
			if not items.has(String(material.item_id)):
				errors.append({"reason": "unknown_material_item", "item_id": String(material.item_id)})
	else:
		errors.append(material_result)

	var facility_result := _facility_item_ids_from_row(row, names)
	if facility_result.ok:
		for facility_id in facility_result.facility_item_ids:
			if not items.has(String(facility_id)):
				errors.append({"reason": "unknown_facility_item", "item_id": String(facility_id)})
	else:
		errors.append(facility_result)

	var craft_seconds_result := _optional_non_negative_number(row, "craft_seconds", 0.0)
	if not craft_seconds_result.ok:
		errors.append(craft_seconds_result)

	return {"ok": true, "definition": {
		"id": id,
		"name": String(row.get("name", id)),
		"category": String(row.get("category", "")),
		"status": String(row.get("status", "")),
		"materials": material_result.get("materials", []),
		"materials_note": String(row.get("materials_note", "")),
		"facility": String(row.get("facility", "")),
		"facility_item_ids": facility_result.get("facility_item_ids", []),
		"result_item_id": result_item_id,
		"result_quantity": quantity_result.get("value", 1),
		"unlock_biome_id": String(row.get("unlock_biome_id", "")),
		"unlock_condition": String(row.get("unlock_condition", "")),
		"craft_seconds": craft_seconds_result.get("value", 0.0),
		"definition_errors": errors
	}}

static func _materials_from_row(row: Dictionary, names: Dictionary) -> Dictionary:
	if row.has("materials") and row.materials != null:
		return _structured_materials(row.materials)
	return _materials_from_note(String(row.get("materials_note", "")), names)

static func _structured_materials(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _fail("invalid_materials", "Recipe materials must be an array.")
	var materials: Array = []
	for raw_material in value:
		if typeof(raw_material) != TYPE_DICTIONARY:
			return _fail("invalid_material", "Recipe material must be a dictionary.")
		var item_id := String(raw_material.get("item_id", ""))
		var quantity_result := _required_positive_integer(raw_material, "quantity")
		if item_id.is_empty():
			return _fail("missing_material_item", "Recipe material is missing item_id.")
		if not quantity_result.ok:
			return quantity_result
		materials.append({"item_id": item_id, "quantity": quantity_result.value})
	return {"ok": true, "materials": _merge_materials(materials)}

static func _materials_from_note(note: String, names: Dictionary) -> Dictionary:
	var materials: Array = []
	var trimmed := note.strip_edges()
	if trimmed.is_empty():
		return {"ok": true, "materials": materials}
	for raw_part in trimmed.replace(",", "+").split("+"):
		var part := String(raw_part).strip_edges()
		if part.is_empty():
			continue
		var parsed := _parse_named_quantity(part, names)
		if not parsed.ok:
			return parsed
		materials.append({"item_id": parsed.item_id, "quantity": parsed.quantity})
	return {"ok": true, "materials": _merge_materials(materials)}

static func _facility_item_ids_from_row(row: Dictionary, names: Dictionary) -> Dictionary:
	var raw_relation = row.get("facility_item_ids", [])
	if typeof(raw_relation) == TYPE_ARRAY and not raw_relation.is_empty():
		var relation_ids: Array = []
		for item_id in raw_relation:
			relation_ids.append(String(item_id))
		return {"ok": true, "facility_item_ids": relation_ids}
	var note := String(row.get("facility", "")).strip_edges()
	if HANDCRAFT_LABELS.has(note):
		return {"ok": true, "facility_item_ids": []}
	var facility_ids: Array = []
	for raw_part in note.replace("+", "·").replace(",", "·").replace("/", "·").split("·"):
		var name := String(raw_part).strip_edges()
		if name.is_empty() or HANDCRAFT_LABELS.has(name):
			continue
		if not names.has(name):
			return _fail("unknown_facility_name", "Unknown facility item name: %s" % name)
		facility_ids.append(String(names[name]))
	return {"ok": true, "facility_item_ids": _unique_strings(facility_ids)}

static func _parse_named_quantity(part: String, names: Dictionary) -> Dictionary:
	for name in _names_by_descending_length(names):
		if part == name:
			return _fail("missing_material_quantity", "Recipe material quantity is missing: %s" % part)
		var prefix := "%s " % name
		if part.begins_with(prefix):
			var quantity_text := part.substr(prefix.length()).strip_edges()
			if not quantity_text.is_valid_int():
				return _fail("invalid_material_quantity", "Recipe material quantity must be an integer: %s" % part)
			var quantity := int(quantity_text)
			if quantity <= 0:
				return _fail("invalid_material_quantity", "Recipe material quantity must be positive: %s" % part)
			return {"ok": true, "item_id": String(names[name]), "quantity": quantity}
	return _fail("unknown_material_name", "Unknown material item name: %s" % part)

static func _names_by_descending_length(names: Dictionary) -> Array:
	var keys := names.keys()
	keys.sort_custom(func(a, b) -> bool:
		return String(a).length() > String(b).length()
	)
	return keys

static func _merge_materials(materials: Array) -> Array:
	var totals: Dictionary = {}
	for material in materials:
		var item_id := String(material.item_id)
		totals[item_id] = int(totals.get(item_id, 0)) + int(material.quantity)
	var ids := totals.keys()
	ids.sort()
	var merged: Array = []
	for item_id in ids:
		merged.append({"item_id": String(item_id), "quantity": int(totals[item_id])})
	return merged

static func _unique_strings(values: Array) -> Array:
	var seen := {}
	var unique: Array = []
	for value in values:
		var text := String(value)
		if seen.has(text):
			continue
		seen[text] = true
		unique.append(text)
	return unique

static func _optional_positive_integer(row: Dictionary, field: String, fallback: int) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return _fail("invalid_definition", "Definition field must be numeric: %s.%s" % [row.get("id", ""), field])
	if float(value) != floor(float(value)) or int(value) <= 0:
		return _fail("invalid_definition", "Definition field must be a positive integer: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": int(value)}

static func _required_positive_integer(row: Dictionary, field: String) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return _fail("missing_definition_field", "Definition is missing required field: %s" % field)
	return _optional_positive_integer(row, field, 1)

static func _optional_non_negative_number(row: Dictionary, field: String, fallback: float) -> Dictionary:
	if not row.has(field) or row[field] == null:
		return {"ok": true, "value": fallback}
	var value = row[field]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		return _fail("invalid_definition", "Definition field must be a non-negative number: %s.%s" % [row.get("id", ""), field])
	return {"ok": true, "value": float(value)}

static func _catalog_definitions(catalog, dataset: String) -> Array:
	return catalog.get_definitions(dataset)

static func _catalog_data_version(catalog) -> String:
	var value = catalog.get("data_version") if catalog.has_method("get") else ""
	return "" if value == null else String(value)

static func _duplicate_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)

static func _duplicate_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)

func _fail_and_emit(error: Dictionary) -> Dictionary:
	operation_failed.emit(error)
	return error

static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "error": message}
