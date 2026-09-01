#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  worktree_pr.sh start <task-slug> [base-dir]
  worktree_pr.sh pr [title] [body-file]
  worktree_pr.sh finish-pr [pr-number|pr-url|branch] [main-worktree] [merge|squash|rebase]
  worktree_pr.sh sync-main [main-worktree]
  worktree_pr.sh help

Environment:
  GIT_REMOTE             Remote name, default: origin
  GIT_MAIN_BRANCH        Main branch name. Auto-detected from origin/HEAD, fallback: main
  CODEX_WORKTREE_BASE    Parent directory for created worktrees
  BRANCH_PREFIX          Branch prefix, default: codex
EOF
}

repo_root() {
  git rev-parse --show-toplevel
}

remote_name() {
  printf '%s\n' "${GIT_REMOTE:-origin}"
}

main_branch() {
  if [[ -n "${GIT_MAIN_BRANCH:-}" ]]; then
    printf '%s\n' "$GIT_MAIN_BRANCH"
    return
  fi
  local remote detected
  remote="$(remote_name)"
  detected="$(git remote show "$remote" 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1 || true)"
  printf '%s\n' "${detected:-main}"
}

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//' |
    cut -c1-64
}

worktree_for_branch() {
  local branch="$1"
  git worktree list --porcelain |
    awk -v ref="refs/heads/$branch" '
      /^worktree / { worktree = substr($0, 10) }
      /^branch / && $2 == ref { print worktree; exit }
    '
}

status_paths() {
  local target="$1"
  git -C "$target" status --porcelain --untracked-files=all |
    sed -E 's/^...//' |
    sed -E 's/^.* -> //' |
    sort -u
}

incoming_paths() {
  local target="$1" remote="$2" main="$3"
  git -C "$target" diff --name-only "HEAD..$remote/$main" | sort -u
}

ensure_pull_will_not_overlap_local_changes() {
  local target="$1" remote="$2" main="$3" overlap
  overlap="$(comm -12 <(status_paths "$target") <(incoming_paths "$target" "$remote" "$main") || true)"
  if [[ -n "$overlap" ]]; then
    printf 'Refusing to sync: local changes would overlap incoming %s/%s files in %s:\n%s\n' "$remote" "$main" "$target" "$overlap" >&2
    exit 2
  fi
}

cmd_start() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi

  local root remote main slug branch base_dir worktree timestamp repo_name
  root="$(repo_root)"
  remote="$(remote_name)"
  main="$(main_branch)"
  slug="$(slugify "$1")"
  if [[ -z "$slug" ]]; then
    echo "Invalid task slug: $1" >&2
    exit 2
  fi

  timestamp="$(date +%Y%m%d%H%M%S)"
  branch="${BRANCH_PREFIX:-codex}/${slug}-${timestamp}"
  repo_name="$(basename "$root")"
  base_dir="${2:-${CODEX_WORKTREE_BASE:-$(dirname "$root")/.codex-worktrees/$repo_name}}"
  worktree="$base_dir/${branch//\//-}"

  git -C "$root" fetch "$remote" "$main" --prune
  mkdir -p "$base_dir"
  git -C "$root" worktree add -b "$branch" "$worktree" "$remote/$main"

  printf 'Created isolated task worktree.\nRepository: %s\nBranch:     %s\nWorktree:   %s\nBase:       %s/%s\n' "$root" "$branch" "$worktree" "$remote" "$main"
}

cmd_pr() {
  local root branch remote main title body_file
  root="$(repo_root)"
  branch="$(git -C "$root" branch --show-current)"
  remote="$(remote_name)"
  main="$(main_branch)"
  title="${1:-$branch}"
  body_file="${2:-}"

  if [[ -z "$branch" || "$branch" == "$main" ]]; then
    echo "Refusing to create a PR from main or detached HEAD." >&2
    exit 2
  fi
  if ! git -C "$root" diff --quiet || ! git -C "$root" diff --cached --quiet; then
    echo "Worktree has uncommitted changes. Commit or stash before PR creation." >&2
    exit 2
  fi

  git -C "$root" fetch "$remote" "$main" --prune
  git -C "$root" rebase "$remote/$main"
  git -C "$root" push -u "$remote" "$branch"

  if command -v gh >/dev/null 2>&1; then
    if [[ -n "$body_file" ]]; then
      gh pr create --base "$main" --head "$branch" --title "$title" --body-file "$body_file"
    else
      gh pr create --base "$main" --head "$branch" --title "$title" --fill
    fi
  else
    printf 'Pushed %s to %s. Create a PR with base %s and head %s.\n' "$branch" "$remote" "$main" "$branch"
  fi
}

