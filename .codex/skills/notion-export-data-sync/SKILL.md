---
name: notion-export-data-sync
description: Notion 콘텐츠·밸런스 데이터베이스를 게임용 정적 데이터로 반영하거나 생성 데이터, 내보내기 스키마, Notion 출처 지도를 점검할 때 사용한다.
metadata:
  short-description: Notion 내보내기 데이터 동기화
---

# Notion Export 데이터 동기화

Notion DB에서 export된 정적 데이터를 다룰 때 사용한다. 런타임은 Notion API를 직접 호출하지 않고 `data/generated/` 아래의 정의 데이터를 읽는다.

## 적용 대상

- `data/generated/*.json`
- `data/schemas/export_schema.json`
- `docs/notion-source-map.md`
- `tools/notion_export/`
- `src/core/data/`
- 데이터 로딩과 schema 검증 테스트

## 정본 매핑

- `data/generated/balance.json` → `⚖️ 밸런스 상수`
- `data/generated/biomes.json` → `지역·바이옴`
- `data/generated/teas.json` → `차 도감`
- `data/generated/items.json` → `아이템·다구`
- `data/generated/recipes.json` → `제작법`
- `data/generated/monsters.json` → `몬스터·요괴`
- `data/generated/abilities.json` → `요술`
- `data/generated/meta_unlocks.json` → `메타 해금`

## 작업 규칙

- 콘텐츠 이름 대신 안정적인 ID를 기준으로 연결한다.
- definition 데이터와 runtime state를 섞지 않는다.
- 수치와 공식은 코드에 하드코딩하지 않고 export 데이터에서 읽게 한다.
- 데이터 버전이 바뀌면 테스트 기대값과 source map도 함께 확인한다.
- 잘못된 데이터는 가능한 한 로딩 단계에서 명확한 오류로 드러나게 한다.

## 검증

- `data/generated/`의 JSON이 파싱되는지 확인한다.
- `DataCatalog` 또는 동일 책임의 데이터 로더 테스트를 실행한다.
- 월드 생성이나 저장 테스트가 데이터 버전에 의존하면 같이 실행한다.
- Godot가 사용 가능하면 `godot --headless --path . --script res://tests/test_runner.gd`를 우선 검증으로 사용한다.
