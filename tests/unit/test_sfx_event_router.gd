extends RefCounted

const SfxEventRouter = preload("res://src/audio/sfx_event_router.gd")

func run(asserts) -> void:
	var ids := SfxEventRouter.event_ids()
	for required_id in [
		SfxEventRouter.EVENT_STEP,
		SfxEventRouter.EVENT_UI_SELECT,
		SfxEventRouter.EVENT_UI_MENU_OPEN,
		SfxEventRouter.EVENT_UI_MENU_CLOSE,
		SfxEventRouter.EVENT_UI_FAIL,
		SfxEventRouter.EVENT_GATHER_WOOD,
		SfxEventRouter.EVENT_GATHER_STONE,
		SfxEventRouter.EVENT_ITEM_PICKUP,
		SfxEventRouter.EVENT_ATTACK_SWING,
		SfxEventRouter.EVENT_COMBAT_HIT,
		SfxEventRouter.EVENT_PLAYER_HIT,
		SfxEventRouter.EVENT_DODGE,
		SfxEventRouter.EVENT_INTERACT_SUCCESS,
		SfxEventRouter.EVENT_INTERACT_FAIL
	]:
		asserts.true_value(ids.has(required_id), "SFX registry includes event id: %s" % required_id)

	asserts.equal(
		SfxEventRouter.event_id_for_acquisition({"kind": "gatherable", "node_id": "terrain_tree_wood_1_0", "item_id": "wood"}),
		SfxEventRouter.EVENT_GATHER_WOOD,
		"wood gatherable resolves to the wood SFX event"
	)
	asserts.equal(
		SfxEventRouter.event_id_for_acquisition({"kind": "gatherable", "node_id": "terrain_mountain_mineral_1_0", "item_id": "stone"}),
		SfxEventRouter.EVENT_GATHER_STONE,
		"stone gatherable resolves to the stone SFX event"
	)
	asserts.equal(
		SfxEventRouter.event_id_for_acquisition({"kind": "pickup", "pickup_id": "pickup_000001", "item_id": "wood"}),
		SfxEventRouter.EVENT_ITEM_PICKUP,
		"world pickup resolves to the pickup SFX event"
	)
	asserts.false_value(
		SfxEventRouter.event_definition(SfxEventRouter.EVENT_GATHER_WOOD).pitch_scale == SfxEventRouter.event_definition(SfxEventRouter.EVENT_GATHER_STONE).pitch_scale,
		"wood and stone gathering keep distinct tone profiles"
	)

	var router := SfxEventRouter.new()
	for path in router.registered_stream_paths():
		asserts.true_value(ResourceLoader.exists(path), "registered SFX stream exists: %s" % path)

	var first: Dictionary = router.play_event(SfxEventRouter.EVENT_UI_SELECT, {}, "same_command", 1000)
	var duplicate: Dictionary = router.play_event(SfxEventRouter.EVENT_UI_SELECT, {}, "same_command", 1000)
	asserts.true_value(first.ok, "first SFX event is accepted")
	asserts.equal(duplicate.get("reason", ""), "duplicate_frame", "same frame duplicate is suppressed")
	asserts.equal(router.count_for(SfxEventRouter.EVENT_UI_SELECT), 1, "duplicate suppression preserves one event per command frame")

	var unknown: Dictionary = router.play_event("missing_event", {}, "missing", 1200)
	asserts.false_value(unknown.ok, "unknown SFX events fail without throwing")
	asserts.equal(router.count_for("missing_event"), 0, "unknown SFX events are not counted as played")
