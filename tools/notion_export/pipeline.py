from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
from typing import Any


class ExportValidationError(ValueError):
    pass


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


class ExportPipeline:
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
            item_id = row["id"]
            if not isinstance(item_id, str) or not id_pattern.fullmatch(item_id):
                raise ExportValidationError(f"{dataset_name} item {item_id}: invalid stable id")
            if item_id in seen_ids:
                raise ExportValidationError(f"{dataset_name}: duplicate stable id {item_id}")
            seen_ids.add(item_id)
            included.append(copy_json_value(row))

        return sorted(included, key=lambda item: item["id"])

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


def copy_json_value(value: Any) -> Any:
    return json.loads(json.dumps(value, ensure_ascii=False))
