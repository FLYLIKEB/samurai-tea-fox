# Notion Export

This folder is reserved for a future exporter.

Rules:

- Notion is an authoring source only.
- The Godot runtime never calls Notion.
- Exported files are written to `data/generated/`.
- Each export must include `data_version`, `source`, and `items`.
- Rows should use stable exported IDs derived from the Notion page ID or an explicit Notion ID field when one is added.
- Relations should export stable IDs, not display names.

Current seed data was generated from the Notion MCP snapshot fetched on 2026-09-01.

