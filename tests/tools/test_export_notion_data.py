import json
from pathlib import Path
import unittest

from tools.notion_export.pipeline import ExportPipeline


ROOT = Path(__file__).resolve().parents[2]
GENERATED = ROOT / "data/generated"
SCHEMA = ROOT / "data/schemas/export_schema.json"


class ExportedNotionDataTests(unittest.TestCase):
    EXPECTED_RUNTIME_ROW_COUNTS = {
        "abilities": 12,
        "balance": 40,
        "biomes": 7,
        "bosses": 3,
        "characters": 9,
        "choices": 13,
        "drops": 34,
        "dungeons": 6,
        "events": 56,
        "items": 39,
        "meta_unlocks": 13,
        "monsters": 21,
        "recipes": 12,
        "shops": 14,
        "teas": 17,
    }

    def test_runtime_snapshots_match_current_notion_source_manifest(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        source_manifest = json.loads(
            (GENERATED / "notion_sources.json").read_text(encoding="utf-8")
        )

        self.assertEqual(source_manifest["data_version"], "notion-2026-09-04")
        self.assertEqual(len(source_manifest["sources"]), 15)
        for dataset_name, source in source_manifest["sources"].items():
            file_name = schema["datasets"][dataset_name]["file"]
            snapshot = json.loads(
                (GENERATED / file_name).read_text(encoding="utf-8")
            )
            self.assertEqual(snapshot["data_version"], source_manifest["data_version"])
            self.assertEqual(snapshot["profile"], "confirmed-test")
            self.assertEqual(snapshot["source"], source)
            self.assertFalse(snapshot["source"].startswith("fixture://"))

        validated = ExportPipeline(schema).validate_directory(GENERATED)
        self.assertEqual(validated["data_version"], source_manifest["data_version"])
        self.assertEqual(len(validated["datasets"]), 15)

    def test_runtime_snapshots_pin_the_complete_live_row_set(self):
        for dataset_name, expected_count in self.EXPECTED_RUNTIME_ROW_COUNTS.items():
            with self.subTest(dataset=dataset_name):
                items = self._items_by_id(f"{dataset_name}.json")
                self.assertEqual(len(items), expected_count)
                self.assertTrue(all(item.get("notion_id") for item in items.values()))

        event_rows = self._items_by_id("events.json").values()
        event_page_ids = [
            notion_id
            for event in event_rows
            for notion_id in event.get("notion_ids", [])
        ]
        self.assertEqual(len(event_page_ids), 75)
        self.assertEqual(len(set(event_page_ids)), 75)

    def test_newly_exported_canonical_rows_are_present(self):
        balance = self._items_by_id("balance.json")
        dungeons = self._items_by_id("dungeons.json")
        items = self._items_by_id("items.json")
        meta_unlocks = self._items_by_id("meta_unlocks.json")
        events = self._items_by_id("events.json")
        recipes = self._items_by_id("recipes.json")

        self.assertEqual(balance["consumable_use_base_seconds"]["value"], 1)
        self.assertEqual(balance["currency_max_stack"]["value"], 999)
        self.assertIn("final_tea_room", dungeons)
        self.assertEqual(dungeons["final_tea_room"]["name"], "마지막 다실")
        self.assertIn("cloth", items)
        self.assertNotIn("item_32", items)
        self.assertEqual(items["bandage"]["use_seconds"], 1)
        self.assertEqual(items["stone_axe"]["max_owned"], 1)
        self.assertEqual(items["mountain_iron_dagger"]["base_damage"], 18)
        self.assertEqual(recipes["stone_axe"]["result_item_id"], "stone_axe")
        self.assertEqual(
            meta_unlocks["meta_10"]["reward_target"],
            "yokai_old_incense_dialogue",
        )
        self.assertEqual(
            meta_unlocks["meta_11"]["reward_target"],
            "unbroken_failure_restoration_record",
        )
        self.assertEqual(
            meta_unlocks["meta_12"]["reward_target"],
            "daimyo_mending_start_choice",
        )
        self.assertIn("story_pro_01", events)
        self.assertIn("story_fin_06", events)

    @staticmethod
    def _items_by_id(file_name):
        snapshot = json.loads((GENERATED / file_name).read_text(encoding="utf-8"))
        return {item["id"]: item for item in snapshot["items"]}


if __name__ == "__main__":
    unittest.main()
