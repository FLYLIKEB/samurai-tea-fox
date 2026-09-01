import unittest

from tools.notion_export.notion_client import NotionClient


class FakeNotionClient(NotionClient):
    def __init__(self, responses):
        super().__init__("test-token")
        self.responses = list(responses)
        self.requests = []

    def _request(self, method, path, body=None):
        self.requests.append((method, path, body))
        return self.responses.pop(0)


class NotionClientTests(unittest.TestCase):
    def test_query_data_source_follows_opaque_cursors(self):
        client = FakeNotionClient(
            [
                {"results": [{"id": "page-1"}], "has_more": True, "next_cursor": "cursor-1"},
                {"results": [{"id": "page-2"}], "has_more": False, "next_cursor": None},
            ]
        )

        pages = client.query_data_source("collection://source-id")

        self.assertEqual([page["id"] for page in pages], ["page-1", "page-2"])
        self.assertEqual(client.requests[0][1], "/v1/data_sources/source-id/query")
        self.assertEqual(client.requests[1][2]["start_cursor"], "cursor-1")

    def test_flatten_page_normalizes_supported_properties_and_full_relations(self):
        client = FakeNotionClient(
            [
                {
                    "object": "list",
                    "results": [
                        {"type": "relation", "relation": {"id": "target-2"}}
                    ],
                    "has_more": False,
                    "next_cursor": None,
                }
            ]
        )
        page = {
            "id": "page-1",
            "properties": {
                "이름": {
                    "id": "title-id",
                    "type": "title",
                    "title": [{"plain_text": "목재"}],
                },
                "설정 상태": {
                    "id": "status-id",
                    "type": "select",
                    "select": {"name": "확정"},
                },
                "값": {"id": "number-id", "type": "number", "number": 3},
                "사용": {"id": "check-id", "type": "checkbox", "checkbox": True},
                "태그": {
                    "id": "tags-id",
                    "type": "multi_select",
                    "multi_select": [{"name": "A"}, {"name": "B"}],
                },
                "관계": {
                    "id": "f%5C%5C%3Ap",
                    "type": "relation",
                    "relation": [{"id": "target-1"}],
                    "has_more": True,
                },
                "고유 ID": {
                    "id": "unique-id",
                    "type": "unique_id",
                    "unique_id": {"prefix": "ART", "number": 8},
                },
            },
        }

        row = client.flatten_page(page)

        self.assertEqual(row["_notion_id"], "page-1")
        self.assertEqual(row["이름"], "목재")
        self.assertEqual(row["설정 상태"], "확정")
        self.assertEqual(row["값"], 3)
        self.assertTrue(row["사용"])
        self.assertEqual(row["태그"], ["A", "B"])
        self.assertEqual(row["관계"], ["target-1", "target-2"])
        self.assertEqual(row["고유 ID"], {"prefix": "ART", "number": 8})
        self.assertTrue(client.requests[0][1].startswith("/v1/pages/page-1/properties/f%5C%5C%3Ap?"))
        self.assertNotIn("%25", client.requests[0][1])


if __name__ == "__main__":
    unittest.main()
