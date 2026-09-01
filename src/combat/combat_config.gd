extends RefCounted
class_name CombatConfig

const BASIC_ATTACK_COMBO_HITS_ID := "basic_attack_combo_hits"
const FINISHER_KNOCKBACK_ID := "basic_combo_finisher_knockback_tiles"
const DODGE_COOLDOWN_ID := "dodge_cooldown_seconds"
const DODGE_DISTANCE_ID := "dodge_distance_tiles"
const DODGE_INVULNERABILITY_ID := "dodge_invulnerability_seconds"
const KI_MULTIPLIER_0_ID := "ki_attack_multiplier_0"
const KI_MULTIPLIER_100_ID := "ki_attack_multiplier_100"
const KI_MAX_ID := "ki_max"
const HIT_INVULNERABILITY_ID := "hit_invulnerability_seconds"

const DEFAULT_WEAPON_ID := "short_travel_sword"

var basic_attack_combo_hits: int
var finisher_knockback_tiles: float
var dodge_cooldown_seconds: float
var dodge_distance_tiles: float
var dodge_invulnerability_seconds: float
var ki_attack_multiplier_0: float
var ki_attack_multiplier_100: float
var ki_max: float
var hit_invulnerability_seconds: float
var weapon_id: String
var weapon_base_damage: int
var weapon_range_tiles: float
var weapon_attack_speed: float
var armor_id: String
var armor_defense: int

func _init(values := {}) -> void:
	basic_attack_combo_hits = int(values.basic_attack_combo_hits)
	finisher_knockback_tiles = float(values.finisher_knockback_tiles)
	dodge_cooldown_seconds = float(values.dodge_cooldown_seconds)
	dodge_distance_tiles = float(values.dodge_distance_tiles)
	dodge_invulnerability_seconds = float(values.dodge_invulnerability_seconds)
	ki_attack_multiplier_0 = float(values.ki_attack_multiplier_0)
	ki_attack_multiplier_100 = float(values.ki_attack_multiplier_100)
	ki_max = float(values.ki_max)
	hit_invulnerability_seconds = float(values.hit_invulnerability_seconds)
	weapon_id = String(values.weapon_id)
	weapon_base_damage = int(values.weapon_base_damage)
	weapon_range_tiles = float(values.weapon_range_tiles)
	weapon_attack_speed = float(values.weapon_attack_speed)
	armor_id = String(values.get("armor_id", ""))
	armor_defense = int(values.get("armor_defense", 0))

static func from_catalog(catalog) -> Dictionary:
	var values := {}
	var balance_fields := {
		BASIC_ATTACK_COMBO_HITS_ID: "basic_attack_combo_hits",
		FINISHER_KNOCKBACK_ID: "finisher_knockback_tiles",
		DODGE_COOLDOWN_ID: "dodge_cooldown_seconds",
		DODGE_DISTANCE_ID: "dodge_distance_tiles",
		DODGE_INVULNERABILITY_ID: "dodge_invulnerability_seconds",
		KI_MULTIPLIER_0_ID: "ki_attack_multiplier_0",
		KI_MULTIPLIER_100_ID: "ki_attack_multiplier_100",
		KI_MAX_ID: "ki_max",
		HIT_INVULNERABILITY_ID: "hit_invulnerability_seconds"
	}
	for id in balance_fields.keys():
		var required_value := _required_balance_value(catalog, id)
		if not required_value.ok:
			return required_value
		values[balance_fields[id]] = required_value.value

	if int(values.basic_attack_combo_hits) < 1:
		return {"ok": false, "error": "Basic attack combo hits must be positive"}
	if float(values.ki_max) <= 0.0:
		return {"ok": false, "error": "Ki maximum must be positive"}
	if float(values.hit_invulnerability_seconds) < 0.0:
		return {"ok": false, "error": "Hit invulnerability must be non-negative"}

	var weapon := _weapon_values(catalog, DEFAULT_WEAPON_ID)
	if not weapon.ok:
		return weapon
	values["weapon_id"] = DEFAULT_WEAPON_ID
	values["weapon_base_damage"] = weapon.base_damage
	values["weapon_range_tiles"] = weapon.range_tiles
	values["weapon_attack_speed"] = weapon.attack_speed

	return {"ok": true, "config": load("res://src/combat/combat_config.gd").new(values)}

