extends RefCounted

const StatusToastPresenter = preload("res://src/ui/hud/status_toast_presenter.gd")
const StatusPanelPresenter = preload("res://src/ui/hud/status_panel_presenter.gd")
const MapPanelPresenter = preload("res://src/ui/hud/map_panel_presenter.gd")
const MobileControlsPresenter = preload("res://src/ui/hud/mobile_controls_presenter.gd")
const SettingsPresenter = preload("res://src/ui/hud/settings_presenter.gd")

const FORBIDDEN_DEP_KEYS := [
	"hud",
	"game_hud",
	"self",
	"provider",
	"read_model_provider",
	"inventory",
	"inventory_command_runtime",
	"crafting_service",
	"tea_service",
	"tea_brewing_command_runtime",
	"meta_codex_command_runtime",
	"player",
	"runtime_context"
]

var presented: Array = []
var commands: Array = []
var movements: Array = []
var layout_requests := 0
var return_requests := 0

func run(asserts) -> void:
	_assert_presenter_deps_stay_narrow(asserts)
	_assert_presenters_keep_public_node_paths(asserts)
	_assert_equipment_snapshot_contract(asserts)
	_assert_toast_queue_contract(asserts)

func _assert_presenter_deps_stay_narrow(asserts) -> void:
	for deps in [_toast_deps(), _status_deps(), _map_deps(), _mobile_deps(), _settings_deps()]:
		for key in FORBIDDEN_DEP_KEYS:
			asserts.false_value(deps.has(key), "HUD feature presenter deps reject broad owner/service key: %s" % key)

func _assert_presenters_keep_public_node_paths(asserts) -> void:
	var root := Control.new()
	StatusToastPresenter.new().build(root, _toast_deps())
	StatusPanelPresenter.new().build(root, _status_deps())
	MapPanelPresenter.new().build(root, _map_deps())
	MobileControlsPresenter.new().build(root, _mobile_deps())
	SettingsPresenter.new().build(root, _settings_deps())
	asserts.true_value(root.get_node_or_null("StatusToastPanel/StatusToastRow/StatusToastLabel") is Label, "toast presenter preserves status toast label path")
	asserts.true_value(root.get_node_or_null("StatusPanel/StatusBody/StatusRows/EquipmentStrip") is HBoxContainer, "status presenter preserves equipment strip path")
	asserts.true_value(root.get_node_or_null("ResourceDetailPanel") is PanelContainer, "status presenter owns resource detail panel")
	asserts.true_value(root.get_node_or_null("MapPanel/MapRows/TimeDialRow/TimeDial") is Control, "map presenter preserves time dial path")
	asserts.true_value(root.get_node_or_null("DPadPanel/DPadBoard/DPadLeft") is Button, "mobile presenter preserves D-pad button path")
	asserts.true_value(root.get_node_or_null("ActionPanel/ActionRows/ActionGrid/AttackButton") is Button, "mobile presenter preserves action button path")
	asserts.true_value(root.get_node_or_null("BottomNavPanel/BottomNavRow/InventoryNavButton") is Button, "mobile presenter preserves bottom nav path")
	asserts.true_value(root.get_node_or_null("FacilitiesShortcutButton") is Button, "mobile presenter keeps facility shortcut outside settings drawer")
	asserts.true_value(root.get_node_or_null("ActionMenuPanel/SettingsRows/GameVolumeSlider") is HSlider, "settings presenter owns volume slider")
	root.free()

func _assert_toast_queue_contract(asserts) -> void:
	presented.clear()
	var root := Control.new()
	var presenter := StatusToastPresenter.new()
	presenter.build(root, _toast_deps())
	asserts.false_value(presenter.enqueue({"message": ""}), "toast presenter rejects empty messages")
	asserts.true_value(presenter.enqueue({"message": "첫째", "event_key": "a"}), "toast presenter accepts first toast")
	asserts.false_value(presenter.enqueue({"message": "중복", "event_key": "a"}), "toast presenter rejects active duplicate keys")
	for index in range(5):
		asserts.true_value(presenter.enqueue({"message": "대기 %d" % index, "event_key": "q%d" % index}), "toast presenter accepts capped queue item")
	var snapshot := presenter.debug_snapshot()
	asserts.equal((snapshot.queue as Array).size(), 3, "toast presenter caps pending to three behind one active")
	asserts.equal(String((snapshot.queue as Array)[0].get("event_key", "")), "q2", "toast presenter drops oldest pending item on overflow")
	asserts.equal(String((snapshot.queue as Array)[2].get("event_key", "")), "q4", "toast presenter keeps newest pending item on overflow")
	var remaining := float(snapshot.remaining)
	presenter.tick(-10.0)
	asserts.equal(presenter.debug_snapshot().label_text, "첫째", "negative delta does not advance the active toast")
	asserts.true_value(is_equal_approx(float(presenter.debug_snapshot().remaining), remaining), "negative delta does not extend toast duration")
	presenter.tick(1.0)
	asserts.equal(String(presenter.debug_snapshot().active.get("event_key", "")), "q2", "toast presenter advances to oldest retained pending item")
	root.free()

