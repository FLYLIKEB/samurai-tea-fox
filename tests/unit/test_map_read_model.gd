extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const DesktopCommandAdapter = preload("res://src/core/commands/desktop_command_adapter.gd")
const MobileCommandAdapter = preload("res://src/core/commands/mobile_command_adapter.gd")
const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const GameHudReadModelProvider = preload("res://src/ui/game_hud_read_model_provider.gd")
const MapReadModelBuilder = preload("res://src/world/map/map_read_model_builder.gd")
const Main = preload("res://src/main/main.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveCodec = preload("res://src/save/save_codec.gd")
const SaveStore = preload("res://src/save/save_store.gd")
const WorldData = preload("res://src/world/data/world_data.gd")

func run(asserts) -> void:
	_assert_map_read_model_respects_discovery_and_markers(asserts)
	_assert_default_discovery_covers_camera_view(asserts)
	_assert_map_read_model_does_not_mutate_world_data(asserts)
	_assert_minimap_is_bounded_around_player(asserts)
	_assert_commands_and_hud_open_full_map(asserts)
	_assert_map_discovery_save_round_trips(asserts)
	_assert_selected_biome_preview_matches_actual_entry_and_resume(asserts)
	_assert_selected_biome_preview_does_not_reuse_current_map_cache(asserts)

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
	asserts.false_value(_tree_has_text(hud, "종류: 텔레포트"), "teleport marker detail is absent before click")
	if teleport_button != null:
		teleport_button.pressed.emit()
		asserts.true_value(_tree_has_text(hud, "지도 정보"), "teleport marker click opens marker detail title")
		asserts.true_value(_tree_has_text(hud, "종류: 텔레포트"), "teleport marker detail shows marker type")
		asserts.true_value(_tree_has_text(hud, "좌표: (1, 4)"), "teleport marker detail shows coordinates")
		asserts.true_value(_tree_has_text(hud, "상태: 확인됨"), "teleport marker detail shows full-map discovery status")
		asserts.true_value(_tree_has_text(hud, "지도 돌아가기"), "teleport marker detail has a map back action")
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

func _assert_selected_biome_preview_matches_actual_entry_and_resume(asserts) -> void:
	var paths := _save_paths("biome-parity")
	_cleanup_paths(paths)
	var main := _generation_main(paths)
	main.run_state.seed = 424242
	main.run_state.current_biome_id = "common_region"
	main.run_state.completed_dungeon_ids = ["common_region"]
	main.run_state.teleport_states = {"common_region": "repaired", "mountain_region": "undiscovered"}
	main.run_state.repaired_teleports = ["common_region"]
	main.run_state.crafting_unlocks = ["common_region"]
	asserts.true_value(main._configure_world_for_current_run().ok, "common run builds biome previews")
	asserts.true_value(main._biome_map_previews.has("mountain_region"), "mountain preview is cached from current run")
	asserts.true_value(main._is_connected_biome("common_region", "mountain_region"), "mountain biome is connected after common teleport repair")
	var preview_contract := _static_map_contract(main._biome_map_previews.mountain_region.world_data)
	var advance: Dictionary = main.biome_progression_state.apply_command(GameCommand.new(GameCommand.Type.ADVANCE_BIOME, Vector2i.ZERO, -1, {"biome_id": "common_region"}))
	asserts.true_value(advance.ok, "runtime progression enters mountain biome: %s" % str(advance))
	var mountain_world: Dictionary = main._configure_world_for_current_run()
	asserts.true_value(mountain_world.ok, "runtime configures entered mountain world: %s" % str(mountain_world))
	var actual_contract := _static_map_contract(main.generated_world.world_data)
	asserts.equal(actual_contract, preview_contract, "mountain preview terrain and required landmarks match actual entry")
	asserts.true_value(main.save_current_run().ok, "entered mountain run saves through explicit test SaveStore paths")
	var loaded: Dictionary = main.save_store.load_run()
	asserts.true_value(loaded.ok, "saved mountain run reloads")

	var restored := _generation_main(paths, false)
	restored.run_state = loaded.run_state
	asserts.true_value(restored._configure_run_services(restored.catalog).ok, "restored main services configure")
	asserts.true_value(restored._configure_world_for_current_run().ok, "restored mountain run regenerates")
	asserts.equal(_static_map_contract(restored.generated_world.world_data), preview_contract, "resumed mountain terrain and required landmarks match preview")
	_cleanup_main(main, false)
	_cleanup_main(restored, false)
	_cleanup_paths(paths)

func _assert_selected_biome_preview_does_not_reuse_current_map_cache(asserts) -> void:
	var provider := GameHudReadModelProvider.new()
	var builder := MapReadModelBuilder.new()
	builder.configure("map-fixture")
	var state := RunState.new()
	state.current_biome_id = "common_region"
	state.map_discovery = MapReadModelBuilder.discover_cells({}, Vector2i(2, 2), 1)
	var current_world := _world()
	var mountain_world := WorldData.new(8, 6, "mountain_path", true)
	mountain_world.add_required_landmark(WorldData.LANDMARK_ENTRY, "mountain_entry", Vector2i(0, 0))
	mountain_world.add_required_landmark(WorldData.LANDMARK_CORE_DUNGEON, "mountain_core", Vector2i(7, 5))
	var player := FakePlayer.new()
	player.global_position = Vector2(64, 64)
	provider.configure(player, {"biome_id": "common_region"}, {"counts": {}}, {
		"map_read_model_builder": builder,
		"world_data": current_world,
		"run_state": state,
		"catalog": FakeCatalog.new(),
		"biome_map_previews": {
			"mountain_region": {"world_data": mountain_world.to_dictionary()}
		}
	})
	var selected: Dictionary = provider.map_read_model({"discovery_radius": 0}, "mountain_region")
	asserts.true_value(selected.ok, "selected biome preview read model builds")
	asserts.equal(selected.dungeon_progress.biome_id, "mountain_region", "selected biome read model uses preview biome identity")
	asserts.equal(_marker_type(selected.markers, "mountain_core"), MapReadModelBuilder.MARKER_DUNGEON, "selected biome read model uses selected preview landmarks")
	asserts.equal(_marker_type(selected.markers, "core_dungeon_0"), "", "selected biome read model does not leak current biome landmarks")
	asserts.equal(_marker_type(selected.markers, "player"), "", "selected biome read model does not show current biome player marker")
	asserts.equal(selected.discovered_count, 0, "selected biome read model does not reuse current biome discovery or player reveal cells")
	var current: Dictionary = provider.map_read_model({"discovery_radius": 0}, "common_region")
	asserts.true_value(current.ok, "current biome read model still builds")
	asserts.equal(_marker_type(current.markers, "core_dungeon_0"), MapReadModelBuilder.MARKER_DUNGEON, "current biome read model keeps current landmarks")
	asserts.equal(_marker_type(current.markers, "mountain_core"), "", "current biome read model does not leak selected preview landmarks")
	asserts.equal(current.discovered_count, 9, "current biome read model keeps current discovery state")
	var missing: Dictionary = provider.map_read_model({}, "wasteland")
	asserts.false_value(missing.ok, "unvisited selected biome without preview is not backed by current map cache")
	asserts.equal(missing.reason, "missing_biome_map_preview", "missing selected biome preview has stable reason")

	var visited_state := RunState.new()
	visited_state.current_biome_id = "common_region"
	visited_state.map_discovery = state.map_discovery
	visited_state.map_discovery_by_biome = {
		"mountain_region": {"discovered_cells": ["7,5"]}
	}
	var visited_provider := GameHudReadModelProvider.new()
	visited_provider.configure(player, {"biome_id": "common_region"}, {"counts": {}}, {
		"map_read_model_builder": builder,
		"world_data": current_world,
		"run_state": visited_state,
		"catalog": FakeCatalog.new(),
		"biome_map_previews": {
			"mountain_region": {"world_data": mountain_world.to_dictionary()}
		}
	})
	var visited: Dictionary = visited_provider.map_read_model({"discovery_radius": 0}, "mountain_region")
	asserts.true_value(visited.ok, "visited selected biome preview read model builds")
	asserts.equal(visited.discovered_count, 1, "selected biome read model uses selected biome discovery when present")
	asserts.true_value(_cell_visible(visited.cells, Vector2i(7, 5)), "selected biome read model preserves the selected biome discovered cell")
	asserts.equal(_marker_type(visited.markers, "player"), "", "visited selected biome still does not show current biome player marker")

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

class FakeCombatDummy:
	extends Node2D
	signal drop_requested(event)
	var monster_id := "test_monster"
	var automatic_attacks := true
	var collision_layer := 2
	var collision_mask := 1
	var combatant := FakeCombatant.new()

	func current_hp() -> int:
		return 1

class FakeCombatant:
	var hp := 1
	var hp_max := 1

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		return [{"id": "ability_equip_slots", "value": 1}] if key == "balance" else []
	func find_by_id(key: String, id: String) -> Dictionary:
		for row in get_definitions(key):
			if row.id == id:
				return row
		return {}

func _generation_main(paths: Dictionary, clean_paths := true) -> Main:
	if clean_paths:
		_cleanup_paths(paths)
	var catalog := DataCatalog.new()
	assert(catalog.load_from_directory("res://data/generated").ok)
	var main := Main.new()
	main.catalog = catalog
	main.run_state = RunState.new()
	main.save_store = SaveStore.new(paths.run, paths.meta)
	main.combat_dummy = FakeCombatDummy.new()
	main.world_visuals = Node2D.new()
	assert(main._configure_run_services(catalog).ok)
	return main

func _static_map_contract(world_dictionary: Dictionary) -> Dictionary:
	var terrain_by_cell := {}
	for raw_cell in world_dictionary.get("cells", []):
		var cell: Dictionary = raw_cell
		var position: Dictionary = cell.get("position", {})
		var terrain: Dictionary = cell.get("layers", {}).get(WorldData.LAYER_TERRAIN, {})
		terrain_by_cell["%d,%d" % [int(position.get("x", 0)), int(position.get("y", 0))]] = {
			"id": String(terrain.get("id", "")),
			"walkable": bool(terrain.get("walkable", false))
		}
	var landmarks := []
	for raw_landmark in world_dictionary.get("required_landmarks", []):
		var landmark: Dictionary = raw_landmark
		landmarks.append({
			"id": String(landmark.get("id", "")),
			"type": String(landmark.get("type", landmark.get("kind", ""))),
			"position": landmark.get("position", {})
		})
	landmarks.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.id) < String(right.id))
	return {"terrain": terrain_by_cell, "required_landmarks": landmarks}

func _save_paths(label: String) -> Dictionary:
	var base := "user://samurai-tea-fox-dev114/%s" % label
	return {
		"run": "%s.run.save.json" % base,
		"meta": "%s.meta.save.json" % base
	}

func _cleanup_main(main: Main, clean_paths := true) -> void:
	var paths := {"run": main.save_store.run_path, "meta": main.save_store.meta_path} if main.save_store != null else {}
	if main.combat_dummy != null:
		main.combat_dummy.free()
	if main.world_visuals != null:
		main.world_visuals.free()
	main.free()
	if clean_paths:
		_cleanup_paths(paths)

func _cleanup_paths(paths: Dictionary) -> void:
	for path in [String(paths.get("run", "")), String(paths.get("meta", "")), "%s.invalidated.json" % String(paths.get("run", ""))]:
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
