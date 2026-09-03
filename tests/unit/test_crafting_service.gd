extends RefCounted

const CraftingService = preload("res://src/crafting/crafting_service.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const FacilityPlacementService = preload("res://src/world/placement/facility_placement_service.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	var data_version := "fixture-crafting"

	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions

	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])

	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_generated_catalog_configures_crafting(asserts)
	_assert_handcraft_consumes_materials_and_grants_result(asserts)
	_assert_material_and_facility_requirements_are_reported(asserts)
	_assert_crafting_read_model_reports_filters_detail_and_reasons(asserts)
	_assert_current_run_biome_unlock_allows_recipe(asserts)
	_assert_crafting_rolls_back_when_result_grant_fails(asserts)
	_assert_facility_placement_reserves_valid_footprint(asserts)
	_assert_facility_placement_rejects_blocked_or_missing_workspace(asserts)
	_assert_facility_placement_preserves_required_paths(asserts)

func _assert_generated_catalog_configures_crafting(asserts) -> void:
	var catalog := DataCatalog.new()
	var catalog_result := catalog.load_from_directory("res://data/generated")
	asserts.true_value(catalog_result.ok, "generated catalog loads for crafting service")
	var service_result: Dictionary = CraftingService.from_catalog(catalog)
	asserts.true_value(service_result.ok, "crafting service initializes from generated catalog")
	if not service_result.ok:
		return
	var service: CraftingService = service_result.crafting_service
	asserts.true_value(service.has_recipe("wooden_workbench"), "generated handcraft recipe is available")
	asserts.true_value(service.is_handcraft("wooden_workbench"), "손제작 recipe has no facility requirement")
	asserts.equal(service.recipe_for("wooden_workbench").unlock_biome_id, "common_region", "generated recipe carries stable unlock biome id")
	asserts.equal(service.required_facility_item_ids("humble_clay_bowl"), ["wooden_workbench"], "facility name maps through item data")

	var inventory_result: Dictionary = InventoryModel.from_catalog(catalog)
	asserts.true_value(inventory_result.ok, "inventory initializes for generated crafting")
	if inventory_result.ok:
		var inventory: InventoryModel = inventory_result.inventory
		asserts.true_value(inventory.add_item("wood", 6).ok, "generated wood can be stocked")
		asserts.true_value(inventory.add_item("stone", 3).ok, "generated stone can be stocked")
		var repair_locked := service.can_craft("wooden_workbench", inventory, {"current_biome_id": "common_region"})
		asserts.false_value(repair_locked.ok, "generated catalog recipe rejects before repair unlock")
		asserts.equal(repair_locked.reason, "locked", "generated catalog recipe reports locked before repair")
		var unlocked_context := {"current_biome_id": "common_region", "unlocked_biome_ids": ["common_region"]}
		var repair_unlocked := service.craft("wooden_workbench", inventory, unlocked_context)
		asserts.true_value(repair_unlocked.ok, "generated catalog recipe executes after repair unlock")
		asserts.true_value(inventory.add_item("cloth", 2).ok, "generated cloth can be stocked")
		asserts.true_value(service.craft("bandage", inventory, unlocked_context).ok, "generated bandage recipe executes")
		asserts.equal(inventory.get_total_quantity("bandage"), 1, "cloth-to-bandage crafting grants bandage")

	var placement_result: Dictionary = FacilityPlacementService.from_catalog(catalog)
	asserts.true_value(placement_result.ok, "placement service initializes from generated catalog")
	if placement_result.ok:
		var world := WorldData.new(3, 3, "grass", true)
		asserts.true_value(
			placement_result.facility_placement_service.place_facility("wooden_workbench", world, Vector2i(1, 1)).ok,
			"generated facility can be placed with default footprint"
		)

func _assert_handcraft_consumes_materials_and_grants_result(asserts) -> void:
	var service := _fixture_crafting_service()
	var inventory := _fixture_inventory(6)
	asserts.true_value(inventory.add_item("wood", 6).ok, "wood add succeeds")
	asserts.true_value(inventory.add_item("stone", 3).ok, "stone add succeeds")

	var crafted: Dictionary = service.craft("wooden_workbench", inventory)
	asserts.true_value(crafted.ok, "handcraft recipe crafts without facility context")
	asserts.equal(inventory.get_total_quantity("wood"), 0, "crafting consumes wood")
	asserts.equal(inventory.get_total_quantity("stone"), 0, "crafting consumes stone")
	asserts.equal(inventory.get_total_quantity("wooden_workbench"), 1, "crafting grants result")

