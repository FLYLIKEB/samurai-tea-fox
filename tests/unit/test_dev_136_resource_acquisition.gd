extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")

class DropSource:
	extends Node
	signal drop_requested(event: Dictionary)

func run(asserts) -> void:
	var catalog := DataCatalog.new()
	var assets := AssetCatalog.new()
	asserts.true_value(catalog.load_from_directory("res://data/generated").ok, "DEV-136 loads generated definitions")
	asserts.true_value(assets.load_manifest().ok, "DEV-136 loads the promoted asset manifest")
	_assert_resource_path(asserts, catalog, assets, "mountain_region", "copper_ore", "asset_assets_sprites_objects_mining_copper_ore_32x32_png", "stone_pickaxe")
	_assert_resource_path(asserts, catalog, assets, "rainforest", "rare_wood", "asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png")

func _assert_resource_path(asserts, catalog: DataCatalog, assets: AssetCatalog, biome_id: String, resource_id: String, source_id: String, tool_id := "") -> void:
	var main := Main.new()
	var combat_source := DropSource.new()
	var world_root := Node2D.new()
	var state := RunState.new()
	state.current_biome_id = biome_id
	state.teleport_states = {"common_region": "repaired", "mountain_region": "repaired", "wasteland": "repaired", "snowfield": "repaired", "rainforest": "repaired"}
	main.catalog = catalog
	main.run_state = state
	main.combat_dummy = combat_source
	main.world_visuals = world_root
	var services: Dictionary = main._configure_run_services(catalog)
	asserts.true_value(services.ok, "%s configures run services" % resource_id)
	var configured: Dictionary = main._configure_world_for_current_run() if services.ok else services
	asserts.true_value(configured.ok, "%s configures its generated biome" % resource_id)
	if configured.ok:
		var resource_node := _resource_node(main.generated_world.get("resource_nodes", []), resource_id)
		asserts.true_value(not resource_node.is_empty(), "%s is generated in %s" % [resource_id, biome_id])
		asserts.true_value(main.generated_world.resource_accessibility.valid, "%s is reachable" % resource_id)
		if not resource_node.is_empty():
			var node_id := String(resource_node.id)
			var gatherable: Dictionary = main.acquisition_service.gatherable_for(node_id)
			asserts.equal(String(gatherable.get("definition_id", "")), resource_id, "%s registers through AcquisitionService" % resource_id)
			asserts.equal(String(gatherable.get("required_tool_item_id", "")), tool_id, "%s keeps its tool contract" % resource_id)
			asserts.equal(String(main._owner_sprite_sources(main.generated_world).get(node_id, "")), source_id, "%s uses its canonical world source" % resource_id)
			asserts.true_value(not assets.id_for_reference(source_id).is_empty(), "%s source resolves to a promoted asset" % resource_id)
			if not tool_id.is_empty():
				asserts.true_value(main.inventory.add_item(tool_id, 1).ok, "%s fixture receives its required tool" % resource_id)
			var before: int = main.inventory.get_total_quantity(resource_id)
			asserts.true_value(main.submit_mobile_action_command(GameCommand.new(GameCommand.Type.INTERACT, Vector2i.ZERO, -1, {"target_id": node_id})), "%s interaction succeeds" % resource_id)
			asserts.equal(main.inventory.get_total_quantity(resource_id), before + 1, "%s reaches inventory" % resource_id)
			asserts.true_value(main.acquisition_service.gatherable_for(node_id).depleted, "%s depletes after acquisition" % resource_id)
			if not tool_id.is_empty():
				asserts.equal(main.inventory.get_total_quantity(tool_id), 1, "%s does not consume its tool" % resource_id)
	main.free()
	combat_source.free()
	world_root.free()

func _resource_node(nodes: Array, resource_id: String) -> Dictionary:
	for node in nodes:
		if String(node.get("resource_id", "")) == resource_id:
			return node
	return {}
