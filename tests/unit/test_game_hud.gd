extends RefCounted

const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

class FakeResources:
	signal hp_changed(previous: int, current: int, maximum: int)
	signal ki_changed(previous: int, current: int, maximum: int)
	signal kokoro_changed(previous: int, current: int, maximum: int)

	var hp := 82
	var hp_max := 100
	var ki := 36
	var ki_max := 60
	var kokoro := 7
	var kokoro_max := 10

	func heal_hp(_amount: int) -> int:
		return 0

	func set_hp(value: int) -> void:
		var previous := hp
		hp = value
		hp_changed.emit(previous, hp, hp_max)

class FakePlayer:
	var resources := FakeResources.new()

class FakeInventory:
	signal changed(snapshot: Dictionary)

	var slot_count := 14
	var slots := [
		{"item_id": "wood", "quantity": 3},
		{},
		{"item_id": "bandage", "quantity": 1}
	]

	func definition_for(item_id: String) -> Dictionary:
		return {"id": item_id, "type": "소모품"} if item_id == "bandage" else {"id": item_id, "type": "재료"}

class FakeTeaService:
	signal changed(snapshot: Dictionary)

	var quickslot_count := 3
	var quick_slots := [
		{"tea_id": "green_tea", "remaining_uses": 1},
		{},
		{}
	]

class FakeTimeConfig:
	func phase_duration_seconds(_phase: StringName) -> float:
		return 120.0

class FakeTimeState:
	signal phase_changed(previous: StringName, current: StringName)

	var phase: StringName = &"night"
	var phase_elapsed_seconds := 30.0
	var config := FakeTimeConfig.new()

class FakeCatalog:
	func get_definitions(key: String) -> Array:
		match key:
			"balance":
				return [{"id": "ability_equip_slots", "value": 2}]
			"recipes":
				return [
					{"id": "bandage", "status": "테스트"},
					{"id": "iron_kettle", "status": "초안"}
				]
			_:
				return []

	func find_by_id(key: String, id: String) -> Dictionary:
		for definition in get_definitions(key):
			if String(definition.get("id", "")) == id:
				return definition
		return {}

func run(asserts) -> void:
	_assert_read_model_uses_runtime_and_balance_sources(asserts)
	_assert_runtime_signals_refresh_labels(asserts)
	_assert_reconfigure_clears_missing_time_context(asserts)
	_assert_dpad_emits_press_and_release_movement(asserts)
	_assert_mobile_controls_emit_shared_commands(asserts)
	_assert_dodge_control_does_not_use_baked_dash_asset(asserts)

func _assert_read_model_uses_runtime_and_balance_sources(asserts) -> void:
	var hud := _configured_hud()
	var read_model: Dictionary = hud.runtime_read_model()
	asserts.equal(read_model.hp, 82, "HUD reads HP from player resources")
	asserts.equal(read_model.ki, 36, "HUD reads ki from player resources")
	asserts.equal(read_model.kokoro, 7, "HUD reads kokoro from player resources")
	asserts.equal(read_model.inventory_slot_count, 14, "HUD inventory slots come from runtime inventory built from balance")
	asserts.equal(read_model.inventory_used_slots, 2, "HUD observes occupied inventory slots without mutating them")
	asserts.equal(read_model.tea_quickslot_count, 3, "HUD tea quick slots come from runtime tea service")
	asserts.true_value(read_model.consumable_ready, "HUD derives the consumable quickslot from item definition data")
	asserts.equal(read_model.ability_slot_count, 2, "HUD ability slots come from balance definitions")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionGrid/TeaButton3") != null, "HUD creates tea controls from the runtime quickslot count")
	asserts.true_value(hud.get_node_or_null("Root/ActionPanel/ActionGrid/AbilityButton2") != null, "HUD creates ability controls from the balance slot count")
	asserts.equal(read_model.time_phase, "night", "HUD reads current time phase")
	asserts.equal(read_model.time_progress_percent, 25, "HUD calculates time progress from the time read model")
	hud.free()

func _assert_runtime_signals_refresh_labels(asserts) -> void:
	var hud := _configured_hud()
	var resources = hud.player.resources
	resources.set_hp(61)
	var hp_label := hud.get("_labels").get("hp") as Label
	asserts.equal(hp_label.text, "HP 61 / 100", "resource signals refresh HUD labels without frame polling")
	hud.time_state.phase = &"dusk"
	hud.time_state.phase_changed.emit(&"night", &"dusk")
	var time_label := hud.get("_labels").get("time") as Label
	asserts.true_value(time_label.text.begins_with("해질녘"), "time phase events refresh the HUD")
	hud.free()

