#!/usr/bin/env bash

detect_project_language() {
  local project_dir="$1"

  if [[ -f "$project_dir/deps.edn" || -f "$project_dir/project.clj" ]]; then
    echo "clojure"
  elif [[ -f "$project_dir/package.json" ]]; then
    echo "typescript"
  elif [[ -f "$project_dir/pom.xml" || -f "$project_dir/build.gradle" || -f "$project_dir/build.gradle.kts" || -f "$project_dir/gradlew" ]]; then
    echo "java"
  elif [[ -f "$project_dir/Gemfile" ]]; then
    echo "ruby"
  elif compgen -G "$project_dir/*.sln" > /dev/null || compgen -G "$project_dir/*.csproj" > /dev/null; then
    echo "dotnet"
  else
    return 1
  fi
}

should_skip_project_search_dir() {
  local dir_name="$1"

  case "$dir_name" in
    .git|.github|.bela|node_modules|vendor|target|build|dist|out|coverage|.gradle|.m2|.gitlibs)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

find_project_dirs() {
  local dir="$1"
  local child
  local child_name

  if detect_project_language "$dir" > /dev/null; then
    echo "$dir"
    return 0
  fi

  while IFS= read -r child; do
    child_name="$(basename "$child")"
    if should_skip_project_search_dir "$child_name"; then
      continue
    fi

    find_project_dirs "$child"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

bela_project_source() {
  local project_dir="$1"
  local repository="${GITHUB_REPOSITORY:-repo}"
  local workspace="${GITHUB_WORKSPACE:-}"
  local workspace_path
  local project_path

  project_dir="$(cd "$project_dir" && pwd -P)"

  if [[ -z "$workspace" ]]; then
    echo "$repository"
    return 0
  fi

  workspace_path="$(cd "$workspace" && pwd -P)"

  if [[ "$project_dir" == "$workspace_path" ]]; then
    echo "$repository"
  elif [[ "$project_dir" == "$workspace_path"/* ]]; then
    project_path="${project_dir#"$workspace_path"/}"
    echo "$repository/$project_path"
  else
    echo "$repository"
  fi
}
