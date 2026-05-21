#!/usr/bin/env bash
set -euo pipefail

working_directory="${BELA_WORKING_DIRECTORY:-.}"
language="${BELA_LANGUAGE:?BELA_LANGUAGE is required. Run detect-language.sh first.}"
source="${BELA_SOURCE:?BELA_SOURCE is required. Run detect-language.sh first.}"
parent_element_path="${BELA_PARENT_ELEMENT_PATH:-}"
updater_tag="${BELA_UPDATER_TAG:-latest}"

cd "$working_directory"
mkdir -p .bela

updater_image="juxhouse/bela-updater-${language}:${updater_tag}"
docker pull "$updater_image"

parent_args=()
case "$language" in
  ruby)
    source_args=(--source "$source")
    if [[ -n "$parent_element_path" ]]; then
      parent_args=(--parent-element-path "$parent_element_path")
    fi
    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      -v "$PWD/.bela/external_gems:/external_gems" \
      "$updater_image" \
      "${source_args[@]}" \
      "${parent_args[@]}"
    ;;

  dotnet)
    source_args=(-source "$source")
    if [[ -n "$parent_element_path" ]]; then
      parent_args=(-parent-element-path "$parent_element_path")
    fi
    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      --entrypoint dotnet \
      "$updater_image" \
      /App/CodeAnalyzer.dll \
      "${source_args[@]}" \
      "${parent_args[@]}" \
      -workspace /workspace \
      -output /.bela/bela-update.ecd
    ;;

  java)
    source_args=(-source "$source")
    if [[ -n "$parent_element_path" ]]; then
      parent_args=(-parent-element-path "$parent_element_path")
    fi

    m2_args=()
    if [[ -d "$PWD/.m2" ]]; then
      m2_args=(-v "$PWD/.m2:/.m2:ro")
    fi

    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      "${m2_args[@]}" \
      "$updater_image" \
      "${source_args[@]}" \
      "${parent_args[@]}"
    ;;

  clojure|typescript)
    source_args=(-source "$source")
    if [[ -n "$parent_element_path" ]]; then
      parent_args=(-parent-element-path "$parent_element_path")
    fi
    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      "$updater_image" \
      "${source_args[@]}" \
      "${parent_args[@]}"
    ;;

  *)
    echo "Unsupported BELA language: $language" >&2
    exit 1
    ;;
esac

test -f .bela/bela-update.ecd
