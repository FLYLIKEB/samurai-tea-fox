extends RefCounted
class_name FacilityPreviewPresenter

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const FacilityPlacementPreview = preload("res://src/presentation/facility_placement_preview.gd")

var preview: FacilityPlacementPreview
var _assets := AssetCatalog.new()
var _manifest_ready := false
var _content_map_ready := false

func update(world_visuals: Node2D, origin: Vector2i, pending: Dictionary, rotation: int, validation: Dictionary, tile_size: float, fallback_footprint: Vector2i) -> void:
	if world_visuals == null or origin.x < 0:
		return
	if preview == null:
		preview = FacilityPlacementPreview.new()
		preview.z_index = 50
		world_visuals.add_child(preview)
	var footprint := fallback_footprint
	if validation.has("footprint_size"):
		footprint = Vector2i(int(validation.footprint_size.x), int(validation.footprint_size.y))
	preview.configure(origin, footprint, tile_size, bool(validation.get("ok", false)), preview_texture(pending), rotation)

func clear() -> void:
	if preview != null:
		preview.clear()

func preview_texture(pending: Dictionary) -> Texture2D:
	if not _ensure_manifest():
		return null
	return _assets.load_texture_reference(String(pending.get("metadata", {}).get("source_id", "")))

func content_image_asset_id(dataset: String, content_id: String) -> String:
	if not _ensure_manifest():
		return ""
	if not _content_map_ready:
		var result: Dictionary = _assets.load_content_image_map()
		if not result.ok:
			return ""
		_content_map_ready = true
	return _assets.content_asset_id(dataset, content_id)

func _ensure_manifest() -> bool:
	if _manifest_ready:
		return true
	var result: Dictionary = _assets.load_manifest()
	if not result.ok:
		return false
	_manifest_ready = true
	return true
