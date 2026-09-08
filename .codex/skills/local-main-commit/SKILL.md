---
name: local-main-commit
description: 현재 로컬 checkout에서만 작업하고, 기존 변경을 보존한 채 요청 범위의 변경만 로컬 커밋할 때 사용한다. worktree, push, PR이 필요한 작업에는 사용하지 않는다.
metadata:
  short-description: 현재 브랜치에서 로컬 커밋만 수행
---

# 로컬 Main 커밋

현재 저장소 checkout에서 요청한 변경을 구현·검증하고 로컬 커밋 하나로 남긴다.

## 필수 규칙

1. 시작 전에 저장소 루트, `git status --short`, 현재 브랜치를 확인한다.
2. 현재 checkout에서 직접 작업한다. 새 branch나 worktree를 만들거나 checkout을 전환하지 않는다.
3. `fetch`, `pull`, `push`, PR 생성·머지 등 remote 작업을 하지 않는다.
4. 기존 미커밋 변경은 사용자의 작업으로 간주한다. 덮어쓰거나 stash하지 않고, 요청 범위와 겹치면 안전하게 분리할 수 있는 경우에만 계속한다.
5. 변경 범위에 맞는 가장 작은 검증을 실행한다.
6. 이번 작업에서 변경한 경로만 명시적으로 stage한다. `git add .`, `git add -A`, `git commit -a`를 사용하지 않는다.
7. staged diff에 기존 변경이 섞이지 않았는지 확인한 뒤 로컬 커밋한다.
8. 완료 시 commit hash, 검증 결과, 남아 있는 기존 변경을 보고한다. push나 PR은 만들지 않는다.

현재 브랜치가 `main`이 아니어도 사용자가 현재 브랜치 작업을 명시했다면 그대로 작업한다. 브랜치 전환이 꼭 필요하거나 기존 변경과 안전하게 분리할 수 없으면 커밋하지 않고 정확한 차단 사유를 보고한다.
