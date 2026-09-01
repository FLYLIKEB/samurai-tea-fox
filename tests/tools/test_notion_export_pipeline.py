import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.notion_export.capture import CaptureBuilder
from tools.notion_export.pipeline import (
    ExportPipeline,
    ExportValidationError,
    canonical_json_bytes,
)


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/notion_export/source.json"
SCHEMA = ROOT / "data/schemas/export_schema.json"
RUNTIME_ID_MAP = ROOT / "data/schemas/runtime_id_map.json"


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

        self.assertEqual([item["id"] for item in confirmed["items"]["items"]], ["oribe_bowl", "wood"])
        self.assertEqual(
            [item["id"] for item in confirmed_test["items"]["items"]],
            ["clay", "oribe_bowl", "wood"],
        )
        self.assertNotIn("day_phase_duration_seconds", [item["id"] for item in confirmed["balance"]["items"]])
        self.assertNotIn("player_hp_max", [item["id"] for item in confirmed["balance"]["items"]])
        self.assertNotIn("biome_min_resource_nodes", [item["id"] for item in confirmed["balance"]["items"]])
        self.assertIn("player_hp_max", [item["id"] for item in confirmed_test["balance"]["items"]])
        self.assertIn("biome_min_resource_nodes", [item["id"] for item in confirmed_test["balance"]["items"]])
        self.assertEqual([item["id"] for item in confirmed["abilities"]["items"]], [])
        self.assertEqual(
            [item["id"] for item in confirmed_test["abilities"]["items"]],
            ["ember", "remaining_incense"],
        )

    def test_ability_export_preserves_duration_and_status_effect_mapping(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        ability_notion = schema["datasets"]["abilities"]["notion"]
        self.assertEqual(ability_notion["field_map"]["지속시간(초)"], "duration_seconds")
        self.assertEqual(ability_notion["field_map"]["상태효과"], "status_effect")
        self.assertIn("duration_seconds", schema["datasets"]["abilities"]["required_fields"])

        snapshots = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        abilities = {item["id"]: item for item in snapshots["abilities"]["items"]}
        self.assertEqual(abilities["ember"]["duration_seconds"], 0)
        self.assertEqual(abilities["ember"]["status_effect"], "")
        self.assertEqual(abilities["remaining_incense"]["duration_seconds"], 2.5)
        self.assertEqual(abilities["remaining_incense"]["status_effect"], "slow")

    def test_monster_export_preserves_runtime_stat_mapping(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        monster_notion = schema["datasets"]["monsters"]["notion"]
        self.assertEqual(monster_notion["field_map"]["HP"], "hp")
        self.assertEqual(monster_notion["field_map"]["경직 저항"], "stagger_resistance")
        self.assertEqual(monster_notion["field_map"]["이동속도"], "movement_speed")
        self.assertEqual(monster_notion["field_map"]["공격력"], "attack")
        self.assertEqual(monster_notion["field_map"]["공격 주기(초)"], "attack_period_seconds")

        rows = {
            "monsters": [
                {
                    "_notion_id": "page-road-bandit",
                    "몬스터 ID": {"prefix": None, "number": 1},
                    "이름": "노상 도적",
                    "설정 상태": "테스트",
                    "HP": 70,
                    "경직 저항": 2.0,
                    "이동속도": 1.6,
                    "공격력": 10,
                    "공격 주기(초)": 1.8,
                }
            ]
        }
        capture = CaptureBuilder(schema, {"page-road-bandit": "road_bandit"}).build_from_rows(
            rows,
            "notion-fixture-v1",
        )
        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        road_bandit = snapshots["monsters"]["items"][0]

        self.assertEqual(road_bandit["hp"], 70)
        self.assertEqual(road_bandit["stagger_resistance"], 2.0)
        self.assertEqual(road_bandit["movement_speed"], 1.6)
        self.assertEqual(road_bandit["attack"], 10)
        self.assertEqual(road_bandit["attack_period_seconds"], 1.8)

    def test_fixture_monsters_export_regenerates_runtime_stats_and_hash(self):
        snapshots = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        monsters = {item["id"]: item for item in snapshots["monsters"]["items"]}
        road_bandit = monsters["road_bandit"]
        wild_dog = monsters["wild_dog"]

        self.assertEqual(road_bandit["hp"], 70)
        self.assertEqual(road_bandit["stagger_resistance"], 2.0)
        self.assertEqual(road_bandit["movement_speed"], 1.6)
        self.assertEqual(road_bandit["attack"], 10)
        self.assertEqual(road_bandit["attack_period_seconds"], 1.8)
        self.assertEqual(wild_dog["hp"], 42)
        self.assertEqual(wild_dog["stagger_resistance"], 0.5)
        self.assertEqual(wild_dog["movement_speed"], 2.2)
        self.assertEqual(wild_dog["attack"], 7)
        self.assertEqual(wild_dog["attack_period_seconds"], 1.25)

        payload = {key: value for key, value in snapshots["monsters"].items() if key != "content_hash"}
        self.assertEqual(
            snapshots["monsters"]["content_hash"],
            hashlib.sha256(canonical_json_bytes(payload)).hexdigest(),
        )

    def test_missing_required_field_fails_with_dataset_and_item_context(self):
        invalid = copy.deepcopy(self.capture)
        wood = next(item for item in invalid["datasets"]["items"]["items"] if item["id"] == "wood")
        del wood["name"]

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
        balance_ids = [item["id"] for item in snapshots["balance"]["items"]]

        self.assertNotIn("day_phase_duration_seconds", balance_ids)
        self.assertNotIn("player_hp_max", balance_ids)

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

    def test_equipment_tea_ware_exports_canonical_effect_fields_only(self):
        snapshots = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        item = next(item for item in snapshots["items"]["items"] if item["id"] == "oribe_bowl")

        self.assertEqual(item["equipment_slot"], "다구")
        self.assertEqual(item["effect_type"], "차 운용")
        self.assertEqual(item["effect_value"], 10)
        self.assertTrue(item["core_tea_ware"])
        self.assertEqual(item["core_tea_ware_order"], 1)
        self.assertNotIn("tea_recovery_bonus", item)

    def test_dev_4_static_combat_exports_are_present(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        items = json.loads((generated / "items.json").read_text(encoding="utf-8"))["items"]
        monsters = json.loads((generated / "monsters.json").read_text(encoding="utf-8"))["items"]
        sword = next(item for item in items if item["id"] == "short_travel_sword")
        road_bandit = next(monster for monster in monsters if monster["id"] == "road_bandit")

        self.assertEqual(sword["base_damage"], 14)
        self.assertEqual(sword["attack_speed"], 1)
        self.assertEqual(sword["range"], 1.15)
        self.assertEqual(sword["status"], "확정")
        self.assertFalse(sword["craftable"])
        self.assertEqual(road_bandit["hp"], 70)
        self.assertEqual(road_bandit["attack"], 10)
        self.assertEqual(road_bandit["status"], "테스트")
        self.assertEqual(road_bandit["movement_speed"], 1.6)
        self.assertEqual(road_bandit["attack_period_seconds"], 1.8)
        self.assertEqual(road_bandit["stagger_resistance"], 2.0)
        monsters_snapshot = json.loads((generated / "monsters.json").read_text(encoding="utf-8"))
        payload = {
            key: value
            for key, value in monsters_snapshot.items()
            if key != "content_hash"
        }
        self.assertEqual(
            monsters_snapshot["content_hash"],
            hashlib.sha256(canonical_json_bytes(payload)).hexdigest(),
        )

    def test_dev_12_static_ability_exports_include_effect_contract_fields(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        abilities = {
            item["id"]: item
            for item in json.loads((generated / "abilities.json").read_text(encoding="utf-8"))["items"]
        }

        self.assertEqual(abilities["ember"]["duration_seconds"], 0)
        self.assertEqual(abilities["ember"]["status_effect"], "")
        self.assertEqual(abilities["water_shadow"]["duration_seconds"], 0)
        self.assertEqual(abilities["water_shadow"]["status_effect"], "")

    def test_dev_6_time_and_sleep_balance_exports_are_present(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        balance = {
            item["id"]: item
            for item in json.loads((generated / "balance.json").read_text(encoding="utf-8"))["items"]
        }
        expected_time_rows = {
            "day_phase_duration_seconds": {
                "name": "낮 지속시간",
                "notion_id": "3ce37369-9e66-8142-bdd7-e6eaff3fe967",
                "unit": "초",
                "value": 300,
                "description": "낮 상태의 프로토타입 지속시간",
                "formula_note": "낮에는 心 감소가 없다. DEV-6 프로토타입 시간대 전이값.",
            },
            "dusk_phase_duration_seconds": {
                "name": "해질녘 지속시간",
                "notion_id": "3ce37369-9e66-8137-8069-e0b914681ae1",
                "unit": "초",
                "value": 120,
                "description": "해질녘 상태의 프로토타입 지속시간",
                "formula_note": "DEV-6 프로토타입 시간대 전이값.",
            },
            "night_phase_duration_seconds": {
                "name": "밤 지속시간",
                "notion_id": "3ce37369-9e66-8191-91c3-c04612c42293",
                "unit": "초",
                "value": 240,
                "description": "밤 상태의 프로토타입 지속시간",
                "formula_note": "DEV-6 프로토타입 시간대 전이값.",
            },
            "late_night_phase_duration_seconds": {
                "name": "심야 지속시간",
                "notion_id": "3ce37369-9e66-817b-a89d-e63126a7d7e3",
                "unit": "초",
                "value": 180,
                "description": "심야 상태의 프로토타입 지속시간",
                "formula_note": "완료 후 낮으로 순환한다. DEV-6 프로토타입 시간대 전이값.",
            },
            "dusk_kokoro_decay_per_second": {
                "name": "해질녘 心 감소율",
                "notion_id": "3ce37369-9e66-810d-a412-c015501c1281",
                "unit": "point/초",
                "value": 0.02,
                "description": "해질녘부터 적용되는 心 감소율",
                "formula_note": "낮 0 < 해질녘 < 밤 < 심야 순으로 증가한다.",
            },
            "night_kokoro_decay_per_second": {
                "name": "밤 心 감소율",
                "notion_id": "3ce37369-9e66-81c2-a7e6-fd48e5eb07d9",
                "unit": "point/초",
                "value": 0.05,
                "description": "밤의 心 감소율",
                "formula_note": "낮 0 < 해질녘 < 밤 < 심야 순으로 증가한다.",
            },
            "late_night_kokoro_decay_per_second": {
                "name": "심야 心 감소율",
                "notion_id": "3ce37369-9e66-815b-872c-e2edbf7fcabd",
                "unit": "point/초",
                "value": 0.1,
                "description": "심야의 心 감소율",
                "formula_note": "낮 0 < 해질녘 < 밤 < 심야 순으로 증가한다.",
            },
            "safe_sleep_hp_recovery_ratio": {
                "name": "안전 수면 HP 회복 비율",
                "notion_id": "3ce37369-9e66-81f9-af8d-f2ba12d04d47",
                "category": "플레이어",
                "unit": "비율",
                "status": "확정",
                "value": 0.2,
                "description": "해질녘·밤에 안전 지점에서 수면 시 최대 HP 기준 회복 비율",
                "formula_note": "sleep_heal = max_hp × 0.20. 心은 완전 회복하며 차·기운은 자동 회복하지 않는다.",
            },
        }

        for item_id, expected in expected_time_rows.items():
            with self.subTest(item_id=item_id):
                self.assertEqual(balance[item_id]["id"], item_id)
                self.assertEqual(balance[item_id]["name"], expected["name"])
                self.assertEqual(balance[item_id]["notion_id"], expected["notion_id"])
                self.assertEqual(balance[item_id]["status"], expected.get("status", "테스트"))
                self.assertEqual(balance[item_id]["category"], expected.get("category", "心"))
                self.assertEqual(balance[item_id]["unit"], expected["unit"])
                self.assertEqual(balance[item_id]["value"], expected["value"])
                self.assertEqual(balance[item_id]["description"], expected["description"])
                self.assertEqual(balance[item_id]["formula_note"], expected["formula_note"])

    def test_dev_6_runtime_id_map_preserves_exact_notion_rows(self):
        runtime_id_map = json.loads(RUNTIME_ID_MAP.read_text(encoding="utf-8"))
        expected = {
            "3ce37369-9e66-8142-bdd7-e6eaff3fe967": ("낮 지속시간", "day_phase_duration_seconds"),
            "3ce37369-9e66-8137-8069-e0b914681ae1": ("해질녘 지속시간", "dusk_phase_duration_seconds"),
            "3ce37369-9e66-8191-91c3-c04612c42293": ("밤 지속시간", "night_phase_duration_seconds"),
            "3ce37369-9e66-817b-a89d-e63126a7d7e3": ("심야 지속시간", "late_night_phase_duration_seconds"),
            "3ce37369-9e66-810d-a412-c015501c1281": ("해질녘 心 감소율", "dusk_kokoro_decay_per_second"),
            "3ce37369-9e66-81c2-a7e6-fd48e5eb07d9": ("밤 心 감소율", "night_kokoro_decay_per_second"),
            "3ce37369-9e66-815b-872c-e2edbf7fcabd": ("심야 心 감소율", "late_night_kokoro_decay_per_second"),
            "3ce37369-9e66-81f9-af8d-f2ba12d04d47": ("안전 수면 HP 회복 비율", "safe_sleep_hp_recovery_ratio"),
        }

        for page_id, (korean_name, stable_id) in expected.items():
            with self.subTest(page_id=page_id):
                self.assertEqual(runtime_id_map["notion_pages"][page_id], stable_id)
                self.assertEqual(runtime_id_map["legacy_names"]["balance"][korean_name], stable_id)

    def test_dev_9_general_biome_balance_export_is_present(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        balance = {
            item["id"]: item
            for item in json.loads((generated / "balance.json").read_text(encoding="utf-8"))["items"]
        }
        minimum = balance["biome_min_resource_nodes"]

        self.assertEqual(minimum["name"], "일반 바이옴 최소 자원 노드 수")
        self.assertEqual(minimum["notion_id"], "3ce37369-9e66-81a1-8047-c02aad9c81dc")
        self.assertEqual(minimum["status"], "테스트")
        self.assertEqual(minimum["category"], "월드")
        self.assertEqual(minimum["unit"], "개")
        self.assertEqual(minimum["value"], 9)

    def test_dev_9_biome_export_uses_sot_resource_field_only(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        biomes = {
            item["id"]: item
            for item in json.loads((generated / "biomes.json").read_text(encoding="utf-8"))["items"]
        }
        common = biomes["common_region"]

        self.assertEqual(common["resources"], "목재, 돌, 점토, 기본 식재료, 일반 찻잎")
        self.assertNotIn("resource_item_ids", common)

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
