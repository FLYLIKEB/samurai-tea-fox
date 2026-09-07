extends RefCounted
## 현재 월드의 채집·드롭 정의를 구성한다. 입력은 호출 시점의 실제 런타임이다.

const AcquisitionService = preload("res://src/world/interactions/acquisition_service.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

const TREE_HARVEST_TOOL_ITEM_ID := "stone_axe"
const TREE_HARVEST_DEFINITION_PREFIX := "terrain_tree_wood"

var catalog
var inventory
var world_data
var biome_id: String

func _init(next_catalog, next_inventory, next_world_data, next_biome_id: String) -> void:
	catalog = next_catalog
	inventory = next_inventory
	world_data = next_world_data
	biome_id = next_biome_id

func confirmed_generated_resource_definitions(resource_nodes: Array) -> Array:
	var definitions := []
	var seen := {}
	for node in resource_nodes:
		var resource_id := String(node.get("resource_id", ""))
		if resource_id.is_empty() or seen.has(resource_id) or inventory == null or not inventory.has_definition(resource_id):
			continue
		var item: Dictionary = catalog.find_by_id("items", resource_id)
		if String(item.get("status", "")) != "확정" or not is_generated_resource_item_type(String(item.get("type", ""))):
			continue
		definitions.append({"id": resource_id, "item_id": resource_id, "quantity": 1, "policy": AcquisitionService.POLICY_DIRECT, "material_tag": String(node.get("material_tag", "")), "required_tool_item_id": required_tool_for_resource_node(resource_id, node)})
		seen[resource_id] = true
	return definitions

func is_generated_resource_item_type(item_type: String) -> bool:
	return item_type == "재료" or item_type == "향"

func terrain_tree_gatherable_definitions() -> Array:
	var definitions: Array = []
	if world_data == null:
		return definitions
	var snapshot: Dictionary = world_data.to_dictionary()
	for cell in snapshot.get("cells", []):
		var tree_profile := tree_harvest_profile_for_cell(cell)
		if tree_profile.is_empty():
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		definitions.append({
			"id": terrain_tree_gatherable_id(position),
			"item_id": "wood",
			"quantity": 1,
			"policy": AcquisitionService.POLICY_DIRECT,
			"material_tag": "wood",
			"required_tool_item_id": TREE_HARVEST_TOOL_ITEM_ID,
			"depleted_terrain": tree_profile
		})
	return definitions

func register_terrain_tree_gatherables(definition_ids: Dictionary, acquisition_service) -> Dictionary:
	if world_data == null or acquisition_service == null:
		return {"ok": true}
	var snapshot: Dictionary = world_data.to_dictionary()
	for cell in snapshot.get("cells", []):
		if tree_harvest_profile_for_cell(cell).is_empty():
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		var node_id := terrain_tree_gatherable_id(position)
		if world_data.get_reservation(node_id).is_empty():
			continue
		if not definition_ids.has(node_id):
			continue
		if not acquisition_service.gatherable_for(node_id).is_empty():
			continue
		var registered: Dictionary = acquisition_service.register_gatherable(node_id, node_id, position)
		if not registered.ok:
			return registered
	return {"ok": true}

func terrain_tree_gatherable_id(position: Vector2i) -> String:
	return "%s_%d_%d" % [TREE_HARVEST_DEFINITION_PREFIX, position.x, position.y]

func mountain_mineral_gatherable_definitions() -> Array:
	var definitions: Array = []
	if world_data == null:
		return definitions
	for cell in world_data.to_dictionary().get("cells", []):
		var terrain: Dictionary = cell.get("layers", {}).get(WorldData.LAYER_TERRAIN, {})
		if String(terrain.get("id", "")) != WorldGenerator.TERRAIN_MOUNTAIN_ROCK:
			continue
		var position := _vector_from_dictionary(cell.get("position", {}))
		var node_id := "terrain_mountain_mineral_%d_%d" % [position.x, position.y]
		var item_id := "iron_ore" if absi(position.x * 31 + position.y * 17) % 3 == 0 else "stone"
		definitions.append({
			"id": node_id,
			"item_id": item_id,
			"quantity": 1,
			"policy": AcquisitionService.POLICY_DIRECT,
			"material_tag": "stone",
			"required_tool_item_id": required_tool_for_resource_interaction(item_id, node_kind_for_resource_action(item_id, "mine")),
			"depleted_terrain": {"id": WorldGenerator.TERRAIN_MOUNTAIN_SLOPE, "walkable": true}
		})
	return definitions

func required_tool_for_resource_node(resource_id: String, node: Dictionary) -> String:
	var node_kind := String(node.get("node_kind", ""))
	if node_kind.is_empty():
		node_kind = node_kind_for_resource_context(resource_id, biome_id)
	return required_tool_for_resource_interaction(resource_id, node_kind)

func node_kind_for_resource_context(item_id: String, biome_id: String) -> String:
	if item_id.is_empty() or catalog == null:
		return ""
	var item: Dictionary = catalog.find_by_id("items", item_id)
	var interaction_definition: Dictionary = item.get("interaction_definition", {})
	var bootstrap: Dictionary = interaction_definition.get("bootstrap", {})
	if String(bootstrap.get("biome_id", "")) == biome_id:
		var pickup_kind := node_kind_for_resource_action(item_id, "pickup")
		if not pickup_kind.is_empty():
			return pickup_kind
	return node_kind_for_resource_action(item_id, "mine")

func node_kind_for_resource_action(item_id: String, action: String) -> String:
	if item_id.is_empty() or catalog == null:
		return ""
	var item: Dictionary = catalog.find_by_id("items", item_id)
	var interaction_definition: Dictionary = item.get("interaction_definition", {})
	for rule in interaction_definition.get("rules", []):
		if rule is Dictionary and String(rule.get("action", "")) == action:
			return String(rule.get("node_kind", ""))
	for rule in interaction_definition.get("rules", []):
		if rule is Dictionary:
			return String(rule.get("node_kind", ""))
	return ""

func required_tool_for_resource_interaction(item_id: String, node_kind: String) -> String:
	if item_id.is_empty() or node_kind.is_empty() or catalog == null:
		return ""
	var item: Dictionary = catalog.find_by_id("items", item_id)
	var interaction_definition: Dictionary = item.get("interaction_definition", {})
	for rule in interaction_definition.get("rules", []):
		if not rule is Dictionary or String(rule.get("node_kind", "")) != node_kind:
			continue
		var required_tool = rule.get("required_tool_item_id", "")
		return String(required_tool) if required_tool != null else ""
	return ""

func register_mountain_mineral_gatherables(definition_ids: Dictionary, acquisition_service) -> Dictionary:
	if world_data == null or acquisition_service == null:
		return {"ok": true}
	for definition_id in definition_ids:
		var id := String(definition_id)
		if not id.begins_with("terrain_mountain_mineral_") or not acquisition_service.gatherable_for(id).is_empty():
			continue
		var parts := id.trim_prefix("terrain_mountain_mineral_").split("_")
		if parts.size() != 2:
			continue
		var position := Vector2i(int(parts[0]), int(parts[1]))
		var registered: Dictionary = acquisition_service.register_gatherable(id, id, position)
		if not registered.ok:
			return registered
	return {"ok": true}

func tree_harvest_profile_for_cell(cell: Dictionary) -> Dictionary:
	var layers: Dictionary = cell.get("layers", {})
	var terrain: Dictionary = layers.get(WorldData.LAYER_TERRAIN, {})
	var terrain_id := String(terrain.get("id", ""))
	match terrain_id:
		WorldGenerator.TERRAIN_FOREST:
			return {"id": WorldGenerator.TERRAIN_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_MOUNTAIN_CONIFER:
			return {"id": WorldGenerator.TERRAIN_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_WASTELAND_DEAD_TREE:
			return {"id": WorldGenerator.TERRAIN_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_SNOWFIELD_PINE:
			return {"id": WorldGenerator.TERRAIN_GRASS, "walkable": true}
		WorldGenerator.TERRAIN_RAINFOREST_JUNGLE, WorldGenerator.TERRAIN_RAINFOREST_AGARWOOD:
			return {"id": WorldGenerator.TERRAIN_GRASS, "walkable": true}
		_:
			return {}

func generated_drop_definitions() -> Array:
	var grants_by_monster := {}
	for drop in catalog.get_definitions("drops"):
		var monster_id := String(drop.get("monster_id", ""))
		var target_id := String(drop.get("item_id", drop.get("tea_id", "")))
		if not grants_by_monster.has(monster_id):
			grants_by_monster[monster_id] = []
		grants_by_monster[monster_id].append({
			"drop_id": String(drop.get("id", "")),
			"item_id": target_id,
			"min_quantity": int(drop.get("min_quantity", 0)),
			"max_quantity": int(drop.get("max_quantity", 0)),
			"chance": float(drop.get("chance", 0.0)),
			"condition": String(drop.get("condition", "")),
			"policy": AcquisitionService.POLICY_DIRECT
		})
	var definitions := []
	var monster_ids: Array = grants_by_monster.keys()
	monster_ids.sort()
	for monster_id in monster_ids:
		definitions.append({"monster_id": monster_id, "grants": grants_by_monster[monster_id]})
	return definitions

func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
