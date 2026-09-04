# Notion 정본 Export

Notion은 편집 정본이며 Godot 런타임은 Notion API를 호출하지 않는다. 배포와 테스트는 `data/generated/`의 정적 JSON snapshot만 읽는다.

## 계약

- `data/schemas/export_schema.json`: 데이터셋, Notion 속성 매핑, 필수값, 상태 profile, relation 계약
- `data/schemas/runtime_id_map.json`: 기존 런타임 ID 보존용 page/name override
- `schema_version`: loader와 export 형식의 호환 버전
- `data_version`: 한 번의 동기화에서 생성된 모든 파일의 정본 버전
- `content_hash`: `content_hash`를 제외한 canonical JSON의 SHA-256
- `confirmed`: `확정`만 포함
- `confirmed-test`: `확정`, `테스트`, `초안` 포함
- `폐기`는 모든 profile에서 제외

## Notion 동기화

Notion integration token을 환경변수로 제공하고 15개 런타임 정본 DB를 한 번에 snapshot으로 만든다. `art_assets`는 별도 제작 파이프라인용 계약이므로 런타임 `sync`에서는 제외한다.

```bash
NOTION_ACCESS_TOKEN=... python3 -m tools.notion_export sync \
  --output data/generated \
  --data-version notion-YYYY-MM-DD \
  --profile confirmed-test
```

동기화는 page ID override를 우선하고, 기존 데이터 이관 중에는 데이터셋별 이름 override를 사용한다. 처음 확인된 page ID는 `runtime_id_map.json`에 기록되어 이후 제목 변경과 무관하게 같은 런타임 ID를 유지한다. 새 행은 Notion `UNIQUE_ID`를 `{dataset_prefix}_{number}` 형식으로 변환한다.

이미 캡처한 JSON을 재현 가능하게 export할 수도 있다.

```bash
python3 -m tools.notion_export export \
  --input tests/fixtures/notion_export/source.json \
  --output /tmp/notion-export \
  --profile confirmed-test
```

## 검증

```bash
tools/notion_export/check.sh
```

단일 명령이 Python exporter/API client 테스트, snapshot 해시·schema·relation 검증, Godot loader smoke를 실행한다. 누락 필드, 중복 ID, 끊어진 relation, profile/version 불일치는 로드 전에 실패한다.
