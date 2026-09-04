from __future__ import annotations

import json
import re
from typing import Any

from tools.notion_export.pipeline import (
    ExportValidationError,
    copy_json_value,
    normalize_structured_fields,
)


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

        prepared_rows = {
            dataset_name: self._prepare_rows(dataset_name, rows)
            for dataset_name, rows in rows_by_dataset.items()
        }
        runtime_ids = self._build_runtime_id_index(prepared_rows)
        self.resolved_runtime_ids = runtime_ids
        datasets: dict[str, dict[str, Any]] = {}
        for dataset_name, rows in prepared_rows.items():
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

    def _prepare_rows(
        self,
        dataset_name: str,
        rows: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        mode = self._dataset_config(dataset_name)["notion"].get("capture_mode")
        if mode in (None, "json_object"):
            return rows
        if mode == "event_lines":
            return self._group_event_lines(dataset_name, rows)
        raise ExportValidationError(f"{dataset_name}: unsupported capture mode {mode}")

    def _group_event_lines(
        self,
        dataset_name: str,
        rows: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        groups: dict[str, list[dict[str, Any]]] = {}
        notion = self._dataset_config(dataset_name)["notion"]
        ignored_statuses = set(notion.get("ignored_statuses", []))
        for row in rows:
            if row.get(notion["status_field"]) in ignored_statuses:
                continue
            event_id = row.get("런타임 이벤트 ID")
            if event_id in (None, ""):
                raise ExportValidationError(
                    f"{dataset_name} page {row.get('_notion_id', '')}: missing runtime event id"
                )
            if not isinstance(event_id, str) or not self.id_pattern.fullmatch(event_id):
                raise ExportValidationError(
                    f"{dataset_name} page {row.get('_notion_id', '')}: invalid runtime event id {event_id}"
                )
            groups.setdefault(event_id, []).append(row)

        return [
            self._build_event_row(dataset_name, event_id, groups[event_id])
            for event_id in sorted(groups)
        ]

    def _build_event_row(
        self,
        dataset_name: str,
        event_id: str,
        rows: list[dict[str, Any]],
    ) -> dict[str, Any]:
        ordered_rows = sorted(
            rows,
            key=lambda row: (
                self._number_or_zero(row.get("라인 순서")),
                str(row.get("노드 ID", "")),
                str(row.get("선택 ID", "")),
                str(row.get("_notion_id", "")),
            ),
        )
        event_name = self._consistent_value(dataset_name, event_id, rows, "이벤트 이름")
        status = self._consistent_value(dataset_name, event_id, rows, "상태")
        replay_policy = self._consistent_value(dataset_name, event_id, rows, "재실행 정책")
        start_rows = [row for row in rows if self._checkbox_value(row.get("시작 노드"))]
        if len(start_rows) != 1:
            raise ExportValidationError(
                f"{dataset_name} item {event_id}: expected exactly one start row"
            )
        start_node_id = start_rows[0].get("노드 ID")
        if not isinstance(start_node_id, str) or not start_node_id:
            raise ExportValidationError(
                f"{dataset_name} item {event_id}: start row is missing 노드 ID"
            )

        nodes_by_id: dict[str, dict[str, Any]] = {}
        node_order: dict[str, tuple[float, str]] = {}
        for row in ordered_rows:
            node_id = row.get("노드 ID")
            option_id = row.get("선택 ID")
            if not isinstance(node_id, str) or not node_id:
                raise ExportValidationError(f"{dataset_name} item {event_id}: missing 노드 ID")
            if not isinstance(option_id, str) or not option_id:
                raise ExportValidationError(f"{dataset_name} item {event_id}: missing 선택 ID")
            text = row.get("본문 KO")
            speaker_id = row.get("화자 ID")
            node = nodes_by_id.setdefault(
                node_id,
                {"id": node_id, "text": text, "options": []},
            )
            if node.get("text") != text:
                raise ExportValidationError(
                    f"{dataset_name} item {event_id}: inconsistent 본문 KO for node {node_id}"
                )
            if isinstance(speaker_id, str) and speaker_id:
                existing_speaker = node.get("speaker_id")
                if existing_speaker not in (None, speaker_id):
                    raise ExportValidationError(
                        f"{dataset_name} item {event_id}: inconsistent 화자 ID for node {node_id}"
                    )
                node["speaker_id"] = speaker_id
            node["options"].append({
                "id": option_id,
                "display_text": row.get("선택 문구"),
                "conditions": self._parse_json_field(
                    dataset_name, event_id, "조건 JSON", row.get("조건 JSON"), list
                ),
                "results": self._parse_json_field(
                    dataset_name, event_id, "결과 JSON", row.get("결과 JSON"), list
                ),
                "next_node_id": row.get("다음 노드 ID") or "",
                "completes_event": self._checkbox_value(row.get("이벤트 완료")),
            })
            node_order.setdefault(
                node_id,
                (self._number_or_zero(row.get("라인 순서")), node_id),
            )

        for node in nodes_by_id.values():
            node["options"].sort(key=lambda option: option["id"])
        nodes = [nodes_by_id[node_id] for node_id in sorted(nodes_by_id, key=node_order.get)]
        metadata_field = self._dataset_config(dataset_name)["notion"].get("event_metadata_field")
        metadata: dict[str, Any] = {}
        if metadata_field:
            values = [row.get(metadata_field) for row in rows if row.get(metadata_field) not in (None, "")]
            if values:
                metadata = self._parse_json_field(
                    dataset_name, event_id, metadata_field, values[0], dict
                )
                if any(value != values[0] for value in values[1:]):
                    raise ExportValidationError(
                        f"{dataset_name} item {event_id}: inconsistent {metadata_field}"
                    )
        protected = {"id", "name", "status", "replay_policy", "start_node_id", "nodes", "notion_id", "notion_ids"}
        overlap = protected.intersection(metadata)
        if overlap:
            raise ExportValidationError(
                f"{dataset_name} item {event_id}: metadata cannot override {sorted(overlap)[0]}"
            )
        return {
            "_notion_id": start_rows[0]["_notion_id"],
            "_notion_ids": sorted(str(row["_notion_id"]) for row in rows),
            "_capture_extra": metadata,
            "런타임 이벤트 ID": event_id,
            "이벤트 이름": event_name,
            "상태": status,
            "재실행 정책": replay_policy,
            "시작 노드 ID": start_node_id,
            "노드": nodes,
        }

    @staticmethod
    def _number_or_zero(value: Any) -> float:
        return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0.0

    @staticmethod
    def _checkbox_value(value: Any) -> bool:
        if value == "__YES__":
            return True
        if value in ("__NO__", None, ""):
            return False
        if isinstance(value, bool):
            return value
        raise ExportValidationError(f"invalid checkbox value {value}")

    @staticmethod
    def _consistent_value(
        dataset_name: str,
        item_id: str,
        rows: list[dict[str, Any]],
        field: str,
    ) -> Any:
        values = {json.dumps(row.get(field), ensure_ascii=False, sort_keys=True) for row in rows}
        if len(values) != 1:
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: inconsistent {field}"
            )
        return rows[0].get(field)

    @staticmethod
    def _parse_json_field(
        dataset_name: str,
        item_id: str,
        field: str,
        value: Any,
        expected_type: type,
    ) -> Any:
        if isinstance(value, expected_type):
            return copy_json_value(value)
        if not isinstance(value, str):
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: invalid {field}"
            )
        text = value.strip()
        if text.startswith("```") and text.endswith("```"):
            first_newline = text.find("\n")
            text = (
                text[first_newline + 1 : -3].strip()
                if first_newline >= 0
                else text[3:-3].strip()
            )
        if len(text) >= 2 and text[0] == "`" and text[-1] == "`":
            text = text[1:-1]
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as error:
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: invalid {field}"
            ) from error
        if not isinstance(parsed, expected_type):
            raise ExportValidationError(
                f"{dataset_name} item {item_id}: invalid {field}"
            )
        return parsed

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
                runtime_id = candidate.strip().lower()
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
        if notion.get("capture_mode") == "json_object":
            item = self._parse_json_field(
                dataset_name,
                runtime_ids[dataset_name][page_id],
                notion["json_field"],
                row.get(notion["json_field"]),
                dict,
            )
            expected = {
                "id": runtime_ids[dataset_name][page_id],
                "name": row.get(notion["title_field"]),
                "status": row.get(notion["status_field"]),
            }
            for field, value in expected.items():
                if item.get(field) != value:
                    raise ExportValidationError(
                        f"{dataset_name} item {expected['id']}: {notion['json_field']} {field} does not match row"
                    )
            item["notion_id"] = page_id
            return normalize_structured_fields(dataset_name, item)
        item: dict[str, Any] = {
            "id": runtime_ids[dataset_name][page_id],
            "notion_id": page_id,
            "name": row.get(notion["title_field"]),
            "status": row.get(notion["status_field"]),
        }
        unique_id_output_field = notion.get("unique_id_output_field")
        if unique_id_output_field:
            unique_id = row.get(notion["unique_id_field"])
            prefix = unique_id.get("prefix") if isinstance(unique_id, dict) else None
            number = unique_id.get("number") if isinstance(unique_id, dict) else None
            if not isinstance(prefix, str) or not prefix or not isinstance(number, int):
                raise ExportValidationError(
                    f"{dataset_name} item {item['id']}: invalid Notion unique id"
                )
            item[unique_id_output_field] = f"{prefix}-{number}"
        for source_field, output_field in notion.get("field_map", {}).items():
            value = row.get(source_field)
            if value not in (None, "", []):
                item[output_field] = copy_json_value(value)

        if dataset_name == "abilities":
            item.setdefault("status_effect", "")
        elif dataset_name == "characters":
            item.setdefault("final_room_target_ids", [])
        elif dataset_name == "recipes":
            item.setdefault("result_quantity", 1)

        extra = row.get("_capture_extra", {})
        if isinstance(extra, dict):
            item.update(copy_json_value(extra))
        notion_ids = row.get("_notion_ids")
        if isinstance(notion_ids, list):
            item["notion_ids"] = copy_json_value(notion_ids)

        for source_field, relation in notion.get("relation_map", {}).items():
            page_ids = row.get(source_field) or []
            if not isinstance(page_ids, list):
                raise ExportValidationError(
                    f"{dataset_name} item {item['id']} relation {relation['field']} must be an array"
                )
            resolved: list[str] = []
            target_ids = runtime_ids.get(relation["target"], {})
            for target_page_id in page_ids:
                target_id = target_ids.get(target_page_id, self.page_overrides.get(target_page_id))
                if target_id is None:
                    raise ExportValidationError(
                        f"{dataset_name} item {item['id']} relation {relation['field']} "
                        f"targets missing Notion page {target_page_id}"
                    )
                resolved.append(target_id)
            if relation.get("many", True):
                if resolved:
                    item[relation["field"]] = sorted(resolved)
            elif len(resolved) > 1:
                raise ExportValidationError(
                    f"{dataset_name} item {item['id']} relation {relation['field']} has multiple targets"
                )
            elif resolved:
                item[relation["field"]] = resolved[0]
        return normalize_structured_fields(dataset_name, item)

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