func damage_for_ki(current_ki: float) -> int:
	var ratio := clampf(current_ki / ki_max, 0.0, 1.0)
	var multiplier := lerpf(ki_attack_multiplier_0, ki_attack_multiplier_100, ratio)
	return int(round(weapon_base_damage * multiplier))

func apply_weapon_query(query: Dictionary) -> Dictionary:
	var weapon := _weapon_values_from_definition(query, String(query.get("weapon_id", "")))
	if not weapon.ok:
		return weapon
	weapon_id = String(query.weapon_id)
	weapon_base_damage = int(weapon.base_damage)
	weapon_range_tiles = float(weapon.range_tiles)
	weapon_attack_speed = float(weapon.attack_speed)
	return {"ok": true}

func apply_armor_query(query: Dictionary) -> Dictionary:
	var armor := _armor_values_from_definition(query, String(query.get("armor_id", "")))
	if not armor.ok:
		return armor
	armor_id = String(query.armor_id)
	armor_defense = int(armor.defense)
	return {"ok": true}

func get_combat_query() -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"base_damage": weapon_base_damage,
		"range": weapon_range_tiles,
		"attack_speed": weapon_attack_speed,
		"armor_id": armor_id,
		"defense": armor_defense
	}

func to_dictionary() -> Dictionary:
	return {
		"basic_attack_combo_hits": basic_attack_combo_hits,
		"finisher_knockback_tiles": finisher_knockback_tiles,
		"dodge_cooldown_seconds": dodge_cooldown_seconds,
		"dodge_distance_tiles": dodge_distance_tiles,
		"dodge_invulnerability_seconds": dodge_invulnerability_seconds,
		"ki_attack_multiplier_0": ki_attack_multiplier_0,
		"ki_attack_multiplier_100": ki_attack_multiplier_100,
		"ki_max": ki_max,
		"hit_invulnerability_seconds": hit_invulnerability_seconds,
		"weapon_id": weapon_id,
		"weapon_base_damage": weapon_base_damage,
		"weapon_range_tiles": weapon_range_tiles,
		"weapon_attack_speed": weapon_attack_speed,
		"armor_id": armor_id,
		"armor_defense": armor_defense
	}

static func _required_balance_value(catalog, id: String) -> Dictionary:
	var definition: Dictionary = catalog.find_by_id("balance", id)
	if definition.is_empty() or not definition.has("value"):
		return {"ok": false, "error": "Missing required combat balance value: %s" % id}
	var value = definition.value
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "Combat balance value must be numeric: %s" % id}
	var numeric_value := float(value)
	if not is_finite(numeric_value):
		return {"ok": false, "error": "Combat balance value must be finite: %s" % id}
	return {"ok": true, "value": numeric_value}

static func _weapon_values(catalog, weapon_id: String) -> Dictionary:
	var definition: Dictionary = catalog.find_by_id("items", weapon_id)
	if definition.is_empty():
		return {"ok": false, "error": "Missing weapon definition: %s" % weapon_id}
	return _weapon_values_from_definition(definition, weapon_id)

static func _weapon_values_from_definition(definition: Dictionary, weapon_id: String) -> Dictionary:
	for field in ["base_damage", "range", "attack_speed"]:
		var value = definition.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
			return {"ok": false, "error": "Weapon field must be a positive number: %s.%s" % [weapon_id, field]}
	if float(definition.base_damage) != floor(float(definition.base_damage)):
		return {"ok": false, "error": "Weapon base damage must be an integer: %s" % weapon_id}
	return {
		"ok": true,
		"base_damage": float(definition.base_damage),
		"range_tiles": float(definition.range),
		"attack_speed": float(definition.attack_speed)
	}

static func _armor_values_from_definition(definition: Dictionary, armor_id: String) -> Dictionary:
	if armor_id == "":
		return {"ok": false, "error": "Missing armor id."}
	var value = definition.get("defense")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
		return {"ok": false, "error": "Armor defense must be a non-negative number: %s" % armor_id}
	if float(value) != floor(float(value)):
		return {"ok": false, "error": "Armor defense must be an integer: %s" % armor_id}
	return {"ok": true, "defense": int(value)}
