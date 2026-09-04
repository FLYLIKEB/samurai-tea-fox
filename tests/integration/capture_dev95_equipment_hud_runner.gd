extends SceneTree

const GameHud = preload("res://src/ui/game_hud.gd")

const CAPTURES := [
	{"name": "desktop_1280x720", "size": Vector2i(1280, 720)},
	{"name": "mobile_360x640", "size": Vector2i(360, 640)}
]
const CAPTURE_DIR := "res://docs/reports/dev-95-equipment-hud"

class FakeResources:
	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

class FakePlayer:
	var resources := FakeResources.new()

class FakeInventoryCommandRuntime:
	signal read_model_changed(read_model: Dictionary)

	func read_model() -> Dictionary:
		return {
			"equipment": {
				"weapon": {
					"slot": "weapon",
					"item_id": "mountain_iron_dagger",
					"instance_id": "capture-weapon",
					"definition": {"id": "mountain_iron_dagger", "name": "산철 단검", "type": "무기"}
				},
				"armor": {
					"slot": "armor",
					"item_id": "traveler_quilted_clothes",
					"instance_id": "capture-armor",
					"definition": {"id": "traveler_quilted_clothes", "name": "나그네 누비옷", "type": "방어구"}
				},
				"tea_ware": {
					"slot": "tea_ware",
					"item_id": "humble_clay_bowl",
					"instance_id": "capture-tea-ware",
					"definition": {"id": "humble_clay_bowl", "name": "소박한 흙찻잔", "type": "다구"}
				}
			},
			"capacity": {"used": 3, "total": 14, "empty": 11, "full": false},
			"slots": []
		}

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		match key:
			"balance":
				return [{"id": "ability_equip_slots", "value": 2}]
			"items":
				return [
					{"id": "mountain_iron_dagger", "name": "산철 단검", "type": "무기"},
					{"id": "traveler_quilted_clothes", "name": "나그네 누비옷", "type": "방어구"},
					{"id": "humble_clay_bowl", "name": "소박한 흙찻잔", "type": "다구"}
				]
			"biomes":
				return [{"id": "common_region", "name": "일반 지역"}]
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
		var result := await _capture_equipment(String(capture.name), capture.size)
		if not result.ok:
			push_error(String(result.get("error", "capture failed")))
			quit(1)
			return
	print("DEV-95 equipment HUD captures saved: %d" % CAPTURES.size())
	quit(0)

func _capture_equipment(capture_name: String, viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "%sViewport" % capture_name
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud := GameHud.new()
	viewport.add_child(hud)
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {
		"catalog": FakeCatalog.new(),
		"inventory_command_runtime": FakeInventoryCommandRuntime.new()
	})
	hud._apply_safe_area_layout()
	await process_frame
	await process_frame
	var strip := hud.get_node_or_null("Root/StatusPanel/StatusBody/StatusRows/EquipmentStrip") as Control
	if strip == null or not strip.visible:
		viewport.queue_free()
		return {"ok": false, "error": "%s missing visible equipment strip" % capture_name}
	var strip_rect := strip.get_global_rect()
	if strip_rect.position.x < 0.0 or strip_rect.position.y < 0.0 or strip_rect.end.x > viewport_size.x or strip_rect.end.y > viewport_size.y:
		viewport.queue_free()
		return {"ok": false, "error": "%s equipment strip outside viewport: %s" % [capture_name, strip_rect]}
	var snapshot: Dictionary = hud.equipment_hud_snapshot()
	for slot_key in ["weapon", "armor", "tea_ware"]:
		var slot: Dictionary = snapshot.get(slot_key, {})
		if String(slot.get("item_id", "")).is_empty():
			viewport.queue_free()
			return {"ok": false, "error": "%s missing %s item" % [capture_name, slot_key]}
		if not bool(slot.get("icon_has_texture", false)):
			viewport.queue_free()
			return {"ok": false, "error": "%s missing %s icon texture" % [capture_name, slot_key]}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "%s produced an empty image" % capture_name}
	var output_path := "%s/%s.png" % [CAPTURE_DIR, capture_name]
	var save_result := image.save_png(output_path)
	viewport.queue_free()
	if save_result != OK:
		return {"ok": false, "error": "%s failed to save %s" % [capture_name, output_path]}
	return {"ok": true, "path": output_path}
