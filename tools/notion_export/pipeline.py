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
    EVENT_REPLAY_POLICIES = {"once", "repeat"}
    EVENT_RESULT_TYPES = {"set_run_flag", "grant_item", "apply_choice"}

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

        snapshots: dict[str, dict[str, Any]] = {}
        for dataset_name in sorted(datasets):
            dataset = datasets[dataset_name]
            config = self._dataset_config(dataset_name)
            source = dataset.get("source") if isinstance(dataset, dict) else None
            rows = dataset.get("items") if isinstance(dataset, dict) else None
            if not isinstance(source, str) or not source:
                raise ExportValidationError(f"{dataset_name}: source must be a non-empty string")
            if not isinstance(rows, list):
                raise ExportValidationError(f"{dataset_name}: items must be an array")

            included = self._filter_and_validate_rows(dataset_name, rows, config, profile)
            payload = {
                "schema_version": self.schema["schema_version"],
                "data_version": capture["data_version"],
                "profile": profile,
                "source": source,
                "items": included,
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

        return sorted(included, key=lambda item: item["id"])

    def _validate_row_contract(self, dataset_name: str, row: dict[str, Any]) -> None:
        if dataset_name == "drops":
            self._validate_drop_contract(row)
            return
        if dataset_name == "choices":
            self._validate_choice_contract(row)
            return
        if dataset_name == "shops":
            self._validate_shop_contract(row)
            return
        if dataset_name == "bosses":
            self._validate_boss_contract(row)
            return
        if dataset_name != "items":
            return
        if row.get("type") != "다구" or row.get("equipment_slot") != "다구":
            return
        self._validate_attachment_stage_data(row)

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
        if "bosses" in snapshots:
            self._validate_boss_nested_summons(
                snapshots["bosses"]["items"],
                ids_by_dataset.get("monsters", set()),
                "monsters" in ids_by_dataset,
            )

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
            self._validate_event_completion_paths(event["id"], start_node_id, nodes_by_id)

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


def normalize_structured_fields(dataset_name: str, row: dict[str, Any]) -> dict[str, Any]:
    normalized = copy_json_value(row)
    if dataset_name != "items":
        return normalized

    if "attachment_stage_thresholds" in normalized:
        normalized["attachment_stage_thresholds"] = _normalize_attachment_stage_thresholds(
            normalized["attachment_stage_thresholds"],
            str(normalized.get("id", "")),
        )
    if "attachment_description_keys" in normalized:
        normalized["attachment_description_keys"] = _normalize_attachment_description_keys(
            normalized["attachment_description_keys"]
        )
    return normalized


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


def _split_comma_list(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]
