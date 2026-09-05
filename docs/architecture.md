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
