extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const RunState = preload("res://src/save/run_state.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

const CAPTURES := [
	{"name": "desktop_1280x720", "size": Vector2i(1280, 720)},
	{"name": "mobile_360x640", "size": Vector2i(360, 640)}
]
const CAPTURE_DIR := "res://docs/reports/dev-115-map-hud"

class FakeResources:
	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

class FakePlayer:
	var resources := FakeResources.new()
	var global_position := Vector2(64, 64)

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		match key:
			"balance":
				return [{"id": "ability_equip_slots", "value": 1}]
			"biomes":
				return [{"id": "common_region", "name": "초록 평원", "progression_order": 1}]
			_:
				return []

	func find_by_id(key: String, id: String) -> Dictionary:
		for definition in get_definitions(key):
			if String(definition.get("id", "")) == id:
				return definition
		return {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	for capture in CAPTURES:
		var result := await _capture_map(String(capture.name), capture.size)
		if not result.ok:
			push_error(String(result.get("error", "capture failed")))
			quit(1)
			return
	print("DEV-115 map HUD captures saved: %d" % CAPTURES.size())
	quit(0)

func _capture_map(capture_name: String, viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % capture_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud := GameHud.new()
	viewport.add_child(hud)
	var builder := MapReadModelBuilder.new()
	builder.configure("dev-115-map-capture")
	var run_state := RunState.new()
	run_state.current_biome_id = "common_region"
	run_state.map_discovery = MapReadModelBuilder.discover_cells({}, Vector2i(2, 2), 1)
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {
		"catalog": FakeCatalog.new(),
		"map_read_model_builder": builder,
		"world_data": _world(),
		"run_state": run_state
	})
	hud.show_map_menu()
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	var menu := hud.get_node_or_null("Root/MenuPanel") as Control
	var grid := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/MapColorGrid") as GridContainer
	if menu == null or not menu.visible:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing visible map menu" % capture_name}
	if grid == null or grid.get_child_count() != 48:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing 8x6 map grid" % capture_name}
	if _color_rect_count(grid) == 0:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing terrain color cells" % capture_name}
	if _marker_button(grid, "teleport_0") == null:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing teleport marker button" % capture_name}
	var menu_rect := menu.get_global_rect()
	if menu_rect.position.x < 0.0 or menu_rect.position.y < 0.0 or menu_rect.end.x > viewport_size.x or menu_rect.end.y > viewport_size.y:
		viewport.queue_free()
		return {"ok": false, "error": "%s map menu outside viewport: %s" % [capture_name, menu_rect]}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "%s requires a rendering display driver; headless dummy renderer has no viewport texture" % capture_name}
	var output_path := "%s/%s.png" % [CAPTURE_DIR, capture_name]
	var save_result := image.save_png(output_path)
	viewport.queue_free()
	if save_result != OK:
		return {"ok": false, "error": "%s failed to save %s" % [capture_name, output_path]}
	return {"ok": true, "path": output_path}

func _world() -> WorldData:
	var world := WorldData.new(8, 6, "grass", true)
	world.set_terrain(Vector2i(7, 5), "water", false)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 0))
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_dungeon_0", Vector2i(6, 4), {"dungeon_id": "forest_core"})
	world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_0", Vector2i(1, 4), {"teleport_id": "teleport_common"})
	return world

func _color_rect_count(node: Node) -> int:
	var count := 1 if node is ColorRect else 0
	for child in node.get_children():
		count += _color_rect_count(child)
	return count

func _marker_button(node: Node, id: String) -> Button:
	if node is Button and (node as Button).tooltip_text == id:
		return node as Button
	for child in node.get_children():
		var found := _marker_button(child, id)
		if found != null:
			return found
	return null
