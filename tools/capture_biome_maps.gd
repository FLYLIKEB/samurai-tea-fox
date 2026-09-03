extends SceneTree

const DataCatalog = preload("res://src/core/data/data_catalog.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")
const WorldSceneRenderer = preload("res://src/world/rendering/world_scene_renderer.gd")

const DEFAULT_OUTPUT_DIR := "res://artifacts/biome-previews"
const PREVIEW_SIZE := Vector2i(1024, 576)
const DEFAULT_SCALE := 0.5
const BIOME_SPECS := [
	{"id": "common_region", "label": "평원", "seed": 11037, "file": "plains_region_example.png"},
	{"id": "wasteland", "label": "황무지", "seed": 34033, "file": "wasteland_region_example.png"},
	{"id": "snowfield", "label": "설원", "seed": 18033, "file": "snowfield_region_example.png"},
	{"id": "mountain_region", "label": "산악", "seed": 22033, "file": "mountain_region_example.png"},
	{"id": "rainforest", "label": "열대우림", "seed": 26033, "file": "rainforest_region_example.png"}
]

var _requested_biome := ""
var _requested_seed: Variant = null
var _output_dir := DEFAULT_OUTPUT_DIR
var _single_output := ""
var _scale := DEFAULT_SCALE
var _make_contact_sheet := true

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_parse_arguments(OS.get_cmdline_user_args())
	root.size = PREVIEW_SIZE

	var catalog := DataCatalog.new()
	var loaded := catalog.load_from_directory("res://data/generated")
	if not loaded.ok:
		push_error("Biome capture catalog load failed: %s" % loaded)
		quit(1)
		return

	var specs := _selected_specs()
	if specs.is_empty():
		push_error("No supported biome selected. Use --list or --biome=<id>.")
		quit(2)
		return

	var generator := WorldGenerator.new()
	var renderer := WorldSceneRenderer.new()
	var world_root := Node2D.new()
	world_root.name = "BiomeCaptureWorld"
	world_root.scale = Vector2(_scale, _scale)
	root.add_child(world_root)

	var output_dir := _globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var captured_images: Array[Dictionary] = []
	var failures := 0
	for spec in specs:
		var biome_id := String(spec.get("id", ""))
		var biome: Dictionary = catalog.find_by_id("biomes", biome_id)
		if biome.is_empty():
			push_error("Biome definition missing: %s" % biome_id)
			failures += 1
			continue

		var seed := int(_requested_seed) if _requested_biome == biome_id and _requested_seed != null else int(spec.get("seed", 0))
		var generated: Dictionary = generator.generate(
			seed,
			catalog.data_version,
			biome,
			catalog.get_definitions("balance"),
			catalog.get_definitions("items")
		)
		if not generated.ok:
			push_error("Biome generation failed: %s seed=%d result=%s" % [biome_id, seed, generated])
			failures += 1
			continue

		# Let the previous render finish before replacing the scene contents for
		# the next biome, especially when the renderer queued old nodes for free.
		await process_frame
		var render_result: Dictionary = renderer.render(world_root, generated.renderer_input, _owner_sprite_sources(generated))
		if not render_result.ok:
			push_error("Biome render failed: %s seed=%d result=%s" % [biome_id, seed, render_result])
			failures += 1
			continue

		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var texture := root.get_texture()
		if texture == null:
			push_error("Viewport texture unavailable: %s" % biome_id)
			failures += 1
			continue
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Viewport image empty: %s" % biome_id)
			failures += 1
			continue
		# get_image() may expose a renderer-owned buffer. Keep an immutable
		# per-biome snapshot before rendering the next map.
		var snapshot: Image = image.duplicate()

		var filename := String(spec.get("file", "%s_seed_%d.png" % [biome_id, seed]))
		if _requested_biome == biome_id and not _single_output.is_empty():
			filename = _single_output
		var output_path := output_dir.path_join(filename)
		var save_result: int = snapshot.save_png(output_path)
		if save_result != OK:
			push_error("PNG save failed: %s error=%d" % [output_path, save_result])
			failures += 1
			continue
		captured_images.append({"id": biome_id, "label": String(spec.get("label", biome_id)), "image": snapshot})
		print("BIOME_CAPTURE_SAVED id=%s label=%s seed=%d path=%s" % [biome_id, String(spec.get("label", biome_id)), seed, output_path])

	if _make_contact_sheet and captured_images.size() > 1:
		var contact_path := output_dir.path_join("biome_map_examples_contact_sheet.png")
		var contact_result := _save_contact_sheet(captured_images, contact_path)
		if contact_result == OK:
			print("BIOME_CAPTURE_CONTACT_SHEET path=%s" % contact_path)
		else:
			push_error("Contact sheet save failed: %s error=%d" % [contact_path, contact_result])
			failures += 1

	world_root.queue_free()
	print("BIOME_CAPTURE_DONE captured=%d failures=%d output_dir=%s" % [captured_images.size(), failures, output_dir])
	quit(0 if failures == 0 else 1)

