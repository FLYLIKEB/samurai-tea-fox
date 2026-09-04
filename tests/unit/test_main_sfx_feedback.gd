extends RefCounted

const Main = preload("res://src/main/main.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

class FeedbackPlayer:
	extends Node
	signal attack_started(swing: Dictionary)
	signal ability_cast(result: Dictionary)
	signal damage_received(event: Dictionary, applied_damage: int)
	signal dodge_started(direction: Vector2, distance_pixels: float)
	signal grid_step_blocked(from_cell: Vector2i, to_cell: Vector2i)

func run(asserts) -> void:
	var main := Main.new()
	var player := FeedbackPlayer.new()
	main.player = player
	main._configure_audio_feedback()
	main._connect_player_feedback_signals()

	player.attack_started.emit({"swing_id": "swing_1"})
	player.attack_started.emit({"swing_id": "swing_1"})
	player.damage_received.emit({"source_id": "enemy_1"}, 2)
	player.dodge_started.emit(Vector2.RIGHT, 64.0)
	player.grid_step_blocked.emit(Vector2i.ZERO, Vector2i.RIGHT)

	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_ATTACK_SWING), 1, "attack signal emits one deduped swing SFX")
	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_PLAYER_HIT), 1, "damage signal emits player hit SFX")
	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_DODGE), 1, "dodge signal emits dodge SFX")
	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_INTERACT_FAIL), 1, "blocked movement emits failure SFX")

	main._play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "inventory"}, "menu:inventory")
	main._play_sfx_event(SfxEventRouter.EVENT_UI_MENU_OPEN, {"menu_id": "inventory"}, "menu:inventory")
	main._play_sfx_event(SfxEventRouter.EVENT_UI_MENU_CLOSE, {}, "menu:hide")
	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_UI_MENU_OPEN), 1, "same command menu open SFX is deduped")
	asserts.equal(main._sfx_router.count_for(SfxEventRouter.EVENT_UI_MENU_CLOSE), 1, "menu close SFX is routed through the central router")
	asserts.equal(main.feedback_beep_count, main._sfx_router.played_events.size(), "legacy feedback counter follows accepted SFX events")

	player.free()
	main.free()
