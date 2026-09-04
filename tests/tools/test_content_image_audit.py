import json
from pathlib import Path
import unittest

from tools.asset_pipeline.content_image_audit import build


ROOT = Path(__file__).resolve().parents[2]


class ContentImageAuditTests(unittest.TestCase):
    def test_all_item_and_monster_rows_resolve_to_runtime_assets(self):
        payload, detail = build(ROOT)
        self.assertEqual(detail["issues"], [])
        self.assertEqual(payload["audit"]["items"], 39)
        self.assertEqual(payload["audit"]["monsters"], 21)
        self.assertEqual(payload["audit"]["missing_or_broken"], 0)
        self.assertEqual(payload["audit"]["path_integrity_missing_or_broken"], 0)
        self.assertEqual(payload["audit"]["dedicated_asset_missing"], 11)
        self.assertEqual(payload["audit"]["art_review_required"], 45)
        self.assertEqual(payload["audit"]["runtime_approved"], 48)
        self.assertEqual(payload["audit"]["by_resolution"]["dedicated_item_icon"], 33)
        self.assertIn("semantic_existing_asset", payload["audit"]["by_resolution"])
        self.assertEqual(payload["audit"]["by_resolution"]["kind_fallback_exception"], 5)
        self.assertEqual(payload["audit"]["by_resolution"]["monster_id_convention"], 15)
        self.assertEqual(payload["audit"]["by_resolution"]["monster_variant_fallback_exception"], 6)
        self.assertEqual(payload["audit"]["by_resolution"]["semantic_existing_asset"], 1)

    def test_written_map_is_current(self):
        payload, _detail = build(ROOT)
        expected = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        actual = (ROOT / "assets/content-image-map.json").read_text(encoding="utf-8")
        self.assertEqual(actual, expected)
