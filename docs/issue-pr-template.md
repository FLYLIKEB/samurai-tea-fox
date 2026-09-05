# GitHub Issue와 PR 템플릿

배송 규칙은 `AGENTS.md`와 `$samurai-tea-fox-ship`을 따른다. 이 문서는 복사할 본문 형식만 제공한다.

## Issue

제목: `DEV-<id>: <Notion 백로그 제목>`

```markdown
## 목표
<Notion 백로그의 목표>

## 범위
<이번 Issue에서 구현할 항목>

## 비범위
<구현하지 않을 항목>

## 완료 조건
<완료로 인정할 조건>

## 검증
<실행할 테스트나 확인 방법>

## Notion 정본
- 백로그: <DEV 행 URL>
- 기획 문서: <관련 문서>
- 정본 DB: <관련 DB 행 또는 해당 없음>

## PR 원칙
집중 PR 하나로 처리하고 `Closes #<issue-number>`를 사용한다.
```

## 작업 시작 코멘트

```markdown
Codex 작업 시작

- Notion: DEV-<id> <Notion URL>
- Branch: <branch>
- Worktree: <worktree path>
- Started: <ISO-8601 datetime>
- Agent: <식별자가 있을 때만>
```

## PR

```markdown
## 요약
- <구현 요약>

## Notion 정합성
- 백로그: <DEV 행 URL>
- 기획 문서: <확인한 문서>
- 정본 DB: <사용한 DB 행 또는 해당 없음>

## 테스트
- [x] <command> - <result>

## 범위 통제
- 범위 밖 발견 사항은 구현하지 않았다.

Closes #<issue-number>
```

검증 실패나 차단 상태를 성공처럼 작성하지 않는다.
