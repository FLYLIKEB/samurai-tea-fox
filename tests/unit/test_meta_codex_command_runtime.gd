extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")
const MetaCodexCommandRuntime = preload("res://src/meta/meta_codex_command_runtime.gd")
const MetaState = preload("res://src/save/meta_state.gd")
const RunState = preload("res://src/save/run_state.gd")

var _run_state: RunState
var _meta_state: MetaState

func run(asserts) -> void:
	_assert_discovered_rows_reveal_canonical_data_and_mask_undiscovered(asserts)
	_assert_filters_detail_and_navigation_are_read_only(asserts)
	_assert_hud_and_commands_expose_meta_codex(asserts)

func _assert_discovered_rows_reveal_canonical_data_and_mask_undiscovered(asserts) -> void:
	var runtime := _runtime()
	var model: Dictionary = runtime.set_tab("teas").read_model
	asserts.true_value(model.read_only, "meta codex read model is read-only")
	var spring := _row(model.rows, "spring_tea")
	var sealed := _row(model.rows, "sealed_tea")
	asserts.equal(spring.name, "봄 덖음차", "discovered tea reveals canonical name")
	asserts.false_value(bool(spring.masked), "discovered tea is unmasked")
	asserts.equal(sealed.name, "미발견", "undiscovered tea hides canonical name")
	asserts.true_value(bool(sealed.masked), "undiscovered tea is masked")
	asserts.true_value(runtime.set_tab("memories").ok, "memory tab can be selected")
	var memories := runtime.read_model()
	asserts.false_value(bool(_row(memories.rows, "memory_spring").masked), "specific memory record unmasks matching memory")
	asserts.true_value(bool(_row(memories.rows, "memory_tea_sealed_tea").masked), "aggregate memory_tea record does not unmask every memory")
	asserts.true_value(runtime.set_tab("yokai").ok, "yokai tab can be selected")
	var yokai := runtime.read_model()
	asserts.false_value(_row(yokai.rows, "foxfire").is_empty(), "yokai tab is backed by monsters catalog")
	asserts.true_value(_row(yokai.rows, "road_bandit").is_empty(), "yokai tab excludes non-yokai monsters")
	asserts.equal(model.detail.masked, false, "selected discovered detail is unmasked")

func _assert_filters_detail_and_navigation_are_read_only(asserts) -> void:
	var runtime := _runtime()
	var before_run := _run_state.to_dictionary()
	var before_meta := _meta_state.to_dictionary()
	asserts.true_value(runtime.set_tab("tea_ware").ok, "tea ware tab can be selected")
	asserts.true_value(runtime.set_filter("discovered").ok, "discovered filter can be selected")
	var discovered_model := runtime.read_model()
	asserts.equal(discovered_model.rows.size(), 1, "discovered filter shows only known tea ware")
	asserts.equal(discovered_model.rows[0].id, "humble_clay_bowl", "discovered tea ware comes from inventory/meta state")
	asserts.true_value(runtime.set_filter("masked").ok, "masked filter can be selected")
	var masked_model := runtime.read_model()
	asserts.true_value(masked_model.rows.size() >= 1, "masked filter shows undiscovered rows")
	asserts.true_value(bool(masked_model.rows[0].masked), "masked row hides spoiler fields")
	asserts.true_value(runtime.navigate(Vector2i.RIGHT).ok, "keyboard-style navigation changes detail")
	asserts.false_value(runtime.handle_command(GameCommand.new(GameCommand.Type.META_CODEX_SELECT_DETAIL, Vector2i.ZERO, -1, {"id": "missing"})).ok, "unknown detail is rejected")
	asserts.equal(_run_state.to_dictionary(), before_run, "codex runtime never mutates run state")
	asserts.equal(_meta_state.to_dictionary(), before_meta, "codex runtime never mutates meta state")

