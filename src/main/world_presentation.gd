extends RefCounted
## 월드의 시각 출처·카메라·안내 표시를 담당한다. 생성/진행/저장 상태는 변경하지 않는다.

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

static func centered_world_origin(renderer_input: Dictionary) -> Vector2:
	var bounds: Dictionary = renderer_input.get("bounds", {})
	var tile_size := int(renderer_input.get("tile_size", RuntimeConstants.float_value("world.tile_size_pixels")))
	return Vector2(
		-float(int(bounds.get("width", 0)) * tile_size) * 0.5,
		-float(int(bounds.get("height", 0)) * tile_size) * 0.5
	)

static func owner_sprite_sources(world: Dictionary) -> Dictionary:
	var sources := {
		WorldData.LANDMARK_ENTRY: "small_signpost",
		WorldData.LANDMARK_CORE_DUNGEON: "asset_assets_sprites_objects_structures_warehouse_2x2_64x64_png",
		WorldData.LANDMARK_RUIN: "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png",
		WorldData.LANDMARK_TELEPORT_ZONE: "asset_assets_tiles_sheets_biome_atlases_biome_tile_map_light_object_biome_map_atlas_crop_1261_363_32x32_resize_32x32_png",
		"wood": "log_resource",
		"stone": "small_rock_resource",
		"clay": "mud_patch_resource"
	}
	merge_projected_owner_sources(sources, world.get("renderer_input", {}))
	for node in world.get("resource_nodes", []):
		var owner_id := String(node.get("id", ""))
		var resource_id := String(node.get("resource_id", ""))
		var source_id := String(node.get("source_id", ""))
		if owner_id != "" and not source_id.is_empty():
			sources[owner_id] = source_id
		elif owner_id != "" and not sources.has(owner_id) and sources.has(resource_id):
			sources[owner_id] = sources[resource_id]
	for node in world.get("facility_nodes", []):
		var owner_id := String(node.get("id", ""))
		var source_id := String(node.get("source_id", ""))
		if owner_id != "" and source_id != "" and not sources.has(owner_id):
			sources[owner_id] = source_id
	# Generated path fences (and other procedural entities) keep their sprite
	# reference in WorldData reservations rather than the high-level node lists.
	var snapshot: Dictionary = world.get("world_data", world)
	for reservation in snapshot.get("reservations", []):
		var reservation_id := String(reservation.get("owner_id", ""))
		var metadata: Dictionary = reservation.get("metadata", {})
		var reservation_source := String(metadata.get("source_id", ""))
		if not reservation_id.is_empty() and not reservation_source.is_empty():
			sources[reservation_id] = reservation_source
	return sources

static func merge_projected_owner_sources(sources: Dictionary, renderer_input: Dictionary) -> void:
	for layer in renderer_input.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		if layer_id not in [WorldData.LAYER_FACILITIES, WorldData.LAYER_ENTITIES, WorldData.LAYER_INTERACTABLES]:
			continue
		for cell in layer.get("cells", []):
			var owner_id := String(cell.get("owner_id", ""))
			var source_id := String(cell.get("source_id", ""))
			if not owner_id.is_empty() and not source_id.is_empty():
				sources[owner_id] = source_id

static func entry_spawn_cell(world: Dictionary) -> Vector2i:
	var landmarks: Array = world.get("required_landmarks", [])
	if landmarks.is_empty():
		landmarks = world.get("landmarks", [])
	if landmarks.is_empty():
		var renderer_input: Dictionary = world.get("renderer_input", {})
		landmarks = renderer_input.get("required_landmarks", [])
	for landmark in landmarks:
		if String(landmark.get("kind", landmark.get("type", ""))) != WorldData.LANDMARK_ENTRY:
			continue
		return _vector_from_dictionary(landmark.get("position", {}))
	return Vector2i.ZERO

static func configure_camera(player, world_data, origin: Vector2, tile_size: float) -> void:
	if player == null or world_data == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.zoom = Vector2.ONE * RuntimeConstants.float_value("camera.zoom")
	camera.limit_left = int(floor(origin.x))
	camera.limit_top = int(floor(origin.y))
	camera.limit_right = int(ceil(origin.x + float(world_data.width) * tile_size))
	camera.limit_bottom = int(ceil(origin.y + float(world_data.height) * tile_size))
	camera.enabled = true

static func update_interaction_prompts(world_visuals, player_cell: Vector2i, tile_size: float) -> void:
	if world_visuals == null:
		return
	for sign in world_visuals.find_children("InteractionPrompt", "PanelContainer", true, false):
		var sign_node := sign as Control
		var local_cell := Vector2i(int(round(sign_node.position.x / tile_size)), int(round((sign_node.position.y + 52.0) / tile_size)))
		sign_node.visible = player_cell.distance_to(local_cell) <= 4.0

static func apply_teleport_states(renderer_input: Dictionary, run_state) -> void:
	if run_state == null:
		return
	var current_biome_id := String(run_state.current_biome_id)
	for landmark in renderer_input.get("required_landmarks", []):
		if String(landmark.get("kind", landmark.get("type", ""))) != WorldData.LANDMARK_TELEPORT_ZONE:
			continue
		landmark["teleport_state"] = String(run_state.teleport_states.get(current_biome_id, "undiscovered"))

static func hide_prototype_visuals(scene_root: Node) -> void:
	for child in scene_root.get_children():
		if child is Polygon2D:
			child.visible = false
		if child is StaticBody2D:
			child.collision_layer = 0
			child.collision_mask = 0
			for descendant in child.find_children("*", "CollisionShape2D", true, false):
				(descendant as CollisionShape2D).disabled = true

static func _vector_from_dictionary(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
