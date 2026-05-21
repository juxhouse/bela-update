#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=project-utils.sh
source "$action_dir/scripts/project-utils.sh"

working_directory="${BELA_WORKING_DIRECTORY:-.}"

working_directory="$(cd "$working_directory" && pwd -P)"
language="$(detect_project_language "$working_directory" || true)"

if [[ -z "$language" ]]; then
  echo "Could not detect a supported BELA importer in $working_directory." >&2
  exit 1
fi

source="$(bela_project_source "$working_directory")"

{
  echo "BELA_LANGUAGE=$language"
  echo "BELA_SOURCE=$source"
} >> "$GITHUB_ENV"

echo "language=$language" >> "$GITHUB_OUTPUT"
echo "Detected BELA language: $language"
