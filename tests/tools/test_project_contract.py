import configparser
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ProjectContractTests(unittest.TestCase):
    def test_project_has_a_loadable_main_scene(self):
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://src/main/main.tscn"', project)
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


if __name__ == "__main__":
    unittest.main()
