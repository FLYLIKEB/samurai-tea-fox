extends RefCounted

const GameHud = preload("res://src/ui/game_hud.gd")
const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

func run(asserts) -> void:
	asserts.equal(SfxEventRouter.event_id_for_toast_kind("success"), SfxEventRouter.EVENT_TOAST_SUCCESS, "success toast uses success SFX")
	asserts.equal(SfxEventRouter.event_id_for_toast_kind("failure"), SfxEventRouter.EVENT_UI_FAIL, "failure toast uses failure SFX")
	asserts.equal(SfxEventRouter.event_id_for_toast_kind("info"), SfxEventRouter.EVENT_TOAST_INFO, "info toast uses info SFX")

	var hud := GameHud.new()
	var presented: Array = []
	hud.status_toast_presented.connect(func(kind: String, event_key: String): presented.append([kind, event_key]))
	hud._build()
	hud.show_status_toast("실패", "failure")
	asserts.equal(presented, [["failure", "message:실패"]], "toast emits its sound kind when it becomes visible")
	hud.show_status_event({"type": "enemy_defeated", "monster_id": "enemy", "event_id": "enemy-1"})
	hud._process(1.0)
	asserts.equal(presented[1][0], "success", "successful status events emit the success sound kind")
	hud.free()
