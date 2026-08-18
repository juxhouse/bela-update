#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utils/project.sh
source "$action_dir/scripts/utils/project.sh"
# shellcheck source=utils/branch.sh
source "$action_dir/scripts/utils/branch.sh"
# shellcheck source=utils/logging.sh
source "$action_dir/scripts/utils/logging.sh"

root_directory="${BELA_WORKING_DIRECTORY:-.}"
root_directory="$(cd "$root_directory" && pwd -P)"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$root_directory}"
logs_directory="$root_directory/.bela/logs"

bela_reset_project_discovery
find_project_dirs "$root_directory"
project_dirs=("${BELA_PROJECT_DIRS[@]}")

if [[ "${#project_dirs[@]}" -eq 0 ]]; then
  echo "Could not detect a supported BELA importer in $root_directory or its child directories." >&2
  exit 1
fi

languages=()
sources=()
source_bases=()
active_branches=()
project_count="${#project_dirs[@]}"
project_index=0

should_sync_active_branches=true
if [[ "${BELA_DRY_RUN:-false}" == "true" || "${BELA_SKIP_UPLOAD:-false}" == "true" ]]; then
  should_sync_active_branches=false
fi

if [[ "$should_sync_active_branches" == true ]]; then
  if ! active_branches_output="$(bela_active_branches "$GITHUB_WORKSPACE")"; then
    echo "Could not determine active Git branches." >&2
    exit 1
  fi

  if [[ -n "$active_branches_output" ]]; then
    mapfile -t active_branches <<< "$active_branches_output"
  fi
fi

bela_log "Detected $project_count BELA project(s)."

for project_dir in "${project_dirs[@]}"; do
  project_index=$((project_index + 1))
  language="$(detect_project_language "$project_dir")"
  source_base="$(bela_project_source_base "$project_dir")"
  source_name="$(bela_project_source "$project_dir")"
  source_slug="$(bela_log_slug "$source_name")"
  build_command="$(bela_project_build_command "$project_dir")"
  updater_args="$(bela_project_updater_args "$project_dir")"
  project_log_directory="$logs_directory/$project_index-$source_slug"

  languages+=("$language")
  sources+=("$source_name")
  source_bases+=("$source_base")

  bela_group_start "Project $project_index/$project_count: $source_name ($language)"
  bela_log "Directory: $project_dir"
  if [[ -n "$build_command" ]]; then
    bela_log "Build command: $build_command"
  fi

  if [[ -n "$updater_args" ]]; then
    bela_log "Updater options:"
    while IFS= read -r updater_arg && IFS= read -r updater_value; do
      bela_log "  ${updater_arg#-}: $updater_value"
    done <<< "$updater_args"
  fi

  if [[ "${BELA_DRY_RUN:-false}" == "true" ]]; then
    bela_log "Dry run enabled. Skipping prepare, updater, and upload."
    bela_group_end
    continue
  fi

  bela_run_logged "Prepare dependencies" "$project_log_directory/prepare.log" \
    env \
      BELA_WORKING_DIRECTORY="$project_dir" \
      BELA_LANGUAGE="$language" \
      BELA_SOURCE="$source_name" \
      "$action_dir/scripts/2-prepare.sh" \
      "$build_command" || {
        status=$?
        bela_group_end
        exit "$status"
      }

  bela_run_logged "Run BELA updater" "$project_log_directory/updater.log" \
    env \
      BELA_WORKING_DIRECTORY="$project_dir" \
      BELA_LANGUAGE="$language" \
      BELA_SOURCE="$source_name" \
      BELA_UPDATER_ARGS="$updater_args" \
      "$action_dir/scripts/3-run-updater.sh" || {
        status=$?
        bela_group_end
        exit "$status"
      }

  if [[ "${BELA_SKIP_UPLOAD:-false}" == "true" ]]; then
    ecd_file="$project_dir/.bela/bela-update.ecd"
    bela_log "Generated ECD: $ecd_file"
    sed -n '1,40p' "$ecd_file"
  else
    bela_run_logged "Upload ECD to BELA" "$project_log_directory/upload.log" \
      env \
        BELA_WORKING_DIRECTORY="$project_dir" \
        "$action_dir/scripts/4-upload.sh" || {
          status=$?
          bela_group_end
          exit "$status"
        }
  fi

  bela_group_end
done

if [[ "$should_sync_active_branches" == true ]]; then
  for source_base in "${source_bases[@]}"; do
    source_slug="$(bela_log_slug "$source_base")"
    bela_run_logged "Sync active branches: $source_base" \
      "$logs_directory/active-branches-$source_slug.log" \
      "$action_dir/scripts/5-sync-active-branches.sh" \
      "$source_base" \
      "${active_branches[@]}" || {
        status=$?
        exit "$status"
      }
  done
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    IFS=,
    echo "languages=${languages[*]}"
    echo "sources=${sources[*]}"
  } >> "$GITHUB_OUTPUT"
fi
