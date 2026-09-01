#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  worktree_pr.sh start <task-slug> [base-dir]
  worktree_pr.sh pr [title] [body-file]
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

cmd_sync_main() {
  local target remote main
  target="${1:-$(repo_root)}"
  remote="$(remote_name)"
  main="$(main_branch)"

  if ! git -C "$target" diff --quiet || ! git -C "$target" diff --cached --quiet; then
    echo "Refusing to sync: target worktree has uncommitted changes: $target" >&2
    exit 2
  fi

  git -C "$target" fetch "$remote" "$main" --prune
  git -C "$target" switch "$main"
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
