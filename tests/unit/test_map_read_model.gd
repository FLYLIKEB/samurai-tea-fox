extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	_assert_map_read_model_respects_discovery_and_markers(asserts)
	_assert_default_discovery_covers_camera_view(asserts)
	_assert_map_read_model_does_not_mutate_world_data(asserts)
	_assert_minimap_is_bounded_around_player(asserts)
	_assert_commands_and_hud_open_full_map(asserts)
	_assert_map_discovery_save_round_trips(asserts)

func _assert_map_read_model_respects_discovery_and_markers(asserts) -> void:
	var world := _world()
	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.map_discovery = MapReadModelBuilder.discover_cells({}, Vector2i(2, 2), 1)
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	var model: Dictionary = builder.build(world, state, Vector2i(2, 2), {"discovery_radius": 0})
	asserts.true_value(model.ok, "map read model builds")
	asserts.true_value(model.read_only, "map read model is read-only")
	asserts.equal(model.bounds.width, 8, "map exposes world width")
	asserts.equal(model.bounds.height, 6, "map exposes world height")
	asserts.equal(model.discovered_count, 9, "map shows only discovered cells plus requested player reveal")
	asserts.equal(model.fog_count, 39, "map reports fog for undiscovered cells")
	asserts.equal(_marker_type(model.markers, "core_dungeon_0"), MapReadModelBuilder.MARKER_DUNGEON, "required dungeon is a known marker")
	asserts.equal(_marker_type(model.markers, "teleport_0"), MapReadModelBuilder.MARKER_TELEPORT, "required teleport is a known marker")
	asserts.false_value(_marker_discovered(model.markers, "teleport_0"), "required teleport marker can be known before its tile is discovered")
	asserts.equal(_marker_type(model.markers, "player"), MapReadModelBuilder.MARKER_PLAYER, "player marker is present")
	asserts.false_value(_cell_visible(model.cells, Vector2i(7, 5)), "undiscovered far cell is not exposed as terrain")
	var optional_world: Dictionary = world.to_dictionary()
	optional_world["required_landmarks"] = []
	optional_world["landmarks"] = [{
		"id": "optional_teleport",
		"type": WorldData.LANDMARK_TELEPORT_ZONE,
		"position": {"x": 7, "y": 5},
		"required": false
	}]
	var hidden_model: Dictionary = builder.build(optional_world, state, Vector2i(2, 2), {"discovery_radius": 0})
	asserts.equal(_marker_type(hidden_model.markers, "optional_teleport"), "", "optional undiscovered teleport marker stays hidden")

func _assert_default_discovery_covers_camera_view(asserts) -> void:
	var world := WorldData.new(24, 16, "grass", true)
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	var model: Dictionary = builder.build(world, RunState.new(), Vector2i(12, 8))
	asserts.true_value(_cell_visible(model.cells, Vector2i(7, 8)), "default discovery reaches the camera's horizontal left edge")
	asserts.true_value(_cell_visible(model.cells, Vector2i(17, 8)), "default discovery reaches the camera's horizontal right edge")
	asserts.true_value(_cell_visible(model.cells, Vector2i(12, 5)), "default discovery reaches the camera's vertical top edge")
	asserts.true_value(_cell_visible(model.cells, Vector2i(12, 11)), "default discovery reaches the camera's vertical bottom edge")

func _assert_map_read_model_does_not_mutate_world_data(asserts) -> void:
	var world := _world()
	var before := world.to_dictionary()
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	builder.build(world, RunState.new(), Vector2i(2, 2))
	asserts.equal(world.to_dictionary(), before, "map read model never mutates WorldData")

func _assert_minimap_is_bounded_around_player(asserts) -> void:
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	var model: Dictionary = builder.build(_world(), RunState.new(), Vector2i(6, 4), {"minimap_width": 5, "minimap_height": 3})
	asserts.true_value(model.ok, "bounded minimap builds")
	asserts.equal(model.minimap.size.width, 5, "minimap width respects bound")
	asserts.equal(model.minimap.size.height, 3, "minimap height respects bound")
	asserts.equal(model.minimap.cell_count, 15, "minimap emits only bounded visible cells")
	asserts.true_value(model.minimap.markers.size() <= model.markers.size(), "minimap marker list is clipped to viewport")

