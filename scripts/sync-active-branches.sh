#!/usr/bin/env bash
set -euo pipefail

source_base="${1:?A source base is required.}"
shift
api_url="${BELA_API_URL:?BELA_API_URL environment variable is required.}"
api_token="${BELA_API_TOKEN:?BELA_API_TOKEN environment variable is required.}"

if ! command -v jq > /dev/null; then
  echo "jq is required to encode the active branches request." >&2
  exit 1
fi

payload="$(jq -cn \
  --arg source "$source_base" \
  --args '{source: $source, activeBranches: $ARGS.positional}' \
  -- "$@")"

curl -f "${api_url%/}/api/active-branches-set" \
  -H "Authorization: $api_token" \
  -H 'Content-Type: application/json' \
  --data "$payload"
