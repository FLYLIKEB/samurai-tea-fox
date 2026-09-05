---
name: notion-backlog-issue-runner
description: 무차우 Notion AI 구현 백로그 한 건을 Issue와 PR로 실행할 때 프로젝트 배송 스킬로 연결한다.
metadata:
  short-description: Notion 백로그 배송 라우터
---

# Notion 백로그 이슈 실행

`DEV-*`, 다음 백로그, 또는 Notion 백로그 기반 구현 요청에 적용한다.

1. 사용자 전역 `$samurai-tea-fox-ship`을 읽고 따른다.
2. repo-local `isolated-worktree-pr`을 함께 적용한다.
3. 본문 형식이 필요할 때만 `docs/issue-pr-template.md`를 읽는다.

이 스킬은 배송 계약을 재정의하지 않는다. 질문·분석·계획·백로그 작성만 요청받으면 구현이나 선점을 시작하지 않는다.
