extends RefCounted

const UiPopupLayout = preload("res://src/ui/ui_popup_layout.gd")
const GameHud = preload("res://src/ui/game_hud.gd")

func run(asserts) -> void:
	asserts.equal(UiPopupLayout.fitted_size(Vector2(500, 280), Vector2(608, 336)), Vector2(498, 280), "wide popup width is capped to the shared game-width ratio")
	asserts.equal(UiPopupLayout.fitted_size(Vector2(500, 280), Vector2(328, 608)), Vector2(328, 280), "narrow popup uses all available width without escaping the game")
	asserts.equal(UiPopupLayout.fitted_size(Vector2(280, 180), Vector2(448, 246)), Vector2(280, 180), "small popup keeps its preferred size")
	var hud := GameHud.new()
	var grid := hud._map_color_grid({
		"origin": {"x": 0, "y": 0},
		"size": {"width": 2, "height": 1},
		"cells": []
	}, GameHud.FULL_MAP_CELL_SIZE)
	asserts.equal((grid.get_child(0) as Control).custom_minimum_size, Vector2(6, 6), "full map cells stay compact inside the popup")
	grid.free()
	hud.free()
