import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.notion_export.pipeline import (
    ExportPipeline,
    ExportValidationError,
    canonical_json_bytes,
)


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/notion_export/source.json"
SCHEMA = ROOT / "data/schemas/export_schema.json"


class NotionExportPipelineTests(unittest.TestCase):
    def setUp(self):
        self.capture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.pipeline = ExportPipeline.from_path(SCHEMA)

    def test_same_input_produces_the_same_snapshot_and_hash(self):
        first = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        reordered = copy.deepcopy(self.capture)
        reordered["datasets"]["items"]["items"].reverse()
        second = self.pipeline.build_snapshots(reordered, "confirmed-test")

        self.assertEqual(first, second)
        self.assertEqual(first["items"]["items"][0]["id"], "clay")
        self.assertEqual(len(first["items"]["content_hash"]), 64)

    def test_profiles_control_test_rows_and_always_exclude_discarded_rows(self):
        confirmed = self.pipeline.build_snapshots(self.capture, "confirmed")
        confirmed_test = self.pipeline.build_snapshots(self.capture, "confirmed-test")

        self.assertEqual([item["id"] for item in confirmed["items"]["items"]], ["wood"])
        self.assertEqual(
            [item["id"] for item in confirmed_test["items"]["items"]],
            ["clay", "wood"],
        )
        self.assertEqual(confirmed["balance"]["items"], [])
        self.assertEqual(confirmed_test["balance"]["items"][0]["id"], "player_hp_max")

    def test_missing_required_field_fails_with_dataset_and_item_context(self):
        invalid = copy.deepcopy(self.capture)
        del invalid["datasets"]["items"]["items"][0]["name"]

        with self.assertRaisesRegex(ExportValidationError, "items.*wood.*name"):
            self.pipeline.build_snapshots(invalid, "confirmed")

    def test_missing_or_unknown_status_fails_instead_of_silently_dropping_row(self):
        missing = copy.deepcopy(self.capture)
        del missing["datasets"]["balance"]["items"][0]["status"]
        with self.assertRaisesRegex(ExportValidationError, "balance.*status"):
            self.pipeline.build_snapshots(missing, "confirmed-test")

        unknown = copy.deepcopy(self.capture)
        unknown["datasets"]["balance"]["items"][0]["status"] = "확정됨"
        with self.assertRaisesRegex(ExportValidationError, "balance.*unknown status.*확정됨"):
            self.pipeline.build_snapshots(unknown, "confirmed-test")

    def test_confirmed_profile_ignores_incomplete_known_test_rows(self):
        incomplete_test = copy.deepcopy(self.capture)
        del incomplete_test["datasets"]["balance"]["items"][0]["value"]

        snapshots = self.pipeline.build_snapshots(incomplete_test, "confirmed")

        self.assertEqual(snapshots["balance"]["items"], [])

    def test_duplicate_stable_id_fails(self):
        invalid = copy.deepcopy(self.capture)
        invalid["datasets"]["items"]["items"].append(
            {"id": "wood", "name": "중복 목재", "status": "확정"}
        )

        with self.assertRaisesRegex(ExportValidationError, "items.*duplicate.*wood"):
            self.pipeline.build_snapshots(invalid, "confirmed")

    def test_broken_relation_fails_with_target_context(self):
        invalid = copy.deepcopy(self.capture)
        invalid["datasets"]["recipes"]["items"][0]["result_item_id"] = "missing_item"

        with self.assertRaisesRegex(
            ExportValidationError,
            "recipes.*wooden_workbench.*result_item_id.*items.*missing_item",
        ):
            self.pipeline.build_snapshots(invalid, "confirmed")

    def test_write_snapshots_round_trips_through_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            written = self.pipeline.export(self.capture, Path(directory), "confirmed-test")
            self.assertEqual({path.stem for path in written}, set(self.capture["datasets"]))
            validated = self.pipeline.validate_directory(Path(directory))
            self.assertEqual(validated["data_version"], "fixture-2026-09-01")
            self.assertEqual(validated["profile"], "confirmed-test")

    def test_validate_directory_rejects_unsupported_schema_version(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pipeline.export(self.capture, Path(directory), "confirmed")
            path = Path(directory) / "items.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["schema_version"] = 99
            payload = {key: value for key, value in snapshot.items() if key != "content_hash"}
            snapshot["content_hash"] = hashlib.sha256(canonical_json_bytes(payload)).hexdigest()
            path.write_text(json.dumps(snapshot, ensure_ascii=False), encoding="utf-8")

            with self.assertRaisesRegex(ExportValidationError, "items.*schema_version"):
                self.pipeline.validate_directory(Path(directory))

    def test_validate_directory_rejects_unknown_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pipeline.export(self.capture, Path(directory), "confirmed")
            path = Path(directory) / "items.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["profile"] = "invalid-profile"
            payload = {key: value for key, value in snapshot.items() if key != "content_hash"}
            snapshot["content_hash"] = hashlib.sha256(canonical_json_bytes(payload)).hexdigest()
            path.write_text(json.dumps(snapshot, ensure_ascii=False), encoding="utf-8")

            with self.assertRaisesRegex(ExportValidationError, "items.*profile"):
                self.pipeline.validate_directory(Path(directory))


if __name__ == "__main__":
    unittest.main()
