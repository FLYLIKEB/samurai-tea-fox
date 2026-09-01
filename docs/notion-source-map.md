# Notion Source Map

Fetched on 2026-09-01 from the current Notion workspace.

## Pages

| Responsibility | Notion source |
| --- | --- |
| Routing index | `무사여우: 한 잔의 도 — 게임 컨셉 바이블` |
| Information ownership | `00. 기획 아키텍처·정본 규칙` |
| Technical architecture | `12. 기술 스펙·아키텍처` |
| Gameplay prototype rules | `11. 상세 게임플레이 규칙` |
| Art, map, UI direction | `09. 아트디렉션·맵·UI` |

## Databases

| Runtime file | Notion DB | Data source |
| --- | --- | --- |
| `assets/sprites/characters/notion-character-map.json` | `캐릭터 목록` | `collection://86d9c16b-e60e-4434-9c84-26b4b00d16c8` |
| `data/generated/balance.json` | `⚖️ 밸런스 상수` | `collection://dd8249a2-14e5-4a96-b26d-77ce33fdc43c` |
| `data/generated/biomes.json` | `지역·바이옴` | `collection://d4b40007-096f-4528-8840-53de80bda0dd` |
| `data/generated/teas.json` | `차 도감` | `collection://58c6edaf-0851-48da-a412-541be09d7dcb` |
| `data/generated/items.json` | `아이템·다구` | `collection://cc4817d1-bb64-45b0-9193-b3c742327064` |
| `data/generated/recipes.json` | `제작법` | `collection://a755c8a9-1e5f-4f04-9ede-4ee63caa0663` |
| `data/generated/monsters.json` | `몬스터·요괴` | `collection://8058308e-e875-45aa-929c-49fd8575601a` |
| `data/generated/abilities.json` | `요술` | `collection://011bff45-d1e8-4d8a-a52d-bbf6c06a3566` |
| `data/generated/meta_unlocks.json` | `메타 해금` | `collection://7927bdc1-70eb-4fe7-82c5-971c74caa5d3` |
| `data/generated/dungeons.json` | `던전·보스` | `collection://cd97553c-f51f-44fe-9604-c257cc9d9342` |
| `data/generated/choices.json` | `선택 결과` | `collection://943e27c2-91e1-40ec-a5e9-30ef62737a40` |
| `data/generated/art_assets.json` | `아트 에셋` | `collection://744f6e01-4531-42b4-82fd-b66b468e45fa` |

전체 매핑과 profile 규칙은 `data/schemas/export_schema.json`이 실행 정본이다. 현재 Godot 카탈로그가 사용하는 8개 파일 외 데이터셋도 같은 export 계약으로 생성되며, 해당 런타임 모듈이 활성화될 때 `DataCatalog.FILES`에 추가한다.
