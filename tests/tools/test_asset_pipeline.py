import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.asset_pipeline.validator import AssetManifestValidator, AssetValidationError


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests/fixtures/assets"


class AssetPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "assets/style").mkdir(parents=True)
        (self.root / "assets/sprites").mkdir(parents=True)
        (self.root / "data/schemas").mkdir(parents=True)
        (self.root / "scenes").mkdir()
        (self.root / "src").mkdir()
        shutil.copy(ROOT / "assets/style/art-style-tokens.json", self.root / "assets/style/art-style-tokens.json")
        shutil.copy(ROOT / "data/schemas/export_schema.json", self.root / "data/schemas/export_schema.json")
        shutil.copy(FIXTURES / "valid_rgba_32x32.png", self.root / "assets/sprites/valid.png")
        (self.root / "project.godot").write_text(
            "[rendering]\ntextures/canvas_textures/default_texture_filter=0\n", encoding="utf-8"
        )
        self.manifest = {
            "schema_version": 1,
            "art_assets_contract": {"schema": "res://data/schemas/export_schema.json", "dataset": "art_assets"},
            "style_tokens": "res://assets/style/art-style-tokens.json",
            "promoted_assets": "res://assets/promoted-assets-manifest.json",
            "runtime_roots": ["res://assets/sprites/"],
            "resource_scan_roots": ["res://scenes/", "res://src/"],
            "import_policy": {
                "texture_filter": "nearest",
                "godot_project_setting": "textures/canvas_textures/default_texture_filter",
                "godot_nearest_value": 0,
            },
            "placeholder_policy": {
                "allow_runtime_placeholders": False,
                "forbidden_path_segments": ["placeholder", "temp"],
            },
            "assets": [self.asset()],
        }
        self.write_manifest()

    def tearDown(self):
        self.temporary.cleanup()

    def asset(self):
        return {
            "id": "valid_sprite",
            "name": "정상 스프라이트",
            "status": "완료",
            "kind": "character_sprite",
            "path": "res://assets/sprites/valid.png",
            "width": 32,
            "height": 32,
            "direction_count": 1,
            "frame_count": 1,
            "frame_grid": {"columns": 1, "rows": 1, "frame_width": 32, "frame_height": 32},
            "alpha_required": True,
            "texture_filter": "nearest",
            "placeholder": False,
        }

    def write_manifest(self):
        (self.root / "assets/asset-manifest.json").write_text(
            json.dumps(self.manifest, ensure_ascii=False), encoding="utf-8"
        )
        promoted = {
            "assets": [
                {
                    "path": asset["path"].removeprefix("res://"),
                    "width": asset["width"],
                    "height": asset["height"],
                    "mode": "RGBA",
                }
                for asset in self.manifest["assets"]
            ]
        }
        (self.root / "assets/promoted-assets-manifest.json").write_text(
            json.dumps(promoted), encoding="utf-8"
        )

    def validate(self):
        return AssetManifestValidator(self.root).validate()

    def assert_invalid(self, pattern):
        self.write_manifest()
        with self.assertRaisesRegex(AssetValidationError, pattern):
            self.validate()

    def test_valid_png_manifest_and_scene_reference_pass(self):
        (self.root / "scenes/valid.tscn").write_text(
            '[gd_scene format=3]\n[ext_resource type="Texture2D" path="res://assets/sprites/valid.png" id="1"]\n',
            encoding="utf-8",
        )
        self.write_manifest()
        result = self.validate()
        self.assertEqual(result, {"asset_count": 1, "resource_count": 1})

    def test_wrong_png_size_fails(self):
        shutil.copy(FIXTURES / "wrong_size_rgba_16x32.png", self.root / "assets/sprites/valid.png")
        self.assert_invalid("PNG size is 16x32, expected 32x32")

    def test_broken_frame_grid_fails(self):
        shutil.copy(FIXTURES / "invalid_grid_rgba_48x32.png", self.root / "assets/sprites/valid.png")
        self.manifest["assets"][0].update({"width": 48, "frame_count": 2})
        self.manifest["assets"][0]["frame_grid"] = {
            "columns": 2, "rows": 1, "frame_width": 32, "frame_height": 32
        }
        self.assert_invalid("frame grid width does not match")

    def test_png_without_alpha_fails(self):
        shutil.copy(FIXTURES / "opaque_rgb_32x32.png", self.root / "assets/sprites/valid.png")
        self.assert_invalid("must provide an alpha channel")

    def test_missing_path_and_broken_scene_reference_fail(self):
        self.manifest["assets"][0]["path"] = "res://assets/sprites/missing.png"
        (self.root / "scenes/broken.tscn").write_text(
            '[gd_scene format=3]\n[ext_resource type="Texture2D" path="res://assets/sprites/also_missing.png" id="1"]\n',
            encoding="utf-8",
        )
        self.assert_invalid("(?s)file is missing.*broken resource reference")

    def test_non_nearest_asset_or_project_filter_fails(self):
        self.manifest["assets"][0]["texture_filter"] = "linear"
        (self.root / "project.godot").write_text(
            "[rendering]\ntextures/canvas_textures/default_texture_filter=1\n", encoding="utf-8"
        )
        self.assert_invalid("(?s)must be 0 for nearest filtering.*texture_filter must be 'nearest'")

    def test_runtime_placeholder_fails(self):
        self.manifest["assets"][0]["placeholder"] = True
        self.assert_invalid("runtime placeholder")

    def test_unregistered_png_scene_reference_fails(self):
        shutil.copy(FIXTURES / "valid_rgba_32x32.png", self.root / "assets/sprites/unregistered.png")
        (self.root / "scenes/unregistered.tscn").write_text(
            '[gd_scene format=3]\n[ext_resource type="Texture2D" path="res://assets/sprites/unregistered.png" id="1"]\n',
            encoding="utf-8",
        )
        self.assert_invalid("unregistered PNG reference")


if __name__ == "__main__":
    unittest.main()
