#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=project-utils.sh
source "$action_dir/scripts/project-utils.sh"
# shellcheck source=branch-utils.sh
source "$action_dir/scripts/branch-utils.sh"
# shellcheck source=logging.sh
source "$action_dir/scripts/logging.sh"

root_directory="${BELA_WORKING_DIRECTORY:-.}"
root_directory="$(cd "$root_directory" && pwd -P)"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$root_directory}"
logs_directory="$root_directory/.bela/logs"

mapfile -t project_dirs < <(find_project_dirs "$root_directory")

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
  parent_element_path="$(bela_effective_parent_element_path "$root_directory" "$project_dir" "${BELA_PARENT_ELEMENT_PATH:-}")"
  build_command="$(bela_effective_build_command "$root_directory" "$project_dir")"
  project_log_directory="$logs_directory/$project_index-$source_slug"

  languages+=("$language")
  sources+=("$source_name")
  source_bases+=("$source_base")

  bela_group_start "Project $project_index/$project_count: $source_name ($language)"
  bela_log "Directory: $project_dir"
  if [[ -n "$parent_element_path" ]]; then
    bela_log "Parent element path: $parent_element_path"
  fi
  if [[ -n "$build_command" ]]; then
    bela_log "Build command: $build_command"
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
      "$action_dir/scripts/prepare.sh" \
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
      BELA_PARENT_ELEMENT_PATH="$parent_element_path" \
      "$action_dir/scripts/run-updater.sh" || {
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
        "$action_dir/scripts/upload.sh" || {
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
      "$action_dir/scripts/sync-active-branches.sh" \
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
