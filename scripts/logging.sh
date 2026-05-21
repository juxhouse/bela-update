#!/usr/bin/env bash

bela_log() {
  printf '%s\n' "$*"
}

bela_warn() {
  printf 'Warning: %s\n' "$*" >&2
}

bela_group_start() {
  local title="$1"

  if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    printf '::group::%s\n' "$title"
  else
    printf '\n==> %s\n' "$title"
  fi
}

bela_group_end() {
  if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    printf '::endgroup::\n'
  fi
}

bela_log_slug() {
  local value="$1"

  value="${value//[^[:alnum:]._-]/-}"
  value="${value##-}"
  value="${value%%-}"

  if [[ -z "$value" ]]; then
    value="project"
  fi

  printf '%s\n' "$value"
}

bela_run_logged() {
  local title="$1"
  local log_file="$2"
  shift 2

  mkdir -p "$(dirname "$log_file")"

  bela_group_start "$title"
  bela_log "Writing detailed logs to $log_file"

  if "$@" > "$log_file" 2>&1; then
    bela_log "Completed: $title"
    bela_group_end
    return 0
  else
    local status=$?
  fi

  local tail_lines="${BELA_LOG_TAIL_LINES:-200}"

  bela_warn "Failed: $title"
  bela_warn "Showing the last $tail_lines lines from $log_file"
  tail -n "$tail_lines" "$log_file" >&2 || true
  bela_group_end

  return "$status"
}
