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

    def test_tea_export_normalizes_recovery_modes_and_validates_optional_runtime_fields(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        rows = {
            "teas": [{
                "_notion_id": "tea-page",
                "차 ID": {"prefix": "TEA", "number": 10},
                "이름": "백설 백차",
                "설정 상태": "확정",
                "기운 회복": 24,
                "마시는 시간(초)": 2.1,
                "1회 소비량": 1,
                "휴대 횟수": 4,
                "회복 방식": "점진",
                "기운 유지 보정": 12,
                "우리기 장소 필요": True,
                "특수 효과": "즉시량은 낮지만 기운 감소를 완만하게 한다.",
            }]
        }
        capture = CaptureBuilder(schema).build_from_rows(rows, "tea-runtime-fixture-v1")
        tea = ExportPipeline(schema).build_snapshots(capture, "confirmed-test")["teas"]["items"][0]
        self.assertEqual(tea["recovery_mode"], "progressive")
        self.assertEqual(tea["drink_seconds"], 2.1)
        self.assertEqual(tea["carry_uses"], 4)
        self.assertEqual(tea["sustain_modifier"], 12)
        self.assertTrue(tea["requires_brewing_location"])

        invalid = copy.deepcopy(capture)
        invalid["datasets"]["teas"]["items"][0]["carry_uses"] = 0
        with self.assertRaisesRegex(ExportValidationError, "teas.*tea_10.*carry_uses"):
            ExportPipeline(schema).build_snapshots(invalid, "confirmed-test")

    def test_monster_export_preserves_runtime_stat_mapping(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        monster_notion = schema["datasets"]["monsters"]["notion"]
        self.assertEqual(monster_notion["field_map"]["HP"], "hp")
        self.assertEqual(monster_notion["field_map"]["경직 저항"], "stagger_resistance")
        self.assertEqual(monster_notion["field_map"]["이동속도"], "movement_speed")
        self.assertEqual(monster_notion["field_map"]["공격력"], "attack")
        self.assertEqual(monster_notion["field_map"]["공격 주기(초)"], "attack_period_seconds")
        self.assertEqual(monster_notion["field_map"]["행동 타입"], "behavior_type")

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

    def test_character_export_preserves_canonical_id_and_meta_memory_checkbox(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        character_notion = schema["datasets"]["characters"]["notion"]
        self.assertEqual(character_notion["source"], "collection://86d9c16b-e60e-4434-9c84-26b4b00d16c8")
        self.assertEqual(character_notion["unique_id_output_field"], "character_id")
        self.assertEqual(character_notion["field_map"]["메타 기억 허용"], "meta_memory")
        self.assertEqual(character_notion["field_map"]["최종 다실 대상 ID"], "final_room_target_ids")

        rows = {
            "characters": [
                {"_notion_id": "father", "캐릭터 ID": {"prefix": "CHR", "number": 1}, "이름": "아버지", "설정 상태": "확정", "메타 기억 허용": True, "최종 다실 대상 ID": []},
                {"_notion_id": "ordinary", "캐릭터 ID": {"prefix": "CHR", "number": 2}, "이름": "보통 인물", "설정 상태": "확정", "메타 기억 허용": False, "최종 다실 대상 ID": ["daimyo"]},
                {"_notion_id": "rikyu", "캐릭터 ID": {"prefix": "CHR", "number": 5}, "이름": "센리큐", "설정 상태": "확정", "메타 기억 허용": True, "최종 다실 대상 ID": []},
                {"_notion_id": "merchant", "캐릭터 ID": {"prefix": "CHR", "number": 9}, "이름": "떠돌이 차 상인", "설정 상태": "확정", "메타 기억 허용": False, "최종 다실 대상 ID": []},
            ]
        }
        capture = CaptureBuilder(schema, {"merchant": "wandering_tea_merchant"}).build_from_rows(rows, "character-memory-fixture-v1")
        characters = ExportPipeline(schema).build_snapshots(capture)["characters"]["items"]

        self.assertEqual([item["id"] for item in characters], ["chr_1", "chr_2", "chr_5", "wandering_tea_merchant"])
        self.assertEqual([item["character_id"] for item in characters], ["CHR-1", "CHR-2", "CHR-5", "CHR-9"])
        self.assertEqual([item["meta_memory"] for item in characters], [True, False, True, False])
        self.assertEqual([item.get("final_room_target_ids", []) for item in characters], [[], ["daimyo"], [], []])

    def test_character_export_rejects_missing_or_non_boolean_meta_memory(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        base = {
            "schema_version": 1,
            "data_version": "character-memory-fixture-v1",
            "datasets": {
                "characters": {
                    "source": schema["datasets"]["characters"]["notion"]["source"],
                    "items": [{"id": "chr_1", "character_id": "CHR-1", "name": "아버지", "status": "확정"}],
                }
            },
        }
        with self.assertRaisesRegex(ExportValidationError, "chr_1.*meta_memory"):
            ExportPipeline(schema).build_snapshots(base)

        base["datasets"]["characters"]["items"][0]["meta_memory"] = "true"
        with self.assertRaisesRegex(ExportValidationError, "chr_1.*meta_memory must be a boolean"):
            ExportPipeline(schema).build_snapshots(base)

        base["datasets"]["characters"]["items"][0]["meta_memory"] = True
        characters = ExportPipeline(schema).build_snapshots(base)["characters"]["items"]
        self.assertNotIn("final_room_target_ids", characters[0])

        base["datasets"]["characters"]["items"][0]["final_room_target_ids"] = ["Bad Target"]
        with self.assertRaisesRegex(ExportValidationError, "chr_1.*final_room_target_ids must contain stable ids"):
            ExportPipeline(schema).build_snapshots(base)

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

    def test_drop_table_export_resolves_exact_relations_and_validates_contract(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertEqual(
            schema["datasets"]["drops"]["notion"]["source"],
            "collection://362e7813-5332-420b-aca0-fb2824dbcce0",
        )
        runtime_ids = json.loads(RUNTIME_ID_MAP.read_text(encoding="utf-8"))["notion_pages"]
        self.assertEqual(runtime_ids["3ce37369-9e66-8168-b78c-db667f533c7d"], "drop_1")
        self.assertEqual(runtime_ids["3ce37369-9e66-810a-8d02-d63e441bbfb6"], "drop_2")
        self.assertEqual(runtime_ids["3ce37369-9e66-81d2-bb71-e90b844fe65d"], "item_33")
        self.assertEqual(runtime_ids["3ce37369-9e66-81f0-a2d4-c3923da3a1b3"], "item_32")
        rows = {
            "monsters": [{
                "_notion_id": "monster-road-bandit",
                "몬스터 ID": {"prefix": "MON", "number": 9},
                "이름": "노상 도적",
                "설정 상태": "테스트",
            }],
            "items": [{
                "_notion_id": "item-coin",
                "아이템 ID": {"prefix": "ITM", "number": 33},
                "이름": "동전",
                "설정 상태": "확정",
            }],
            "drops": [{
                "_notion_id": "drop-road-bandit-coin",
                "드롭 ID": {"prefix": "DRT", "number": 1},
                "이름": "노상 도적 — 동전",
                "설정 상태": "테스트",
                "몬스터": ["monster-road-bandit"],
                "아이템": ["item-coin"],
                "차": [],
                "조건": "항상",
                "최소 수량": 1,
                "최대 수량": 3,
                "확률": 0.8,
            }],
        }
        capture = CaptureBuilder(schema).build_from_rows(rows, "notion-drop-fixture-v1")
        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        drop = snapshots["drops"]["items"][0]

        self.assertEqual(drop["id"], "drop_1")
        self.assertEqual(drop["monster_id"], "monster_9")
        self.assertEqual(drop["item_id"], "item_33")
        self.assertNotIn("tea_id", drop)
        self.assertEqual((drop["min_quantity"], drop["max_quantity"], drop["chance"]), (1, 3, 0.8))

        ambiguous = copy.deepcopy(capture)
        ambiguous["datasets"]["teas"] = {
            "source": "collection://teas",
            "items": [{"id": "tea_8", "name": "들녘 덖음차", "status": "확정"}],
        }
        ambiguous["datasets"]["drops"]["items"][0]["tea_id"] = "tea_8"
        with self.assertRaisesRegex(ExportValidationError, "exactly one of item_id or tea_id"):
            self.pipeline.build_snapshots(ambiguous, "confirmed-test")

        broken_relation = copy.deepcopy(capture)
        broken_relation["datasets"]["drops"]["items"][0]["item_id"] = "missing_item"
        with self.assertRaisesRegex(ExportValidationError, "drops.*drop_1.*item_id.*missing_item"):
            self.pipeline.build_snapshots(broken_relation, "confirmed-test")

        unsupported_condition = copy.deepcopy(capture)
        unsupported_condition["datasets"]["drops"]["items"][0]["condition"] = "비"
        with self.assertRaisesRegex(ExportValidationError, "drop_1.*unsupported condition"):
            self.pipeline.build_snapshots(unsupported_condition, "confirmed-test")

        reversed_quantity = copy.deepcopy(capture)
        reversed_quantity["datasets"]["drops"]["items"][0]["min_quantity"] = 4
        reversed_quantity["datasets"]["drops"]["items"][0]["max_quantity"] = 2
        with self.assertRaisesRegex(ExportValidationError, "drop_1.*quantity range"):
            self.pipeline.build_snapshots(reversed_quantity, "confirmed-test")

    def test_missing_required_field_fails_with_dataset_and_item_context(self):
        invalid = copy.deepcopy(self.capture)
        wood = next(item for item in invalid["datasets"]["items"]["items"] if item["id"] == "wood")
        del wood["name"]

        with self.assertRaisesRegex(ExportValidationError, "items.*wood.*name"):
            self.pipeline.build_snapshots(invalid, "confirmed")

    def test_shop_export_resolves_subject_and_seller_and_validates_numbers(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        overrides = json.loads(RUNTIME_ID_MAP.read_text(encoding="utf-8"))
        rows = {
            "items": [{"_notion_id": "item-page", "아이템 ID": {"number": 31}, "이름": "천 붕대", "설정 상태": "확정"}],
            "shops": [{
                "_notion_id": "shop-page", "재고 ID": {"number": 1}, "이름": "초기 — 천 붕대", "설정 상태": "테스트",
                "판매자": ["3ce37369-9e66-818d-934e-c07894388bde"], "아이템": ["item-page"], "차": [],
                "가격": 8, "판매 가능": True, "판매가": 4, "재고 수량": 5, "최소 진행 단계": 0, "해금 조건": "런 시작부터",
            }],
        }
        capture = CaptureBuilder(schema, overrides).build_from_rows(rows, "notion-shop-fixture-v1")
        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        shop = snapshots["shops"]["items"][0]
        self.assertEqual(shop["id"], "shop_1")
        self.assertEqual(shop["item_id"], "item_31")
        self.assertEqual(shop["seller_id"], "wandering_tea_merchant")
        self.assertEqual((shop["buy_price"], shop["sell_price"]), (8, 4))
        for field, value in (("buy_price", None), ("buy_price", 0), ("sell_price", -1), ("stock_quantity", 1.5)):
            invalid = copy.deepcopy(capture)
            if value is None:
                invalid["datasets"]["shops"]["items"][0].pop(field)
            else:
                invalid["datasets"]["shops"]["items"][0][field] = value
            with self.assertRaises(ExportValidationError):
                self.pipeline.build_snapshots(invalid, "confirmed-test")

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

    def test_boss_dungeon_and_nested_summon_relations_are_validated(self):
        capture = self._minimal_boss_capture()

        missing_dungeon = copy.deepcopy(capture)
        missing_dungeon["datasets"]["bosses"]["items"][0]["dungeon_id"] = "missing_dungeon"
        with self.assertRaisesRegex(ExportValidationError, "bosses.*fixture_boss.*dungeon_id.*missing_dungeon"):
            self.pipeline.build_snapshots(missing_dungeon, "confirmed-test")

        missing_monster = copy.deepcopy(capture)
        missing_monster["datasets"]["bosses"]["items"][0]["phases"][0]["patterns"][0]["summon_monster_ids"] = ["missing_monster"]
        with self.assertRaisesRegex(ExportValidationError, "bosses.*fixture_boss.*summon_monster_ids.*missing_monster"):
            self.pipeline.build_snapshots(missing_monster, "confirmed-test")

    def test_boss_tea_contract_and_nested_relations_are_validated(self):
        capture = self._minimal_boss_tea_capture()
        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        self.assertEqual(
            snapshots["bosses"]["items"][0]["tea_resolution"]["choice_id"],
            "fixture_share_tea",
        )

        missing_choice = copy.deepcopy(capture)
        missing_choice["datasets"]["choices"]["items"] = []
        with self.assertRaisesRegex(ExportValidationError, "tea_resolution.choice_id.*fixture_share_tea"):
            self.pipeline.build_snapshots(missing_choice, "confirmed-test")

        missing_tea = copy.deepcopy(capture)
        missing_tea["datasets"]["teas"]["items"] = []
        with self.assertRaisesRegex(ExportValidationError, "required_tea_ids.*oribe_green_matcha"):
            self.pipeline.build_snapshots(missing_tea, "confirmed-test")

        invalid_condition = copy.deepcopy(capture)
        invalid_condition["datasets"]["bosses"]["items"][0]["tea_resolution"]["peaceful_conditions"] = [
            {"type": "meta_flag", "id": "forbidden_meta"}
        ]
        with self.assertRaisesRegex(ExportValidationError, "unsupported condition type meta_flag"):
            self.pipeline.build_snapshots(invalid_condition, "confirmed-test")

        combat_only = copy.deepcopy(capture)
        combat_only["datasets"]["bosses"]["items"][0]["resolution_types"] = ["combat"]
        with self.assertRaisesRegex(ExportValidationError, "tea_resolution requires peaceful"):
            self.pipeline.build_snapshots(combat_only, "confirmed-test")

        invalid_hook = copy.deepcopy(capture)
        invalid_hook["datasets"]["bosses"]["items"][0]["tea_resolution"]["hooks"]["common"]["memory"] = [
            "dialogue.wrong_channel"
        ]
        with self.assertRaisesRegex(ExportValidationError, "memory hook keys.*stable channel keys"):
            self.pipeline.build_snapshots(invalid_hook, "confirmed-test")

    def test_event_result_grant_item_must_target_catalog_item(self):
        invalid = self._minimal_event_capture()
        invalid["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["results"][0]["id"] = "missing_item"

        with self.assertRaisesRegex(ExportValidationError, "events.*grant_item.*missing item id missing_item"):
            self.pipeline.build_snapshots(invalid, "confirmed-test")

    def test_event_result_grant_item_requires_items_dataset(self):
        invalid = self._minimal_event_capture()
        del invalid["datasets"]["items"]

        with self.assertRaisesRegex(ExportValidationError, "events.*grant_item.*missing dataset items"):
            self.pipeline.build_snapshots(invalid, "confirmed-test")

    def test_event_result_grant_item_directory_validation_requires_items_dataset(self):
        invalid = self._minimal_event_capture()
        events = invalid["datasets"]["events"]

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.json"
            path.write_text(
                json.dumps(
                    self._snapshot("fixture-events-2026-09-01", "confirmed-test", events["source"], events["items"]),
                    ensure_ascii=False,
                    sort_keys=True,
                    indent=2,
                ) + "\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ExportValidationError, "events.*grant_item.*missing dataset items"):
                self.pipeline.validate_directory(Path(directory))

    def test_event_result_set_run_flag_allows_events_only_export(self):
        capture = self._minimal_event_capture()
        del capture["datasets"]["items"]
        capture["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["results"] = [
            {"type": "set_run_flag", "id": "met_old_keeper"}
        ]

        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        self.assertEqual(sorted(snapshots), ["events"])

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.json"
            path.write_text(
                json.dumps(snapshots["events"], ensure_ascii=False, sort_keys=True, indent=2) + "\n",
                encoding="utf-8",
            )
            validated = self.pipeline.validate_directory(Path(directory))

        self.assertEqual(validated["datasets"], ["events"])

    def test_event_result_apply_choice_requires_a_known_choice(self):
        capture = self._minimal_event_capture()
        capture["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["results"] = [
            {"type": "apply_choice", "id": "daimyo_defeat"}
        ]
        with self.assertRaisesRegex(ExportValidationError, "apply_choice.*missing dataset choices"):
            self.pipeline.build_snapshots(capture, "confirmed-test")

        capture["datasets"]["choices"] = {
            "source": "collection://choices",
            "items": [self._choice_definition("daimyo_relinquish_tea")],
        }
        with self.assertRaisesRegex(ExportValidationError, "apply_choice.*missing choice id daimyo_defeat"):
            self.pipeline.build_snapshots(capture, "confirmed-test")

        capture["datasets"]["choices"]["items"].append(self._choice_definition("daimyo_defeat"))
        snapshots = self.pipeline.build_snapshots(capture, "confirmed-test")
        self.assertEqual(snapshots["events"]["items"][0]["nodes"][0]["options"][0]["results"][0]["id"], "daimyo_defeat")

    def test_choice_contract_is_rejected_before_export(self):
        for field, value, error in [
            ("choice_key", "bad key", "choice_key"),
            ("run_flag", "Bad Flag", "run_flag"),
            ("meta_record", "yes", "meta_record"),
            ("target_survives", 1, "target_survives"),
            ("philosophy_marks", "和·공존", "philosophy_marks"),
            ("philosophy_marks", [""], "philosophy_marks"),
        ]:
            capture = {
                "schema_version": 1,
                "data_version": "choice-contract-v1",
                "datasets": {"choices": {"source": "collection://choices", "items": [self._choice_definition("daimyo_defeat")]}},
            }
            capture["datasets"]["choices"]["items"][0][field] = value
            with self.subTest(field=field, value=value):
                with self.assertRaisesRegex(ExportValidationError, error):
                    self.pipeline.build_snapshots(capture, "confirmed-test")

    def test_choice_conditions_and_multiple_results_are_rejected(self):
        capture = {
            "schema_version": 1,
            "data_version": "choice-contract-v1",
            "datasets": {"choices": {"source": "collection://choices", "items": [self._choice_definition("daimyo_defeat")]}},
        }
        capture["datasets"]["choices"]["items"][0]["conditions"] = "not-an-array"
        with self.assertRaisesRegex(ExportValidationError, "conditions"):
            self.pipeline.build_snapshots(capture, "confirmed-test")

        events = self._minimal_event_capture()
        events["datasets"]["choices"] = capture["datasets"]["choices"]
        events["datasets"]["choices"]["items"][0]["conditions"] = []
        events["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["results"] = [
            {"type": "apply_choice", "id": "daimyo_defeat"},
            {"type": "apply_choice", "id": "daimyo_defeat"},
        ]
        with self.assertRaisesRegex(ExportValidationError, "multiple apply_choice"):
            self.pipeline.build_snapshots(events, "confirmed-test")

    def test_event_duplicate_ids_and_non_completing_paths_fail(self):
        duplicate_node = self._minimal_event_capture()
        duplicate_node["datasets"]["events"]["items"][0]["nodes"].append(
            {"id": "start", "text": "duplicate", "options": []}
        )
        with self.assertRaisesRegex(ExportValidationError, "events.*duplicate node id start"):
            self.pipeline.build_snapshots(duplicate_node, "confirmed-test")

        duplicate_option = self._minimal_event_capture()
        duplicate_option["datasets"]["events"]["items"][0]["nodes"][0]["options"].append(
            {"id": "take", "display_text": "Again", "results": [], "next_node_id": "", "completes_event": True}
        )
        with self.assertRaisesRegex(ExportValidationError, "events.*duplicate option id take"):
            self.pipeline.build_snapshots(duplicate_option, "confirmed-test")

        non_terminating = self._minimal_event_capture()
        non_terminating["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["completes_event"] = False
        non_terminating["datasets"]["events"]["items"][0]["nodes"][0]["options"][0]["next_node_id"] = ""
        with self.assertRaisesRegex(ExportValidationError, "events.*neither completes nor advances"):
            self.pipeline.build_snapshots(non_terminating, "confirmed-test")

        cycle = self._minimal_event_capture()
        cycle["datasets"]["events"]["items"][0]["nodes"] = [
            {
                "id": "start",
                "text": "start",
                "options": [{"id": "loop", "display_text": "Loop", "results": [], "next_node_id": "again", "completes_event": False}],
            },
            {
                "id": "again",
                "text": "again",
                "options": [{"id": "back", "display_text": "Back", "results": [], "next_node_id": "start", "completes_event": False}],
            },
        ]
        with self.assertRaisesRegex(ExportValidationError, "events.*reachable dialogue cycle"):
            self.pipeline.build_snapshots(cycle, "confirmed-test")

    def test_recipe_unlock_biome_relation_uses_stable_id(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        recipe_notion = schema["datasets"]["recipes"]["notion"]
        self.assertEqual(
            recipe_notion["relation_map"]["해금 지역 관계"],
            {"field": "unlock_biome_id", "target": "biomes", "many": False},
        )

        snapshots = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        recipe = snapshots["recipes"]["items"][0]

        self.assertEqual(recipe["unlock_biome_id"], "common_region")

    def test_write_snapshots_round_trips_through_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            written = self.pipeline.export(self.capture, Path(directory), "confirmed-test")
            self.assertEqual({path.stem for path in written}, set(self.capture["datasets"]))
            validated = self.pipeline.validate_directory(Path(directory))
            self.assertEqual(validated["data_version"], "fixture-2026-09-01")
            self.assertEqual(validated["profile"], "confirmed-test")

    def test_meta_unlock_contract_accepts_canonical_fields(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        field_map = schema["datasets"]["meta_unlocks"]["notion"]["field_map"]
        self.assertEqual(field_map["표준 조건 유형"], "condition_event")
        self.assertEqual(field_map["조건 대상"], "condition_target")
        self.assertEqual(field_map["표준 조건 연산자"], "condition_operator")
        self.assertEqual(field_map["표준 보상 유형"], "reward_kind")
        self.assertEqual(field_map["보상 대상"], "reward_target")
        self.assertNotIn("조건 연산자", field_map)

        capture = self._minimal_meta_unlock_capture()
        snapshot = self.pipeline.build_snapshots(capture, "confirmed-test")["meta_unlocks"]
        item = snapshot["items"][0]
        self.assertEqual(item["condition_event"], "cumulative_event_count_at_least")
        self.assertEqual(item["condition_target"], "discovered_record:memory_tea")
        self.assertEqual(item["condition_operator"], "at_least")
        self.assertEqual(item["reward_kind"], "discovered_record")
        self.assertEqual(item["reward_quantity"], 1)

    def test_meta_unlock_contract_rejects_unknown_types_and_operator(self):
        for field, value, message in (
            ("condition_event", "unknown_condition", "invalid condition_event"),
            ("condition_operator", "approximately", "invalid condition_operator"),
            ("reward_kind", "permanent_attack", "invalid reward_kind"),
        ):
            with self.subTest(field=field):
                capture = self._minimal_meta_unlock_capture()
                capture["datasets"]["meta_unlocks"]["items"][0][field] = value
                with self.assertRaisesRegex(ExportValidationError, message):
                    self.pipeline.build_snapshots(capture, "confirmed-test")

    def _minimal_meta_unlock_capture(self):
        return {
            "schema_version": 1,
            "data_version": "fixture-meta-unlocks-2026-09-02",
            "datasets": {
                "meta_unlocks": {
                    "source": "collection://meta-unlocks",
                    "items": [{
                        "id": "third_memory_tea",
                        "name": "Third Memory Tea",
                        "status": "테스트",
                        "condition_type": "기억 발견",
                        "condition_event": "cumulative_event_count_at_least",
                        "condition_target": "discovered_record:memory_tea",
                        "condition_operator": "at_least",
                        "cumulative": True,
                        "threshold": 3,
                        "reward_type": "도감",
                        "reward_kind": "discovered_record",
                        "reward_target": "third_memory_tea",
                        "reward_quantity": 1,
                    }],
                },
            },
        }

    def _minimal_event_capture(self):
        return {
            "schema_version": 1,
            "data_version": "fixture-events-2026-09-01",
            "datasets": {
                "items": {
                    "source": "collection://items",
                    "items": [{"id": "ash_stained_iron_kettle", "name": "재 묻은 철솥", "status": "초안"}],
                },
                "events": {
                    "source": "fixture://events",
                    "items": [
                        {
                            "id": "sample_event",
                            "name": "Sample Event",
                            "status": "확정",
                            "replay_policy": "once",
                            "start_node_id": "start",
                            "nodes": [
                                {
                                    "id": "start",
                                    "text": "start",
                                    "options": [
                                        {
                                            "id": "take",
                                            "display_text": "Take",
                                            "conditions": [],
                                            "results": [{"type": "grant_item", "id": "ash_stained_iron_kettle", "quantity": 1}],
                                            "next_node_id": "",
                                            "completes_event": True,
                                        }
                                    ],
                                }
                            ],
                        }
                    ],
                },
            },
        }

    def _snapshot(self, data_version, profile, source, items):
        payload = {
            "schema_version": self.pipeline.schema["schema_version"],
            "data_version": data_version,
            "profile": profile,
            "source": source,
            "items": items,
        }
        return {
            **payload,
            "content_hash": hashlib.sha256(canonical_json_bytes(payload)).hexdigest(),
        }

    def _minimal_boss_capture(self):
        return {
            "schema_version": 1,
            "data_version": "fixture-boss-relations-v1",
            "datasets": {
                "dungeons": {"source": "collection://dungeons", "items": [{"id": "dungeon_4", "name": "Dungeon", "status": "확정"}]},
                "biomes": {"source": "collection://biomes", "items": [{"id": "common_region", "name": "Biome", "status": "확정"}]},
                "items": {"source": "collection://items", "items": [{"id": "reward_bowl", "name": "Reward", "status": "확정"}]},
                "monsters": {"source": "collection://monsters", "items": [{"id": "road_bandit", "name": "Bandit", "status": "확정"}]},
                "bosses": {"source": "fixture://bosses", "items": [{
                    "id": "fixture_boss",
                    "name": "Boss",
                    "status": "테스트",
                    "dungeon_id": "dungeon_4",
                    "biome_id": "common_region",
                    "max_hp": 100,
                    "phases": [{"id": "opening", "health_ratio_threshold": 1.0, "patterns": [{"id": "call", "interval_seconds": 1.0, "summon_monster_ids": ["road_bandit"]}]}],
                    "resolution_types": ["combat"],
                    "reward_item_ids": ["reward_bowl"],
                    "progression_unlock_ids": ["common_region"],
                    "summon_monster_ids": ["road_bandit"],
                }]},
            },
        }

    def _minimal_boss_tea_capture(self):
        capture = self._minimal_boss_capture()
        capture["datasets"]["choices"] = {
            "source": "collection://choices",
            "items": [self._choice_definition("fixture_share_tea")],
        }
        capture["datasets"]["teas"] = {
            "source": "collection://teas",
            "items": [{"id": "oribe_green_matcha", "name": "Tea", "status": "확정", "ki_recovery": 0}],
        }
        boss = capture["datasets"]["bosses"]["items"][0]
        boss["resolution_types"] = ["combat", "peaceful"]
        boss["tea_resolution"] = {
            "choice_id": "fixture_share_tea",
            "required_tea_ids": ["oribe_green_matcha"],
            "peaceful_conditions": [
                {"type": "prepared_tea", "id": "oribe_green_matcha"},
                {"type": "run_flag", "id": "met_boss"},
            ],
            "hooks": {
                "common": {"memory": ["memory.fixture_boss.met"]},
                "combat_started": {"dialogue": ["dialogue.fixture_boss.combat_started"]},
            },
        }
        return capture

    def _choice_definition(self, choice_id):
        return {
            "id": choice_id,
            "name": choice_id,
            "status": "확정",
            "choice_key": choice_id.upper(),
            "run_flag": f"{choice_id}_flag",
            "display_text": choice_id,
            "resolution": "다도",
            "meta_record": True,
            "target_survives": True,
            "philosophy_marks": [],
            "final_room_effect": f"{choice_id} effect",
        }

    def test_equipment_tea_ware_exports_canonical_effect_fields_only(self):
        snapshots = self.pipeline.build_snapshots(self.capture, "confirmed-test")
        item = next(item for item in snapshots["items"]["items"] if item["id"] == "oribe_bowl")

        self.assertEqual(item["equipment_slot"], "다구")
        self.assertEqual(item["effect_type"], "차 운용")
        self.assertEqual(item["effect_value"], 10)
        self.assertTrue(item["core_tea_ware"])
        self.assertEqual(item["core_tea_ware_order"], 1)
        self.assertEqual(item["attachment_stage_thresholds"], [0, 3, 7])
        self.assertEqual(
            item["attachment_description_keys"],
            [
                "items.oribe_bowl.attachment.stage_0",
                "items.oribe_bowl.attachment.stage_1",
                "items.oribe_bowl.attachment.stage_2",
            ],
        )
        self.assertNotIn("tea_recovery_bonus", item)

    def test_equipment_tea_ware_attachment_fields_accept_flattened_notion_strings(self):
        flattened = copy.deepcopy(self.capture)
        item = next(item for item in flattened["datasets"]["items"]["items"] if item["id"] == "oribe_bowl")
        item["attachment_stage_thresholds"] = "0, 3, 7"
        item["attachment_description_keys"] = (
            "items.oribe_bowl.attachment.stage_0, "
            "items.oribe_bowl.attachment.stage_1, "
            "items.oribe_bowl.attachment.stage_2"
        )

        snapshots = self.pipeline.build_snapshots(flattened, "confirmed-test")
        exported = next(item for item in snapshots["items"]["items"] if item["id"] == "oribe_bowl")

        self.assertEqual(exported["attachment_stage_thresholds"], [0, 3, 7])
        self.assertEqual(
            exported["attachment_description_keys"],
            [
                "items.oribe_bowl.attachment.stage_0",
                "items.oribe_bowl.attachment.stage_1",
                "items.oribe_bowl.attachment.stage_2",
            ],
        )

    def test_equipment_tea_ware_attachment_threshold_list_strings_remain_supported(self):
        flattened = copy.deepcopy(self.capture)
        item = next(item for item in flattened["datasets"]["items"]["items"] if item["id"] == "oribe_bowl")
        item["attachment_stage_thresholds"] = ["0", "3", "7"]

        snapshots = self.pipeline.build_snapshots(flattened, "confirmed-test")
        exported = next(item for item in snapshots["items"]["items"] if item["id"] == "oribe_bowl")

        self.assertEqual(exported["attachment_stage_thresholds"], [0, 3, 7])

    def test_equipment_tea_ware_attachment_stage_export_is_required(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        item_notion = schema["datasets"]["items"]["notion"]
        self.assertEqual(item_notion["field_map"]["정붙음 단계 임계값"], "attachment_stage_thresholds")
        self.assertEqual(item_notion["field_map"]["정붙음 설명 키"], "attachment_description_keys")

        missing = copy.deepcopy(self.capture)
        item = next(item for item in missing["datasets"]["items"]["items"] if item["id"] == "oribe_bowl")
        del item["attachment_stage_thresholds"]
        with self.assertRaisesRegex(ExportValidationError, "oribe_bowl.*attachment_stage_thresholds"):
            self.pipeline.build_snapshots(missing, "confirmed-test")

        too_few = copy.deepcopy(self.capture)
        item = next(item for item in too_few["datasets"]["items"]["items"] if item["id"] == "oribe_bowl")
        item["attachment_stage_thresholds"] = [0, 3]
        with self.assertRaisesRegex(ExportValidationError, "oribe_bowl.*at least 3"):
            self.pipeline.build_snapshots(too_few, "confirmed-test")

        bad_keys = copy.deepcopy(self.capture)
        item = next(item for item in bad_keys["datasets"]["items"]["items"] if item["id"] == "oribe_bowl")
        item["attachment_description_keys"] = ["items.oribe_bowl.attachment.stage_0"]
        with self.assertRaisesRegex(ExportValidationError, "oribe_bowl.*cover every threshold"):
            self.pipeline.build_snapshots(bad_keys, "confirmed-test")

    def test_dev_4_static_combat_exports_are_present(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        items = json.loads((generated / "items.json").read_text(encoding="utf-8"))["items"]
        monsters = json.loads((generated / "monsters.json").read_text(encoding="utf-8"))["items"]
        sword = next(item for item in items if item["id"] == "short_travel_sword")
        oribe_bowl = next(item for item in items if item["id"] == "oribe_green_glazed_bowl")
        road_bandit = next(monster for monster in monsters if monster["id"] == "road_bandit")

        self.assertEqual(sword["base_damage"], 14)
        self.assertEqual(sword["attack_speed"], 1)
        self.assertEqual(sword["range"], 1.15)
        self.assertEqual(sword["status"], "확정")
        self.assertFalse(sword["craftable"])
        self.assertEqual(oribe_bowl["attachment_stage_thresholds"], [0, 3, 7])
        self.assertEqual(
            oribe_bowl["attachment_description_keys"],
            [
                "items.oribe_green_glazed_bowl.attachment.stage_0",
                "items.oribe_green_glazed_bowl.attachment.stage_1",
                "items.oribe_green_glazed_bowl.attachment.stage_2",
            ],
        )
        self.assertEqual(road_bandit["hp"], 70)
        self.assertEqual(road_bandit["attack"], 10)
        self.assertEqual(road_bandit["status"], "테스트")
        self.assertEqual(road_bandit["movement_speed"], 1.6)
        self.assertEqual(road_bandit["attack_period_seconds"], 1.8)
        self.assertEqual(road_bandit["stagger_resistance"], 0.2)
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

    def test_dev_16_generated_character_memory_policy_matches_canon(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        characters = json.loads((generated / "characters.json").read_text(encoding="utf-8"))["items"]
        by_character_id = {item["character_id"]: item for item in characters}

        self.assertEqual(set(by_character_id), {f"CHR-{number}" for number in range(1, 10)})
        self.assertEqual(
            {character_id for character_id, item in by_character_id.items() if item["meta_memory"]},
            {"CHR-1", "CHR-5"},
        )
        self.assertTrue(all(isinstance(item["meta_memory"], bool) for item in characters))
        self.assertTrue(all(isinstance(item["final_room_target_ids"], list) for item in characters))
        self.assertEqual(by_character_id["CHR-2"]["final_room_target_ids"], ["daimyo"])
        self.assertEqual(by_character_id["CHR-9"]["id"], "wandering_tea_merchant")

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
        self.assertEqual(minimum["value"], 14)

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

    def test_dev_10_generated_recipes_have_stable_unlock_biome_ids(self):
        generated = ROOT / "data/generated"
        self.pipeline.validate_directory(generated)

        recipes = {
            item["id"]: item
            for item in json.loads((generated / "recipes.json").read_text(encoding="utf-8"))["items"]
        }

        self.assertEqual(recipes["bandage"]["unlock_biome_id"], "common_region")
        self.assertEqual(recipes["wooden_workbench"]["unlock_biome"], "일반")
        self.assertEqual(recipes["wooden_workbench"]["unlock_biome_id"], "common_region")
        self.assertEqual(recipes["mountain_kiln"]["unlock_biome_id"], "mountain_region")
        self.assertEqual(recipes["repair_hammer"]["unlock_biome_id"], "wasteland")
        self.assertEqual(recipes["insulated_tea_bottle"]["unlock_biome_id"], "snowfield")
        self.assertEqual(recipes["incense_sticks"]["unlock_biome_id"], "rainforest")

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
