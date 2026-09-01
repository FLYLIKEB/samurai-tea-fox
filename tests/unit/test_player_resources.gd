extends RefCounted

const PlayerResources = preload("res://src/player/player_resources.gd")

func run(asserts) -> void:
	var resources := PlayerResources.new(100, 100, 100)
	resources.apply_damage(25)
	asserts.equal(resources.hp, 75, "damage reduces HP")
	resources.spend_ki(40)
	asserts.equal(resources.ki, 60, "ability spending uses ki")
	resources.reduce_kokoro(100)
	asserts.equal(resources.kokoro, 0, "kokoro clamps to zero")
	resources.sleep_until_morning()
	asserts.equal(resources.kokoro, 100, "sleep restores kokoro")

