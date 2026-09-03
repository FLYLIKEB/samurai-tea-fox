extends SceneTree

const GameCommand = preload("res://src/core/commands/game_command.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunState = preload("res://src/save/run_state.gd")
const SaveStore = preload("res://src/save/save_store.gd")

const LIFECYCLE_DIRECTORY := "user://dev24_main_lifecycle_integration"
const RUN_PATH := LIFECYCLE_DIRECTORY + "/run.json"
const META_PATH := LIFECYCLE_DIRECTORY + "/meta.json"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		failures.append("main scene loads")
		finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame

	var world_visuals := main.get_node_or_null("WorldVisuals") as Node2D
	if world_visuals == null:
		failures.append("main scene owns a WorldVisuals node")
	else:
		var terrain := world_visuals.get_node_or_null("TerrainTileMap") as TileMapLayer
		if terrain == null:
			failures.append("generated world terrain is rendered as a TileMapLayer")
		elif terrain.get_used_cells().size() < 100:
			failures.append("generated world terrain tilemap contains generated cells")
		elif terrain.tile_set == null or terrain.tile_set.get_source_count() == 0:
			failures.append("terrain tilemap has a runtime tileset from promoted assets")
		var entities := world_visuals.get_node_or_null("Entities") as Node2D
		if entities == null or entities.get_child_count() == 0:
			failures.append("resource nodes are rendered with object sprites")
		var landmarks := world_visuals.get_node_or_null("Landmarks") as Node2D
		if landmarks == null or landmarks.get_child_count() == 0:
			failures.append("required landmarks are rendered with object sprites")

	var ground := main.get_node_or_null("Ground") as Polygon2D
	if ground != null and ground.visible:
		failures.append("prototype polygon ground is hidden after runtime sprite render")

	var player = main.get_node_or_null("Player")
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D if player != null else null
	if sprite == null or sprite.texture == null:
		failures.append("player sprite remains visible in main scene")
	if player != null:
		var expected_spawn_cell: Vector2i = main._entry_spawn_cell(main.generated_world)
		var actual_spawn_cell: Vector2i = main.world_cell_from_world_position(player.global_position)
		if actual_spawn_cell != expected_spawn_cell:
			failures.append("player starts on the generated entry cell")
		if not main.world_data.is_walkable(actual_spawn_cell):
			failures.append("player starts on a walkable generated map cell")
		var walkable_neighbor := _first_walkable_neighbor(main, actual_spawn_cell)
		if walkable_neighbor == Vector2i.ZERO:
			failures.append("player entry cell has an adjacent walkable movement target")
		else:
			if not main.submit_mobile_movement_direction(walkable_neighbor):
				failures.append("player can submit movement from entry toward a walkable neighbor")
			await physics_frame
			if player.is_grid_step_active():
				for _step_frame in 20:
					await physics_frame
					if not player.is_grid_step_active():
						break
			var moved_cell: Vector2i = main.world_cell_from_world_position(player.global_position)
			var expected_cell: Vector2i = actual_spawn_cell + walkable_neighbor
			if moved_cell != expected_cell:
				failures.append("player movement grid matches generated world walkability: spawn=%s direction=%s expected=%s actual=%s position=%s" % [actual_spawn_cell, walkable_neighbor, expected_cell, moved_cell, player.global_position])
			player.global_position = main.world_position_for_cell_center(actual_spawn_cell)

	var dummy = main.get_node_or_null("CombatDummy")
	var dummy_sprite := dummy.get_node_or_null("Sprite2D") as Sprite2D if dummy != null else null
	if dummy_sprite == null or dummy_sprite.texture == null:
		failures.append("combat dummy renders with a promoted enemy character sprite")
	if dummy != null:
		var dummy_cell: Vector2i = main.world_cell_from_world_position(dummy.global_position)
		if dummy.global_position != main.world_position_for_cell_center(dummy_cell):
			failures.append("combat dummy snaps to the center of its current terrain cell")
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera == null:
			failures.append("player keeps a runtime camera")
		else:
			var origin: Vector2 = main._runtime_world_origin()
			var tile_size: float = main._runtime_tile_size()
			if camera.limit_left != int(floor(origin.x)) or camera.limit_top != int(floor(origin.y)):
				failures.append("runtime camera follows generated world origin limits")
			if camera.limit_right != int(ceil(origin.x + float(main.world_data.width) * tile_size)) or camera.limit_bottom != int(ceil(origin.y + float(main.world_data.height) * tile_size)):
				failures.append("runtime camera follows generated world bottom-right limits")

	_assert_runtime_death_replaces_run(main, player)
	_assert_stale_full_death_retry_preserves_newer_run(main)

	var hud := main.get_node_or_null("GameHud")
	if hud == null:
		failures.append("main scene owns a runtime HUD")
	else:
		if hud.has_method("narrative_dialogue_visible") and hud.narrative_dialogue_visible():
			hud.hide_narrative_dialogue()
			await process_frame
		var status_panel := hud.get_node_or_null("Root/StatusPanel")
		var map_panel := hud.get_node_or_null("Root/MapPanel")
		var quickslot_panel := hud.get_node_or_null("Root/QuickSlotPanel")
		var dpad_panel := hud.get_node_or_null("Root/DPadPanel")
		var action_panel := hud.get_node_or_null("Root/ActionPanel")
		var enemy_panel := hud.get_node_or_null("Root/EnemyPanel")
		if status_panel == null or map_panel == null or quickslot_panel == null or dpad_panel == null or action_panel == null or enemy_panel == null:
			failures.append("runtime HUD shows status, map, enemy, quickslot, dpad, and action panels")
		elif not dpad_panel.visible or dpad_panel.custom_minimum_size.x > 90.0:
			failures.append("runtime HUD shows the compact mockup-style directional pad")
		elif _texture_rect_count(status_panel) < 4 or _label_count(status_panel) < 3:
			failures.append("runtime HUD status panel renders portrait plus icon-backed resource rows")
		elif not enemy_panel.visible or _label_count(enemy_panel) < 3:
			failures.append("runtime HUD enemy panel renders combat target name, HP, and weapon stats")
		elif _texture_rect_count(quickslot_panel) < 4 or _label_count(quickslot_panel) < 4:
			failures.append("runtime HUD quickslots render icon-backed rows")
		else:
			_assert_hud_layout_fits_viewport([status_panel, map_panel, enemy_panel, quickslot_panel, action_panel])
			_assert_hud_layout_keeps_center_play_area_clear([status_panel, map_panel, enemy_panel, quickslot_panel, dpad_panel, action_panel])
			var visible_action_buttons := _button_count(action_panel)
			if visible_action_buttons > 9:
				failures.append("runtime HUD keeps secondary actions grouped instead of showing every command at once: %d buttons" % visible_action_buttons)
			if action_panel.get_node_or_null("ActionScroll/ActionRows/ActionTabs/MenuTab") == null:
				failures.append("runtime HUD exposes secondary action groups through category tabs")
			var time_label := hud.get("_labels").get("time") as Label
			if time_label == null or not time_label.get_parent().visible:
				failures.append("runtime HUD shows the canonical runtime time state")
		if not _passive_controls_ignore_mouse(hud):
			failures.append("runtime HUD passive controls do not block world click and touch input")

	var unopened_inventory := GameCommand.new(GameCommand.Type.OPEN_INVENTORY)
	if not main.submit_mobile_action_command(unopened_inventory):
		failures.append("OPEN_INVENTORY opens the fast inventory menu")
	if hud != null:
		var inventory_menu := hud.get_node_or_null("Root/MenuPanel")
		if inventory_menu == null or not inventory_menu.visible:
			failures.append("inventory command makes the side menu visible without covering screen center")
	if main.feedback_beep_count <= 0:
		failures.append("accepted runtime UI command plays feedback beep")

	main.queue_free()
	_cleanup_lifecycle_files()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("Main runtime rendering integration passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _texture_rect_count(node: Node) -> int:
	var count := 1 if node is TextureRect and (node as TextureRect).texture != null else 0
	for child in node.get_children():
		count += _texture_rect_count(child)
	return count

func _label_count(node: Node) -> int:
	var count := 1 if node is Label and not (node as Label).text.is_empty() else 0
	for child in node.get_children():
		count += _label_count(child)
	return count

func _button_count(node: Node) -> int:
	var count := 1 if node is BaseButton else 0
	for child in node.get_children():
		count += _button_count(child)
	return count

func _first_walkable_neighbor(main, origin: Vector2i) -> Vector2i:
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if main.world_data.is_walkable(origin + direction):
			return direction
	return Vector2i.ZERO

func _passive_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and not node is BaseButton and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _passive_controls_ignore_mouse(child):
			return false
	return true

func _assert_hud_layout_fits_viewport(panels: Array) -> void:
	var viewport_size := Vector2(640, 360)
	if not panels.is_empty() and panels[0] is Control:
		var actual_size := (panels[0] as Control).get_viewport_rect().size
		if actual_size.x > 64.0 and actual_size.y > 64.0:
			viewport_size = actual_size
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	for panel in panels:
		var control := panel as Control
		if control == null:
			continue
		if not viewport_rect.encloses(control.get_global_rect()):
			failures.append("runtime HUD panel stays inside the 640x360 viewport: %s rect=%s viewport=%s" % [control.name, control.get_global_rect(), viewport_rect])
		var minimum := control.get_combined_minimum_size()
		if minimum.x > control.size.x + 0.5 or minimum.y > control.size.y + 0.5:
			failures.append("runtime HUD panel content fits its frame: %s" % control.name)

func _assert_hud_layout_keeps_center_play_area_clear(panels: Array) -> void:
	var center_play_area := Rect2(Vector2(272, 132), Vector2(96, 96))
	for panel in panels:
		var control := panel as Control
		if control == null or not control.visible:
			continue
		if center_play_area.intersects(control.get_global_rect(), true):
			failures.append("runtime HUD panel avoids the central 640x360 play area: %s rect=%s safe=%s" % [control.name, control.get_global_rect(), center_play_area])

func _assert_runtime_death_replaces_run(main, player) -> void:
	_cleanup_lifecycle_files()
	var store := SaveStore.new(RUN_PATH, META_PATH)
	if not _has_property(main, "save_store"):
		failures.append("main runtime exposes an injectable run save boundary")
		return
	main.save_store = store
	main.run_state.lifecycle_epoch = 0
	main.run_state.seed = 701
	if not main.inventory.add_item("wood", 1).ok:
		failures.append("main lifecycle fixture stores run-only inventory")
		return
	main.run_state.inventory = main.inventory.to_snapshot()
	if not store.save_run(main.run_state).ok:
		failures.append("main lifecycle fixture persists the current run")
		return
	var meta := MetaState.new()
	meta.run_count = 9
	if not store.save_meta(meta).ok:
		failures.append("main lifecycle fixture persists meta separately")
		return
	var meta_before := FileAccess.get_file_as_string(META_PATH)
	var lifecycle_before = main.run_lifecycle_service
	var inventory_before = main.inventory
	var acquisition_before = main.acquisition_service
	player.resources.apply_damage(player.resources.hp_max)

	var loaded := SaveStore.new(RUN_PATH, META_PATH).load_run()
	if not loaded.ok:
		failures.append("real main death path persists a fresh resumable run")
		return
	if loaded.state.lifecycle_epoch != 1 or loaded.state.seed != 0:
		failures.append("real main death path advances lifecycle epoch and replaces run data")
	if main.run_state.lifecycle_epoch != 1 or main.run_state.seed != 0:
		failures.append("real main runtime activates the persisted fresh run")
	if main.run_lifecycle_service == lifecycle_before or main.run_lifecycle_service.death_confirmed:
		failures.append("real main death path reinitializes lifecycle service")
	if main.inventory == inventory_before or main.acquisition_service == acquisition_before:
		failures.append("real main death path reinitializes run-owned services")
	if main.inventory.get_total_quantity("wood") != 0:
		failures.append("real main death path clears run-only inventory")
	if player.resources.hp != player.resources.hp_max:
		failures.append("real main death path reinitializes player resources")
	if FileAccess.get_file_as_string(META_PATH) != meta_before:
		failures.append("real main death replacement preserves meta save")
	var marker = JSON.parse_string(FileAccess.get_file_as_string(RUN_PATH + ".invalidated.json"))
	if typeof(marker) != TYPE_DICTIONARY or int(marker.get("invalidated_lifecycle_epoch", -1)) != 0:
		failures.append("real main death path invalidates the old epoch before fresh persistence")

func _assert_stale_full_death_retry_preserves_newer_run(main) -> void:
	_cleanup_lifecycle_files()
	var store := SaveStore.new(RUN_PATH, META_PATH)
	main.save_store = store
	var stale_run := RunState.new()
	stale_run.data_version = main.catalog.data_version
	stale_run.lifecycle_epoch = 0
	stale_run.seed = 801
	stale_run.inventory = main.inventory.to_snapshot()
	if not store.save_run(stale_run).ok or not store.invalidate_run(stale_run).ok:
		failures.append("stale full-death fixture invalidates epoch zero")
		return

	if not main.inventory.add_item("wood", 3).ok:
		failures.append("stale full-death fixture creates non-default fresh inventory")
		return
	var preserved_run := RunState.new()
	preserved_run.data_version = main.catalog.data_version
	preserved_run.lifecycle_epoch = 1
	preserved_run.seed = 8675309
	preserved_run.currency = 47
	preserved_run.inventory = main.inventory.to_snapshot()
	if not store.save_run(preserved_run).ok:
		failures.append("stale full-death fixture persists newer non-default run")
		return
	var preserved_bytes := FileAccess.get_file_as_string(RUN_PATH)
	var restored: Dictionary = main.restore_run_state(stale_run)
	if not restored.ok:
		failures.append("stale full-death fixture restores stale runtime state")
		return
	main.run_lifecycle_service.death_pending = true

	var retry: Dictionary = main._replace_confirmed_dead_run()
	if not retry.ok or retry.get("state", "") != "preserved_run_activated":
		failures.append("main treats stale full-death retry as preserved-run activation")
	if not bool(retry.get("preserved_newer_run", false)):
		failures.append("main propagates preserved newer run result")
	if FileAccess.get_file_as_string(RUN_PATH) != preserved_bytes:
		failures.append("stale full-death retry keeps exact persisted bytes")
	var restarted := SaveStore.new(RUN_PATH, META_PATH).load_run()
	if not restarted.ok:
		failures.append("process restart loads preserved non-default run after stale full-death retry")
		return
	if restarted.state.lifecycle_epoch != 1 or restarted.state.seed != 8675309 or restarted.state.currency != 47:
		failures.append("stale full-death retry preserves newer run identity and scalar payload")
	if main.run_state.lifecycle_epoch != 1 or main.run_state.seed != 8675309 or main.inventory.get_total_quantity("wood") != 3:
		failures.append("main activates exact preserved epoch, seed, and inventory")

func _cleanup_lifecycle_files() -> void:
	for path in [RUN_PATH, RUN_PATH + ".tmp", RUN_PATH + ".invalidated.json", RUN_PATH + ".invalidated.json.tmp", META_PATH, META_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var directory := ProjectSettings.globalize_path(LIFECYCLE_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)

func _has_property(object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.name) == property_name:
			return true
	return false
