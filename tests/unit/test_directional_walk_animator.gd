extends RefCounted

const AssetCatalog = preload("res://src/core/data/asset_catalog.gd")
const DirectionalWalkAnimator = preload("res://src/presentation/directional_walk_animator.gd")

const WALK_ASSET_IDS := [
	"chr_1_kitsune_father_walk",
	"chr_2_wasteland_daimyo_walk",
	"chr_3_furuta_oribe_walk",
	"chr_4_snow_monk_walk",
	"chr_5_sen_rikyu_walk",
	"chr_6_yokai_tea_master_walk",
	"chr_7_mountain_potter_walk",
	"chr_8_fox_samurai_walk",
	"chr_9_wandering_tea_merchant_walk"
]
const ATTACK_ASSET_ID := "chr_8_fox_samurai_attack"

func run(asserts) -> void:
	var catalog := AssetCatalog.new()
	var load_result := catalog.load_manifest()
	asserts.true_value(load_result.ok, "walk animation asset manifest loads")
	if not load_result.ok:
		return

	for asset_id in WALK_ASSET_IDS:
		var validator := DirectionalWalkAnimator.new()
		var definition_result := validator.validate_definition(catalog.definition_for(asset_id))
		asserts.true_value(
			definition_result.ok,
			"%s follows the shared 4x8 walk contract: %s" % [asset_id, definition_result.get("error", "")]
		)
	var attack_validator := DirectionalWalkAnimator.new()
	var attack_definition_result := attack_validator.validate_definition(catalog.definition_for(ATTACK_ASSET_ID), "Attack")
	asserts.true_value(
		attack_definition_result.ok,
		"%s follows the shared 4x8 attack contract: %s" % [ATTACK_ASSET_ID, attack_definition_result.get("error", "")]
	)

	var sprite := Sprite2D.new()
	var animator := DirectionalWalkAnimator.new()
	var configure_result := animator.configure_for_character(
		sprite,
		catalog,
		"CHR-8",
		{
			"south": "fox_samurai_front_idle",
			"west": "fox_samurai_left_idle",
			"east": "fox_samurai_right_idle",
			"north": "fox_samurai_back_idle"
		}
	)
	asserts.true_value(
		configure_result.ok,
		"directional walk animator configures from stable asset IDs: %s" % configure_result.get("error", "")
	)
	if not configure_result.ok:
		return
	asserts.equal(animator.current_asset_id(), "fox_samurai_front_idle", "animator starts on the south idle asset")
	asserts.equal(Vector2i(sprite.hframes, sprite.vframes), Vector2i.ONE, "idle texture uses a single frame")

	animator.update(0.0, "east", true)
	asserts.equal(animator.current_asset_id(), "chr_8_fox_samurai_walk", "movement selects the walk sheet")
	asserts.equal(Vector2i(sprite.hframes, sprite.vframes), Vector2i(8, 4), "walk sheet exposes an 8x4 frame grid")
	asserts.equal(sprite.frame_coords, Vector2i(0, 2), "east movement starts on the east row")

	animator.update(0.125, "east", true)
	asserts.equal(sprite.frame_coords, Vector2i(1, 2), "walk timing advances one frame at eight frames per second")
	animator.update(0.125, "north", true)
	asserts.equal(sprite.frame_coords, Vector2i(0, 3), "direction changes reset on the north row")

	animator.update(0.0, "north", false)
	asserts.equal(animator.current_asset_id(), "fox_samurai_back_idle", "stopping restores the facing idle asset")
	asserts.equal(Vector2i(sprite.hframes, sprite.vframes), Vector2i.ONE, "stopping restores the single-frame texture contract")

	asserts.true_value(animator.play_attack("west"), "configured CHR-8 animator starts the attack sheet")
	asserts.equal(animator.current_asset_id(), ATTACK_ASSET_ID, "attack selects the CHR-8 attack sheet")
	asserts.equal(Vector2i(sprite.hframes, sprite.vframes), Vector2i(8, 4), "attack sheet exposes an 8x4 frame grid")
	asserts.equal(sprite.frame_coords, Vector2i(0, 1), "attack starts on the requested direction row")
	animator.update(0.0625, "west", false)
	asserts.equal(sprite.frame_coords, Vector2i(1, 1), "attack timing advances one frame at sixteen frames per second")
	animator.update(0.5, "west", false)
	asserts.equal(animator.current_asset_id(), "fox_samurai_left_idle", "attack returns to idle after the final frame")
	asserts.false_value(animator.is_attacking(), "attack state ends after the non-looping sequence")

	var npc_sprite := Sprite2D.new()
	var npc_animator := DirectionalWalkAnimator.new()
	var npc_result := npc_animator.configure_for_character(npc_sprite, catalog, "CHR-1")
	asserts.true_value(npc_result.ok, "major NPC walk presentation resolves from its stable character ID")
	if npc_result.ok:
		npc_animator.update(0.0, "west", true)
		asserts.equal(npc_animator.current_asset_id(), "chr_1_kitsune_father_walk", "major NPC movement selects its own walk sheet")
		asserts.equal(npc_sprite.frame_coords, Vector2i(0, 1), "major NPC movement selects the west row")
