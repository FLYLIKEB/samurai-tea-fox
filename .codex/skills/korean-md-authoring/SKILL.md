---
name: korean-md-authoring
description: 이 프로젝트에서 Markdown 문서나 Codex 스킬을 만들거나 수정할 때 본문과 사용자-facing 설명을 한국어 기반으로 작성하도록 한다.
metadata:
  short-description: Markdown과 스킬 한국어 작성 규칙
---

# Markdown 한국어 작성

이 프로젝트에서 Markdown 기반 산출물을 만들거나 수정할 때 사용한다. 특히 `*.md`, `SKILL.md`, 프로젝트 문서, 작업 절차 문서, README성 안내, Codex 스킬 설명을 작성할 때 적용한다.

## 기본 원칙

- Markdown 본문은 한국어를 기본 언어로 작성한다.
- Codex 스킬의 `description`, `metadata.short-description`, UI 표시 설명, 본문 안내도 한국어 기반으로 작성한다.
- 문서 제목과 섹션 제목도 특별한 이유가 없으면 한국어로 쓴다.
- 기존 문서가 한국어와 영어를 섞어 쓰더라도 새로 추가하는 설명 문장은 한국어를 우선한다.

## 그대로 유지할 것

- 파일명, 경로, 브랜치명, 명령어, 코드 식별자, API 이름, 클래스명, 함수명, 설정 키는 원문을 유지한다.
- 인용문, 외부 공식 명칭, 라이선스 문구, 에러 메시지, CLI 출력은 의미가 바뀌지 않도록 원문을 유지하거나 필요한 경우 한국어 설명을 덧붙인다.
- 사용자가 특정 언어를 명시하면 그 지시를 우선한다.

## 작성 방식

- 한국어 문장은 짧고 직접적으로 쓴다.
- 영어 용어가 더 정확한 기술 명칭이면 억지로 번역하지 않는다. 예: `worktree`, `remote`, `rebase`, `fast-forward`, `PR`.
- 절차 문서는 실행 순서와 검증 조건을 분명히 쓴다.
- 스킬 문서는 자동 선택에 필요한 frontmatter 설명을 구체적으로 작성하되, 관련 없는 요청까지 끌어오지 않도록 범위를 좁힌다.

## 완료 전 확인

- 새 Markdown 파일이나 수정한 Markdown 블록에 불필요한 영어 설명 문장이 남아 있지 않은지 확인한다.
- `SKILL.md`를 만들었다면 frontmatter와 본문이 유효하고, 자동 호출이 필요하면 `agents/openai.yaml`의 `policy.allow_implicit_invocation`을 `true`로 둔다.
- 코드 블록, 명령어, 경로, 외부 원문은 번역 과정에서 손상되지 않았는지 확인한다.
