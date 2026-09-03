extends SceneTree

const AcquisitionEffect = preload("res://src/presentation/acquisition_effect.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var effect := AcquisitionEffect.new()
	effect.configure("gatherable", "목재", 2, Vector2(64.0, 96.0))
	root.add_child(effect)
	if effect.position != Vector2(64.0, 96.0):
		failures.append("effect is anchored to the acquisition world position")
	var caption := effect.get_node_or_null("Caption") as Label
	if caption == null or caption.text != "채집 목재 x2":
		failures.append("gathering effect shows item and quantity feedback")
	await create_timer(0.2).timeout
	if not is_instance_valid(effect) or effect.get("_elapsed_seconds") <= 0.0:
		failures.append("effect animates while active")
	await create_timer(0.6).timeout
	if is_instance_valid(effect):
		failures.append("effect removes itself after the short animation")
	if failures.is_empty():
		print("Acquisition effect integration passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
