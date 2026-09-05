from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any


class ExportValidationError(ValueError):
    pass


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


class ExportPipeline:
    DROP_CONDITIONS = {"항상", "낮", "밤"}
    EVENT_REPLAY_POLICIES = {"once", "repeat"}
    EVENT_RESULT_TYPES = {"set_run_flag", "grant_item", "apply_choice"}
    PRE_BOSS_TRIGGER_TIMINGS = {"보스 전", "보스전 전", "전투 전", "pre_boss", "pre_boss_dialogue"}
    EVENT_CONDITION_TYPES = {
        "always",
        "run_flag",
        "run_not_flag",
        "current_biome",
        "has_item",
        "meta_flag",
        "meta_not_flag",
        "meta_run_count_at_least",
        "meta_past_choice",
        "meta_reached_place",
        "meta_death_record",
    }
    BOSS_TEA_CONDITION_TYPES = {"always", "prepared_tea", "run_flag", "run_not_flag", "current_biome", "has_item"}
    BOSS_TEA_HOOK_GROUPS = {"common", "peaceful_tea_ceremony", "mixed", "combat_started"}
    BOSS_TEA_HOOK_CHANNELS = {"memory", "weakness", "dialogue"}
    TEA_RECOVERY_MODES = {"instant", "progressive", "conditional"}

    def __init__(self, schema: dict[str, Any]):
        self.schema = schema

    @classmethod
    def from_path(cls, path: Path) -> "ExportPipeline":
        return cls(json.loads(path.read_text(encoding="utf-8")))

    def build_snapshots(self, capture: dict[str, Any], profile: str = "confirmed") -> dict[str, dict[str, Any]]:
        self._validate_capture_header(capture, profile)
        datasets = capture.get("datasets")
        if not isinstance(datasets, dict) or not datasets:
            raise ExportValidationError("capture.datasets must be a non-empty object")

        included_by_dataset: dict[str, list[dict[str, Any]]] = {}
        source_by_dataset: dict[str, str] = {}
        for dataset_name in sorted(datasets):
            dataset = datasets[dataset_name]
            config = self._dataset_config(dataset_name)
            source = dataset.get("source") if isinstance(dataset, dict) else None
            rows = dataset.get("items") if isinstance(dataset, dict) else None
            if not isinstance(source, str) or not source:
                raise ExportValidationError(f"{dataset_name}: source must be a non-empty string")
            if not isinstance(rows, list):
                raise ExportValidationError(f"{dataset_name}: items must be an array")

            included_by_dataset[dataset_name] = self._filter_and_validate_rows(dataset_name, rows, config, profile)
            source_by_dataset[dataset_name] = source

        self._apply_pre_boss_dialogue_links(included_by_dataset)

        snapshots: dict[str, dict[str, Any]] = {}
        for dataset_name in sorted(included_by_dataset):
            payload = {
                "schema_version": self.schema["schema_version"],
                "data_version": capture["data_version"],
                "profile": profile,
                "source": source_by_dataset[dataset_name],
                "items": included_by_dataset[dataset_name],
            }
            snapshots[dataset_name] = {
                **payload,
                "content_hash": hashlib.sha256(canonical_json_bytes(payload)).hexdigest(),
            }

        self._validate_relations(snapshots)
        return snapshots

    def export(self, capture: dict[str, Any], output_directory: Path, profile: str = "confirmed") -> list[Path]:
        snapshots = self.build_snapshots(capture, profile)
        output_directory.mkdir(parents=True, exist_ok=True)
        written: list[Path] = []
        for dataset_name, snapshot in snapshots.items():
            path = output_directory / self._dataset_config(dataset_name)["file"]
            path.write_text(
                json.dumps(snapshot, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
                encoding="utf-8",
            )
            written.append(path)
        return written

    def validate_directory(self, directory: Path) -> dict[str, Any]:
        snapshots: dict[str, dict[str, Any]] = {}
        data_version: str | None = None
        profile: str | None = None

        for path in sorted(directory.glob("*.json")):
            matching = [name for name, config in self.schema["datasets"].items() if config["file"] == path.name]
            if not matching:
                continue
            dataset_name = matching[0]
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            self._validate_snapshot(dataset_name, snapshot)
            if data_version is None:
                data_version = snapshot["data_version"]
                profile = snapshot["profile"]
            elif snapshot["data_version"] != data_version:
                raise ExportValidationError(f"{path}: mismatched data_version")
            elif snapshot["profile"] != profile:
                raise ExportValidationError(f"{path}: mismatched profile")
            snapshots[dataset_name] = snapshot

        if not snapshots:
            raise ExportValidationError(f"{directory}: no export snapshots found")
        self._validate_relations(snapshots)
        return {"data_version": data_version, "profile": profile, "datasets": sorted(snapshots)}

    def _validate_capture_header(self, capture: dict[str, Any], profile: str) -> None:
        if not isinstance(capture, dict):
            raise ExportValidationError("capture must be a JSON object")
        if capture.get("schema_version") != self.schema.get("schema_version"):
            raise ExportValidationError("capture schema_version does not match export schema")
        if not isinstance(capture.get("data_version"), str) or not capture["data_version"]:
            raise ExportValidationError("capture.data_version must be a non-empty string")
        if profile not in self.schema.get("profiles", {}):
            raise ExportValidationError(f"unknown export profile: {profile}")

    def _dataset_config(self, dataset_name: str) -> dict[str, Any]:
        try:
            return self.schema["datasets"][dataset_name]
        except KeyError as error:
            raise ExportValidationError(f"unknown dataset: {dataset_name}") from error

    def _filter_and_validate_rows(
        self,
        dataset_name: str,
        rows: list[Any],
        config: dict[str, Any],
        profile: str,
    ) -> list[dict[str, Any]]:
        confirmed = set(config.get("confirmed_statuses", ["확정"]))
        test = set(config.get("test_statuses", ["테스트", "초안"]))
        discarded = set(config.get("discarded_statuses", ["폐기"]))
        include_test = bool(self.schema["profiles"][profile].get("include_test"))
        included_statuses = confirmed | (test if include_test else set())
        required_fields = config.get("required_fields", ["id", "name", "status"])
        id_pattern = re.compile(self.schema["stable_id_pattern"])
        seen_ids: set[str] = set()
        included: list[dict[str, Any]] = []

        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise ExportValidationError(f"{dataset_name}[{index}]: item must be an object")
            item_id = row.get("id", f"index-{index}")
            status = row.get("status")
            if status in (None, ""):
                raise ExportValidationError(f"{dataset_name} item {item_id}: missing required field status")
            known_statuses = confirmed | test | discarded
            if status not in known_statuses:
                raise ExportValidationError(f"{dataset_name} item {item_id}: unknown status {status}")
            if status in discarded or status not in included_statuses:
                continue
            for field in required_fields:
                if field not in row or row[field] in (None, ""):
                    raise ExportValidationError(f"{dataset_name} item {item_id}: missing required field {field}")
            normalized_row = normalize_structured_fields(dataset_name, row)
            self._validate_row_contract(dataset_name, normalized_row)
            item_id = normalized_row["id"]
            if not isinstance(item_id, str) or not id_pattern.fullmatch(item_id):
                raise ExportValidationError(f"{dataset_name} item {item_id}: invalid stable id")
            if item_id in seen_ids:
                raise ExportValidationError(f"{dataset_name}: duplicate stable id {item_id}")
            seen_ids.add(item_id)
            included.append(copy_json_value(normalized_row))

        if dataset_name == "events":
            return sorted(included, key=self._event_sort_key)
        return sorted(included, key=lambda item: item["id"])

    @staticmethod
    def _event_sort_key(item: dict[str, Any]) -> tuple[float, float, float, str]:
        source_lines = item.get("source_lines", [])
        line_order = 0.0
        if isinstance(source_lines, list) and source_lines:
            first_line = source_lines[0] if isinstance(source_lines[0], dict) else {}
            line_order = _number_or_end(first_line.get("line_order"))
        return (
            _number_or_end(item.get("story_order")),
            _number_or_end(item.get("scene_order")),
            line_order,
            str(item.get("id", "")),
        )

    def _validate_row_contract(self, dataset_name: str, row: dict[str, Any]) -> None:
        if dataset_name == "biomes":
            self._validate_biome_contract(row)
            return
        if dataset_name == "characters":
            self._validate_character_contract(row)
            return
        if dataset_name == "drops":
            self._validate_drop_contract(row)
            return
        if dataset_name == "choices":
            self._validate_choice_contract(row)
            return
        if dataset_name == "shops":
            self._validate_shop_contract(row)
            return
        if dataset_name == "meta_unlocks":
            self._validate_meta_unlock_contract(row)
            return
        if dataset_name == "bosses":
            self._validate_boss_contract(row)
            return
        if dataset_name == "dungeons":
            self._validate_dungeon_contract(row)
            return
        if dataset_name == "teas":
            self._validate_tea_contract(row)
            return
        if dataset_name == "recipes":
            self._validate_recipe_contract(row)
            return
        if dataset_name != "items":
            return
        self._validate_item_contract(row)
        if row.get("type") != "다구" or row.get("equipment_slot") != "다구":
            return
        self._validate_attachment_stage_data(row)

    def _validate_item_contract(self, row: dict[str, Any]) -> None:
        item_id = row.get("id", "")
        for field in ("max_stack", "max_owned"):
            value = row.get(field)
            if value is not None and (
                not isinstance(value, int) or isinstance(value, bool) or value <= 0
            ):
                raise ExportValidationError(
                    f"items item {item_id}: {field} must be a positive integer"
                )

        item_type = row.get("type")
        if item_type == "무기":
            self._validate_equipment_item(row, "무기", ("base_damage", "attack_speed", "range"))
        elif item_type == "방어구":
            self._validate_equipment_item(row, "방어구", ("defense",))
        elif item_type == "소모품":
            self._validate_positive_number(row, "use_seconds", "items", item_id)

    def _validate_equipment_item(
        self,
        row: dict[str, Any],
        expected_slot: str,
        numeric_fields: tuple[str, ...],
    ) -> None:
        item_id = row.get("id", "")
        if row.get("equipment_slot") != expected_slot:
            raise ExportValidationError(
                f"items item {item_id}: equipment_slot must be {expected_slot}"
            )
        for field in numeric_fields:
            self._validate_positive_number(row, field, "items", item_id)

    def _validate_recipe_contract(self, row: dict[str, Any]) -> None:
        recipe_id = row.get("id", "")
        required_fields = set(
            self._dataset_config("recipes").get("required_fields", [])
        )
        for field in ("result_item_id", "facility", "materials_note"):
            if field not in required_fields:
                continue
            value = row.get(field)
            if not isinstance(value, str) or not value.strip():
                raise ExportValidationError(
                    f"recipes item {recipe_id}: {field} must be a non-empty string"
                )
        result_item_id = row.get("result_item_id")
        if result_item_id is not None and not re.fullmatch(
            self.schema["stable_id_pattern"], result_item_id
        ):
            raise ExportValidationError(
                f"recipes item {recipe_id}: result_item_id must be a stable id"
            )
        if "result_quantity" not in required_fields:
            return
        quantity = row.get("result_quantity")
        if not isinstance(quantity, int) or isinstance(quantity, bool) or quantity <= 0:
            raise ExportValidationError(
                f"recipes item {recipe_id}: result_quantity must be a positive integer"
            )

    @staticmethod
    def _validate_positive_number(
        row: dict[str, Any],
        field: str,
        dataset_name: str,
        item_id: str,
    ) -> None:
        value = row.get(field)
        if (
            not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not math.isfinite(float(value))
            or float(value) <= 0.0
        ):
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: {field} must be a positive number"
            )

    def _validate_tea_contract(self, row: dict[str, Any]) -> None:
        tea_id = row.get("id", "")
        recovery = row.get("ki_recovery")
        if not isinstance(recovery, int) or isinstance(recovery, bool) or recovery < 0:
            raise ExportValidationError(
                f"teas item {tea_id}: ki_recovery must be a non-negative integer"
            )
        recovery_mode = row.get("recovery_mode", "instant")
        if recovery_mode not in self.TEA_RECOVERY_MODES:
            raise ExportValidationError(
                f"teas item {tea_id}: invalid recovery_mode {recovery_mode}"
            )
        self._validate_optional_positive_number(row, "drink_seconds", tea_id)
        self._validate_optional_positive_integer(row, "serving_size", tea_id)
        self._validate_optional_positive_integer(row, "carry_uses", tea_id)
        sustain = row.get("sustain_modifier")
        if sustain is not None and (
            not isinstance(sustain, (int, float))
            or isinstance(sustain, bool)
            or not math.isfinite(float(sustain))
            or not -100.0 <= float(sustain) <= 100.0
        ):
            raise ExportValidationError(
                f"teas item {tea_id}: sustain_modifier must be between -100 and 100"
            )
        condition_key = row.get("condition_key")
        if condition_key not in (None, "") and (
            not isinstance(condition_key, str)
            or not re.fullmatch(self.schema["stable_id_pattern"], condition_key)
        ):
            raise ExportValidationError(
                f"teas item {tea_id}: condition_key must be a stable id"
            )
        if "requires_brewing_location" in row and not isinstance(row["requires_brewing_location"], bool):
            raise ExportValidationError(
                f"teas item {tea_id}: requires_brewing_location must be a boolean"
            )
        if "special_effect" in row and not isinstance(row["special_effect"], str):
            raise ExportValidationError(
                f"teas item {tea_id}: special_effect must be a string"
            )

    @staticmethod
    def _validate_optional_positive_number(row: dict[str, Any], field: str, tea_id: str) -> None:
        value = row.get(field)
        if value is None:
            return
        if (
            not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not math.isfinite(float(value))
            or float(value) <= 0.0
        ):
            raise ExportValidationError(
                f"teas item {tea_id}: {field} must be a positive number"
            )

    @staticmethod
    def _validate_optional_positive_integer(row: dict[str, Any], field: str, tea_id: str) -> None:
        value = row.get(field)
        if value is None:
            return
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ExportValidationError(
                f"teas item {tea_id}: {field} must be a positive integer"
            )

    def _validate_biome_contract(self, row: dict[str, Any]) -> None:
        if row.get("type") != "바이옴":
            return
        biome_id = row.get("id", "")
        stable_id = re.compile(self.schema["stable_id_pattern"])
        if row.get("generation_profile_id") != biome_id:
            raise ExportValidationError(
                f"biomes item {biome_id}: generation_profile_id must match biome id"
            )
        for field in (
            "generation_terrain_ids",
            "generation_chunk_rule_ids",
            "generation_resource_item_ids",
            "generation_walkability_rule_ids",
        ):
            self._validate_stable_id_array("biomes", biome_id, field, row.get(field))
        for field in ("generation_facility_ids", "generation_facility_source_ids"):
            value = row.get(field, [])
            if value is None:
                value = []
            if not isinstance(value, list):
                raise ExportValidationError(
                    f"biomes item {biome_id}: {field} must be an array"
                )
            for entry in value:
                if not isinstance(entry, str) or not stable_id.fullmatch(entry):
                    raise ExportValidationError(
                        f"biomes item {biome_id}: {field} must contain stable ids"
                    )
        facility_ids = row.get("generation_facility_ids", [])
        facility_source_ids = row.get("generation_facility_source_ids", [])
        if len(facility_ids) != len(facility_source_ids):
            raise ExportValidationError(
                f"biomes item {biome_id}: generation facility IDs and source IDs must align"
            )
        minimum = row.get("generation_minimum_facility_nodes")
        if not isinstance(minimum, int) or isinstance(minimum, bool) or minimum < 0:
            raise ExportValidationError(
                f"biomes item {biome_id}: generation_minimum_facility_nodes must be a non-negative integer"
            )
        if minimum > len(facility_ids):
            raise ExportValidationError(
                f"biomes item {biome_id}: generation_minimum_facility_nodes exceeds facility IDs"
            )
        mapping = row.get("generation_resource_source_by_id", {})
        if not isinstance(mapping, dict):
            raise ExportValidationError(
                f"biomes item {biome_id}: generation_resource_source_by_id must be an object"
            )
        resource_ids = set(row.get("generation_resource_item_ids", []))
        for resource_id, source_id in mapping.items():
            if resource_id not in resource_ids:
                raise ExportValidationError(
                    f"biomes item {biome_id}: generation_resource_source_by_id references unknown resource {resource_id}"
                )
            if not isinstance(source_id, str) or not stable_id.fullmatch(source_id):
                raise ExportValidationError(
                    f"biomes item {biome_id}: generation_resource_source_by_id must contain stable source ids"
                )

    def _validate_stable_id_array(
        self,
        dataset_name: str,
        item_id: str,
        field: str,
        value: Any,
    ) -> None:
        if not isinstance(value, list) or not value:
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: {field} must be a non-empty array"
            )
        stable_id = re.compile(self.schema["stable_id_pattern"])
        seen: set[str] = set()
        for entry in value:
            if not isinstance(entry, str) or not stable_id.fullmatch(entry):
                raise ExportValidationError(
                    f"{dataset_name} item {item_id}: {field} must contain stable ids"
                )
            if entry in seen:
                raise ExportValidationError(
                    f"{dataset_name} item {item_id}: {field} contains duplicate id {entry}"
                )
            seen.add(entry)

    def _validate_character_contract(self, row: dict[str, Any]) -> None:
        character_id = row.get("character_id")
        if not isinstance(character_id, str) or not re.fullmatch(r"CHR-[1-9][0-9]*", character_id):
            raise ExportValidationError(
                f"characters item {row.get('id', '')}: character_id must match CHR-<number>"
            )
        if not isinstance(row.get("meta_memory"), bool):
            raise ExportValidationError(
                f"characters item {row['id']}: meta_memory must be a boolean"
            )
        target_ids = row.get("final_room_target_ids", [])
        if not isinstance(target_ids, list):
            raise ExportValidationError(
                f"characters item {row['id']}: final_room_target_ids must be an array"
            )
        for target_id in target_ids:
            if not isinstance(target_id, str) or not re.fullmatch(self.schema["stable_id_pattern"], target_id):
                raise ExportValidationError(
                    f"characters item {row['id']}: final_room_target_ids must contain stable ids"
                )


    def _validate_meta_unlock_contract(self, row: dict[str, Any]) -> None:
        unlock_id = row.get("id", "")
        if row.get("condition_event") not in {"event_seen", "cumulative_event_count_at_least", "run_count_at_least", "best_biome_order_at_least", "value_at_least"}:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: invalid condition_event {row.get('condition_event')}")
        if row.get("reward_kind") not in {"unlock_flag", "dialogue_memory_flag", "discovered_record"}:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: invalid reward_kind {row.get('reward_kind')}")
        if not isinstance(row.get("condition_target"), str) or not row["condition_target"]:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: condition_target must be non-empty")
        if not isinstance(row.get("reward_target"), str) or not row["reward_target"]:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: reward_target must be non-empty")
        if row.get("condition_operator") not in {"equals", "at_least"}:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: invalid condition_operator {row.get('condition_operator')}")
        if not isinstance(row.get("cumulative"), bool):
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: cumulative must be a boolean")
        threshold = row.get("threshold", 1)
        if not isinstance(threshold, int) or isinstance(threshold, bool) or threshold <= 0:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: threshold must be a positive integer")
        reward_quantity = row.get("reward_quantity", 1)
        if not isinstance(reward_quantity, int) or isinstance(reward_quantity, bool) or reward_quantity <= 0:
            raise ExportValidationError(f"meta_unlocks item {unlock_id}: reward_quantity must be a positive integer")

    def _validate_shop_contract(self, row: dict[str, Any]) -> None:
        shop_id = row.get("id", "")
        if bool(row.get("item_id")) == bool(row.get("tea_id")):
            raise ExportValidationError(f"shops item {shop_id}: exactly one of item_id or tea_id is required")
        if not isinstance(row.get("can_sell"), bool):
            raise ExportValidationError(f"shops item {shop_id}: can_sell must be a boolean")
        for field in ("buy_price", "sell_price", "stock_quantity", "min_progress_stage"):
            value = row.get(field)
            if not isinstance(value, int) or isinstance(value, bool):
                raise ExportValidationError(f"shops item {shop_id}: {field} must be an integer")
        if row["buy_price"] <= 0 or row["sell_price"] <= 0:
            raise ExportValidationError(f"shops item {shop_id}: prices must be positive")
        if row["stock_quantity"] < 0 or row["min_progress_stage"] < 0:
            raise ExportValidationError(f"shops item {shop_id}: stock and progress must be non-negative")

    def _validate_drop_contract(self, row: dict[str, Any]) -> None:
        drop_id = row.get("id", "")
        item_id = row.get("item_id")
        tea_id = row.get("tea_id")
        if bool(item_id) == bool(tea_id):
            raise ExportValidationError(
                f"drops item {drop_id}: exactly one of item_id or tea_id is required"
            )
        condition = row.get("condition")
        if condition not in self.DROP_CONDITIONS:
            raise ExportValidationError(
                f"drops item {drop_id}: unsupported condition {condition}"
            )
        minimum = row.get("min_quantity")
        maximum = row.get("max_quantity")
        if (
            not isinstance(minimum, int)
            or isinstance(minimum, bool)
            or not isinstance(maximum, int)
            or isinstance(maximum, bool)
            or minimum <= 0
            or maximum < minimum
        ):
            raise ExportValidationError(
                f"drops item {drop_id}: quantity range must be positive ordered integers"
            )
        chance = row.get("chance")
        if (
            not isinstance(chance, (int, float))
            or isinstance(chance, bool)
            or not math.isfinite(float(chance))
            or float(chance) < 0.0
            or float(chance) > 1.0
        ):
            raise ExportValidationError(
                f"drops item {drop_id}: chance must be between zero and one"
            )

    def _validate_choice_contract(self, row: dict[str, Any]) -> None:
        choice_id = row.get("id", "")
        choice_key = row.get("choice_key")
        if not isinstance(choice_key, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", choice_key):
            raise ExportValidationError(f"choices item {choice_id}: invalid choice_key {choice_key}")
        run_flag = row.get("run_flag")
        if not isinstance(run_flag, str) or not re.fullmatch(self.schema["stable_id_pattern"], run_flag):
            raise ExportValidationError(f"choices item {choice_id}: invalid run_flag {run_flag}")
        for field in ("meta_record", "target_survives"):
            if not isinstance(row.get(field), bool):
                raise ExportValidationError(f"choices item {choice_id}: {field} must be a boolean")
        philosophy_marks = row.get("philosophy_marks")
        if not isinstance(philosophy_marks, list) or any(
            not isinstance(mark, str) or not mark.strip() for mark in philosophy_marks
        ):
            raise ExportValidationError(
                f"choices item {choice_id}: philosophy_marks must contain non-empty strings"
            )
        conditions = row.get("conditions", [])
        if not isinstance(conditions, list) or any(not isinstance(condition, dict) for condition in conditions):
            raise ExportValidationError(
                f"choices item {choice_id}: conditions must be an array of objects"
            )

    def _validate_attachment_stage_data(self, row: dict[str, Any]) -> None:
        item_id = row.get("id", "")
        thresholds = row.get("attachment_stage_thresholds")
        description_keys = row.get("attachment_description_keys")
        if not isinstance(thresholds, list) or len(thresholds) < 3:
            raise ExportValidationError(
                f"items item {item_id}: attachment_stage_thresholds must contain at least 3 stages"
            )
        if not isinstance(description_keys, list) or len(description_keys) < len(thresholds):
            raise ExportValidationError(
                f"items item {item_id}: attachment_description_keys must cover every threshold"
            )
        previous = -1
        for threshold in thresholds:
            if not isinstance(threshold, int) or threshold < 0 or threshold <= previous:
                raise ExportValidationError(
                    f"items item {item_id}: attachment_stage_thresholds must be ascending non-negative integers"
                )
            previous = threshold
        for description_key in description_keys:
            if not isinstance(description_key, str) or not description_key:
                raise ExportValidationError(
                    f"items item {item_id}: attachment_description_keys must contain non-empty strings"
                )

    def _validate_boss_contract(self, row: dict[str, Any]) -> None:
        boss_id = row.get("id", "")
        phases = row.get("phases")
        if not isinstance(phases, list):
            raise ExportValidationError(f"bosses item {boss_id}: phases must be an array")
        for phase in phases:
            if not isinstance(phase, dict):
                continue
            patterns = phase.get("patterns", [])
            if not isinstance(patterns, list):
                continue
            for pattern in patterns:
                if not isinstance(pattern, dict):
                    continue
                summon_ids = pattern.get("summon_monster_ids", [])
                if not isinstance(summon_ids, list):
                    raise ExportValidationError(
                        f"bosses item {boss_id} pattern {pattern.get('id', '')}: summon_monster_ids must be an array"
                    )
        config = row.get("tea_resolution", {})
        if config is None:
            return
        if not isinstance(config, dict):
            raise ExportValidationError(f"bosses item {boss_id}: tea_resolution must be an object")
        if not config:
            return
        if "peaceful" not in row.get("resolution_types", []):
            raise ExportValidationError(
                f"bosses item {boss_id}: tea_resolution requires peaceful resolution support"
            )
        stable_id = re.compile(self.schema["stable_id_pattern"])
        choice_id = config.get("choice_id")
        if not isinstance(choice_id, str) or not stable_id.fullmatch(choice_id):
            raise ExportValidationError(f"bosses item {boss_id}: tea_resolution.choice_id must be a stable id")
        tea_ids = config.get("required_tea_ids", [])
        if not isinstance(tea_ids, list) or any(
            not isinstance(tea_id, str) or not stable_id.fullmatch(tea_id)
            for tea_id in tea_ids
        ):
            raise ExportValidationError(
                f"bosses item {boss_id}: tea_resolution.required_tea_ids must contain stable ids"
            )
        conditions = config.get("peaceful_conditions", [])
        if not isinstance(conditions, list):
            raise ExportValidationError(
                f"bosses item {boss_id}: tea_resolution.peaceful_conditions must be an array"
            )
        for condition in conditions:
            if not isinstance(condition, dict):
                raise ExportValidationError(
                    f"bosses item {boss_id}: tea_resolution.peaceful_conditions must contain objects"
                )
            condition_type = condition.get("type")
            if condition_type not in self.BOSS_TEA_CONDITION_TYPES:
                raise ExportValidationError(
                    f"bosses item {boss_id}: tea_resolution unsupported condition type {condition_type}"
                )
            allowed_fields = {"type"} if condition_type == "always" else {"type", "id"}
            unsupported_fields = set(condition) - allowed_fields
            if unsupported_fields:
                raise ExportValidationError(
                    f"bosses item {boss_id}: tea_resolution condition has unsupported field {sorted(unsupported_fields)[0]}"
                )
            if condition_type != "always":
                condition_id = condition.get("id")
                if not isinstance(condition_id, str) or not stable_id.fullmatch(condition_id):
                    raise ExportValidationError(
                        f"bosses item {boss_id}: tea_resolution condition id must be stable"
                    )
        self._validate_boss_tea_hooks(boss_id, config.get("hooks", {}))

    def _validate_dungeon_contract(self, row: dict[str, Any]) -> None:
        boss_id = row.get("boss_id", "")
        if not boss_id:
            return
        stable_id = re.compile(self.schema["stable_id_pattern"])
        if not isinstance(boss_id, str) or not stable_id.fullmatch(boss_id):
            raise ExportValidationError(f"dungeons item {row.get('id', '')}: boss_id must be a stable id")

    def _apply_pre_boss_dialogue_links(self, items_by_dataset: dict[str, list[dict[str, Any]]]) -> None:
        dungeons = items_by_dataset.get("dungeons")
        events = items_by_dataset.get("events")
        if not dungeons or not events:
            return
        event_by_boss = self._pre_boss_event_by_boss(events)
        for dungeon in dungeons:
            boss_id = dungeon.get("boss_id", "")
            if not boss_id:
                continue
            event_id = dungeon.get("pre_boss_dialogue_event_id", "")
            mapped_event_id = event_by_boss.get(boss_id, "")
            if event_id and mapped_event_id and event_id != mapped_event_id:
                raise ExportValidationError(
                    f"dungeons item {dungeon['id']}: pre_boss_dialogue_event_id conflicts with event source lines"
                )
            if not event_id and mapped_event_id:
                dungeon["pre_boss_dialogue_event_id"] = mapped_event_id
            if not dungeon.get("pre_boss_dialogue_event_id", ""):
                raise ExportValidationError(
                    f"dungeons item {dungeon['id']}: pre_boss_dialogue_event_id is required for boss dungeons"
                )

    def _pre_boss_event_by_boss(self, events: list[dict[str, Any]]) -> dict[str, str]:
        event_by_boss: dict[str, str] = {}
        for event in events:
            for line in event.get("source_lines", []):
                if not isinstance(line, dict):
                    continue
                boss_id = line.get("boss_id", "")
                trigger_timing = line.get("trigger_timing", "")
                if not boss_id or trigger_timing not in self.PRE_BOSS_TRIGGER_TIMINGS:
                    continue
                previous_event_id = event_by_boss.get(boss_id)
                if previous_event_id and previous_event_id != event["id"]:
                    raise ExportValidationError(
                        f"events item {event['id']}: duplicate pre-boss dialogue mapping for boss {boss_id}"
                    )
                event_by_boss[boss_id] = event["id"]
        return event_by_boss

    def _validate_pre_boss_dialogue_links(
        self,
        dungeons: list[dict[str, Any]],
        events: list[dict[str, Any]],
    ) -> None:
        event_by_boss = self._pre_boss_event_by_boss(events)
        for dungeon in dungeons:
            boss_id = dungeon.get("boss_id", "")
            if not boss_id:
                continue
            event_id = dungeon.get("pre_boss_dialogue_event_id", "")
            mapped_event_id = event_by_boss.get(boss_id, "")
            if event_id and mapped_event_id and event_id != mapped_event_id:
                raise ExportValidationError(
                    f"dungeons item {dungeon['id']}: pre_boss_dialogue_event_id conflicts with event source lines"
                )
            if not event_id:
                raise ExportValidationError(
                    f"dungeons item {dungeon['id']}: pre_boss_dialogue_event_id is required for boss dungeons"
                )

    def _validate_boss_tea_hooks(self, boss_id: str, hooks: Any) -> None:
        if not isinstance(hooks, dict):
            raise ExportValidationError(f"bosses item {boss_id}: tea_resolution.hooks must be an object")
        hook_key = re.compile(r"[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+")
        for group, channels in hooks.items():
            if group not in self.BOSS_TEA_HOOK_GROUPS:
                raise ExportValidationError(
                    f"bosses item {boss_id}: tea_resolution.hooks unsupported group {group}"
                )
            if not isinstance(channels, dict):
                raise ExportValidationError(
                    f"bosses item {boss_id}: tea_resolution hook group {group} must be an object"
                )
            for channel, keys in channels.items():
                if channel not in self.BOSS_TEA_HOOK_CHANNELS:
                    raise ExportValidationError(
                        f"bosses item {boss_id}: tea_resolution unsupported hook channel {channel}"
                    )
                if not isinstance(keys, list) or any(
                    not isinstance(key, str)
                    or not hook_key.fullmatch(key)
                    or not key.startswith(f"{channel}.")
                    for key in keys
                ):
                    raise ExportValidationError(
                        f"bosses item {boss_id}: tea_resolution {channel} hook keys must be stable channel keys"
                    )

    def _validate_snapshot(self, dataset_name: str, snapshot: dict[str, Any]) -> None:
        if not isinstance(snapshot, dict):
            raise ExportValidationError(f"{dataset_name}: snapshot must be an object")
        for key in self.schema["required_file_keys"]:
            if key not in snapshot:
                raise ExportValidationError(f"{dataset_name}: missing snapshot key {key}")
        if snapshot["schema_version"] != self.schema["schema_version"]:
            raise ExportValidationError(f"{dataset_name}: unsupported schema_version")
        if not isinstance(snapshot["data_version"], str) or not snapshot["data_version"]:
            raise ExportValidationError(f"{dataset_name}: invalid data_version")
        if snapshot["profile"] not in self.schema["profiles"]:
            raise ExportValidationError(f"{dataset_name}: unknown profile {snapshot['profile']}")
        if not isinstance(snapshot["source"], str) or not snapshot["source"]:
            raise ExportValidationError(f"{dataset_name}: invalid source")
        if not isinstance(snapshot["items"], list):
            raise ExportValidationError(f"{dataset_name}: items must be an array")
        if not isinstance(snapshot["content_hash"], str):
            raise ExportValidationError(f"{dataset_name}: content_hash must be a string")
        payload = {key: value for key, value in snapshot.items() if key != "content_hash"}
        expected = hashlib.sha256(canonical_json_bytes(payload)).hexdigest()
        if snapshot["content_hash"] != expected:
            raise ExportValidationError(f"{dataset_name}: content_hash mismatch")
        self._filter_and_validate_rows(
            dataset_name,
            snapshot["items"],
            self._dataset_config(dataset_name),
            snapshot["profile"],
        )

    def _validate_relations(self, snapshots: dict[str, dict[str, Any]]) -> None:
        ids_by_dataset = {
            name: {item["id"] for item in snapshot["items"]}
            for name, snapshot in snapshots.items()
        }
        for dataset_name, snapshot in snapshots.items():
            relations = self._dataset_config(dataset_name).get("relations", {})
            for item in snapshot["items"]:
                for field, target_dataset in relations.items():
                    if field not in item or item[field] in (None, "", []):
                        continue
                    values = item[field] if isinstance(item[field], list) else [item[field]]
                    if target_dataset not in ids_by_dataset:
                        raise ExportValidationError(
                            f"{dataset_name} item {item['id']} relation {field} targets missing dataset {target_dataset}"
                        )
                    for value in values:
                        if value not in ids_by_dataset[target_dataset]:
                            raise ExportValidationError(
                                f"{dataset_name} item {item['id']} relation {field} targets {target_dataset} missing id {value}"
                            )
        if "events" in snapshots:
            self._validate_events(
                snapshots["events"]["items"],
                ids_by_dataset.get("items", set()),
                "items" in ids_by_dataset,
                ids_by_dataset.get("choices", set()),
                "choices" in ids_by_dataset,
            )
        if "dungeons" in snapshots and "events" in snapshots:
            self._validate_pre_boss_dialogue_links(
                snapshots["dungeons"]["items"],
                snapshots["events"]["items"],
            )
        if "bosses" in snapshots:
            self._validate_boss_nested_summons(
                snapshots["bosses"]["items"],
                ids_by_dataset.get("monsters", set()),
                "monsters" in ids_by_dataset,
            )
            self._validate_boss_tea_references(snapshots["bosses"]["items"], ids_by_dataset)

    def _validate_boss_nested_summons(
        self,
        bosses: list[dict[str, Any]],
        monster_ids: set[str],
        monsters_available: bool,
    ) -> None:
        for boss in bosses:
            for phase in boss.get("phases", []):
                if not isinstance(phase, dict):
                    continue
                for pattern in phase.get("patterns", []):
                    if not isinstance(pattern, dict):
                        continue
                    summon_ids = pattern.get("summon_monster_ids", [])
                    if not summon_ids:
                        continue
                    if not monsters_available:
                        raise ExportValidationError(
                            f"bosses item {boss['id']} pattern {pattern.get('id', '')}: summon_monster_ids targets missing dataset monsters"
                        )
                    for monster_id in summon_ids:
                        if monster_id not in monster_ids:
                            raise ExportValidationError(
                                f"bosses item {boss['id']} pattern {pattern.get('id', '')}: summon_monster_ids targets monsters missing id {monster_id}"
                            )

    def _validate_boss_tea_references(
        self,
        bosses: list[dict[str, Any]],
        ids_by_dataset: dict[str, set[str]],
    ) -> None:
        for boss in bosses:
            config = boss.get("tea_resolution", {})
            if not config:
                continue
            choice_id = config["choice_id"]
            if "choices" not in ids_by_dataset:
                raise ExportValidationError(
                    f"bosses item {boss['id']}: tea_resolution.choice_id targets missing dataset choices"
                )
            if choice_id not in ids_by_dataset["choices"]:
                raise ExportValidationError(
                    f"bosses item {boss['id']}: tea_resolution.choice_id targets choices missing id {choice_id}"
                )
            tea_ids = list(config.get("required_tea_ids", []))
            for condition in config.get("peaceful_conditions", []):
                if condition["type"] == "prepared_tea" and condition["id"] not in tea_ids:
                    tea_ids.append(condition["id"])
            if tea_ids and "teas" not in ids_by_dataset:
                raise ExportValidationError(
                    f"bosses item {boss['id']}: tea_resolution.required_tea_ids targets missing dataset teas"
                )
            for tea_id in tea_ids:
                if tea_id not in ids_by_dataset["teas"]:
                    raise ExportValidationError(
                        f"bosses item {boss['id']}: tea_resolution.required_tea_ids targets teas missing id {tea_id}"
                    )

    def _validate_events(
        self,
        events: list[dict[str, Any]],
        item_ids: set[str],
        items_available: bool,
        choice_ids: set[str],
        choices_available: bool,
    ) -> None:
        stable_id = re.compile(self.schema["stable_id_pattern"])
        for event in events:
            replay_policy = event.get("replay_policy")
            if replay_policy not in self.EVENT_REPLAY_POLICIES:
                raise ExportValidationError(
                    f"events item {event['id']}: invalid replay_policy {replay_policy}"
                )
            start_node_id = event.get("start_node_id")
            nodes = event.get("nodes")
            if not isinstance(start_node_id, str) or not start_node_id:
                raise ExportValidationError(f"events item {event['id']}: missing start_node_id")
            if not isinstance(nodes, list):
                raise ExportValidationError(f"events item {event['id']}: nodes must be an array")

            nodes_by_id: dict[str, dict[str, Any]] = {}
            event_option_ids: set[str] = set()
            for node_index, node in enumerate(nodes):
                if not isinstance(node, dict):
                    raise ExportValidationError(f"events item {event['id']}: nodes[{node_index}] must be an object")
                node_id = node.get("id")
                if not isinstance(node_id, str) or not node_id:
                    raise ExportValidationError(f"events item {event['id']}: nodes[{node_index}] missing id")
                if node_id in nodes_by_id:
                    raise ExportValidationError(f"events item {event['id']}: duplicate node id {node_id}")
                options = node.get("options", [])
                if not isinstance(options, list):
                    raise ExportValidationError(f"events item {event['id']} node {node_id}: options must be an array")
                seen_options: set[str] = set()
                for option_index, option in enumerate(options):
                    if not isinstance(option, dict):
                        raise ExportValidationError(
                            f"events item {event['id']} node {node_id}: options[{option_index}] must be an object"
                        )
                    option_id = option.get("id")
                    if not isinstance(option_id, str) or not option_id:
                        raise ExportValidationError(f"events item {event['id']} node {node_id}: option missing id")
                    if option_id in seen_options:
                        raise ExportValidationError(
                            f"events item {event['id']} node {node_id}: duplicate option id {option_id}"
                        )
                    if option_id in event_option_ids:
                        raise ExportValidationError(f"events item {event['id']}: duplicate option id {option_id}")
                    seen_options.add(option_id)
                    event_option_ids.add(option_id)
                    results = option.get("results", [])
                    if not isinstance(results, list):
                        raise ExportValidationError(
                            f"events item {event['id']} node {node_id} option {option_id}: results must be an array"
                        )
                    conditions = option.get("conditions", [])
                    self._validate_event_conditions(
                        event["id"],
                        node_id,
                        option_id,
                        conditions,
                        stable_id,
                    )
                    self._validate_event_results(event["id"], node_id, option_id, results, item_ids, items_available, choice_ids, choices_available, stable_id)
                nodes_by_id[node_id] = node

            if start_node_id not in nodes_by_id:
                raise ExportValidationError(
                    f"events item {event['id']}: start_node_id targets missing node {start_node_id}"
                )
            for node_id, node in nodes_by_id.items():
                for option in node.get("options", []):
                    next_node_id = option.get("next_node_id", "")
                    if next_node_id and next_node_id not in nodes_by_id:
                        raise ExportValidationError(
                            f"events item {event['id']} node {node_id} option {option['id']}: next_node_id targets missing node {next_node_id}"
                        )
            self._validate_event_source_lines(event, nodes_by_id)
            self._validate_event_completion_paths(event["id"], start_node_id, nodes_by_id)

    def _validate_event_source_lines(
        self,
        event: dict[str, Any],
        nodes_by_id: dict[str, dict[str, Any]],
    ) -> None:
        source_lines = event.get("source_lines", [])
        if source_lines in (None, []):
            return
        if not isinstance(source_lines, list):
            raise ExportValidationError(f"events item {event['id']}: source_lines must be an array")
        notion_ids = event.get("notion_ids", [])
        if not isinstance(notion_ids, list):
            raise ExportValidationError(f"events item {event['id']}: notion_ids must be an array")
        line_notion_ids: set[str] = set()
        dialogue_keys: dict[str, str] = {}
        for line_index, line in enumerate(source_lines):
            if not isinstance(line, dict):
                raise ExportValidationError(f"events item {event['id']}: source_lines[{line_index}] must be an object")
            notion_id = line.get("notion_id")
            if not isinstance(notion_id, str) or not notion_id:
                raise ExportValidationError(f"events item {event['id']}: source_lines[{line_index}] missing notion_id")
            if notion_id in line_notion_ids:
                raise ExportValidationError(f"events item {event['id']}: duplicate source line notion_id {notion_id}")
            line_notion_ids.add(notion_id)
            node_id = line.get("node_id")
            if not isinstance(node_id, str) or node_id not in nodes_by_id:
                raise ExportValidationError(f"events item {event['id']}: source line {notion_id} targets missing node")
            node = nodes_by_id[node_id]
            if line.get("text") != node.get("text"):
                raise ExportValidationError(
                    f"events item {event['id']} source line {notion_id}: text does not match node text"
                )
            if line.get("speaker_id") not in (None, "", node.get("speaker_id", "")):
                raise ExportValidationError(
                    f"events item {event['id']} source line {notion_id}: speaker_id does not match node"
                )
            option_id = line.get("option_id")
            option_ids = {
                option.get("id")
                for option in node.get("options", [])
                if isinstance(option, dict)
            }
            if not isinstance(option_id, str) or option_id not in option_ids:
                raise ExportValidationError(
                    f"events item {event['id']} source line {notion_id}: option_id targets missing option"
                )
            dialogue_key = line.get("dialogue_key", "")
            if dialogue_key:
                if not isinstance(dialogue_key, str):
                    raise ExportValidationError(
                        f"events item {event['id']} source line {notion_id}: dialogue_key must be a string"
                    )
                if dialogue_key in dialogue_keys:
                    raise ExportValidationError(
                        f"events item {event['id']}: duplicate dialogue_key {dialogue_key}"
                    )
                dialogue_keys[dialogue_key] = notion_id
            next_dialogue_key = line.get("next_dialogue_key", "")
            if next_dialogue_key not in ("", "END") and next_dialogue_key not in dialogue_keys:
                pending = {
                    pending_line.get("dialogue_key")
                    for pending_line in source_lines[line_index + 1 :]
                    if isinstance(pending_line, dict)
                }
                if next_dialogue_key not in pending:
                    raise ExportValidationError(
                        f"events item {event['id']} source line {notion_id}: next_dialogue_key targets missing line {next_dialogue_key}"
                    )
            for numeric_field in ("story_order", "scene_order", "line_order"):
                value = line.get(numeric_field)
                if value is not None and (not isinstance(value, (int, float)) or isinstance(value, bool)):
                    raise ExportValidationError(
                        f"events item {event['id']} source line {notion_id}: {numeric_field} must be numeric"
                    )
            for json_field in ("presentation_commands",):
                value = line.get(json_field, {})
                if value is not None and not isinstance(value, dict):
                    raise ExportValidationError(
                        f"events item {event['id']} source line {notion_id}: {json_field} must be an object"
                    )
        if set(notion_ids) != line_notion_ids:
            raise ExportValidationError(
                f"events item {event['id']}: source_lines must match notion_ids exactly"
            )

    def _validate_event_conditions(
        self,
        event_id: str,
        node_id: str,
        option_id: str,
        conditions: Any,
        stable_id: re.Pattern[str],
    ) -> None:
        if not isinstance(conditions, list):
            raise ExportValidationError(
                f"events item {event_id} node {node_id} option {option_id}: conditions must be an array"
            )
        for condition_index, condition in enumerate(conditions):
            if not isinstance(condition, dict):
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: conditions[{condition_index}] must be an object"
                )
            condition_type = condition.get("type")
            if condition_type not in self.EVENT_CONDITION_TYPES:
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: unknown condition type {condition_type}"
                )
            if condition_type == "always":
                allowed_fields = {"type"}
            elif condition_type == "meta_run_count_at_least":
                allowed_fields = {"type", "value"}
            else:
                allowed_fields = {"type", "id"}
            unsupported_fields = set(condition) - allowed_fields
            if unsupported_fields:
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: condition has unsupported field {sorted(unsupported_fields)[0]}"
                )
            if condition_type == "meta_run_count_at_least":
                value = condition.get("value")
                if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: meta_run_count_at_least value must be a non-negative integer"
                    )
            elif condition_type != "always":
                condition_id = condition.get("id")
                if not isinstance(condition_id, str) or not stable_id.fullmatch(condition_id):
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: condition id must be stable"
                    )

    def _validate_event_results(
        self,
        event_id: str,
        node_id: str,
        option_id: str,
        results: list[Any],
        item_ids: set[str],
        items_available: bool,
        choice_ids: set[str],
        choices_available: bool,
        stable_id: re.Pattern[str],
    ) -> None:
        choice_result_count = 0
        for result_index, result in enumerate(results):
            if not isinstance(result, dict):
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: results[{result_index}] must be an object"
                )
            result_type = result.get("type")
            if result_type not in self.EVENT_RESULT_TYPES:
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: invalid result type {result_type}"
                )
            result_id = result.get("id")
            if not isinstance(result_id, str) or not stable_id.fullmatch(result_id):
                raise ExportValidationError(
                    f"events item {event_id} node {node_id} option {option_id}: invalid result id {result_id}"
                )
            if result_type == "grant_item":
                if not items_available:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: grant_item targets missing dataset items"
                    )
                quantity = result.get("quantity")
                if not isinstance(quantity, int) or isinstance(quantity, bool) or quantity <= 0:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: grant_item quantity must be a positive integer"
                    )
                if result_id not in item_ids:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: grant_item targets missing item id {result_id}"
                    )
            if result_type == "apply_choice":
                choice_result_count += 1
                if choice_result_count > 1:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: multiple apply_choice results are not allowed"
                    )
                if not choices_available:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: apply_choice targets missing dataset choices"
                    )
                if result_id not in choice_ids:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option_id}: apply_choice targets missing choice id {result_id}"
                    )

    def _validate_event_completion_paths(
        self,
        event_id: str,
        start_node_id: str,
        nodes_by_id: dict[str, dict[str, Any]],
    ) -> None:
        def visit(node_id: str, visiting: set[str]) -> None:
            if node_id in visiting:
                raise ExportValidationError(f"events item {event_id}: reachable dialogue cycle at node {node_id}")
            node = nodes_by_id[node_id]
            options = node.get("options", [])
            if not options:
                raise ExportValidationError(f"events item {event_id} node {node_id}: no completing path")
            next_visiting = {*visiting, node_id}
            for option in options:
                if option.get("completes_event") is True:
                    continue
                next_node_id = option.get("next_node_id", "")
                if not next_node_id:
                    raise ExportValidationError(
                        f"events item {event_id} node {node_id} option {option['id']}: neither completes nor advances"
                    )
                visit(next_node_id, next_visiting)

        visit(start_node_id, set())


