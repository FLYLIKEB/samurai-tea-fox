extends SceneTree

const NarrativeDialoguePresenter = preload("res://src/ui/narrative_dialogue_presenter.gd")
const CAPTURE_SIZE := Vector2i(640, 360)
const MAP_SENTINEL_COLOR := Color("ff00ff")
const DIALOGUES := [
	["story_pro_01", "dlg_pro_000", "아버지와의 마지막 차 한 잔."],
	["story_pro_01", "dlg_pro_001", "길을 떠날 시간이구나."],
	["story_pro_02", "dlg_pro_002", "숲 너머로 바람이 분다."],
	["story_pro_03", "dlg_1", "물길은 먼 곳으로 이어진다."],
	["story_pro_04", "dlg_pro_004", "달빛 아래 산등성이가 보인다."],
	["story_pro_05", "dlg_pro_005a", "동굴 깊은 곳에서 빛이 흔들린다."],
	["story_pro_05", "dlg_pro_005b", "어둠 속에서 길을 찾는다."],
	["story_pro_06", "dlg_pro_006", "붉은 문을 지나 앞으로 간다."],
	["story_pro_07", "dlg_4", "안개 낀 숲이 조용히 열린다."],
	["story_pro_07", "dlg_pro_007b", "먼 산 위에 달이 걸렸다."],
	["story_pro_08", "dlg_pro_008", "마지막 빛을 향해 걷는다."]
]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var output_dir := OS.get_environment("PROLOGUE_CAPTURE_DIR")
	if output_dir.is_empty():
		output_dir = "user://dev64-prologue-backdrops"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	for index in range(DIALOGUES.size()):
		var result := await _capture_dialogue(index, DIALOGUES[index], output_dir)
		if not result.ok:
			push_error(String(result.error))
			quit(1)
			return
	print("DEV-64 prologue backdrop captures saved: %d" % DIALOGUES.size())
	quit(0)

func _capture_dialogue(index: int, dialogue: Array, output_dir: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var map_sentinel := ColorRect.new()
	map_sentinel.name = "GameMapSentinel"
	map_sentinel.color = MAP_SENTINEL_COLOR
	map_sentinel.size = CAPTURE_SIZE
	viewport.add_child(map_sentinel)
	var presenter := NarrativeDialoguePresenter.new()
	viewport.add_child(presenter)
	presenter.configure(Callable(), func(_speaker_id: String): return "무차우")
	presenter.show_read_model({
		"event_id": dialogue[0],
		"node_id": dialogue[1],
		"speaker_id": "CHR-8",
		"sequence_id": "PRO",
		"chain_scene_sequence": true,
		"text": dialogue[2],
		"options": [{"id": "continue", "display_text": "계속"}]
	})
	presenter.apply_layout(CAPTURE_SIZE, Vector4.ZERO)
	await process_frame
	await process_frame
	var backdrop := presenter.get_node_or_null("NarrativePlaceholderBackdrop") as Control
	if backdrop == null or not backdrop.visible or backdrop.size != Vector2(CAPTURE_SIZE):
		viewport.queue_free()
		return {"ok": false, "error": "capture %d does not have a full-screen placeholder backdrop" % index}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "capture %d produced an empty image" % index}
	if _contains_color(image, MAP_SENTINEL_COLOR):
		viewport.queue_free()
		return {"ok": false, "error": "capture %d leaks the game-map sentinel through the dialogue" % index}
	var output_path := "%s/%02d_%s_%s.png" % [output_dir, index + 1, dialogue[0], dialogue[1]]
	var save_result := image.save_png(output_path)
	viewport.queue_free()
	return {"ok": save_result == OK, "error": "capture %d failed to save" % index}

func _contains_color(image: Image, color: Color) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y) == color:
				return true
	return false
