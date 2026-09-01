# GitHub Issue와 PR 템플릿

이 문서는 Notion `🤖 AI 구현 백로그` 항목을 GitHub Issue와 PR로 옮길 때 사용하는 기본 형식이다.

## 중복 Issue 확인

새 Issue를 만들기 전에 열린 Issue와 닫힌 Issue를 모두 검색한다.

```bash
gh issue list --state all --search "DEV-7 in:title,body" --limit 20
```

`DEV-7`은 실제 DEV ID로 바꾼다. 같은 작업을 다루는 Issue가 있으면 중복 생성하지 않고 기존 Issue를 재사용한다.

## Issue 제목

가능하면 다음 형식을 사용한다.

```text
DEV-<id>: <Notion 백로그 제목>
```

예:

```text
DEV-7: 플레이어 자원 모델 구현
```

## Issue 본문

```markdown
## 목표
<Notion 백로그의 목표>

## 범위
<이번 Issue에서 구현할 항목>

## 비범위
<이번 Issue에서 구현하지 않을 항목>

## 완료 조건
<완료로 인정할 조건>

## 검증
<실행할 테스트나 확인 방법>

## Notion 정본
- 백로그: <DEV row 제목과 URL>
- 기획 문서: <관련 Notion 문서>
- 정본 DB: <관련 DB row 또는 해당 없음>

## PR 원칙
이 Issue는 하나의 집중 PR로 처리한다. 완료 시 `Closes #<issue-number>`를 사용한다.
```

## 브랜치 이름

```text
codex/DEV-<id>-short-description
```

예:

```text
codex/DEV-7-player-resources
```

가능하면 브랜치 이름은 소문자 ASCII로 작성한다.

## PR 본문

```markdown
## 요약
- <구현 요약>

## Notion 정합성
- 백로그: <DEV row URL>
- 기획 문서: <확인한 문서>
- 정본 DB: <사용한 DB row 또는 해당 없음>

## 테스트
- [x] <command> - <result>

## 범위 통제
- 범위 밖 발견 사항은 구현하지 않았다.

Closes #<issue-number>
```

검증이 실패한 상태에서는 성공처럼 보이는 PR 본문을 작성하지 않는다.

## 완료 보고

사용자에게는 한국어로 다음을 보고한다.

- 변경 파일
- 구현 내용
- 설계 결정
- Notion 정합성
- 테스트 결과
- 남은 위험
- 후속 Issue 후보
- PR URL 또는 차단 사유