func _assert_equipment_snapshot_contract(asserts) -> void:
	var root := Control.new()
	var presenter := StatusPanelPresenter.new()
	presenter.build(root, _status_deps())
	presenter.update({
		"hp": 1,
		"hp_max": 1,
		"ki": 1,
		"ki_max": 1,
		"kokoro": 1,
		"kokoro_max": 1,
		"equipment": {
			"weapon": {"item_id": "mountain_iron_dagger", "name": "산철 단검"},
			"armor": {"item_id": "traveler_quilted_clothes", "name": "나그네 누비옷"},
			"tea_ware": {"item_id": "humble_clay_bowl", "name": "소박한 흙찻잔"}
		}
	})
	var snapshot := presenter.equipment_hud_snapshot()
	for slot_key in ["weapon", "armor", "tea_ware"]:
		var slot: Dictionary = snapshot.get(slot_key, {})
		for key in ["slot_key", "slot_label", "item_id", "name", "display_text", "icon_reference", "icon_has_texture", "tooltip"]:
			asserts.true_value(slot.has(key), "equipment snapshot preserves %s for %s" % [key, slot_key])
	asserts.equal(String(snapshot.armor.slot_label), "방어", "armor equipment label stays compatible")
	root.free()

func _toast_deps() -> Dictionary:
	return {"texture_resolver": Callable(self, "_null_texture"), "presented": Callable(self, "_record_presented")}

func _status_deps() -> Dictionary:
	return {
		"texture_resolver": Callable(self, "_null_texture"),
		"item_icon_reference": Callable(self, "_item_icon_reference"),
		"request_layout": Callable(self, "_record_layout"),
		"runtime_read_model": Callable(self, "_resource_model")
	}

func _map_deps() -> Dictionary:
	return {
		"texture_resolver": Callable(self, "_null_texture"),
		"press_mobile_button": Callable(self, "_record_button"),
		"show_detail_popup": Callable(self, "_record_popup"),
		"request_map_refresh": Callable(self, "_record_layout"),
		"emit_command": Callable(self, "_record_command")
	}

func _mobile_deps() -> Dictionary:
	return {
		"texture_resolver": Callable(self, "_null_texture"),
		"press_mobile_button": Callable(self, "_record_button"),
		"movement_changed": Callable(self, "_record_movement"),
		"tea_quickslot_count": Callable(self, "_tea_slots"),
		"balance_integer": Callable(self, "_balance_integer")
	}

func _settings_deps() -> Dictionary:
	return {"request_layout": Callable(self, "_record_layout"), "return_to_start": Callable(self, "_record_return")}

func _null_texture(_reference: String) -> Texture2D:
	return null

func _item_icon_reference(_item_id: String, _kind: String, _definition: Dictionary) -> String:
	return ""

func _resource_model() -> Dictionary:
	return {"hp": 1, "hp_max": 1, "ki": 1, "ki_max": 1, "kokoro": 1, "kokoro_max": 1}

func _record_presented(kind: String, event_key: String) -> void:
	presented.append({"kind": kind, "event_key": event_key})

func _record_button(button_id: String, direction := Vector2i.ZERO, slot := 0) -> void:
	commands.append({"button_id": button_id, "direction": direction, "slot": slot})

func _record_movement(direction: Vector2i) -> void:
	movements.append(direction)

func _record_command(command) -> void:
	commands.append(command)

func _record_popup(_title: String, _content: Control) -> void:
	layout_requests += 1

func _record_layout() -> void:
	layout_requests += 1

func _record_return() -> void:
	return_requests += 1

func _tea_slots() -> int:
	return 3

func _balance_integer(_id: String) -> int:
	return 2
