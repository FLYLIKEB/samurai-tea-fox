# Notion 정본 출처 지도

2026-09-04 기준 현재 Notion workspace와 Repository 구현을 대조했다.

## 문서 정본

| 책임 | Notion 정본 |
| --- | --- |
| 라우팅 인덱스 | `무차우: 한 잔의 도 — 게임 컨셉 바이블` |
| 정보 책임 경계 | `00. 기획 아키텍처·정본 규칙` |
| 기술 아키텍처 | `12. 기술 스펙·아키텍처` |
| 상세 게임플레이 규칙 | `11. 상세 게임플레이 규칙` |
| 아트·맵·UI 방향 | `09. 아트디렉션·맵·UI` |
| 구현 작업 범위 | `🤖 AI 구현 백로그`와 연결된 GitHub Issue |

## 런타임 데이터 카탈로그

`src/core/data/data_catalog.gd`의 `DataCatalog.FILES`가 아래 15개 immutable definition dataset을 필수로 읽는다. 각 생성 파일의 `source`가 실제 export 출처이며, `data/schemas/export_schema.json`이 필드·relation·profile 계약의 실행 정본이다.

| 런타임 파일 | 현재 source | Notion 정본 DB |
| --- | --- | --- |
| `data/generated/balance.json` | `collection://dd8249a2-14e5-4a96-b26d-77ce33fdc43c` | `⚖️ 밸런스 상수` |
| `data/generated/biomes.json` | `collection://d4b40007-096f-4528-8840-53de80bda0dd` | `지역·바이옴` |
| `data/generated/dungeons.json` | `collection://cd97553c-f51f-44fe-9604-c257cc9d9342` | `던전·보스전` |
| `data/generated/teas.json` | `collection://58c6edaf-0851-48da-a412-541be09d7dcb` | `차 도감` |
| `data/generated/items.json` | `collection://cc4817d1-bb64-45b0-9193-b3c742327064` | `아이템·다구` |
| `data/generated/recipes.json` | `collection://a755c8a9-1e5f-4f04-9ede-4ee63caa0663` | `제작법` |
| `data/generated/monsters.json` | `collection://8058308e-e875-45aa-929c-49fd8575601a` | `몬스터·요괴` |
| `data/generated/drops.json` | `collection://362e7813-5332-420b-aca0-fb2824dbcce0` | `🎁 드롭 테이블` |
| `data/generated/abilities.json` | `collection://011bff45-d1e8-4d8a-a52d-bbf6c06a3566` | `요술` |
| `data/generated/meta_unlocks.json` | `collection://7927bdc1-70eb-4fe7-82c5-971c74caa5d3` | `메타 해금` |
| `data/generated/events.json` | `collection://671bff29-b822-4706-87b2-64fc4cff057d` | `🎬 인게임 대사 스크립트` |
| `data/generated/choices.json` | `collection://943e27c2-91e1-40ec-a5e9-30ef62737a40` | `선택·결과` |
| `data/generated/characters.json` | `collection://86d9c16b-e60e-4434-9c84-26b4b00d16c8` | `캐릭터 목록` |
| `data/generated/shops.json` | `collection://3f6354ff-02fb-4b92-9b81-9f821ae6408b` | `상점·거래` |
| `data/generated/bosses.json` | `collection://7bd9f233-5ff4-40aa-ad2a-08d146ea1475` | `런타임 보스 정의` |

`events.json`은 루트 정본의 대사 작업대가 관리하는 `🎬 인게임 대사 스크립트` DB의 런타임 이벤트 ID별 대사 행을 노드·선택지 객체로 묶어 생성한다. 상태가 `검토 필요`인 비런타임 대사 묶음만 명시적으로 제외하며, 그 밖의 행에 런타임 이벤트 ID가 없으면 export를 실패시킨다. 개별 스토리 사건의 상위 기획 책임은 `스토리·퀘스트` DB가 소유한다.

`bosses.json`은 `런타임 보스 정의` DB의 검증된 `정의 JSON`을 사용한다. `던전·보스전` DB는 던전별 보스 이름·HP·페이즈 수 같은 상위 설계를 소유하고, 런타임 패턴·소환·다도 해결 구조는 보스 정의 DB가 소유한다.

## 보조 출처와 에셋 경계

- `data/generated/notion_sources.json`은 export 출처를 추적하는 보조 source map이며 런타임 데이터셋이 아니다. `DataCatalog`는 각 생성 파일의 `source`를 직접 읽는다.
- `data/schemas/export_schema.json`은 `art_assets.json` export 계약도 정의하지만, 현재 `data/generated/art_assets.json`은 생성되지 않으며 `DataCatalog.FILES`에도 포함되지 않는다.
- 런타임 이미지 경로는 `src/core/data/asset_catalog.gd`의 `AssetCatalog`가 `assets/asset-manifest.json`을 통해 조회한다.
- `assets/sprites/characters/notion-character-map.json`은 캐릭터와 승격 에셋을 대조하기 위한 보조 매핑이며 `DataCatalog` dataset이 아니다.

## 유지 규칙

1. `DataCatalog.FILES`를 변경하면 이 문서의 런타임 목록과 `tests/tools/test_project_contract.py`의 계약 검증을 함께 갱신한다.
2. 생성 파일을 갱신할 때는 파일 내부의 `source`, `data_version`, `schema_version`, `profile`을 검증한다.
3. Notion의 개별 콘텐츠 값과 수치는 이 문서에 복제하지 않고 해당 DB 행과 export snapshot을 따른다.
4. 아트 에셋 DB, export용 `art_assets` dataset, 런타임 asset manifest의 책임을 섞지 않는다.
