---
name: notion-backlog-issue-runner
description: 이 프로젝트에서 Notion AI 구현 백로그 한 건을 선택하거나 지정받아 GitHub 이슈, 구현, 검증, 풀 리퀘스트까지 한 작업 단위로 처리할 때 사용한다.
metadata:
  short-description: Notion 백로그 한 건 실행 흐름
---

# Notion 백로그 이슈 실행

`무사여우: 한 잔의 도` 저장소에서 Notion `🤖 AI 구현 백로그` 항목 하나를 실행할 때 사용한다. 목표는 백로그 한 건을 GitHub Issue 하나와 PR 하나로 끝내는 것이다.

## 적용 조건

- 사용자가 `DEV-*` 또는 Notion 백로그 항목 구현을 요청한다.
- 사용자가 “다음 작업”, “백로그 하나”, “이슈 만들어서 구현”처럼 Notion 구현 백로그 기반 작업을 요청한다.
- 이미 GitHub Issue가 있더라도 그 Issue가 Notion 백로그 한 건과 연결되는 작업이면 적용한다.

## 필수 순서

1. 루트 바이블의 `AI_CONTEXT`를 확인한다.
2. `00. 기획 아키텍처·정본 규칙`에서 정보 책임과 충돌 우선순위를 확인한다.
3. `12. 기술 스펙·아키텍처`에서 구현 경계와 테스트 규칙을 확인한다.
4. `🤖 AI 구현 백로그`에서 현재 작업 항목 하나만 선택하거나 지정 항목을 찾는다. `상태`가 `진행 중` 또는 `완료`인 항목은 새 작업 대상으로 선택하지 않는다.
5. 해당 항목의 `목표 / 범위 / 비범위 / 완료 조건 / 검증 방법 / PR 원칙`을 작업 경계로 삼는다.
6. `관련 기획` 문서와 `관련 데이터` DB만 추가로 읽는다.
7. GitHub Issue가 없으면 중복 여부를 확인한 뒤 새로 만들고, 있으면 기존 Issue를 사용한다.
8. 구현을 시작하기 전에 Notion 백로그와 GitHub Issue에 작업 시작 표시를 남긴다.
9. 구현, 테스트, PR 생성, 머지, 로컬 main 동기화, main 복귀까지 완료한다.

## 작업 선점과 중복 방지

- Notion `🤖 AI 구현 백로그`의 실제 상태 필드는 `상태`이며 옵션은 `시작 전 / 진행 중 / 완료`다.
- 자동으로 다음 항목을 고를 때는 `상태 = 시작 전`인 항목만 후보로 본다. `진행 중` 항목은 다른 Codex 에이전트가 선점한 작업으로 보고 건드리지 않는다.
- 사용자가 특정 `DEV-*`를 지정했더라도 해당 Notion 행이 `진행 중`이면 구현하지 않는다. 기존 작업 현황을 보고하고, 사용자가 명시적으로 takeover를 지시하기 전에는 새 브랜치나 PR을 만들지 않는다.
- GitHub Issue 검색 결과에 `status: in-progress`, `codex-working` 같은 작업중 라벨, 열린 연결 PR, 또는 최근 `Codex 작업 시작` 코멘트가 있으면 작업중으로 본다.
- 로컬에 같은 `DEV-*`를 포함한 활성 worktree나 branch가 있으면 작업중 가능성으로 보고 먼저 상태를 확인한다.
- 항목을 고른 뒤에는 바로 다시 Notion 행과 GitHub Issue를 확인한다. 그 사이 `상태`가 `진행 중`으로 바뀌었으면 선점을 포기하고 다른 후보를 고른다.

## 작업 시작 표시

구현 파일을 수정하기 전에 다음 선점 표시를 완료한다. 둘 중 하나라도 권한이나 도구 문제로 실패하면 구현을 시작하지 않고 차단 사유를 보고한다.

1. Notion 백로그 행의 `상태`를 `진행 중`으로 바꾼다.
2. Notion 백로그 행의 `GitHub Issue`가 비어 있으면 사용할 Issue URL을 기록한다.
3. GitHub Issue에 `status: in-progress` 또는 `codex-working` 라벨을 붙인다. 라벨이 없고 권한이 있으면 생성해서 붙인다.
4. GitHub Issue에 작업 시작 코멘트를 남긴다.

```markdown
Codex 작업 시작

- Notion: DEV-<id> <Notion URL>
- Branch: <branch>
- Worktree: <worktree path>
- Started: <ISO-8601 datetime>
- Agent: <가능하면 세션/에이전트 식별자>
```

완료 시에는 Notion `상태`를 `완료`로 바꾸고 `GitHub PR` URL을 기록한다. GitHub Issue는 PR의 `Closes #<issue-number>`로 닫히게 하거나, 실패 시 차단 코멘트를 남긴다.

## 범위 규칙

- 한 번에 백로그 항목 하나만 구현한다.
- `비범위`는 구현하지 않는다.
- 범위 밖 요구사항을 발견하면 즉석에서 같이 구현하지 않고 후속 Issue 후보로 보고한다.
- 콘텐츠 값과 수치는 코드에 하드코딩하지 않는다. 해당 콘텐츠 DB 또는 `⚖️ 밸런스 상수`를 정본으로 사용한다.
- 게임 런타임에서 Notion API를 직접 호출하지 않는다.

## git 작업 규칙

`isolated-worktree-pr` 스킬이 사용 가능하면 반드시 함께 적용한다. 작업마다 새 브랜치와 별도 git worktree를 만들고, PR 머지 후 로컬 main을 원격 main에 fast-forward 동기화하고, 완료 보고 전 `main` 브랜치로 복귀한다.

작업 시작 표시에 branch와 worktree 경로가 필요하므로, 대상 Notion 항목과 GitHub Issue를 정한 뒤 구현 파일을 수정하기 전에 전용 branch/worktree를 먼저 만든다. 단, worktree 생성 후에도 Notion/GitHub 선점 표시가 실패하면 구현하지 않는다.

## 완료 보고

완료 보고는 한국어로 작성하고 다음 항목을 포함한다.

- 변경 파일
- 구현 요약
- 설계 결정
- 테스트 결과
- 미해결 위험
- 후속 Issue 후보
- 최종 브랜치와 main 동기화 상태
