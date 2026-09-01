---
name: isolated-worktree-pr
description: 병렬 Codex 에이전트 간 커밋 충돌을 막기 위해 코딩 작업마다 새 Git 브랜치와 독립 작업 트리를 만들고, 풀 리퀘스트·병합·로컬 메인 동기화까지 수행할 때 사용한다.
metadata:
  short-description: 독립 브랜치와 작업 트리 기반 PR 흐름
---

# 독립 Worktree PR

병렬 Codex 에이전트가 같은 브랜치나 작업 트리를 공유하면 안 되는 저장소 작업에 이 스킬을 사용한다. 이 스킬은 git 격리와 반영 절차만 정의한다. 프로젝트별 구현 규칙이 따로 있으면 해당 스킬과 함께 사용한다.

## 목표 결과

각 작업은 전용 브랜치와 전용 git worktree에서 완료한다. 변경사항은 PR로 검토·머지하고, 이후 로컬 main worktree를 원격 main 상태로 fast-forward 동기화한다. 완료 보고 직전의 기준 checkout은 항상 `main` 브랜치여야 한다.

## 필수 워크플로

1. 파일을 수정하기 전에 저장소 루트, 기본 remote, main 브랜치를 확인한다.
2. 원격 main 브랜치를 fetch하고, 최신 원격 main에서 고유한 작업 브랜치를 만든다.
3. 해당 브랜치용 별도 git worktree를 만든다. 모든 파일 수정, 테스트, 커밋, PR 명령은 그 worktree 안에서 수행한다.
4. 원래/main worktree에서 직접 구현하지 않는다. 저장소 구조상 다른 판단이 필요하다는 증거가 없는 한, 원래 worktree는 안정적인 로컬 main checkout으로만 사용한다.
5. PR을 열기 전에 작업 브랜치를 현재 원격 main과 rebase하거나 그에 준해 정합성을 맞춘다. 그 다음 작업 worktree에서 필요한 검증을 실행한다.
6. 작업 브랜치를 push하고 PR을 연다. 구현 요약, 검증 증거, 알려진 위험을 포함한다.
7. PR이 준비되고 저장소의 check/review 조건을 만족한 뒤에만 머지한다. 저장소의 통상 머지 전략이 확인되면 그 방식을 사용하고, 확인되지 않으면 보수적인 merge commit 또는 명시된 사용자/프로젝트 관례를 따른다.
8. 머지 후 관련 로컬 main checkout마다 `git fetch` 후 `git pull --ff-only`로 원격 main에 맞춘다. 작업 브랜치가 더 필요 없으면 작업 worktree 제거, 로컬 브랜치 삭제, 원격 브랜치 삭제, 오래된 worktree 메타데이터 prune을 수행한다.
9. 마지막 검증과 완료 보고는 `main` worktree에서 수행한다. `git branch --show-current`가 `main`이 아니면 완료로 보고하지 않는다.

## PR 머지 후 안전 정리

작업 worktree 안에서 `gh pr merge --delete-branch`를 직접 실행하지 않는다. GitHub CLI가 머지 후 현재 worktree를 base branch로 전환하거나 로컬 브랜치를 즉시 삭제하려고 하면서, 이미 다른 worktree가 `main`을 사용 중이면 `fatal: 'main' is already used by worktree` 오류가 날 수 있다.

대신 다음 순서를 사용한다.

1. 작업 worktree가 clean인지 확인한다.
2. `gh pr merge <PR> --merge`처럼 `--delete-branch` 없이 원격 PR만 머지한다.
3. 로컬 `main` worktree에서 `git fetch`와 `git pull --ff-only`를 수행한다.
4. PR head 원격 브랜치를 삭제한다.
5. `main` worktree에서 작업 worktree를 제거한다.
6. 그 다음 로컬 작업 브랜치를 삭제하고 `git worktree prune`을 실행한다.

가능하면 이 과정을 직접 명령으로 나누지 말고 `scripts/worktree_pr.sh finish-pr <PR>`를 사용한다. 이 명령은 현재 작업 브랜치와 PR head가 같은지 확인하고, main worktree를 찾아 동기화한 뒤, worktree 제거와 브랜치 정리를 순서대로 수행한다.

## Main 복귀 규칙

- 작업이 끝나면 항상 로컬 기준 checkout을 `main`으로 돌려놓는다.
- PR 작업은 `scripts/worktree_pr.sh finish-pr <PR>`로 끝낸다. 이 명령은 main worktree가 없으면 기본 worktree를 안전하게 `main`으로 전환한 뒤 정리한다.
- PR 없이 중단되거나 문서/검증만 수행한 작업도 마지막에 `scripts/worktree_pr.sh return-main [target-worktree]` 또는 동등한 안전 절차로 `main` 복귀를 확인한다.
- `return-main`은 로컬 변경 파일과 `origin/main`으로 전환될 때 바뀌는 파일이 겹치면 중단한다. 이 경우 변경을 덮어쓰거나 stash하지 말고, 겹치는 파일 목록과 현재 브랜치를 보고한다.
- 완료 보고에는 최종 브랜치가 `main`인지, `origin/main`과 동기화됐는지, 남아 있는 로컬 변경이 사용자의 기존 변경인지 구분해 적는다.

## 가드레일

- 다른 작업의 브랜치나 worktree를 재사용하지 않는다.
- 사용자가 명시적으로 요청하지 않는 한 force push, hard reset, 다른 에이전트의 브랜치 삭제, 다른 worktree 제거 같은 파괴적 작업을 하지 않는다.
- 로컬 main checkout에 미커밋 변경이 있으면 덮어쓰지 않는다. 정확한 blocker를 보고하고, 사용자 변경을 위험에 빠뜨리지 않는 안전한 원격 측 정리만 계속한다.
- 로컬 main checkout에 미커밋 변경이 있어도 incoming 변경 파일과 겹치지 않으면 fast-forward pull은 가능하다. 겹치는 파일이 있으면 동기화를 중단하고 정확한 파일 목록을 보고한다.
- 작업 브랜치가 원격 main과 깔끔하게 rebase/merge되지 않으면 충돌 해결은 작업 worktree 안에서만 한다.
- PR 생성, 머지, 원격 push에 자격 증명이나 보호 브랜치 권한이 없으면 마지막으로 검증된 로컬 상태에서 멈추고 정확한 blocker를 보고한다.
- 로컬 검증 증거는 최신으로 유지한다. 먼저 변경 범위에 맞는 targeted test를 실행하고, 필요하면 lint/typecheck/build/smoke check를 실행한다.

## 헬퍼 스크립트

일반적인 저장소에서는 독립 worktree 생성, PR 생성, 머지 후 정리, main 복귀에 `scripts/worktree_pr.sh` 헬퍼를 우선 사용할 수 있다. 정확한 명령 형식이 필요하면 `scripts/worktree_pr.sh help`를 실행한다.

이 헬퍼는 안전한 setup/sync 작업과 PR 편의 명령으로 범위를 제한한다. 저장소별 테스트, 코드 리뷰 조건, 충돌 해결을 대체하지 않는다.
