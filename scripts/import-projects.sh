#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=project-utils.sh
source "$action_dir/scripts/project-utils.sh"
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
project_count="${#project_dirs[@]}"
project_index=0

bela_log "Detected $project_count BELA project(s)."

for project_dir in "${project_dirs[@]}"; do
  project_index=$((project_index + 1))
  language="$(detect_project_language "$project_dir")"
  source_name="$(bela_project_source "$project_dir")"
  source_slug="$(bela_log_slug "$source_name")"
  project_log_directory="$logs_directory/$project_index-$source_slug"

  languages+=("$language")
  sources+=("$source_name")

  bela_group_start "Project $project_index/$project_count: $source_name ($language)"
  bela_log "Directory: $project_dir"

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
      "$action_dir/scripts/prepare.sh" || {
        status=$?
        bela_group_end
        exit "$status"
      }

  bela_run_logged "Run BELA updater" "$project_log_directory/updater.log" \
    env \
      BELA_WORKING_DIRECTORY="$project_dir" \
      BELA_LANGUAGE="$language" \
      BELA_SOURCE="$source_name" \
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

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    IFS=,
    echo "languages=${languages[*]}"
    echo "sources=${sources[*]}"
  } >> "$GITHUB_OUTPUT"
fi