cmd_finish_pr() {
  local root branch remote main pr main_worktree strategy flag head_ref head_oid base_ref state is_draft
  root="$(repo_root)"
  branch="$(git -C "$root" branch --show-current)"
  remote="$(remote_name)"
  main="$(main_branch)"
  pr="${1:-$branch}"
  main_worktree="${2:-}"
  strategy="${3:-merge}"

  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI 'gh' is required to finish a PR." >&2
    exit 2
  fi
  if [[ -z "$branch" || "$branch" == "$main" ]]; then
    echo "Run finish-pr from the task worktree branch, not main or detached HEAD." >&2
    exit 2
  fi
  if [[ -n "$(git -C "$root" status --porcelain)" ]]; then
    echo "Task worktree has uncommitted changes. Commit or remove them before finish-pr." >&2
    exit 2
  fi

  head_ref="$(gh pr view "$pr" --json headRefName --jq .headRefName)"
  head_oid="$(gh pr view "$pr" --json headRefOid --jq .headRefOid)"
  base_ref="$(gh pr view "$pr" --json baseRefName --jq .baseRefName)"
  state="$(gh pr view "$pr" --json state --jq .state)"
  is_draft="$(gh pr view "$pr" --json isDraft --jq .isDraft)"

  if [[ "$head_ref" != "$branch" ]]; then
    printf 'Refusing to finish PR: current branch is %s but PR head is %s.\n' "$branch" "$head_ref" >&2
    exit 2
  fi
  if [[ "$base_ref" != "$main" ]]; then
    printf 'Refusing to finish PR: PR base is %s but configured main is %s.\n' "$base_ref" "$main" >&2
    exit 2
  fi
  if [[ "$is_draft" == "true" ]]; then
    echo "Refusing to merge a draft PR." >&2
    exit 2
  fi

  case "$strategy" in
    merge|squash|rebase)
      flag="--$strategy"
      ;;
    *)
      echo "Invalid merge strategy: $strategy" >&2
      exit 2
      ;;
  esac

  if [[ "$state" != "MERGED" ]]; then
    gh pr merge "$pr" "$flag" --match-head-commit "$head_oid"
  fi

  if [[ -z "$main_worktree" ]]; then
    main_worktree="$(worktree_for_branch "$main")"
  fi
  if [[ -z "$main_worktree" ]]; then
    printf 'Could not find a local worktree for %s. Pass it explicitly as the second argument.\n' "$main" >&2
    exit 2
  fi

  cmd_sync_main "$main_worktree"

  if git ls-remote --exit-code --heads "$remote" "$head_ref" >/dev/null 2>&1; then
    git push "$remote" --delete "$head_ref"
  fi

  git -C "$main_worktree" worktree remove "$root"
  git -C "$main_worktree" branch -d "$head_ref"
  git -C "$main_worktree" worktree prune
}

cmd_sync_main() {
  local target remote main target_branch
  remote="$(remote_name)"
  main="$(main_branch)"
  target="${1:-}"

  if [[ -z "$target" ]]; then
    if [[ "$(git branch --show-current)" == "$main" ]]; then
      target="$(repo_root)"
    else
      target="$(worktree_for_branch "$main")"
    fi
  fi
  if [[ -z "$target" ]]; then
    printf 'Could not find a local worktree for %s. Pass it explicitly.\n' "$main" >&2
    exit 2
  fi

  target_branch="$(git -C "$target" branch --show-current)"
  if [[ "$target_branch" != "$main" ]]; then
    printf 'Refusing to sync: target worktree is on %s, expected %s: %s\n' "$target_branch" "$main" "$target" >&2
    exit 2
  fi

  git -C "$target" fetch "$remote" "$main" --prune
  ensure_pull_will_not_overlap_local_changes "$target" "$remote" "$main"
  git -C "$target" pull --ff-only "$remote" "$main"
  git -C "$target" worktree prune
}

case "${1:-help}" in
  start)
    shift
    cmd_start "$@"
    ;;
  pr)
    shift
    cmd_pr "$@"
    ;;
  finish-pr)
    shift
    cmd_finish_pr "$@"
    ;;
  sync-main)
    shift
    cmd_sync_main "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
