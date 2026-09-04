from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from .capture import CaptureBuilder
from .notion_client import NotionClient
from .pipeline import ExportPipeline, ExportValidationError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build deterministic game snapshots from a Notion capture.")
    parser.add_argument("--schema", type=Path, default=Path("data/schemas/export_schema.json"))
    subparsers = parser.add_subparsers(dest="command", required=True)
    export_parser = subparsers.add_parser("export", help="Validate and export a capture")
    export_parser.add_argument("--input", type=Path, required=True)
    export_parser.add_argument("--output", type=Path, required=True)
    export_parser.add_argument("--profile", default="confirmed")
    validate_parser = subparsers.add_parser("validate", help="Validate an export directory")
    validate_parser.add_argument("--directory", type=Path, required=True)
    sync_parser = subparsers.add_parser("sync", help="Query Notion and export runtime snapshots")
    sync_parser.add_argument("--output", type=Path, required=True)
    sync_parser.add_argument("--data-version", required=True)
    sync_parser.add_argument("--profile", default="confirmed")
    sync_parser.add_argument(
        "--id-map", type=Path, default=Path("data/schemas/runtime_id_map.json")
    )
    sync_parser.add_argument("--token-env", default="NOTION_ACCESS_TOKEN")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        schema = json.loads(args.schema.read_text(encoding="utf-8"))
        pipeline = ExportPipeline(schema)
        if args.command == "export":
            capture = json.loads(args.input.read_text(encoding="utf-8"))
            written = pipeline.export(capture, args.output, args.profile)
            print(f"Exported {len(written)} deterministic snapshots to {args.output}")
        elif args.command == "validate":
            result = pipeline.validate_directory(args.directory)
            print(
                f"Validated snapshots: version={result['data_version']} "
                f"profile={result['profile']} datasets={len(result['datasets'])}"
            )
        else:
            token = os.environ.get(args.token_env, "")
            client = NotionClient(token)
            id_map = json.loads(args.id_map.read_text(encoding="utf-8"))
            runtime_datasets = {
                name: config
                for name, config in schema["datasets"].items()
                if config.get("runtime", True)
            }
            rows_by_dataset = {
                name: [client.flatten_page(page) for page in client.query_data_source(config["notion"]["source"])]
                for name, config in runtime_datasets.items()
            }
            builder = CaptureBuilder(schema, id_map)
            capture = builder.build_from_rows(rows_by_dataset, args.data_version)
            written = pipeline.export(capture, args.output, args.profile)
            promoted = dict(id_map.get("notion_pages", {}))
            for ids in builder.resolved_runtime_ids.values():
                promoted.update(ids)
            id_map["notion_pages"] = dict(sorted(promoted.items()))
            args.id_map.write_text(
                json.dumps(id_map, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
                encoding="utf-8",
            )
            print(
                f"Synced {len(written)} deterministic snapshots from Notion to {args.output}"
            )
    except (OSError, json.JSONDecodeError, ExportValidationError) as error:
        print(f"Notion export failed: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
