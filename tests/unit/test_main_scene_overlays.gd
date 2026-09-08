extends RefCounted

const MainSceneOverlays = preload("res://src/ui/main_scene_overlays.gd")

func run(asserts) -> void:
	var scene_root := Node.new()
	var label := MainSceneOverlays.create_loading(scene_root)
	var overlay := scene_root.get_node_or_null("LoadingOverlay") as CanvasLayer
	var backdrop := scene_root.get_node_or_null("LoadingOverlay/LoadingBackdrop") as TextureRect
	var scrim := scene_root.get_node_or_null("LoadingOverlay/LoadingScrim") as ColorRect
	var spinner := scene_root.get_node_or_null("LoadingOverlay/LoadingSpinner") as Label

	asserts.true_value(overlay != null, "loading overlay is mounted above the scene")
	asserts.true_value(backdrop != null and backdrop.texture != null, "loading overlay mounts the placeholder backdrop image")
	asserts.equal(backdrop.anchor_right, 1.0, "placeholder backdrop covers the viewport width")
	asserts.equal(backdrop.anchor_bottom, 1.0, "placeholder backdrop covers the viewport height")
	asserts.equal(backdrop.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "placeholder backdrop crops to cover without exposing the map")
	asserts.equal(backdrop.mouse_filter, Control.MOUSE_FILTER_STOP, "placeholder backdrop blocks world input while loading")
	asserts.true_value(scrim != null and scrim.color.a > 0.0, "loading backdrop has a visible dark scrim")
	asserts.true_value(spinner != null and spinner.text == "↻", "loading overlay shows a rotating spinner")
	asserts.equal(spinner.anchor_left, 0.5, "loading spinner is centered horizontally")
	asserts.equal(spinner.anchor_top, 0.5, "loading spinner is centered vertically")
	asserts.equal(spinner.size, Vector2(48.0, 48.0), "loading spinner is large enough to read at screen center")
	var initial_rotation := spinner.rotation
	spinner._process(0.25)
	asserts.true_value(spinner.rotation > initial_rotation, "loading spinner rotates while the overlay is visible")
	asserts.equal(label.text, "0% · 준비 중…", "loading status starts with a visible percentage")
	asserts.equal(label, scene_root.get_node_or_null("LoadingOverlay/LoadingStatusPanel/LoadingStatus"), "loading status remains available above the backdrop")

	var repeated := MainSceneOverlays.create_loading(scene_root)
	asserts.equal(repeated, label, "repeated loading creation reuses the existing status overlay")
	scene_root.free()