def copy_json_value(value: Any) -> Any:
    return json.loads(json.dumps(value, ensure_ascii=False))


def _number_or_end(value: Any) -> float:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else float("inf")


def normalize_structured_fields(dataset_name: str, row: dict[str, Any]) -> dict[str, Any]:
    normalized = copy_json_value(row)
    if dataset_name == "biomes":
        for field in (
            "generation_terrain_ids",
            "generation_chunk_rule_ids",
            "generation_facility_ids",
            "generation_facility_source_ids",
            "generation_resource_item_ids",
            "generation_walkability_rule_ids",
        ):
            if field in normalized:
                normalized[field] = _normalize_comma_list(normalized[field])
        if "generation_resource_source_by_id" in normalized:
            normalized["generation_resource_source_by_id"] = _normalize_mapping(
                normalized["generation_resource_source_by_id"],
                str(normalized.get("id", "")),
                "generation_resource_source_by_id",
            )
        if "generation_minimum_facility_nodes" in normalized and isinstance(
            normalized["generation_minimum_facility_nodes"], float
        ):
            value = normalized["generation_minimum_facility_nodes"]
            if value.is_integer():
                normalized["generation_minimum_facility_nodes"] = int(value)
        return normalized
    if dataset_name == "teas" and "recovery_mode" in normalized:
        normalized["recovery_mode"] = {
            "즉시": "instant",
            "점진": "progressive",
            "조건부": "conditional",
        }.get(normalized["recovery_mode"], normalized["recovery_mode"])
    if dataset_name != "items":
        return normalized

    if normalized.get("equipment_slot") == "없음":
        normalized["equipment_slot"] = ""

    if "attachment_stage_thresholds" in normalized:
        normalized["attachment_stage_thresholds"] = _normalize_attachment_stage_thresholds(
            normalized["attachment_stage_thresholds"],
            str(normalized.get("id", "")),
        )
    if "attachment_description_keys" in normalized:
        normalized["attachment_description_keys"] = _normalize_attachment_description_keys(
            normalized["attachment_description_keys"]
        )
    if "interaction_definition" in normalized:
        normalized["interaction_definition"] = _normalize_json_object_field(
            normalized["interaction_definition"],
            str(normalized.get("id", "")),
            "interaction_definition",
        )
    return normalized


