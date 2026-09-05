import unittest

from tools.notion_export.capture import CaptureBuilder
from tools.notion_export.pipeline import ExportPipeline, ExportValidationError


def copy_rows(rows):
    return {
        dataset_name: [dict(row) for row in dataset_rows]
        for dataset_name, dataset_rows in rows.items()
    }


class NotionCaptureTests(unittest.TestCase):
    def setUp(self):
        self.schema = {
            "schema_version": 1,
            "stable_id_pattern": "^[a-z][a-z0-9_]*$",
            "profiles": {"confirmed": {"include_test": False}},
            "required_file_keys": [],
            "datasets": {
                "items": {
                    "file": "items.json",
                    "required_fields": ["id", "name", "status"],
                    "notion": {
                        "source": "collection://items",
                        "title_field": "이름",
                        "status_field": "설정 상태",
                        "unique_id_field": "아이템 ID",
                        "id_prefix": "item",
                        "stable_id_field": "런타임 ID",
                        "field_map": {
                            "종류": "type",
                            "장비 슬롯": "equipment_slot",
                            "상호작용 정의 JSON": "interaction_definition",
                            "정붙음 단계 임계값": "attachment_stage_thresholds",
                            "정붙음 설명 키": "attachment_description_keys",
                            "태그": "tags",
                        },
                    },
                },
                "biomes": {
                    "file": "biomes.json",
                    "required_fields": ["id", "name", "status"],
                    "notion": {
                        "source": "collection://biomes",
                        "title_field": "이름",
                        "status_field": "설정 상태",
                        "unique_id_field": "지역 ID",
                        "id_prefix": "biome",
                    },
                },
                "recipes": {
                    "file": "recipes.json",
                    "required_fields": ["id", "name", "status"],
                    "relations": {"result_item_id": "items", "unlock_biome_id": "biomes"},
                    "notion": {
                        "source": "collection://recipes",
                        "title_field": "이름",
                        "status_field": "설정 상태",
                        "unique_id_field": "제작법 ID",
                        "id_prefix": "recipe",
                        "relation_map": {
                            "결과 아이템": {"field": "result_item_id", "target": "items", "many": False},
                            "해금 지역 관계": {"field": "unlock_biome_id", "target": "biomes", "many": False},
                        },
                    },
                },
            },
        }
        self.rows = {
            "items": [
                {
                    "_notion_id": "page-item",
                    "아이템 ID": {"prefix": None, "number": 7},
                    "이름": "목재",
                    "설정 상태": "확정",
                    "종류": "재료",
                }
            ],
            "biomes": [
                {
                    "_notion_id": "page-biome",
                    "지역 ID": {"prefix": None, "number": 2},
                    "이름": "일반 지역",
                    "설정 상태": "확정",
                }
            ],
            "recipes": [
                {
                    "_notion_id": "page-recipe",
                    "제작법 ID": {"prefix": None, "number": 3},
                    "이름": "목재 작업대 제작",
                    "설정 상태": "확정",
                    "결과 아이템": ["page-item"],
                    "해금 지역 관계": ["page-biome"],
                }
            ],
        }

    def test_builds_runtime_fields_and_stable_relation_ids(self):
        builder = CaptureBuilder(self.schema, {"page-item": "wood"})
        capture = builder.build_from_rows(self.rows, "notion-fixture-v1")
        snapshots = ExportPipeline(self.schema).build_snapshots(capture)

        self.assertEqual(capture["datasets"]["items"]["items"][0]["id"], "wood")
        self.assertEqual(capture["datasets"]["biomes"]["items"][0]["id"], "biome_2")
        recipe = capture["datasets"]["recipes"]["items"][0]
        self.assertEqual(recipe["result_item_id"], "wood")
        self.assertEqual(recipe["unlock_biome_id"], "biome_2")
        self.assertEqual(snapshots["recipes"]["items"][0]["id"], "recipe_3")

    def test_stable_id_field_is_normalized_for_runtime_id(self):
        schema = {
            **self.schema,
            "datasets": {
                "choices": {
                    "file": "choices.json",
                    "required_fields": ["id", "name", "status", "choice_key"],
                    "notion": {
                        "source": "collection://choices",
                        "title_field": "이름",
                        "status_field": "설정 상태",
                        "unique_id_field": "선택 ID",
                        "id_prefix": "choice",
                        "stable_id_field": "선택 키",
                        "field_map": {"선택 키": "choice_key"},
                    },
                }
            },
        }
        rows = {"choices": [{"_notion_id": "choice-page", "선택 ID": {"number": 5}, "이름": "선택", "설정 상태": "확정", "선택 키": "DAIMYO_RELINQUISH_TEA"}]}
        capture = CaptureBuilder(schema).build_from_rows(rows, "choice-v1")
        item = capture["datasets"]["choices"]["items"][0]
        self.assertEqual(item["id"], "daimyo_relinquish_tea")
        self.assertEqual(item["choice_key"], "DAIMYO_RELINQUISH_TEA")

    def test_missing_relation_target_fails_during_capture(self):
        self.rows["recipes"][0]["결과 아이템"] = ["missing-page"]
        with self.assertRaisesRegex(ExportValidationError, "recipes.*result_item_id.*missing-page"):
            CaptureBuilder(self.schema).build_from_rows(self.rows, "notion-fixture-v1")

    def test_legacy_name_override_bootstraps_existing_runtime_id(self):
        overrides = {
            "notion_pages": {},
            "legacy_names": {"items": {"목재": "wood"}},
        }
        capture = CaptureBuilder(self.schema, overrides).build_from_rows(
            self.rows, "notion-fixture-v1"
        )

        self.assertEqual(capture["datasets"]["items"]["items"][0]["id"], "wood")

    def test_live_flattened_attachment_fields_export_as_structured_arrays(self):
        rows = copy_rows(self.rows)
        rows["items"][0].update(
            {
                "종류": "다구",
                "장비 슬롯": "다구",
                "정붙음 단계 임계값": "0, 3, 7",
                "정붙음 설명 키": (
                    "items.oribe_bowl.attachment.stage_0, "
                    "items.oribe_bowl.attachment.stage_1, "
                    "items.oribe_bowl.attachment.stage_2"
                ),
                "태그": ["existing", "array"],
            }
        )

        capture = CaptureBuilder(self.schema, {"page-item": "oribe_bowl"}).build_from_rows(
            rows,
            "notion-fixture-v1",
        )
        snapshots = ExportPipeline(self.schema).build_snapshots(capture)
        item = snapshots["items"]["items"][0]

        self.assertEqual(item["attachment_stage_thresholds"], [0, 3, 7])
        self.assertEqual(
            item["attachment_description_keys"],
            [
                "items.oribe_bowl.attachment.stage_0",
                "items.oribe_bowl.attachment.stage_1",
                "items.oribe_bowl.attachment.stage_2",
            ],
        )
        self.assertEqual(item["tags"], ["existing", "array"])

    def test_attachment_list_string_threshold_input_still_exports_as_integers(self):
        rows = copy_rows(self.rows)
        rows["items"][0].update(
            {
                "종류": "다구",
                "장비 슬롯": "다구",
                "정붙음 단계 임계값": ["0", "3", "7"],
                "정붙음 설명 키": [
                    "items.oribe_bowl.attachment.stage_0",
                    "items.oribe_bowl.attachment.stage_1",
                    "items.oribe_bowl.attachment.stage_2",
                ],
            }
        )

        capture = CaptureBuilder(self.schema, {"page-item": "oribe_bowl"}).build_from_rows(
            rows,
            "notion-fixture-v1",
        )
        item = ExportPipeline(self.schema).build_snapshots(capture)["items"]["items"][0]

        self.assertEqual(item["attachment_stage_thresholds"], [0, 3, 7])

    def test_item_runtime_id_and_plain_interaction_json_export(self):
        rows = copy_rows(self.rows)
        rows["items"][0].update(
            {
                "런타임 ID": "stone_pickaxe",
                "상호작용 정의 JSON": '{"schema_version":1,"rules":[{"node_kind":"rock","action":"mine","required_tool_item_id":"stone_pickaxe"}],"tool_consumed":false}',
            }
        )

        capture = CaptureBuilder(self.schema).build_from_rows(rows, "notion-fixture-v1")
        item = ExportPipeline(self.schema).build_snapshots(capture)["items"]["items"][0]

        self.assertEqual(item["id"], "stone_pickaxe")
        self.assertEqual(
            item["interaction_definition"]["rules"][0]["required_tool_item_id"],
            "stone_pickaxe",
        )


if __name__ == "__main__":
    unittest.main()
