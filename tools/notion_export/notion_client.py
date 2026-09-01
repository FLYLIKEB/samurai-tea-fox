from __future__ import annotations

import json
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote
from urllib.request import Request, urlopen

from .pipeline import ExportValidationError


class NotionClient:
    API_VERSION = "2026-03-11"

    def __init__(self, token: str, base_url: str = "https://api.notion.com"):
        if not token:
            raise ExportValidationError("Notion access token is required")
        self.token = token
        self.base_url = base_url.rstrip("/")

    def query_data_source(self, data_source: str) -> list[dict[str, Any]]:
        data_source_id = data_source.removeprefix("collection://")
        path = f"/v1/data_sources/{quote(data_source_id, safe='')}/query"
        pages: list[dict[str, Any]] = []
        cursor: str | None = None

        while True:
            body: dict[str, Any] = {"page_size": 100}
            if cursor:
                body["start_cursor"] = cursor
            response = self._request("POST", path, body)
            request_status = response.get("request_status", {})
            if isinstance(request_status, dict) and request_status.get("type") == "incomplete":
                raise ExportValidationError(
                    f"Notion query for {data_source} returned an incomplete result set"
                )
            results = response.get("results")
            if not isinstance(results, list):
                raise ExportValidationError(f"Notion query for {data_source} omitted results")
            pages.extend(results)
            if not response.get("has_more"):
                return pages
            cursor = response.get("next_cursor")
            if not isinstance(cursor, str) or not cursor:
                raise ExportValidationError(
                    f"Notion query for {data_source} has_more without next_cursor"
                )

    def flatten_page(self, page: dict[str, Any]) -> dict[str, Any]:
        page_id = page.get("id")
        properties = page.get("properties")
        if not isinstance(page_id, str) or not isinstance(properties, dict):
            raise ExportValidationError("Notion page must include id and properties")

        row: dict[str, Any] = {"_notion_id": page_id}
        for name, prop in properties.items():
            if not isinstance(prop, dict):
                continue
            row[name] = self._normalize_property(page_id, prop)
        return row

    def _normalize_property(self, page_id: str, prop: dict[str, Any]) -> Any:
        property_type = prop.get("type")
        value = prop.get(property_type) if isinstance(property_type, str) else None
        if property_type in ("title", "rich_text"):
            return _plain_text(value)
        if property_type in ("number", "checkbox", "url", "email", "phone_number"):
            return value
        if property_type in ("select", "status"):
            return value.get("name") if isinstance(value, dict) else None
        if property_type == "multi_select":
            return [entry.get("name") for entry in value or [] if entry.get("name")]
        if property_type == "relation":
            relation_ids = [entry.get("id") for entry in value or [] if entry.get("id")]
            if prop.get("has_more"):
                full_values = self._retrieve_property_items(page_id, str(prop.get("id", "")))
                relation_ids.extend(
                    entry["relation"]["id"]
                    for entry in full_values
                    if entry.get("type") == "relation"
                    and isinstance(entry.get("relation"), dict)
                    and entry["relation"].get("id")
                )
            return list(dict.fromkeys(relation_ids))
        if property_type == "unique_id":
            if not isinstance(value, dict):
                return None
            return {"prefix": value.get("prefix"), "number": value.get("number")}
        if property_type == "files":
            return [_normalize_file(entry) for entry in value or []]
        if property_type == "date":
            return value
        if property_type == "formula" and isinstance(value, dict):
            formula_type = value.get("type")
            return value.get(formula_type)
        return value

    def _retrieve_property_items(self, page_id: str, property_id: str) -> list[dict[str, Any]]:
        encoded_property_id = quote(unquote(property_id), safe="")
        path = f"/v1/pages/{quote(page_id, safe='')}/properties/{encoded_property_id}"
        items: list[dict[str, Any]] = []
        cursor: str | None = None
        while True:
            request_path = path
            query = ["page_size=100"]
            if cursor:
                query.append(f"start_cursor={quote(cursor, safe='')}")
            request_path += "?" + "&".join(query)
            response = self._request("GET", request_path)
            if response.get("object") != "list":
                return [response]
            items.extend(response.get("results", []))
            if not response.get("has_more"):
                return items
            cursor = response.get("next_cursor")
            if not isinstance(cursor, str) or not cursor:
                raise ExportValidationError(
                    f"Notion property {property_id} has_more without next_cursor"
                )

    def _request(self, method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = Request(
            self.base_url + path,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Notion-Version": self.API_VERSION,
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            details = error.read().decode("utf-8", errors="replace")
            raise ExportValidationError(
                f"Notion API {method} {path} failed with HTTP {error.code}: {details}"
            ) from error
        except (URLError, TimeoutError, json.JSONDecodeError) as error:
            raise ExportValidationError(f"Notion API {method} {path} failed: {error}") from error


def _plain_text(value: Any) -> str:
    if not isinstance(value, list):
        return ""
    return "".join(str(entry.get("plain_text", "")) for entry in value if isinstance(entry, dict))


def _normalize_file(entry: dict[str, Any]) -> dict[str, Any]:
    file_type = entry.get("type")
    file_value = entry.get(file_type, {}) if isinstance(file_type, str) else {}
    return {"name": entry.get("name", ""), "url": file_value.get("url", "")}
