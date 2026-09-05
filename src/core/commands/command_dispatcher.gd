extends RefCounted
class_name CommandDispatcher

const GameCommand = preload("res://src/core/commands/game_command.gd")

signal command_issued(command)

func dispatch(command) -> bool:
	if not command is GameCommand:
		return false
	command_issued.emit(command)
	return true

func result_for(command, accepted: bool, overrides := {}) -> Dictionary:
	if not command is GameCommand:
		return {
			"ok": false,
			"accepted": false,
			"reason": "invalid_command",
			"command": command,
			"consumes_turn": false,
			"queues_enemy_turn": false,
			"feedback_beep": false,
			"sync_tea_runtime": false,
			"interact_failure_sfx": false
		}
	var policy := _policy_for(command)
	for key in overrides:
		policy[key] = overrides[key]
	if bool(policy.get("placement_pending", false)):
		policy["consumes_turn"] = false
		policy["queues_enemy_turn"] = false
	var accepted_command := bool(accepted)
	return {
		"ok": true,
		"accepted": accepted_command,
		"command": command,
		"type": command.type,
		"consumes_turn": accepted_command and bool(policy.get("consumes_turn", false)),
		"queues_enemy_turn": accepted_command and bool(policy.get("queues_enemy_turn", false)),
		"feedback_beep": accepted_command and bool(policy.get("feedback_beep", false)),
		"sync_tea_runtime": accepted_command and bool(policy.get("sync_tea_runtime", false)),
		"interact_failure_sfx": not accepted_command and bool(policy.get("interact_failure_sfx", false))
	}

func _policy_for(command: GameCommand) -> Dictionary:
	match command.type:
		GameCommand.Type.INTERACT:
			return {"consumes_turn": true, "queues_enemy_turn": true, "interact_failure_sfx": true}
		GameCommand.Type.DRINK_TEA:
			return {"consumes_turn": true, "queues_enemy_turn": true, "feedback_beep": true}
		GameCommand.Type.USE_CONSUMABLE:
			return {"feedback_beep": true}
		GameCommand.Type.CRAFT_RECIPE:
			return {"consumes_turn": true, "queues_enemy_turn": true, "feedback_beep": true}
		GameCommand.Type.ATTACK, GameCommand.Type.DODGE:
			return {"consumes_turn": true, "queues_enemy_turn": true}
		GameCommand.Type.CAST_ABILITY:
			return {"consumes_turn": true, "queues_enemy_turn": true, "sync_tea_runtime": true}
		GameCommand.Type.NARRATIVE_SELECT_OPTION, \
				GameCommand.Type.SLEEP, \
				GameCommand.Type.COMPLETE_DUNGEON, \
				GameCommand.Type.REPAIR_TELEPORT, \
				GameCommand.Type.ADVANCE_BIOME, \
				GameCommand.Type.TRAVEL_TO_BIOME, \
				GameCommand.Type.TEA_BREW_SELECT_LEAF, \
				GameCommand.Type.TEA_BREW_SELECT_VESSEL, \
				GameCommand.Type.TEA_BREW_SELECT_SLOT, \
				GameCommand.Type.TEA_BREW_NAVIGATE, \
				GameCommand.Type.BREW_TEA, \
				GameCommand.Type.META_CODEX_SET_TAB, \
				GameCommand.Type.META_CODEX_SET_FILTER, \
				GameCommand.Type.META_CODEX_SELECT_DETAIL, \
				GameCommand.Type.META_CODEX_NAVIGATE, \
				GameCommand.Type.INVENTORY_SET_FILTER, \
				GameCommand.Type.INVENTORY_SORT, \
				GameCommand.Type.INVENTORY_SELECT_SLOT, \
				GameCommand.Type.INVENTORY_NAVIGATE, \
				GameCommand.Type.EQUIP_INVENTORY_SLOT, \
				GameCommand.Type.UNEQUIP_SLOT, \
				GameCommand.Type.USE_INVENTORY_SLOT:
			return {"feedback_beep": true}
	return {}