func _parse_arguments(arguments: PackedStringArray) -> void:
	var index := 0
	while index < arguments.size():
		var argument := String(arguments[index])
		if argument == "--list":
			for spec in BIOME_SPECS:
				print("%s\t%s\tseed=%d" % [String(spec.id), String(spec.label), int(spec.seed)])
			quit(0)
			return
		if argument == "--no-contact-sheet":
			_make_contact_sheet = false
		elif argument.begins_with("--biome="):
			_requested_biome = argument.trim_prefix("--biome=")
		elif argument.begins_with("--seed="):
			_requested_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--output-dir="):
			_output_dir = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--output="):
			_single_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--scale="):
			_scale = maxf(0.1, float(argument.trim_prefix("--scale=")))
		index += 1

func _selected_specs() -> Array:
	if _requested_biome.is_empty():
		return BIOME_SPECS.duplicate(true)
	for spec in BIOME_SPECS:
		if String(spec.get("id", "")) == _requested_biome:
			return [spec.duplicate(true)]
	return []

func _globalize_path(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/"):
		return path
	return ProjectSettings.globalize_path("res://%s" % path.trim_prefix("./"))

func _save_contact_sheet(captured_images: Array[Dictionary], output_path: String) -> int:
	var thumb_size := Vector2i(512, 288)
	var columns := 2
	var rows := int(ceil(float(captured_images.size()) / float(columns)))
	var sheet := Image.create(thumb_size.x * columns, thumb_size.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("191612"))
	for index in range(captured_images.size()):
		var source := captured_images[index].get("image") as Image
		if source == null:
			continue
		var thumbnail := source.duplicate()
		thumbnail.resize(thumb_size.x, thumb_size.y, Image.INTERPOLATE_NEAREST)
		var destination := Vector2i(index % columns * thumb_size.x, int(index / columns) * thumb_size.y)
		sheet.blit_rect(thumbnail, Rect2i(Vector2i.ZERO, thumb_size), destination)
	return sheet.save_png(output_path)

func _owner_sprite_sources(world: Dictionary) -> Dictionary:
	var sources := {
		WorldData.LANDMARK_ENTRY: "small_signpost",
		WorldData.LANDMARK_CORE_DUNGEON: "asset_assets_sprites_objects_structures_warehouse_2x2_64x64_png",
		WorldData.LANDMARK_RUIN: "asset_assets_sprites_objects_structures_ruined_wall_1x2_64x32_png",
		WorldData.LANDMARK_TELEPORT_ZONE: WorldGenerator.RENDER_TELEPORT_ZONE,
		"wood": "log_resource",
		"stone": "small_rock_resource",
		"clay": "mud_patch_resource"
	}
	for node in world.get("resource_nodes", []):
		var owner_id := String(node.get("id", ""))
		var resource_id := String(node.get("resource_id", ""))
		var source_id := String(node.get("source_id", ""))
		if not owner_id.is_empty() and not source_id.is_empty():
			sources[owner_id] = source_id
		elif not owner_id.is_empty() and sources.has(resource_id):
			sources[owner_id] = sources[resource_id]
	for node in world.get("facility_nodes", []):
		var owner_id := String(node.get("id", ""))
		var source_id := String(node.get("source_id", ""))
		if not owner_id.is_empty() and not source_id.is_empty():
			sources[owner_id] = source_id
	for reservation in world.get("world_data", {}).get("reservations", []):
		var reservation_id := String(reservation.get("owner_id", ""))
		var metadata: Dictionary = reservation.get("metadata", {})
		var reservation_source := String(metadata.get("source_id", ""))
		if not reservation_id.is_empty() and not reservation_source.is_empty():
			sources[reservation_id] = reservation_source
	return sources
