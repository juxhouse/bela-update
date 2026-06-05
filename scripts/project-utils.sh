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

bela_trim() {
  local value="$1"

  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s\n' "$value"
}

bela_unquote_config_value() {
  local value="$1"
  local length="${#value}"

  if [[ "$length" -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value:length-1:1}" == '"' ]]; then
      value="${value:1:length-2}"
    elif [[ "${value:0:1}" == "'" && "${value:length-1:1}" == "'" ]]; then
      value="${value:1:length-2}"
    fi
  fi

  printf '%s\n' "$value"
}

bela_strip_inline_comment() {
  local value="$1"
  local result=""
  local char
  local previous=""
  local in_single_quote="false"
  local in_double_quote="false"
  local length="${#value}"
  local i

  for ((i = 0; i < length; i++)); do
    char="${value:i:1}"

    if [[ "$char" == "'" && "$in_double_quote" == "false" ]]; then
      if [[ "$in_single_quote" == "true" ]]; then
        in_single_quote="false"
      else
        in_single_quote="true"
      fi
    elif [[ "$char" == '"' && "$in_single_quote" == "false" ]]; then
      if [[ "$in_double_quote" == "true" ]]; then
        in_double_quote="false"
      else
        in_double_quote="true"
      fi
    elif [[ "$char" == "#" && "$in_single_quote" == "false" && "$in_double_quote" == "false" ]]; then
      if [[ -z "$previous" || "$previous" =~ [[:space:]] ]]; then
        break
      fi
    fi

    result+="$char"
    previous="$char"
  done

  bela_trim "$result"
}

bela_config_file() {
  local dir="$1"

  printf '%s/.bela/bela.yml\n' "$dir"
}

bela_read_config_value() {
  local file="$1"
  local key="$2"
  local line
  local trimmed
  local value

  BELA_CONFIG_VALUE=""

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(bela_trim "$line")"

    if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
      continue
    fi

    if [[ "$trimmed" == "$key":* ]]; then
      value="${trimmed#*:}"
      value="$(bela_trim "$value")"
      value="$(bela_strip_inline_comment "$value")"
      BELA_CONFIG_VALUE="$(bela_unquote_config_value "$value")"
      return 0
    fi
  done < "$file"

  return 1
}

bela_config_ignore_projects() {
  local dir="$1"
  local file
  local value

  file="$(bela_config_file "$dir")"

  if ! bela_read_config_value "$file" "ignore-projects"; then
    return 1
  fi

  value="${BELA_CONFIG_VALUE,,}"
  [[ "$value" == "true" ]]
}

find_project_dirs() {
  local dir="$1"

  find_project_dirs_with_config "$dir"
}

find_project_dirs_with_config() {
  local dir="$1"
  local child
  local child_name

  if bela_config_ignore_projects "$dir"; then
    return 0
  fi

  if detect_project_language "$dir" > /dev/null; then
    echo "$dir"
    return 0
  fi

  while IFS= read -r child; do
    child_name="$(basename "$child")"
    if should_skip_project_search_dir "$child_name"; then
      continue
    fi

    find_project_dirs_with_config "$child"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

bela_config_scope_dirs() {
  local root_dir="$1"
  local project_dir="$2"
  local relative_path
  local current_dir
  local path_part
  local -a path_parts

  root_dir="$(cd "$root_dir" && pwd -P)"
  project_dir="$(cd "$project_dir" && pwd -P)"

  printf '%s\n' "$root_dir"

  if [[ "$project_dir" == "$root_dir" ]]; then
    return 0
  fi

  if [[ "$project_dir" != "$root_dir"/* ]]; then
    return 0
  fi

  relative_path="${project_dir#"$root_dir"/}"
  current_dir="$root_dir"

  IFS=/ read -r -a path_parts <<< "$relative_path"
  for path_part in "${path_parts[@]}"; do
    current_dir="$current_dir/$path_part"
    printf '%s\n' "$current_dir"
  done
}

bela_effective_parent_element_path() {
  local root_dir="$1"
  local project_dir="$2"
  local effective_value="${3:-}"
  local scope_dir
  local file

  while IFS= read -r scope_dir; do
    file="$(bela_config_file "$scope_dir")"
    if bela_read_config_value "$file" "parent-element-path"; then
      effective_value="$BELA_CONFIG_VALUE"
    fi
  done < <(bela_config_scope_dirs "$root_dir" "$project_dir")

  printf '%s\n' "$effective_value"
}

bela_effective_build_command() {
  local root_dir="$1"
  local project_dir="$2"
  local effective_value="${3:-}"
  local scope_dir
  local file

  while IFS= read -r scope_dir; do
    file="$(bela_config_file "$scope_dir")"
    if bela_read_config_value "$file" "build-command"; then
      effective_value="$BELA_CONFIG_VALUE"
    fi
  done < <(bela_config_scope_dirs "$root_dir" "$project_dir")

  printf '%s\n' "$effective_value"
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
