#!/usr/bin/env bash

bela_origin_main_branch() {
  local working_directory="$1"
  local main_branch
  local default_branch

  main_branch="$(git -C "$working_directory" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$main_branch" ]]; then
    printf '%s\n' "$main_branch"
    return 0
  fi

  if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]] && command -v jq > /dev/null; then
    default_branch="$(jq -r '.repository.default_branch // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
    if [[ -n "$default_branch" ]] && git -C "$working_directory" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
      printf 'origin/%s\n' "$default_branch"
      return 0
    fi
  fi

  git -C "$working_directory" remote set-head origin --auto >/dev/null 2>&1 || true
  main_branch="$(git -C "$working_directory" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$main_branch" ]]; then
    printf '%s\n' "$main_branch"
    return 0
  fi

  return 1
}

bela_active_branches() {
  local working_directory="$1"
  local main_branch

  if git -C "$working_directory" rev-parse --is-shallow-repository | grep -q true; then
    git -C "$working_directory" fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune --filter=blob:none --unshallow >&2 || return $?
  else
    git -C "$working_directory" fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune --filter=blob:none >&2 || return $?
  fi

  if ! main_branch="$(bela_origin_main_branch "$working_directory")"; then
    echo "Could not determine the main branch from origin/HEAD or the GitHub event." >&2
    return 1
  fi

  git -C "$working_directory" branch -r --no-merged "$main_branch" |
    sed 's|^ *origin/||'
}
