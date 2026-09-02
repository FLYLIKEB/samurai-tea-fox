extends SceneTree

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DirectionalWalkAnimator = preload("res://src/presentation/directional_walk_animator.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := AssetCatalog.new()
	var load_result := catalog.load_manifest()
	if not load_result.ok:
		failures.append(load_result.error)
		finish()
		return

	var sprite := Sprite2D.new()
	root.add_child(sprite)
	var animator := DirectionalWalkAnimator.new()
	var configure_result := animator.configure_for_character(sprite, catalog, "CHR-1")
	if not configure_result.ok:
		failures.append(configure_result.error)
	else:
		animator.update(0.0, "west", true)
		animator.update(0.125, "west", true)
		if animator.current_asset_id() != "chr_1_kitsune_father_walk":
			failures.append("major character resolves its walk sheet from CHR-1")
		elif Vector2i(sprite.hframes, sprite.vframes) != Vector2i(8, 4):
			failures.append("major character uses the shared 8x4 walk grid")
		elif sprite.frame_coords != Vector2i(1, 1):
			failures.append("major character advances on the west walk row")

	sprite.queue_free()
	finish()

func finish() -> void:
	if failures.is_empty():
		print("Major character walk presentation integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
