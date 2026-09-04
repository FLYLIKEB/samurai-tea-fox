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
        self.assertEqual(payload["audit"]["dedicated_asset_missing"], 0)
        self.assertEqual(payload["audit"]["art_review_required"], 39)
        self.assertEqual(payload["audit"]["runtime_approved"], 60)
        self.assertEqual(payload["audit"]["by_resolution"]["dedicated_item_icon"], 39)
        self.assertNotIn("semantic_existing_asset", payload["audit"]["by_resolution"])
        self.assertNotIn("kind_fallback_exception", payload["audit"]["by_resolution"])
        self.assertEqual(payload["audit"]["by_resolution"]["monster_id_convention"], 21)
        self.assertNotIn("monster_variant_fallback_exception", payload["audit"]["by_resolution"])
        items = {entry["content_id"]: entry for entry in payload["content"]["items"]}
        self.assertEqual(items["stone_axe"]["asset_id"], "item_stone_axe_icon")
        self.assertEqual(items["stone_axe"]["path"], "res://assets/sprites/items/stone_axe_32x32.png")
        self.assertTrue(items["stone_axe"]["runtime_approved"])
        self.assertEqual(
            items["blacksmith_forge"]["asset_id"],
            "item_blacksmith_forge_object_64",
        )
        self.assertEqual(
            items["metal_workbench"]["asset_id"],
            "item_metal_workbench_object_64",
        )
        self.assertEqual(
            items["traveler_quilted_clothes"]["asset_id"],
            "item_traveler_quilted_clothes_icon",
        )
        self.assertEqual(
            items["mountain_wind_layered_clothes"]["asset_id"],
            "item_mountain_wind_layered_clothes_icon",
        )
        self.assertEqual(
            items["snow_bamboo_overcoat"]["asset_id"],
            "item_snow_bamboo_overcoat_icon",
        )
        monsters = {entry["content_id"]: entry for entry in payload["content"]["monsters"]}
        self.assertEqual(monsters["monster_16"]["asset_id"], "monster_monster_16_front_idle")
        self.assertEqual(monsters["monster_17"]["asset_id"], "monster_monster_17_front_idle")
        self.assertEqual(monsters["monster_18"]["asset_id"], "monster_monster_18_front_idle")
        self.assertEqual(monsters["monster_19"]["asset_id"], "monster_monster_19_front_idle")
        self.assertEqual(monsters["monster_20"]["asset_id"], "monster_monster_20_front_idle")
        self.assertEqual(monsters["monster_21"]["asset_id"], "monster_monster_21_front_idle")

    def test_written_map_is_current(self):
        payload, _detail = build(ROOT)
        expected = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        actual = (ROOT / "assets/content-image-map.json").read_text(encoding="utf-8")
        self.assertEqual(actual, expected)
