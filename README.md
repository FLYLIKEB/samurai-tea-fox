# 무사여우: 한 잔의 도

Godot 4.x + GDScript 기반의 top-down 32x32 pixel-art roguelike RPG입니다.

이 저장소는 Notion 문서 **무사여우: 한 잔의 도 — 게임 컨셉 바이블**을 기획 정본으로 사용합니다. 게임 런타임은 Notion API를 직접 호출하지 않고, `data/generated/` 아래에 export된 정적 데이터를 읽습니다.

## 정본

- 기획 라우팅 인덱스: `무사여우: 한 잔의 도 — 게임 컨셉 바이블`
- 정보 책임: `00. 기획 아키텍처·정본 규칙`
- 기술 선택과 구현 경계: `12. 기술 스펙·아키텍처`
- 개별 콘텐츠와 수치: Notion 콘텐츠 DB와 `⚖️ 밸런스 상수`

충돌 시 우선순위는 `00 정본 규칙 -> 12 기술 스펙 -> 현재 백로그 이슈 -> 해당 시스템 문서 -> 콘텐츠/밸런스 DB -> 오래된 설명`입니다. 단, 정확한 콘텐츠 값과 수치는 항상 해당 DB가 우선합니다.

## 기술 원칙

- Engine: Godot 4.x
- Language: GDScript
- Targets: mobile + desktop
- Graphics: 32x32 기반 저해상도 픽셀아트, nearest filtering, 정수 배율 우선, 캐릭터·맵·맵 내 사물 정면 고정
- AI Source: AI 생성 raw와 중간 후보는 `assets/source/imagegen/`에만 보관하고 Git에는 올리지 않음
- Map: TileMapLayer + 데이터 주도 월드 생성
- Data: Notion planning DB -> exported static data -> runtime definition -> runtime state
- Save: run save와 meta save 분리, schema version 필수
- Input: keyboard/touch/gamepad 입력은 platform-independent game command로 변환

## 구조

```text
assets/
  source/
    imagegen/  # AI 생성 raw와 중간 후보, Git 제외
  sprites/
  tiles/
  ui/
  audio/
data/
  generated/
  schemas/
docs/
scenes/
src/
  core/
    commands/
    data/
    rng/
  player/
  combat/
  tea/
  inventory/
  crafting/
  world/
    biome/
    generation/
  dungeon/
  enemy/
  ability/
  time/
  save/
  meta/
  ui/
tests/
tools/
  asset_browser/
  notion_export/
```

## 도구

에셋 이미지를 로컬 앱에서 확인하고 선택한 경로나 Codex용 프롬프트를 복사하려면:

```sh
tools/asset_browser/run.sh
```

앱 본체는 별도 레포 `https://github.com/FLYLIKEB/samurai-tea-fox-asset-browser`에서 관리하고,
현재 레포에는 무사여우 전용 프롬프트 템플릿과 launcher만 둡니다.

## 게임 실행

Godot 편집기에서 프로젝트를 연 뒤 `F6`이 아닌 `F5`를 누르거나, 저장소 루트에서 다음 명령을 실행합니다.

```sh
godot --path .
```

플레이어는 `W`, `A`, `S`, `D`로 이동하고 `J`로 검 공격, `K`로 회피합니다. 이동과 회피는 벽과 장애물을 통과하지 않으며 카메라는 플레이어를 따라갑니다.

## 검증

Godot가 설치된 환경에서:

```sh
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/integration/test_player_scene_runner.gd
godot --headless --path . --script res://tests/integration/test_player_combat_runner.gd
```

현재 테스트 골격은 다음 경계를 확인합니다.

- 같은 seed + 같은 data version은 같은 월드 데이터를 생성한다.
- 플랫폼 입력은 게임 명령으로만 변환된다.
- 플레이어 이동 방향, 대각선 속도, 벽 충돌, 카메라 연결을 확인한다.
- 기본 공격 피해, 중복 피해 방지, 피격 무적, 회피 무적·쿨다운·벽 충돌을 확인한다.
- run save와 meta save는 schema version과 kind를 분리한다.

Godot 설치 전에도 프로젝트 진입점, 공통 입력 명령 경계, 데스크톱·모바일 export template을 정적으로 확인할 수 있습니다.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_project_contract
```
