# Architecture

## Boundary

The game is a Godot 4.x project written in GDScript. It is not a web game and does not reuse `roguelike-survivor` code.

The runtime boundary is:

```text
Notion planning DB
  -> exported static data
  -> runtime definition
  -> runtime state
  -> presentation
```

Godot scenes and UI do not own domain state. They translate input into commands, render current state, and call explicit APIs.

## Domain Modules

- `core`: command layer, stable IDs, deterministic RNG, data catalog
- `player`: HP, 기운, 心, tails, player state
- `combat`: basic attack, dodge, damage, invulnerability windows
- `tea`: brewing, prepared tea, drinking timing, ki recovery
- `inventory`: slot inventory, stack limits, serialization
- `crafting`: recipe validation, instant crafting, facility requirements
- `world`: biome definitions, deterministic generation, connectivity validation
- `dungeon`: required biome dungeon and boss entry points
- `enemy`: definition-driven enemy behavior categories
- `ability`: ki-consuming yokai abilities
- `time`: day/night and sleep transitions
- `save`: versioned run save and meta save codecs
- `meta`: run-end unlock conditions and persistent records
- `ui`: HUD/menu presentation and input adapters only

## Command Layer

Platform input must become `GameCommand` objects before touching game logic.

Keyboard, controller, and mobile controls may differ visually, but they must call the same command API:

```text
Input adapter -> GameCommand -> domain service -> runtime state update -> UI observes state
```

## World Generation

World generation is deterministic by contract:

```text
seed
  -> biome definition
  -> chunk/rule composition
  -> required landmark placement
  -> resource/enemy placement
  -> connectivity validation
  -> retry or accept
  -> visual TileMapLayer rendering
```

The generator creates world data. A later renderer is responsible for TileMapLayer presentation.

## Save Boundary

`run save` contains current run-only state:

- map seed/progress
- inventory/currency
- tails/abilities
- teleport and current-run crafting unlocks

`meta save` contains persistent state:

- run count
- codex/discovery records
- best reached biome
- meta unlocks and dialogue conditions

Death discards run save and updates only eligible meta records. Mid-run save is for continuing the current run, not death rollback.


## Main 기능 구성

Main의 기능별 협력 객체, 상태 소유권, 장면 전환 순서는 [Main의 기능별 구성](main-composition.md)을 따른다.

## HUD 기능 구성

`GameHud`는 공개 API, read model 전달, 메뉴 전환, 명령·신호 연결과 화면 전체 배치를 담당한다. `src/ui/hud/`의 컴포넌트는 다음 표시 상태와 노드를 직접 관리한다.

- `status_toast_presenter.gd`: 토스트 대기열, 중복 방지, 표시 시간과 알림 노드.
- `status_panel_presenter.gd`: HP·기운·心 아이콘, 자원 상세창과 장비 슬롯.
- `map_panel_presenter.gd`: 미니맵, 시간 표시, 전체 지도, 지역 선택과 이동 메뉴.
- `mobile_controls_presenter.gd`: 방향키, 행동 버튼과 메뉴 바로가기.
- `settings_presenter.gd`: 설정창 열림 상태, 음량 조절과 시작 화면 복귀 요청.

컴포넌트에는 표시할 데이터와 필요한 UI 협력 객체만 전달한다. `GameHud`나 런타임 서비스 전체를 넘기지 않으며, 게임 상태 변경은 기존 명령 계층으로 보낸다. 공용 메뉴 내용은 기존 menu builder를 재사용한다.
