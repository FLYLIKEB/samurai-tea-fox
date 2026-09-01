# AGENTS.md — 무사여우 구현 계약

이 저장소는 **Godot 4.x + GDScript** 기반 2D 픽셀 로그라이크 게임 **Samurai Tea Fox / 무사여우: 한 잔의 도** 프로젝트다.

Codex와 기타 AI 코딩 에이전트는 이 문서를 저장소의 최상위 구현 계약으로 따른다.

## 정본 역할

- **Repository**: 현재 실제 구현 상태의 정본이다. 수정 전에 구조, 기존 코드, 공개 API, 테스트, 문서 규칙을 확인한다.
- **Notion**: 게임 기획, 시스템 의도, 콘텐츠, 밸런스의 정본이다. 기억이나 추측으로 게임 규칙, 콘텐츠 값, 밸런스 수치, 에셋 요구사항을 만들지 않는다.
- **GitHub Issue**: 이번 작업 범위의 정본이다. 한 번에 하나의 Issue만 구현하고, 비범위 작업은 후속 Issue 후보로만 남긴다.

## 정본 우선순위

정보가 충돌하면 다음 순서를 따른다.

1. `00. 기획 아키텍처·정본 규칙`
2. `12. 기술 스펙·아키텍처`
3. 현재 GitHub Issue 또는 Notion `🤖 AI 구현 백로그` 항목
4. 관련 시스템 설계 문서
5. 관련 콘텐츠 또는 밸런스 DB
6. 오래된 설명이나 예시

예외: 정확한 콘텐츠 값과 수치·공식은 항상 관련 정본 DB를 우선한다.

## Notion 기준

- 라우팅 인덱스: `무사여우: 한 잔의 도 — 게임 컨셉 바이블`
- 정보 책임: `00. 기획 아키텍처·정본 규칙`
- 기술 정본: `12. 기술 스펙·아키텍처`
- 작업 범위: `🤖 AI 구현 백로그`
- Notion 매핑: [docs/notion-source-map.md](docs/notion-source-map.md)

`전체 정본 확인`은 모든 Notion 페이지를 전부 읽는다는 뜻이 아니다. 루트 페이지를 인덱스로 삼고, 현재 Issue에 필요한 관련 기획 문서와 정본 DB 행만 정밀하게 확인한다.

## 기술 문서

- 아키텍처와 모듈 경계: [docs/architecture.md](docs/architecture.md)
- 대상 플랫폼과 export 원칙: [docs/export-targets.md](docs/export-targets.md)
- Codex 실행 절차: [docs/codex-workflow.md](docs/codex-workflow.md)
- Issue/PR 템플릿: [docs/issue-pr-template.md](docs/issue-pr-template.md)
- 이미지 생성과 픽셀아트 스타일 토큰: [assets/style/art-style-tokens.json](assets/style/art-style-tokens.json)

## 절대 제약

- 플레이어 상시 자원은 `HP / 기운 / 心`만 사용한다.
- `MP`, `SP`, stamina, hunger, thirst, body temperature, fatigue 게이지를 추가하지 않는다.
- 차는 기본적으로 `Camellia sinensis` 기반 차로 취급한다.
- Biome 진행 순서는 고정이고, 각 biome 내부 맵만 런마다 절차 생성한다.
- 런타임 코드는 Notion API를 직접 호출하지 않는다.
- `data/generated/`의 export 데이터는 런타임에서 immutable definition data다.
- definition data와 runtime state를 섞지 않는다.
- run save와 meta save는 논리적으로 분리한다.
- 런 종료 시 아이템, 화폐, 꼬리, 요술, 텔레포트 상태, 제작 해금 등 런 내부 성장은 초기화한다.
- 센리큐와 구미호 아버지는 meta save 상태를 통해 이전 런을 기억할 수 있다.
- UI는 game logic을 소유하지 않는다. UI는 상태를 관찰하고 command를 보낸다.
- 콘텐츠 이름별 조건문 성장을 피하고 stable ID와 data-driven definition을 사용한다.
- 색상 팔레트, 공통 시각 컨셉, 이미지 생성용 prompt token은 `assets/style/art-style-tokens.json`에서만 관리한다.
- 모든 캐릭터, 맵, 맵 내 사물 에셋은 정사각형 타일 기반 탑뷰 로그라이크 가독성을 위해 정면을 보게 제작한다. 측면, 후면, 3/4, 아이소메트릭 시점 에셋을 만들지 않는다.

## 구현 규칙

- 수정 전에 `git status --short`, 현재 브랜치, 저장소 구조를 확인한다.
- 관련 없는 local change를 덮어쓰거나 PR에 섞지 않는다.
- gameplay 구현은 한 GitHub Issue 또는 Notion 백로그 항목 단위로 제한한다.
- 기존 시스템이 있으면 확장하고, 같은 시스템을 다시 만들지 않는다.
- 현재 구조가 합리적이면 문서의 예시 구조보다 현재 구조를 우선한다.
- `roguelike-survivor` 코드는 재사용하지 않는다. deterministic generation, platform-independent command layer, versioned saves, mobile + desktop target 같은 원칙만 참고한다.
- 현재 작업이 명시적으로 필요로 하지 않는 dependency를 추가하지 않는다.
- 범위 밖 리팩터링, 밸런스 조정, UI polish, 미래 기능용 framework는 구현하지 않는다.

## 테스트와 완료 기준

- pure domain, generation, save, data validation 동작은 가능한 한 자동 테스트로 검증한다.
- 변경 범위에 맞는 targeted test를 먼저 실행하고, 필요하면 Godot import/build/smoke check를 실행한다.
- 관련 테스트나 검증이 실패한 상태에서는 완료라고 주장하지 않는다.
- 검증을 실행할 수 없으면 이유와 대신 수행한 확인을 명확히 보고한다.

## 완료 보고

작업 완료 보고는 한국어로 작성하고 다음 항목을 포함한다.

- 변경 파일
- 구현 내용
- 설계 결정
- Notion 정합성
- 테스트 결과
- 남은 위험
- 후속 Issue 후보
- PR URL 또는 차단 사유
