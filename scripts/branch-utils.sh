#!/usr/bin/env bash

bela_active_branches() {
  local working_directory="$1"
  local main_branch

  if git -C "$working_directory" rev-parse --is-shallow-repository | grep -q true; then
    git -C "$working_directory" fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune --filter=blob:none --unshallow >&2 || return $?
  else
    git -C "$working_directory" fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune --filter=blob:none >&2 || return $?
  fi

  if ! main_branch="$(git -C "$working_directory" symbolic-ref --quiet --short refs/remotes/origin/HEAD)"; then
    echo "Could not determine the main branch from origin/HEAD." >&2
    return 1
  fi

  git -C "$working_directory" branch -r --no-merged "$main_branch" |
    sed 's|^ *origin/||'
}
