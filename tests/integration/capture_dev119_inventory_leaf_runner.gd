extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const InventoryModel = preload("res://src/inventory/inventory_model.gd")
const EquipmentModel = preload("res://src/inventory/equipment_model.gd")
const InventoryCommandRuntime = preload("res://src/inventory/inventory_command_runtime.gd")
const ConsumableService = preload("res://src/consumable/consumable_service.gd")

const CAPTURE_DIR := "res://docs/reports/dev-119-inventory-leaf-use"
const CAPTURE_PATH := "%s/mobile_360x640.png" % CAPTURE_DIR

class FakeResources:
	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

class FakePlayer:
	var resources := FakeResources.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	var result := await _capture_inventory_leaf()
	if not result.ok:
		push_error(String(result.get("error", "capture failed")))
		quit(1)
		return
	print("DEV-119 inventory leaf capture saved: %s" % CAPTURE_PATH)
	quit(0)

func _capture_inventory_leaf() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "Dev119InventoryLeafViewport"
	viewport.size = Vector2i(360, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var catalog := _catalog()
	var inventory: InventoryModel = InventoryModel.from_catalog(catalog).inventory
	var equipment: EquipmentModel = EquipmentModel.from_catalog(catalog).equipment
	var consumable: ConsumableService = ConsumableService.from_catalog(catalog).consumable_service
	inventory.add_item("father_spring_pan_fired_tea", 3)
	inventory.add_item("bandage", 2)
	inventory.add_item("short_travel_sword", 1)
	var runtime := InventoryCommandRuntime.new()
	runtime.configure(inventory, equipment, consumable, "dev-119")
	var leaf_slot := inventory.first_slot_with_item("father_spring_pan_fired_tea")
	runtime.select_slot(leaf_slot)
	var hud := GameHud.new()
	viewport.add_child(hud)
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {
		"inventory": inventory,
		"inventory_command_runtime": runtime,
		"catalog": catalog
	})
	hud.show_inventory_menu()
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	var menu := hud.get_node_or_null("Root/MenuPanel") as Control
	if menu == null or not menu.visible:
		viewport.queue_free()
		return {"ok": false, "error": "inventory menu is not visible"}
	if not _tree_has_text(hud, "서호용정"):
		viewport.queue_free()
		return {"ok": false, "error": "selected tea leaf is not visible"}
	if _tree_has_text(hud, "사용"):
		viewport.queue_free()
		return {"ok": false, "error": "tea leaf exposes a direct use button"}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "capture requires a rendering display driver"}
	var save_result := image.save_png(CAPTURE_PATH)
	viewport.queue_free()
	if save_result != OK:
		return {"ok": false, "error": "failed to save %s" % CAPTURE_PATH}
	return {"ok": true}

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and text in (node as Label).text:
		return true
	if node is Button and text in (node as Button).text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

func _catalog() -> DataCatalog:
	var catalog := DataCatalog.new()
	catalog.load_from_directory("res://data/generated")
	return catalog