func _assert_material_and_facility_requirements_are_reported(asserts) -> void:
	var service := _fixture_crafting_service()
	var inventory := _fixture_inventory(4)
	asserts.true_value(inventory.add_item("clay", 2).ok, "partial clay add succeeds")

	var missing_materials: Dictionary = service.can_craft("humble_clay_bowl", inventory, {"available_facility_item_ids": ["wooden_workbench"]})
	asserts.false_value(missing_materials.ok, "insufficient material rejects crafting")
	asserts.equal(missing_materials.missing_materials[0].item_id, "clay", "missing material reports item id")
	asserts.equal(missing_materials.missing_materials[0].required, 3, "missing material reports required quantity")

	asserts.true_value(inventory.add_item("clay", 1).ok, "remaining clay add succeeds")
	var missing_facility: Dictionary = service.can_craft("humble_clay_bowl", inventory)
	asserts.false_value(missing_facility.ok, "facility recipe rejects missing facility")
	asserts.equal(missing_facility.missing_facility_item_ids, ["wooden_workbench"], "missing facility reports required item")

	var craftable: Dictionary = service.can_craft("humble_clay_bowl", inventory, {"facility_item_id": "wooden_workbench"})
	asserts.true_value(craftable.ok, "facility item context allows recipe")

func _assert_crafting_read_model_reports_filters_detail_and_reasons(asserts) -> void:
	var service := _fixture_crafting_service()
	var inventory := _fixture_inventory(6)
	asserts.true_value(inventory.add_item("wood", 6).ok, "read model wood add succeeds")
	asserts.true_value(inventory.add_item("stone", 3).ok, "read model stone add succeeds")
	asserts.true_value(inventory.add_item("clay", 2).ok, "read model partial clay add succeeds")

	var model: Dictionary = service.read_model(inventory, {"unlocked_biome_ids": ["common_region"]}, {
		"category": "다구",
		"selected_recipe_id": "humble_clay_bowl"
	})
	asserts.true_value(model.ok, "crafting read model builds")
	asserts.equal(model.selected_filter, "다구", "read model records selected category filter")
	asserts.equal(model.rows.size(), 3, "category filter includes all teaware recipes")
	asserts.equal(model.detail.recipe_id, "humble_clay_bowl", "read model keeps selected stable recipe id")
	asserts.equal(model.detail.result.item_id, "humble_clay_bowl", "read model exposes result item id")
	asserts.equal(model.detail.result.name, "소박한 흙사발", "read model resolves result item name")
	asserts.equal(model.detail.materials[0].item_id, "clay", "read model exposes material item id")
	asserts.equal(model.detail.materials[0].available, 2, "read model exposes owned material quantity")
	asserts.equal(model.detail.materials[0].required, 3, "read model exposes required material quantity")
	asserts.equal(model.detail.reason, "missing_materials", "read model distinguishes material shortage")
	asserts.equal(model.detail.reason_label, "재료 부족", "read model labels material shortage")
	asserts.true_value(inventory.add_item("clay", 1).ok, "read model remaining clay add succeeds")
	var locked: Dictionary = service.read_model(inventory, {}, {"selected_recipe_id": "regional_bowl"})
	asserts.equal(locked.detail.reason, "locked", "read model distinguishes current-run locked recipe")
	var missing_facility: Dictionary = service.read_model(inventory, {"unlocked_biome_ids": ["common_region"]}, {"selected_recipe_id": "humble_clay_bowl"})
	asserts.equal(missing_facility.detail.facilities[0].item_id, "wooden_workbench", "read model exposes required facility item id")
	asserts.false_value(missing_facility.detail.facilities[0].available, "read model marks missing facility")
	var facility_available: Dictionary = service.read_model(inventory, {"facility_item_id": "wooden_workbench"}, {"selected_recipe_id": "humble_clay_bowl"})
	asserts.true_value(facility_available.detail.facilities[0].available, "read model marks available facility")

func _assert_crafting_rolls_back_when_result_grant_fails(asserts) -> void:
	var service := _fixture_crafting_service()
	var inventory := _fixture_inventory(2)
	asserts.true_value(inventory.add_item("clay", 3).ok, "clay add succeeds")
	asserts.true_value(inventory.add_item("stone", 1).ok, "stone add succeeds")
	var before: Dictionary = inventory.to_snapshot()

	var result: Dictionary = service.craft("crowded_bowl", inventory)
	asserts.false_value(result.ok, "full inventory rejects result grant")
	asserts.equal(result.reason, "inventory_full", "result grant failure is surfaced")
	asserts.equal(inventory.to_snapshot(), before, "failed result grant rolls back consumed materials")

func _assert_current_run_biome_unlock_allows_recipe(asserts) -> void:
	var service := _fixture_crafting_service()
	var inventory := _fixture_inventory(2)
	asserts.true_value(inventory.add_item("clay", 3).ok, "locked recipe material add succeeds")
	var locked: Dictionary = service.can_craft("regional_bowl", inventory)
	asserts.false_value(locked.ok, "biome recipe stays locked without current-run unlock")
	asserts.equal(locked.reason, "locked", "locked biome recipe reports stable reason")
	var current_only: Dictionary = service.can_craft("regional_bowl", inventory, {"current_biome_id": "common_region"})
	asserts.false_value(current_only.ok, "current biome alone does not unlock recipe")
	var unlocked: Dictionary = service.can_craft("regional_bowl", inventory, {"unlocked_biome_ids": ["common_region"]})
	asserts.true_value(unlocked.ok, "current-run biome unlock allows recipe")

