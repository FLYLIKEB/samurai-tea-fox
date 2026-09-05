extends RefCounted

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")

func run(asserts) -> void:
	var start_screen_scene: PackedScene = load("res://scenes/ui/start_screen.tscn")
	var start_screen: Node = start_screen_scene.instantiate()
	var cheat_button := start_screen.get_node_or_null("Content/CheatButton") as Button
	asserts.true_value(cheat_button != null, "start screen exposes a cheat mode button")
	if cheat_button != null:
		asserts.equal(cheat_button.text, "치트 모드로 시작", "cheat mode button clearly labels its behavior")
		asserts.true_value(not cheat_button.get_signal_connection_list("pressed").is_empty(), "cheat mode button is connected to its start handler")
	start_screen.free()

	var catalog := DataCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "cheat start catalog loads")

	var runtime := Main.new()
	runtime.catalog = catalog
	runtime.run_state = RunState.new()
	runtime._start_mode = Main.START_MODE_CHEAT
	asserts.true_value(runtime._configure_run_services(catalog).ok, "cheat start services configure")
	var result: Dictionary = runtime._apply_cheat_start_inventory()
	asserts.true_value(result.ok, "cheat start inventory initializes")
	asserts.true_value(result.applied, "cheat inventory reports that it was applied")
	asserts.equal(runtime.inventory.slot_count, 1000, "cheat inventory expands to 1000 slots")
	for definition in catalog.get_definitions("items"):
		var item_id := String(definition.get("id", ""))
		if String(definition.get("type", "")) == "재료":
			asserts.equal(runtime.inventory.get_total_quantity(item_id), 99, "cheat start grants 99 of material %s" % item_id)
		elif item_id == "bandage":
			asserts.equal(runtime.inventory.get_total_quantity("bandage"), 200, "cheat start grants 200 bandages")
		else:
			asserts.equal(runtime.inventory.get_total_quantity(item_id), 0, "cheat start does not bypass ownership rules for %s" % item_id)
	asserts.equal(runtime.run_state.inventory.slot_count, 1000, "cheat inventory capacity enters run state")
	asserts.true_value(runtime.run_state.completed_dungeon_ids.has("common_region"), "cheat start unlocks the first dungeon clear")
	asserts.true_value(runtime.run_state.completed_dungeon_ids.has("mountain_region"), "cheat start unlocks the mountain dungeon clear")
	asserts.equal(runtime.run_state.teleport_states.get("common_region", ""), "repaired", "cheat start repairs the first teleport")
	asserts.equal(runtime.run_state.teleport_states.get("mountain_region", ""), "repaired", "cheat start repairs the mountain teleport")
	asserts.equal(runtime.equipment.get_equipped_slot("weapon").get("item_id", ""), "mountain_iron_dagger", "cheat start equips the strongest weapon")

	var normal_runtime := Main.new()
	normal_runtime.catalog = catalog
	normal_runtime.run_state = RunState.new()
	normal_runtime._start_mode = Main.START_MODE_NEW
	asserts.true_value(normal_runtime._configure_run_services(catalog).ok, "normal start services configure")
	var normal_result: Dictionary = normal_runtime._apply_cheat_start_inventory()
	asserts.true_value(normal_result.ok, "normal start bypasses cheat initialization safely")
	asserts.false_value(normal_result.applied, "normal start does not receive cheat inventory")
	asserts.equal(normal_runtime.inventory.slot_count, 24, "normal start keeps the balance-defined inventory capacity")

	runtime.free()
	normal_runtime.free()
