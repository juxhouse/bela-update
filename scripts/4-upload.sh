#!/usr/bin/env bash
set -euo pipefail

working_directory="${BELA_WORKING_DIRECTORY:-.}"
api_url="${BELA_API_URL:?BELA_API_URL environment variable is required.}"
api_token="${BELA_API_TOKEN:?BELA_API_TOKEN environment variable is required.}"

# A BELA_API_URL built from a repository variable can pick up a trailing
# newline, carriage return or space. curl refuses such a URL outright, with
# "URL rejected: Malformed input to a URL function", so trim it here.
api_url="${api_url//[$'\r\n']/}"
api_url="${api_url#"${api_url%%[![:space:]]*}"}"
api_url="${api_url%"${api_url##*[![:space:]]}"}"

if [[ -z "$api_url" ]]; then
  echo "BELA_API_URL environment variable is required." >&2
  exit 1
fi

cd "$working_directory"

ecd_file=".bela/bela-update.ecd"
if [[ ! -f "$ecd_file" ]]; then
  echo "Could not find generated ECD file at $ecd_file" >&2
  exit 1
fi

curl -f "${api_url%/}/api/ecd-architecture" \
  -H "Authorization: $api_token" \
  --data-binary "@$ecd_file"
