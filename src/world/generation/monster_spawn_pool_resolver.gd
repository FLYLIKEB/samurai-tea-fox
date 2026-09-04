extends RefCounted
class_name MonsterSpawnPoolResolver

const DeterministicRng = preload("res://src/core/rng/deterministic_rng.gd")
const MonsterDefinition = preload("res://src/enemy/monster_definition.gd")

const DAY_NIGHT_DAY := "낮"
const DAY_NIGHT_NIGHT := "밤"
const DAY_NIGHT_BOTH := "둘 다"
const GLOBAL_BIOME := "전역"
const RARE_BEHAVIOR_TYPE := "희귀"

func resolve(biome_definition: Dictionary, monster_definitions: Array, phase: String, seed: int, data_version: String) -> Dictionary:
	var biome_id := String(biome_definition.get("id", ""))
	var bucket := _time_bucket(phase)
	var candidate_ids := []
	var spawnable_entries := []
	var skipped := []

	for monster in _sorted_monsters(monster_definitions):
		var monster_id := String(monster.get("id", ""))
		if monster_id.is_empty():
			continue
		if not _matches_biome(monster, biome_definition):
			continue
		if not _matches_time(monster, bucket):
			continue
		candidate_ids.append(monster_id)
		var validation := MonsterDefinition.validate_row(monster)
		if not validation.ok:
			skipped.append({"id": monster_id, "reason": validation.get("error", "invalid_runtime_definition")})
			continue
		spawnable_entries.append(_entry(monster, biome_id, bucket))

	var rare_variant := {}
	if bucket == "night" and not spawnable_entries.is_empty():
		rare_variant = _rare_variant(spawnable_entries, seed, data_version, biome_id, String(phase))
		spawnable_entries.append(rare_variant)

	return {
		"ok": true,
		"biome_id": biome_id,
		"phase": String(phase),
		"time_bucket": bucket,
		"candidate_ids": candidate_ids,
		"spawnable_ids": _ids_from_entries(spawnable_entries),
		"entries": spawnable_entries,
		"skipped_ids": skipped,
		"rare_variant": rare_variant
	}

func _entry(monster: Dictionary, biome_id: String, bucket: String) -> Dictionary:
	return {
		"id": String(monster.id),
		"monster_id": String(monster.id),
		"name": String(monster.get("name", "")),
		"biome_id": biome_id,
		"time_bucket": bucket,
		"day_night": String(monster.get("day_night", DAY_NIGHT_BOTH)),
		"kind": String(monster.get("kind", "")),
		"behavior_type": String(monster.get("behavior_type", "")),
		"rare": false
	}

func _rare_variant(entries: Array, seed: int, data_version: String, biome_id: String, phase: String) -> Dictionary:
	var candidates := entries.duplicate(true)
	candidates.sort_custom(Callable(self, "_sort_rare_candidates"))
	var index := _variant_index(seed, data_version, biome_id, phase, candidates.size())
	var base: Dictionary = candidates[index]
	return {
		"id": "%s_night_rare_variant" % String(base.monster_id),
		"monster_id": String(base.monster_id),
		"variant_of": String(base.monster_id),
		"name": "%s 밤 희귀 변형" % String(base.name),
		"biome_id": biome_id,
		"time_bucket": "night",
		"day_night": DAY_NIGHT_NIGHT,
		"kind": String(base.kind),
		"behavior_type": RARE_BEHAVIOR_TYPE,
		"behavior_type_override": RARE_BEHAVIOR_TYPE,
		"rare": true
	}

func _variant_index(seed: int, data_version: String, biome_id: String, phase: String, size: int) -> int:
	var hash: int = max(1, seed)
	for character in "%s:%s:%s:night_rare_variant" % [data_version, biome_id, phase]:
		hash = int((hash * 31 + character.unicode_at(0)) % DeterministicRng.MODULUS)
	return absi(hash) % maxi(size, 1)

func _sort_rare_candidates(a: Dictionary, b: Dictionary) -> bool:
	var a_night := String(a.get("day_night", "")) == DAY_NIGHT_NIGHT
	var b_night := String(b.get("day_night", "")) == DAY_NIGHT_NIGHT
	if a_night != b_night:
		return a_night
	var a_yokai := String(a.get("kind", "")) == "요괴"
	var b_yokai := String(b.get("kind", "")) == "요괴"
	if a_yokai != b_yokai:
		return a_yokai
	return String(a.get("monster_id", "")) < String(b.get("monster_id", ""))

func _ids_from_entries(entries: Array) -> Array:
	var ids := []
	for entry in entries:
		ids.append(String(entry.get("id", entry.get("monster_id", ""))))
	return ids

func _sorted_monsters(monster_definitions: Array) -> Array:
	var rows := monster_definitions.duplicate(true)
	rows.sort_custom(Callable(self, "_sort_by_id"))
	return rows

func _sort_by_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("id", "")) < String(b.get("id", ""))

func _matches_time(monster: Dictionary, bucket: String) -> bool:
	var value := String(monster.get("day_night", DAY_NIGHT_BOTH))
	if value == DAY_NIGHT_BOTH:
		return true
	if bucket == "night":
		return value == DAY_NIGHT_NIGHT
	return value == DAY_NIGHT_DAY

func _time_bucket(phase: String) -> String:
	return "night" if phase in ["night", "late_night"] else "day"

func _matches_biome(monster: Dictionary, biome_definition: Dictionary) -> bool:
	var biome_id := String(biome_definition.get("id", ""))
	var biome_ids = monster.get("biome_ids", [])
	if biome_ids is Array and biome_ids.has(biome_id):
		return true
	var label := String(monster.get("biome", ""))
	if label == GLOBAL_BIOME:
		return true
	if label.is_empty():
		return false
	var aliases := _biome_aliases(biome_definition)
	return aliases.has(_normalized_biome_label(label))

func _biome_aliases(biome_definition: Dictionary) -> Dictionary:
	var aliases := {}
	for value in [biome_definition.get("id", ""), biome_definition.get("name", "")]:
		var normalized := _normalized_biome_label(String(value))
		if not normalized.is_empty():
			aliases[normalized] = true
	return aliases

func _normalized_biome_label(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized.ends_with(" 지역"):
		normalized = normalized.trim_suffix(" 지역").strip_edges()
	if normalized.ends_with("지역"):
		normalized = normalized.trim_suffix("지역").strip_edges()
	normalized = normalized.replace(" ", "_")
	if normalized.ends_with("_region"):
		normalized = normalized.trim_suffix("_region")
	return normalized
