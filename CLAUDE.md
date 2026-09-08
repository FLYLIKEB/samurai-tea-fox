# CLAUDE.md — 무차우: 한 잔의 도 구현 가이드

**Godot 4.x + GDScript** 기반 2D 픽셀 로그라이크 게임 프로젝트.

## 기본 원칙

See [AGENTS.md](AGENTS.md) for authority hierarchy and scope rules. This file documents code patterns and local conventions.

## 코드 패턴

### 절차적 사운드 생성 (UI 효과음)

**Pattern**: WAV 자산 의존 대신 runtime에서 AudioStreamWAV PCM 생성.

작은 UI 효과음(예: 텍스트 reveal beep)은 자산 파이프라인 오버헤드를 피하기 위해 절차적으로 생성한다.

**구현 예**: `src/ui/dialogue_text_effect.gd::_generate_beep_stream()`
- 상수로 정의된 beep 특성: `BEEP_SAMPLE_RATE`, `BEEP_FREQ_START`, `BEEP_FREQ_END`, `BEEP_DURATION`
- 진폭(0.9), 어택/릴리즈 감쇠 설정
- 필요시 `voice_pitch` 파라미터로 런타임 톤 조정 가능 (캐릭터별 목소리)

**When to apply**: 짧고 단순한 UI 사운드는 절차 생성 고려. 복잡하거나 오래 재생되는 음악/음성은 WAV 자산 사용.

---

## 전체 화면 오버레이 입력 차단

**Pitfall**: `ColorRect` / `Label` 의 `mouse_filter` 기본값은 `STOP`. 투명(`modulate.a = 0.0`)해도 클릭을 삼킨다. 상시 마운트되는 `CanvasLayer` 안에 full-rect 로 배치하면, HUD 보다 트리에 나중에 추가된 경우 (같은 layer) 게임 전체 입력을 막는다.

**Rule**: 순수 시각 효과용 오버레이 Control 은 `mouse_filter = Control.MOUSE_FILTER_IGNORE` 를 명시한다.

**구현 예**: `src/ui/sleep_transition_presenter.gd` (fade rect + label 둘 다 IGNORE)

**검증**: headless 스크립트로 자식 노드의 `mouse_filter` 확인, 또는 라이브 실행 중 scene tree dump 로 sibling 순서/layer 확인.

---

## UI 텍스트 효과

**Class**: `DialogueTextEffect` (extends Label)

문자 단위 텍스트 공개 애니메이션 (동물의숲 대화 스타일).

**Public API**:
- `start_reveal(text: String, voice_pitch: float = 1.0)` — 텍스트 공개 시작
- `skip_to_end()` — 즉시 완성
- `is_revealing() -> bool` — 공개 중인지 확인

**Signals**:
- `text_reveal_started`
- `text_reveal_completed`

**Parameters**:
- `REVEAL_SPEED = 0.05` (문자당 50ms)
- `SOUND_INTERVAL = 0.08` (음성 재생 간격)
- `DEFAULT_VOICE_PITCH = 1.0`

**Integration**: `narrative_dialogue_presenter.gd`에서 사용. 대사 표시 시 `_voice_pitch_for_speaker(speaker_id)` 조회하여 캐릭터별 톤 지정.

---

## 테스트 및 검증

See [README.md](README.md) for test commands.

**Before completing a task**:
1. Run targeted unit/integration tests for changed modules
2. If scene/resource changes: `tools/asset_pipeline/check.sh`
3. If Godot changes needed: headless smoke check via `godot --headless --path . --script ...`
4. Report test results and verification method in Korean

---

## Memory & Authority

- **Project memory**: `~/.claude/projects/-Users-jwp-Developer-samurai-tea-fox/memory/`
- **Authority hierarchy**: See [AGENTS.md](AGENTS.md)
- **Related memories**: [[project_setup]], [[dialogue_text_reveal]]
