extends RefCounted

const RuntimeConstants = preload("res://src/core/config/runtime_constants.gd")
const WorldData = preload("res://src/world/data/world_data.gd")
const WorldGenerator = preload("res://src/world/generation/world_generator.gd")

func run(asserts) -> void:
	asserts.equal(RuntimeConstants.int_value("world.overworld_width"), 48, "world width comes from runtime constants")
	asserts.equal(RuntimeConstants.int_value("world.overworld_height"), 28, "world height comes from runtime constants")
	asserts.equal(RuntimeConstants.int_value("world.chunk_width"), 8, "chunk width comes from runtime constants")
	asserts.equal(RuntimeConstants.int_value("world.chunk_height"), 6, "chunk height comes from runtime constants")
	asserts.equal(RuntimeConstants.float_value("world.tile_size_pixels"), 32.0, "tile size comes from runtime constants")
	asserts.equal(RuntimeConstants.float_value("game.turn_seconds"), 1.0, "turn duration comes from runtime constants")
	asserts.equal(WorldData.new(1, 1).tile_size, 32, "new world data uses the configured tile size")
	asserts.equal(WorldGenerator.MAP_WIDTH, RuntimeConstants.int_value("world.overworld_width"), "world generator width is configured")
	asserts.equal(WorldGenerator.MAP_HEIGHT, RuntimeConstants.int_value("world.overworld_height"), "world generator height is configured")
	asserts.equal(WorldGenerator.TEMPLATE_BANK.size(), 10, "world template bank contains ten layouts")
	asserts.true_value(not String(WorldGenerator._template_for_seed(11037, "common_region").get("id", "")).is_empty(), "seed selects a named world template")
