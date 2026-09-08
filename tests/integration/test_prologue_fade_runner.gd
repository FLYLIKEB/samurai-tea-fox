extends SceneTree

const SleepTransitionPresenter = preload("res://src/ui/sleep_transition_presenter.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var presenter := SleepTransitionPresenter.new()
	root.add_child(presenter)
	await process_frame
	presenter.play_fade_from_black()
	var fade_rect := presenter.get_node_or_null("FadeRect") as ColorRect
	if fade_rect == null or fade_rect.modulate.a < 0.99 or fade_rect.mouse_filter != Control.MOUSE_FILTER_STOP:
		push_error("prologue fade starts fully black and blocks input")
		quit(1)
		return
	await create_timer(1.0).timeout
	if fade_rect.modulate.a > 0.01 or fade_rect.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("prologue fade reveals gameplay and restores input")
		quit(1)
		return
	print("Prologue fade integration passed")
	quit(0)