def _normalize_json_object_field(value: Any, item_id: str, field: str) -> Any:
    if isinstance(value, dict):
        return copy_json_value(value)
    if not isinstance(value, str):
        return value
    text = value.strip()
    if not text:
        return value
    if text.startswith("\\{") or text.startswith("\\["):
        text = text.replace("\\{", "{").replace("\\}", "}").replace("\\[", "[").replace("\\]", "]")
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as error:
        raise ExportValidationError(
            f"items item {item_id}: {field} must be valid JSON"
        ) from error
    if not isinstance(parsed, dict):
        raise ExportValidationError(
            f"items item {item_id}: {field} must be a JSON object"
        )
    return parsed


def _normalize_attachment_stage_thresholds(value: Any, item_id: str) -> Any:
    if isinstance(value, str):
        parts = _split_comma_list(value)
    elif isinstance(value, list) and all(isinstance(part, str) for part in value):
        parts = value
    elif isinstance(value, list):
        return value
    else:
        return value

    thresholds: list[int] = []
    for part in parts:
        stripped = part.strip()
        if not stripped:
            continue
        try:
            thresholds.append(int(stripped))
        except ValueError as error:
            raise ExportValidationError(
                f"items item {item_id}: attachment_stage_thresholds must contain integers"
            ) from error
    return thresholds


def _normalize_attachment_description_keys(value: Any) -> Any:
    if isinstance(value, str):
        return _split_comma_list(value)
    if isinstance(value, list) and all(isinstance(part, str) for part in value):
        return [part.strip() for part in value if part.strip()]
    return value


def _normalize_comma_list(value: Any) -> Any:
    if isinstance(value, str):
        return _split_comma_list(value)
    if isinstance(value, list) and all(isinstance(part, str) for part in value):
        return [part.strip() for part in value if part.strip()]
    return value


def _normalize_mapping(value: Any, item_id: str, field: str) -> Any:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str):
        return value
    mapping: dict[str, str] = {}
    for part in _split_semicolon_list(value):
        if "=" not in part:
            raise ExportValidationError(
                f"biomes item {item_id}: {field} entries must use resource_id=source_id"
            )
        key, raw_value = part.split("=", 1)
        key = key.strip()
        raw_value = raw_value.strip()
        if not key or not raw_value:
            raise ExportValidationError(
                f"biomes item {item_id}: {field} entries must be non-empty"
            )
        mapping[key] = raw_value
    return mapping


def _split_comma_list(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]


def _split_semicolon_list(value: str) -> list[str]:
    return [part.strip() for part in value.split(";") if part.strip()]
