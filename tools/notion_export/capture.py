from __future__ import annotations

import re
from typing import Any

from tools.notion_export.pipeline import ExportValidationError, copy_json_value


class CaptureBuilder:
    def __init__(
        self,
        schema: dict[str, Any],
        stable_id_overrides: dict[str, Any] | None = None,
    ):
        self.schema = schema
        raw_overrides = stable_id_overrides or {}
        if "notion_pages" in raw_overrides or "legacy_names" in raw_overrides:
            self.page_overrides = raw_overrides.get("notion_pages", {})
            self.legacy_name_overrides = raw_overrides.get("legacy_names", {})
        else:
            self.page_overrides = raw_overrides
            self.legacy_name_overrides = {}
        self.id_pattern = re.compile(schema["stable_id_pattern"])

    def build_from_rows(
        self,
        rows_by_dataset: dict[str, list[dict[str, Any]]],
        data_version: str,
    ) -> dict[str, Any]:
        if not isinstance(data_version, str) or not data_version:
            raise ExportValidationError("capture data_version must be a non-empty string")

        runtime_ids = self._build_runtime_id_index(rows_by_dataset)
        self.resolved_runtime_ids = runtime_ids
        datasets: dict[str, dict[str, Any]] = {}
        for dataset_name, rows in rows_by_dataset.items():
            config = self._dataset_config(dataset_name)
            notion = config["notion"]
            datasets[dataset_name] = {
                "source": notion["source"],
                "items": [
                    self._build_item(dataset_name, row, runtime_ids)
                    for row in rows
                ],
            }

        return {
            "schema_version": self.schema["schema_version"],
            "data_version": data_version,
            "datasets": datasets,
        }

    def _build_runtime_id_index(
        self,
        rows_by_dataset: dict[str, list[dict[str, Any]]],
    ) -> dict[str, dict[str, str]]:
        result: dict[str, dict[str, str]] = {}
        for dataset_name, rows in rows_by_dataset.items():
            notion = self._dataset_config(dataset_name)["notion"]
            ids: dict[str, str] = {}
            seen_runtime_ids: set[str] = set()
            for index, row in enumerate(rows):
                page_id = row.get("_notion_id")
                if not isinstance(page_id, str) or not page_id:
                    raise ExportValidationError(
                        f"{dataset_name}[{index}]: missing _notion_id"
                    )
                runtime_id = self._runtime_id(dataset_name, row, notion)
                if runtime_id in seen_runtime_ids:
                    raise ExportValidationError(
                        f"{dataset_name}: duplicate stable id {runtime_id}"
                    )
                ids[page_id] = runtime_id
                seen_runtime_ids.add(runtime_id)
            result[dataset_name] = ids
        return result

    def _runtime_id(
        self,
        dataset_name: str,
        row: dict[str, Any],
        notion: dict[str, Any],
    ) -> str:
        page_id = row["_notion_id"]
        runtime_id = self.page_overrides.get(page_id)
        if runtime_id is None:
            title = row.get(notion["title_field"])
            runtime_id = self.legacy_name_overrides.get(dataset_name, {}).get(title)
        stable_id_field = notion.get("stable_id_field")
        if runtime_id is None and stable_id_field:
            candidate = row.get(stable_id_field)
            if isinstance(candidate, str) and candidate:
                runtime_id = candidate
        if runtime_id is None:
            unique_id = row.get(notion["unique_id_field"])
            number = unique_id.get("number") if isinstance(unique_id, dict) else None
            if not isinstance(number, int):
                raise ExportValidationError(
                    f"{dataset_name} page {page_id}: missing Notion unique id"
                )
            runtime_id = f"{notion['id_prefix']}_{number}"
        if not self.id_pattern.fullmatch(runtime_id):
            raise ExportValidationError(
                f"{dataset_name} page {page_id}: invalid stable id {runtime_id}"
            )
        return runtime_id

    def _build_item(
        self,
        dataset_name: str,
        row: dict[str, Any],
        runtime_ids: dict[str, dict[str, str]],
    ) -> dict[str, Any]:
        config = self._dataset_config(dataset_name)
        notion = config["notion"]
        page_id = row["_notion_id"]
        item: dict[str, Any] = {
            "id": runtime_ids[dataset_name][page_id],
            "notion_id": page_id,
            "name": row.get(notion["title_field"]),
            "status": row.get(notion["status_field"]),
        }
        for source_field, output_field in notion.get("field_map", {}).items():
            value = row.get(source_field)
            if value not in (None, "", []):
                item[output_field] = copy_json_value(value)

        for source_field, relation in notion.get("relation_map", {}).items():
            page_ids = row.get(source_field) or []
            if not isinstance(page_ids, list):
                raise ExportValidationError(
                    f"{dataset_name} item {item['id']} relation {relation['field']} must be an array"
                )
            resolved: list[str] = []
            target_ids = runtime_ids.get(relation["target"], {})
            for target_page_id in page_ids:
                if target_page_id not in target_ids:
                    raise ExportValidationError(
                        f"{dataset_name} item {item['id']} relation {relation['field']} "
                        f"targets missing Notion page {target_page_id}"
                    )
                resolved.append(target_ids[target_page_id])
            if relation.get("many", True):
                if resolved:
                    item[relation["field"]] = sorted(resolved)
            elif len(resolved) > 1:
                raise ExportValidationError(
                    f"{dataset_name} item {item['id']} relation {relation['field']} has multiple targets"
                )
            elif resolved:
                item[relation["field"]] = resolved[0]
        return item

    def _dataset_config(self, dataset_name: str) -> dict[str, Any]:
        try:
            config = self.schema["datasets"][dataset_name]
            if "notion" not in config:
                raise KeyError("notion")
            return config
        except KeyError as error:
            raise ExportValidationError(
                f"{dataset_name}: missing Notion capture configuration"
            ) from error
