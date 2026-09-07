extends RefCounted

const NarrativeDialoguePresenter = preload("res://src/ui/narrative_dialogue_presenter.gd")
const NarrativePlaceholderBackdrop = preload("res://src/ui/narrative_placeholder_backdrop.gd")

const DIALOGUE_KEYS := [
	["story_pro_01", "dlg_pro_000"],
	["story_pro_01", "dlg_pro_001"],
	["story_pro_02", "dlg_pro_002"],
	["story_pro_03", "dlg_1"],
	["story_pro_04", "dlg_pro_004"],
	["story_pro_05", "dlg_pro_005a"],
	["story_pro_05", "dlg_pro_005b"],
	["story_pro_06", "dlg_pro_006"],
	["story_pro_07", "dlg_4"],
	["story_pro_07", "dlg_pro_007b"],
	["story_pro_08", "dlg_pro_008"]
]

func run(asserts) -> void:
	var presenter := NarrativeDialoguePresenter.new()
	presenter.build()
	var backdrop := presenter.get_node_or_null("NarrativePlaceholderBackdrop") as NarrativePlaceholderBackdrop
	var texture_background := presenter.get_node_or_null("NarrativeBackground") as TextureRect
	asserts.true_value(backdrop != null, "presenter mounts the prologue placeholder backdrop")
	presenter.apply_layout(Vector2(640.0, 360.0), Vector4.ZERO)
	asserts.equal(backdrop.anchor_right, 1.0, "presenter layout anchors the placeholder backdrop to the right edge")
	asserts.equal(backdrop.anchor_bottom, 1.0, "presenter layout anchors the placeholder backdrop to the bottom edge")
	var keys := {}
	var variants := {}
	for dialogue_key in DIALOGUE_KEYS:
		asserts.true_value(presenter.show_read_model(_prologue_model(dialogue_key)), "canonical prologue node opens")
		var signature := backdrop.debug_signature()
		asserts.true_value(backdrop.visible, "prologue placeholder backdrop remains visible")
		asserts.true_value(bool(signature.get("opaque", false)), "prologue placeholder backdrop fully covers the game map")
		asserts.false_value(keys.has(signature.get("key", "")), "each prologue dialogue node receives a distinct backdrop key")
		asserts.false_value(variants.has(signature.get("variant", -1)), "each prologue dialogue node receives a visibly distinct backdrop variant")
		keys[signature.get("key", "")] = true
		variants[signature.get("variant", -1)] = true
		asserts.false_value(texture_background.visible, "placeholder backdrop replaces the legacy texture background")
	asserts.equal(keys.size(), DIALOGUE_KEYS.size(), "all canonical prologue nodes have unique placeholder backdrops")
	presenter.hide_dialogue()
	asserts.false_value(backdrop.visible, "placeholder backdrop hides with the dialogue")
	presenter.show_read_model({
		"event_id": "sample_bamboo_guardian_pre_boss",
		"node_id": "boss_warning",
		"speaker_id": "CHR-2",
		"text": "보스 대화",
		"options": []
	})
	asserts.false_value(backdrop.visible, "non-prologue dialogue does not reuse the placeholder backdrop")
	presenter.free()

func _prologue_model(dialogue_key: Array) -> Dictionary:
	return {
		"event_id": dialogue_key[0],
		"node_id": dialogue_key[1],
		"speaker_id": "CHR-8",
		"sequence_id": "PRO",
		"chain_scene_sequence": true,
		"text": "임시 배경 검증",
		"options": []
	}
