import json
from pathlib import Path
import unittest

from tools.asset_pipeline.content_image_audit import build


ROOT = Path(__file__).resolve().parents[2]


class ContentImageAuditTests(unittest.TestCase):
    def test_all_item_and_monster_rows_resolve_to_runtime_assets(self):
        payload, detail = build(ROOT)
        self.assertEqual(detail["issues"], [])
        self.assertEqual(payload["audit"]["items"], 40)
        self.assertEqual(payload["audit"]["monsters"], 15)
        self.assertEqual(payload["audit"]["missing_or_broken"], 0)
        self.assertIn("semantic_existing_asset", payload["audit"]["by_resolution"])
        self.assertEqual(payload["audit"]["by_resolution"]["monster_id_convention"], 15)

    def test_written_map_is_current(self):
        payload, _detail = build(ROOT)
        expected = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        actual = (ROOT / "assets/content-image-map.json").read_text(encoding="utf-8")
        self.assertEqual(actual, expected)