func _assert_reconfigure_clears_missing_time_context(asserts) -> void:
	var hud := _configured_hud()
	var time_label := hud.get("_labels").get("time") as Label
	asserts.true_value(time_label.get_parent().visible, "HUD shows time while a runtime time state is supplied")
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {})
	asserts.equal(hud.time_state, null, "HUD clears a stale time observer when the new runtime context omits it")
	asserts.false_value(time_label.get_parent().visible, "HUD hides the time row after its runtime time state is removed")
	hud.free()

func _assert_dpad_emits_press_and_release_movement(asserts) -> void:
	var hud := _configured_hud()
	var received: Array[Vector2i] = []
	hud.movement_button_changed.connect(func(direction: Vector2i): received.append(direction))
	var left_button := hud.get_node_or_null("Root/DPadPanel/DPadBoard/DPadLeft") as Button
	asserts.true_value(left_button != null, "HUD owns a left dpad button")
	if left_button != null:
		left_button.button_down.emit()
		left_button.button_up.emit()
	asserts.equal(received, [Vector2i.LEFT, Vector2i.ZERO], "dpad press starts movement and release stops it")
	hud.free()

func _assert_mobile_controls_emit_shared_commands(asserts) -> void:
	var hud := _configured_hud()
	var received: Array = []
	hud.mobile_command_issued.connect(func(command): received.append(command))
	asserts.true_value(hud.press_mobile_button("move", Vector2i.LEFT), "HUD accepts mobile movement control")
	asserts.true_value(hud.press_mobile_button("attack", Vector2i.RIGHT), "HUD accepts mobile attack control")
	asserts.true_value(hud.press_mobile_button("dodge", Vector2i.LEFT), "HUD accepts mobile dodge control")
	asserts.true_value(hud.press_mobile_button("drink_tea", Vector2i.ZERO, 1), "HUD accepts mobile tea control")
	asserts.true_value(hud.press_mobile_button("use_consumable", Vector2i.ZERO, 0), "HUD accepts mobile consumable control")
	asserts.true_value(hud.press_mobile_button("cast_ability", Vector2i.UP, 0), "HUD accepts mobile ability control")
	asserts.true_value(hud.press_mobile_button("cast_ability", Vector2i.UP, 1), "HUD accepts the second mobile ability slot")
	asserts.true_value(hud.press_mobile_button("open_inventory"), "HUD accepts inventory command control")
	asserts.equal(received.size(), 8, "HUD emits exactly one command per valid mobile control")
	asserts.equal(received[0].type, GameCommand.Type.MOVE, "movement control emits shared move command")
	asserts.equal(received[1].type, GameCommand.Type.ATTACK, "attack control emits shared attack command")
	asserts.equal(received[2].type, GameCommand.Type.DODGE, "dodge control emits shared dodge command")
	asserts.equal(received[3].type, GameCommand.Type.DRINK_TEA, "tea control emits shared tea command")
	asserts.equal(received[4].type, GameCommand.Type.USE_CONSUMABLE, "consumable control emits shared consumable command")
	asserts.equal(received[5].type, GameCommand.Type.CAST_ABILITY, "ability control emits shared ability command")
	asserts.equal(received[6].type, GameCommand.Type.CAST_ABILITY, "second ability control emits shared ability command")
	asserts.equal(received[6].slot, 1, "second ability control preserves its stable slot index")
	asserts.equal(received[7].type, GameCommand.Type.OPEN_INVENTORY, "inventory control emits shared inventory command")
	var untouched_hud := _configured_hud()
	asserts.equal(untouched_hud.player.resources.hp, 82, "HUD button emission does not mutate player resources")
	untouched_hud.free()
	hud.free()

func _assert_dodge_control_does_not_use_baked_dash_asset(asserts) -> void:
	var hud := _configured_hud()
	var root := hud.get_node_or_null("Root")
	asserts.true_value(root != null, "HUD root is built")
	asserts.false_value(_tree_uses_texture(root, "dash_button.png"), "HUD does not use baked dash text asset")
	asserts.true_value(_tree_has_text(root, "회피"), "HUD renders official dodge term as font text")
	hud.free()

func _configured_hud() -> GameHud:
	var hud := GameHud.new()
	hud.configure(FakePlayer.new(), {"biome_id": "common_region"}, {"counts": {}}, {
		"catalog": FakeCatalog.new(),
		"inventory": FakeInventory.new(),
		"tea_service": FakeTeaService.new(),
		"time_state": FakeTimeState.new()
	})
	return hud

func _tree_uses_texture(node: Node, needle: String) -> bool:
	var texture = null
	if node is TextureRect:
		texture = (node as TextureRect).texture
	elif node is TextureButton:
		texture = (node as TextureButton).texture_normal
	if texture != null and String(texture.resource_path).contains(needle):
		return true
	for child in node.get_children():
		if _tree_uses_texture(child, needle):
			return true
	return false

func _tree_has_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, text):
			return true
	return false
