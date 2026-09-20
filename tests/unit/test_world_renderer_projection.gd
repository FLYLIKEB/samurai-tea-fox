extends RefCounted

const WorldData = preload("res://src/world/data/world_data.gd")
const WorldRendererProjection = preload("res://src/world/rendering/world_renderer_projection.gd")

func run(asserts) -> void:
	var world := WorldData.new(4, 1, "common_ground", true)
	var expected_sources := {
		"wood": "item_wood_icon",
		"old_wood": "item_old_wood_icon",
		"conifer_wood": "item_conifer_wood_icon"
	}
	for index in range(expected_sources.size()):
		var item_id := String(expected_sources.keys()[index])
		asserts.true_value(world.reserve_entity("resource_%s" % item_id, Vector2i(index, 0), Vector2i.ONE, true, {"resource_id": item_id, "biome_rule_id": "common_region", "ground_pickup": true}).ok, "%s pickup node reserves" % item_id)
	asserts.true_value(world.reserve_entity("terrain_tree_wood_3_0", Vector2i(3, 0), Vector2i.ONE, true, {"resource_id": "wood", "terrain_id": "common_forest", "terrain_overlay": "tree"}).ok, "harvestable tree reserves")
	var sources := _entity_sources(WorldRendererProjection.new().project(world.to_dictionary()))
	for item_id in expected_sources:
		asserts.equal(sources.get("resource_%s" % item_id, ""), expected_sources[item_id], "%s road pickup uses its cut-wood item sprite" % item_id)
	asserts.equal(sources.get("terrain_tree_wood_3_0", ""), "terrain_tree_broadleaf_32x32", "harvestable tree keeps the tree sprite")

func _entity_sources(projection: Dictionary) -> Dictionary:
	var sources := {}
	for layer in projection.get("layers", []):
		if String(layer.get("id", "")) != WorldData.LAYER_ENTITIES:
			continue
		for cell in layer.get("cells", []):
			sources[String(cell.get("owner_id", ""))] = String(cell.get("source_id", ""))
	return sources
