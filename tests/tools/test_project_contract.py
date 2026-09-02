import configparser
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ProjectContractTests(unittest.TestCase):
    def test_korean_product_name_is_muchau(self):
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('config/name="무차우"', project)

        contract_files = (
            ROOT / "AGENTS.md",
            ROOT / "README.md",
            ROOT / "assets/sprites/characters/notion-character-map.json",
            ROOT / "assets/style/art-style-tokens.json",
            ROOT / "data/generated/notion_sources.json",
            ROOT / "docs/notion-source-map.md",
            ROOT / "project.godot",
        )
        legacy_names = tuple(
            left + separator + right
            for left, right in (("무사", "여우"), ("여우", "무사"))
            for separator in ("", " ")
        )

        for path in contract_files:
            content = path.read_text(encoding="utf-8")
            for legacy_name in legacy_names:
                self.assertNotIn(legacy_name, content, f"{legacy_name} in {path}")

    def test_project_has_a_loadable_main_scene(self):
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://scenes/ui/start_screen.tscn"', project)
        self.assertTrue((ROOT / "scenes/ui/start_screen.tscn").is_file())
        self.assertTrue((ROOT / "src/main/main.tscn").is_file())

    def test_export_template_covers_desktop_and_mobile_targets(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / "export_presets.example.cfg", encoding="utf-8")
        expected = {
            "preset.0": ("Desktop", "macOS", "exports/desktop/samurai-tea-fox.dmg"),
            "preset.1": ("Android", "Android", "exports/android/samurai-tea-fox.apk"),
            "preset.2": ("iOS", "iOS", "exports/ios/samurai-tea-fox.ipa"),
        }

        for section, (name, platform, export_path) in expected.items():
            self.assertTrue(parser.has_section(section), section)
            self.assertEqual(parser.get(section, "name"), f'"{name}"')
            self.assertEqual(parser.get(section, "platform"), f'"{platform}"')
            self.assertEqual(parser.get(section, "export_filter"), '"all_resources"')
            self.assertEqual(parser.get(section, "export_path"), f'"{export_path}"')

    def test_platform_adapters_share_the_game_command_boundary(self):
        desktop = ROOT / "src/core/commands/desktop_command_adapter.gd"
        mobile = ROOT / "src/core/commands/mobile_command_adapter.gd"
        command = ROOT / "src/core/commands/game_command.gd"

        self.assertTrue(desktop.is_file())
        for adapter in (desktop, mobile):
            source = adapter.read_text(encoding="utf-8")
            self.assertIn('res://src/core/commands/game_command.gd', source)
        self.assertTrue(command.is_file())

    def test_boss_export_contract_is_registered(self):
        schema = json.loads(
            (ROOT / "data/schemas/export_schema.json").read_text(encoding="utf-8")
        )
        bosses = schema["datasets"]["bosses"]

        self.assertEqual(bosses["file"], "bosses.json")
        self.assertEqual(
            bosses["relations"],
            {
                "dungeon_id": "dungeons",
                "biome_id": "biomes",
                "reward_item_ids": "items",
                "summon_monster_ids": "monsters",
            },
        )
        self.assertTrue((ROOT / "data/generated/bosses.json").is_file())
        self.assertTrue((ROOT / "data/generated/dungeons.json").is_file())


if __name__ == "__main__":
    unittest.main()
