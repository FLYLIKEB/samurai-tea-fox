# Codex 실행 절차

구현 작업의 정본은 다음 문서로 나눈다.

- 프로젝트 불변조건·완료 기준: [AGENTS.md](../AGENTS.md)
- Notion 백로그 배송: `$samurai-tea-fox-ship`
- Git 격리·PR·main 복귀: `.codex/skills/isolated-worktree-pr/SKILL.md`
- Issue·PR 본문 형식: [issue-pr-template.md](issue-pr-template.md)
- Notion 책임 위치: [notion-source-map.md](notion-source-map.md)

## 실행 흐름

1. 저장소 상태와 기존 Issue·PR·worktree를 확인한다.
2. `00` → `12` → 현재 백로그/Issue → 직접 연결된 문서·DB만 읽는다.
3. 목표, 범위, 비범위, 완료 조건, 선행 작업과 검증을 한 번 요약한다.
4. Notion과 GitHub 양쪽에 작업 시작 표시를 남긴다.
5. 최신 `origin/main` 기반 전용 worktree에서만 구현·검증·PR 작업을 한다.
6. PR 머지 뒤 Notion을 완료 처리하고 기준 checkout을 `main`으로 복귀·동기화한다.

지정 항목이 `진행 중`·`완료`이거나 선행 작업, 정본, 권한, 중복 방지가 충족되지 않으면 구현하지 않는다. 범위 밖 발견은 후속 Issue 후보로 남긴다.

## 컨텍스트 절약

- 처음 만든 작업 요약과 도구 원문을 재사용한다.
- 변경 파일·통계를 먼저 보고 위험 구간과 관련 테스트만 펼친다.
- 상세 로그는 파일에 남기고 상태·실패·핵심 diff만 보고한다.
- 장시간 작업은 종료 알림 중심으로 기다린다.
- 저장 격리, 백업, 대상 경로·해시 확인은 생략하지 않는다.
