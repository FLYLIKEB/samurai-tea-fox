# AGENTS.md

## Project Contract

This repository implements **무사여우: 한 잔의 도** as a Godot 4.x + GDScript project.

Notion is the planning source of truth. Do not add game rules, content facts, balance values, or asset requirements from memory when a Notion source exists.

## Source Of Truth

- Routing index: `무사여우: 한 잔의 도 — 게임 컨셉 바이블`
- Information ownership: `00. 기획 아키텍처·정본 규칙`
- Technical architecture: `12. 기술 스펙·아키텍처`
- Work scope: `🤖 AI 구현 백로그`
- Content rows: relevant Notion content databases
- Numeric values and formulas: `⚖️ 밸런스 상수` or the relevant content DB

Conflict priority:

1. `00. 기획 아키텍처·정본 규칙`
2. `12. 기술 스펙·아키텍처`
3. Current backlog issue
4. Relevant system document
5. Relevant content or balance database
6. Older prose/examples

Exact content values and numeric values always come from the relevant database.

## Hard Constraints

- Persistent player resources are only `HP / 기운 / 心`.
- Do not add `MP`, `SP`, stamina, hunger, thirst, body temperature, or fatigue gauges.
- Biome progression order is fixed. Only the inside of each biome map is randomized per run.
- Runtime code must not call Notion.
- Exported data in `data/generated/` is immutable definition data at runtime.
- Runtime state and definition data must stay separate.
- Run save and meta save must stay logically separate.
- Run-end growth, items, currency, tails, abilities, teleport state, and crafting unlocks reset with the run.
- Sen Rikyu and the gumiho father may remember previous runs through meta save state.
- UI must not own game logic. UI observes state and sends commands.
- Avoid content-name conditionals. Use stable IDs and data-driven definitions.

## Implementation Rules

- Read the repository structure before editing.
- Work one backlog issue at a time when implementing gameplay.
- Keep diffs small and scoped.
- Do not reuse code from `roguelike-survivor`.
- Reuse only principles: deterministic generation, platform-independent command layer, versioned saves, mobile + desktop targets.
- Do not add dependencies unless a current task explicitly needs them.
- Add tests for pure domain, generation, save, and data validation behavior.
- Verify with relevant tests and Godot import/build checks before claiming completion.

## Completion Report

Use this shape:

- Changed files
- Implementation summary
- Design decisions
- Test result
- Remaining risks
- Follow-up issue candidates