func _assert_commands_and_hud_open_full_map(asserts) -> void:
	var desktop := DesktopCommandAdapter.new()
	var mobile := MobileCommandAdapter.new()
	asserts.equal(desktop.command_for_action("open_map").type, GameCommand.Type.OPEN_MAP, "desktop open_map maps to shared command")
	asserts.equal(mobile.command_for_button("open_map").type, GameCommand.Type.OPEN_MAP, "mobile open_map maps to shared command")
	var project := FileAccess.get_file_as_string("res://project.godot")
	asserts.true_value("open_map={" in project, "project input map exposes open_map")

	var hud := GameHud.new()
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	var player := FakePlayer.new()
	player.global_position = Vector2(64, 64)
	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.map_discovery = MapReadModelBuilder.discover_cells({}, Vector2i(2, 2), 1)
	hud.configure(player, {"biome_id": "common_region"}, {"counts": {}}, {"map_read_model_builder": builder, "world_data": _world(), "run_state": state, "catalog": FakeCatalog.new()})
	asserts.true_value(hud.press_mobile_button("open_map"), "HUD emits open map command")
	asserts.true_value(hud.show_map_menu(), "HUD opens full map menu")
	asserts.true_value(_tree_has_text(hud, "지도 8x6"), "full map menu displays map bounds")
	var map_grid := hud.get_node_or_null("Root/MenuPanel/MenuRows/MenuScroll/MenuContent/MapColorGrid") as GridContainer
	asserts.true_value(map_grid != null, "full map menu renders map cells as a color grid")
	if map_grid != null:
		asserts.equal(map_grid.get_child_count(), 8 * 6, "full map color grid is clipped to the world bounds")
		asserts.true_value(_color_rect_count(map_grid) > 0, "full map grid renders terrain as color cells")
		asserts.true_value(_button_count(map_grid) > 0, "full map grid renders known markers as buttons")
		asserts.true_value(_marker_button_exists(map_grid, "teleport_0"), "full map grid includes the teleport marker button")
	asserts.true_value(_tree_has_text(hud, "텔레포트 · teleport_0"), "full map menu displays teleport marker")
	var teleport_button := _marker_button(map_grid, "teleport_0") if map_grid != null else null
	asserts.true_value(teleport_button != null, "teleport marker is clickable")
	if teleport_button != null:
		teleport_button.pressed.emit()
		asserts.true_value(_tree_has_text(hud, "teleport_0"), "teleport marker click opens marker detail")
	hud.free()

	var main := Main.new()
	main.map_read_model_builder = builder
	main.world_data = _world()
	main.run_state = RunState.new()
	asserts.true_value(main.map_read_model().ok, "Main exposes current map read model")
	main._record_current_map_discovery()
	asserts.true_value(main.run_state.map_discovery.discovered_cells.has("0,0"), "Main persists discovery outside the HUD")
	main.free()

func _assert_map_discovery_save_round_trips(asserts) -> void:
	var state := RunState.new()
	state.map_discovery = MapReadModelBuilder.discover_cells({}, Vector2i(1, 1), 1)
	var decoded: Dictionary = SaveCodec.decode_run(SaveCodec.encode_run(state))
	asserts.true_value(decoded.ok, "run save decodes with map discovery")
	asserts.true_value(decoded.run_state.map_discovery.discovered_cells.has("1,1"), "map discovery survives run save round-trip")

func _world() -> WorldData:
	var world := WorldData.new(8, 6, "grass", true)
	world.set_terrain(Vector2i(7, 5), "water", false)
	world.add_required_landmark(WorldData.LANDMARK_ENTRY, "entry_0", Vector2i(0, 0))
	world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "core_dungeon_0", Vector2i(6, 4), {"dungeon_id": "forest_core"})
	world.add_required_landmark(WorldData.LANDMARK_TELEPORT_ZONE, "teleport_0", Vector2i(1, 4), {"teleport_id": "teleport_common"})
	return world

func _marker_type(markers: Array, id: String) -> String:
	for marker in markers:
		if String(marker.get("id", "")) == id:
			return String(marker.get("marker_type", ""))
	return ""

func _marker_discovered(markers: Array, id: String) -> bool:
	for marker in markers:
		if String(marker.get("id", "")) == id:
			return bool(marker.get("discovered", true))
	return false

func _cell_visible(cells: Array, position: Vector2i) -> bool:
	for cell in cells:
		var raw: Dictionary = cell.get("position", {})
		if int(raw.get("x", -1)) == position.x and int(raw.get("y", -1)) == position.y:
			return true
	return false

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and text in node.text:
		return true
	if node is Button and text in node.text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

func _color_rect_count(node: Node) -> int:
	var count := 1 if node is ColorRect else 0
	for child in node.get_children():
		count += _color_rect_count(child)
	return count

func _button_count(node: Node) -> int:
	var count := 1 if node is Button else 0
	for child in node.get_children():
		count += _button_count(child)
	return count

func _marker_button_exists(node: Node, id: String) -> bool:
	return _marker_button(node, id) != null

func _marker_button(node: Node, id: String) -> Button:
	if node is Button and (node as Button).tooltip_text == id:
		return node as Button
	for child in node.get_children():
		var found := _marker_button(child, id)
		if found != null:
			return found
	return null

class FakeResources:
	var hp := 10
	var hp_max := 10
	var ki := 4
	var ki_max := 4
	var kokoro := 1
	var kokoro_max := 1

class FakePlayer:
	var resources := FakeResources.new()
	var global_position := Vector2.ZERO

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		return [{"id": "ability_equip_slots", "value": 1}] if key == "balance" else []
	func find_by_id(key: String, id: String) -> Dictionary:
		for row in get_definitions(key):
			if row.id == id:
				return row
		return {}