func _assert_hud_and_commands_expose_meta_codex(asserts) -> void:
	var runtime := _runtime()
	var open_command := GameCommand.new(GameCommand.Type.OPEN_META_CODEX)
	asserts.equal(open_command.type, GameCommand.Type.OPEN_META_CODEX, "open codex command exists")
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {}, {"counts": {}}, {"meta_codex_command_runtime": runtime, "catalog": FakeCatalog.new(_definitions())})
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.press_mobile_button("open_meta_codex"), "HUD action button emits open meta codex command")
	asserts.true_value(hud.show_meta_codex_menu(), "HUD opens meta codex menu")
	asserts.equal(hud.active_menu_id(), "meta_codex", "HUD active menu gates codex keyboard navigation")
	asserts.true_value(_tree_has_text(hud, "도감"), "HUD renders codex title")
	asserts.true_value(_tree_has_text(hud, "미발견"), "HUD renders masked state guidance")
	runtime.set_tab("memories")
	runtime.select_detail("memory_spring")
	hud.show_meta_codex_menu()
	asserts.true_value(_tree_has_text(hud, "아버지"), "HUD renders resolved related character names")
	asserts.equal(received[0].type, GameCommand.Type.OPEN_META_CODEX, "HUD emits shared codex command")
	hud.free()
	var project := FileAccess.get_file_as_string("res://project.godot")
	asserts.true_value("open_meta_codex={" in project, "project input map exposes codex menu")
	asserts.true_value("meta_codex_next={" in project, "project input map exposes codex navigation")

func _runtime() -> MetaCodexCommandRuntime:
	_run_state = RunState.new()
	_run_state.current_biome_id = "common_region"
	_run_state.discovered_records = ["spring_tea", "memory_spring"]
	_run_state.narrative_event_counts = {"memory_spring": 1}
	_run_state.inventory = {"slots": [{"item_id": "humble_clay_bowl", "quantity": 1}, {"item_id": "spring_tea", "quantity": 2}]}
	_meta_state = MetaState.new()
	_meta_state.discovered_records = ["humble_clay_bowl", "memory_tea", "foxfire"]
	_meta_state.past_choice_ids = ["daimyo_defeat"]
	var runtime := MetaCodexCommandRuntime.new()
	var configured := runtime.configure(FakeCatalog.new(_definitions()), func(): return _run_state, func(): return _meta_state, "fixture-meta")
	assert(configured.ok)
	return runtime

func _definitions() -> Dictionary:
	return {
		"teas": [
			{"id": "spring_tea", "name": "봄 덖음차", "status": "확정", "origin": "봄 산기슭", "memory": true, "memory_event_id": "memory_spring"},
			{"id": "sealed_tea", "name": "봉인 저장차", "status": "확정", "origin": "비밀", "memory": true}
		],
		"items": [
			{"id": "humble_clay_bowl", "name": "소박한 사발", "status": "확정", "type": "다구"},
			{"id": "black_bamboo_tea_scoop", "name": "검은 대나무 찻숟가락", "status": "확정", "type": "다구"}
		],
		"bosses": [
			{"id": "daimyo", "name": "다이묘", "status": "확정", "dungeon_id": "wasteland_castle"}
		],
		"monsters": [
			{"id": "foxfire", "name": "여우불", "status": "확정", "kind": "요괴", "biome": "일반"},
			{"id": "empty_armor_yokai", "name": "빈 갑주 요괴", "status": "확정", "kind": "요괴", "biome": "황무지"},
			{"id": "road_bandit", "name": "노상 도적", "status": "확정", "kind": "도적·무사", "biome": "일반"}
		],
		"events": [
			{"id": "memory_spring", "name": "봄 기억", "nodes": [{"speaker_id": "CHR-1", "text": "차"}]}
		],
		"choices": [
			{"id": "daimyo_defeat", "name": "다이묘 격파", "status": "확정"}
		],
		"characters": [
			{"id": "chr_1", "character_id": "CHR-1", "name": "아버지", "status": "확정", "meta_memory": true}
		]
	}

func _row(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if String(row.get("id", "")) == id:
			return row
	return {}

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and text in node.text:
		return true
	if node is Button and text in node.text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false

class FakeCatalog:
	extends RefCounted
	var definitions: Dictionary
	func _init(initial_definitions: Dictionary) -> void:
		definitions = initial_definitions
	func get_definitions(dataset: String) -> Array:
		return definitions.get(dataset, [])
	func find_by_id(dataset: String, id: String) -> Dictionary:
		for definition in definitions.get(dataset, []):
			if definition.get("id", "") == id:
				return definition
		return {}
	func find_character_by_id(character_id: String) -> Dictionary:
		for definition in definitions.get("characters", []):
			if definition.get("id", "") == character_id or definition.get("character_id", "") == character_id:
				return definition
		return {}

class FakeResources:
	var hp := 10
	var hp_max := 10
	var ki := 4
	var ki_max := 4
	var kokoro := 1
	var kokoro_max := 1

class FakePlayer:
	var resources := FakeResources.new()
	var global_position := Vector2.ZERO
