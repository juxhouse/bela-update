#!/usr/bin/env bash
set -euo pipefail

working_directory="${BELA_WORKING_DIRECTORY:-.}"
language="${BELA_LANGUAGE:?BELA_LANGUAGE is required. Run 1-detect-language.sh first.}"
source="${BELA_SOURCE:?BELA_SOURCE is required. Run 1-detect-language.sh first.}"
updater_tag="${BELA_UPDATER_TAG:-latest}"
updater_args=()

cd "$working_directory"
mkdir -p .bela

updater_image="juxhouse/bela-updater-${language}:${updater_tag}"
docker pull "$updater_image"

if [[ -n "${BELA_UPDATER_ARGS:-}" ]]; then
  mapfile -t configured_updater_args <<< "$BELA_UPDATER_ARGS"
  updater_args+=("${configured_updater_args[@]}")
fi

case "$language" in
  dotnet)
    source_args=(-source "$source")
    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      --entrypoint dotnet \
      "$updater_image" \
      /App/CodeAnalyzer.dll \
      "${source_args[@]}" \
      "${updater_args[@]}" \
      -workspace /workspace \
      -output /.bela/bela-update.ecd
    ;;

  java)
    source_args=(-source "$source")

    m2_args=()
    if [[ -f pom.xml ]]; then
      m2_directory="${HOME:?HOME is required to locate the default Maven .m2 directory.}/.m2"
      mkdir -p "$m2_directory"
      m2_directory="$(cd "$m2_directory" && pwd -P)"
      m2_args=(-v "$m2_directory:/.m2:ro")
    fi

    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      "${m2_args[@]}" \
      "$updater_image" \
      "${source_args[@]}" \
      "${updater_args[@]}"
    ;;

  clojure|typescript)
    source_args=(-source "$source")
    docker run --rm --pull=never --network=none \
      -v "$PWD:/workspace" \
      -v "$PWD/.bela:/.bela" \
      "$updater_image" \
      "${source_args[@]}" \
      "${updater_args[@]}"
    ;;

  *)
    echo "Unsupported BELA language: $language" >&2
    exit 1
    ;;
esac

test -f .bela/bela-update.ecd