func _assert_facility_placement_reserves_valid_footprint(asserts) -> void:
	var service := _fixture_placement_service()
	var world := WorldData.new(5, 5, "grass", true)
	var placed: Dictionary = service.place_facility("wooden_workbench", world, Vector2i(1, 1))

	asserts.true_value(placed.ok, "valid footprint places facility")
	asserts.true_value(world.is_occupied(Vector2i(1, 1)), "placement reserves origin")
	asserts.true_value(world.is_occupied(Vector2i(2, 1)), "placement reserves full footprint")
	asserts.equal(world.get_interactables(Vector2i(2, 1)), ["wooden_workbench@1,1"], "placement creates interactable footprint")

func _assert_facility_placement_rejects_blocked_or_missing_workspace(asserts) -> void:
	var service := _fixture_placement_service()
	var world := WorldData.new(4, 4, "grass", true)
	asserts.true_value(world.reserve_entity("fox", Vector2i(1, 1)).ok, "entity occupies target cell")
	var blocked: Dictionary = service.can_place_facility("wooden_workbench", world, Vector2i(1, 1))
	asserts.false_value(blocked.ok, "occupied footprint rejects facility placement")
	asserts.equal(blocked.reason, "blocked", "blocked footprint uses stable reason")

	var tight_world := WorldData.new(2, 1, "grass", true)
	var missing_workspace: Dictionary = service.can_place_facility("wooden_workbench", tight_world, Vector2i(0, 0))
	asserts.false_value(missing_workspace.ok, "placement requires adjacent workspace by default")
	asserts.equal(missing_workspace.reason, "missing_workspace", "missing workspace uses stable reason")

func _assert_facility_placement_preserves_required_paths(asserts) -> void:
	var service := _fixture_placement_service()
	var world := WorldData.new(3, 2, "grass", true)
	world.set_terrain(Vector2i(0, 1), "water", false)
	world.set_terrain(Vector2i(2, 1), "water", false)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 0))
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_0", Vector2i(2, 0))

	var blocked_path: Dictionary = service.can_place_facility("small_stool", world, Vector2i(1, 0))
	asserts.false_value(blocked_path.ok, "facility placement cannot block required landmark path")
	asserts.equal(blocked_path.reason, "blocks_required_path", "path blocking uses stable reason")

	var without_path_check: Dictionary = service.can_place_facility("small_stool", world, Vector2i(1, 0), {"preserve_required_paths": false})
	asserts.true_value(without_path_check.ok, "path preservation can be disabled for isolated tests")

func _fixture_crafting_service() -> CraftingService:
	var result: Dictionary = CraftingService.from_catalog(FakeCatalog.new({
		"items": _item_rows(),
		"teas": [],
		"recipes": _recipe_rows()
	}))
	return result.crafting_service

func _fixture_placement_service() -> FacilityPlacementService:
	var result: Dictionary = FacilityPlacementService.from_catalog(FakeCatalog.new({
		"items": [
			{"id": "wooden_workbench", "name": "목재 작업대", "status": "테스트", "type": "도구", "footprint": "2x1"},
			{"id": "small_stool", "name": "작은 의자", "status": "테스트", "type": "도구"}
		]
	}))
	return result.facility_placement_service

func _fixture_inventory(slot_count: int) -> InventoryModel:
	var result: Dictionary = InventoryModel.from_catalog(FakeCatalog.new({
		"balance": [{"id": "inventory_base_slots", "name": "인벤토리 기본 슬롯", "status": "테스트", "value": slot_count}],
		"items": _item_rows(),
		"teas": []
	}))
	return result.inventory

func _item_rows() -> Array:
	return [
		{"id": "wood", "name": "목재", "status": "테스트", "type": "재료", "max_stack": 10},
		{"id": "stone", "name": "돌", "status": "테스트", "type": "재료", "max_stack": 10},
		{"id": "clay", "name": "점토", "status": "테스트", "type": "재료", "max_stack": 10},
		{"id": "wooden_workbench", "name": "목재 작업대", "status": "테스트", "type": "도구"},
		{"id": "humble_clay_bowl", "name": "소박한 흙사발", "status": "테스트", "type": "다구"},
		{"id": "crowded_bowl", "name": "꽉 찬 사발", "status": "테스트", "type": "다구"}
	]

func _recipe_rows() -> Array:
	return [
		{"id": "wooden_workbench", "name": "목재 작업대 제작", "status": "테스트", "category": "도구", "facility": "손제작", "materials_note": "목재 6 + 돌 3"},
		{"id": "humble_clay_bowl", "name": "소박한 흙사발 제작", "status": "테스트", "category": "다구", "facility": "목재 작업대", "materials_note": "점토 3"},
		{"id": "regional_bowl", "result_item_id": "humble_clay_bowl", "name": "지역 흙사발 제작", "status": "테스트", "category": "다구", "facility": "손제작", "materials_note": "점토 3", "unlock_biome_id": "common_region"},
		{"id": "crowded_bowl", "name": "꽉 찬 사발 제작", "status": "테스트", "category": "다구", "facility": "손제작", "materials": [{"item_id": "clay", "quantity": 2}]}
	]
