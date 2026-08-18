#!/usr/bin/env bash

declare -a BELA_PROJECT_DIRS=()
declare -A BELA_PROJECT_BUILD_COMMANDS=()
declare -A BELA_PROJECT_UPDATER_ARGS=()

bela_reset_project_discovery() {
  BELA_PROJECT_DIRS=()
  BELA_PROJECT_BUILD_COMMANDS=()
  BELA_PROJECT_UPDATER_ARGS=()
}

detect_project_language() {
  local project_dir="$1"

  if [[ -f "$project_dir/deps.edn" || -f "$project_dir/project.clj" ]]; then
    echo "clojure"
  elif [[ -f "$project_dir/package.json" ]]; then
    echo "typescript"
  elif [[ -f "$project_dir/pom.xml" || -f "$project_dir/build.gradle" || -f "$project_dir/build.gradle.kts" || -f "$project_dir/gradlew" ]]; then
    echo "java"
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

bela_line_indent() {
  local value="$1"
  local value_without_cr
  local without_indent

  value_without_cr="${value%$'\r'}"
  without_indent="${value_without_cr#"${value_without_cr%%[![:space:]]*}"}"

  printf '%s\n' "$((${#value_without_cr} - ${#without_indent}))"
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
  local indent
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

    indent="$(bela_line_indent "$line")"
    if [[ "$indent" != "0" ]]; then
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

bela_read_config_map() {
  local file="$1"
  local key="$2"
  local line
  local trimmed
  local indent
  local map_indent=""
  local value
  local child_key
  local child_value

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$(bela_trim "$line")"

    if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
      continue
    fi

    indent="$(bela_line_indent "$line")"

    if [[ -n "$map_indent" ]]; then
      if (( indent <= map_indent )); then
        break
      fi

      trimmed="$(bela_strip_inline_comment "$trimmed")"
      if [[ -z "$trimmed" ]]; then
        continue
      fi

      if [[ "$trimmed" != *:* ]]; then
        echo "Unsupported YAML entry under '$key' in $file: $trimmed" >&2
        return 2
      fi

      child_key="${trimmed%%:*}"
      child_value="${trimmed#*:}"
      child_key="$(bela_trim "$child_key")"
      child_value="$(bela_trim "$child_value")"

      if [[ -z "$child_key" || "$child_key" == -* ]]; then
        echo "Unsupported YAML entry under '$key' in $file: $trimmed" >&2
        return 2
      fi

      printf '%s\t%s\n' "$child_key" "$(bela_unquote_config_value "$child_value")"
      continue
    fi

    if [[ "$indent" != "0" ]]; then
      continue
    fi

    if [[ "$trimmed" == "$key":* ]]; then
      value="${trimmed#*:}"
      value="$(bela_trim "$value")"
      value="$(bela_strip_inline_comment "$value")"
      if [[ -n "$value" ]]; then
        echo "Unsupported inline value for '$key' in $file. Use a nested mapping." >&2
        return 2
      fi
      map_indent="$indent"
    fi
  done < "$file"

  [[ -n "$map_indent" ]]
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

bela_valid_updater_option_name() {
  local option_name="$1"

  [[ "$option_name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]
}

bela_apply_directory_config() {
  local dir="$1"
  local build_command_name="$2"
  local updater_options_name="$3"
  local file
  local option_name
  local option_value
  local option_line
  local option_output
  local status
  local -n build_command_ref="$build_command_name"
  local -n updater_options_ref="$updater_options_name"

  file="$(bela_config_file "$dir")"

  if bela_read_config_value "$file" "build-command"; then
    build_command_ref="$BELA_CONFIG_VALUE"
  fi

  if option_output="$(bela_read_config_map "$file" "updater-args")"; then
    if [[ -n "$option_output" ]]; then
      while IFS= read -r option_line; do
        option_name="${option_line%%$'\t'*}"
        option_value="${option_line#*$'\t'}"

        if ! bela_valid_updater_option_name "$option_name"; then
          echo "Invalid updater option name '$option_name' in $file. Use letters, numbers, underscores, and hyphens only." >&2
          return 1
        fi

        updater_options_ref["$option_name"]="$option_value"
      done <<< "$option_output"
    fi
  else
    status=$?
    if [[ "$status" -gt 1 ]]; then
      return "$status"
    fi
  fi
}

bela_updater_args_from_options() {
  local updater_options_name="$1"
  local option_name
  local -n updater_options_ref="$updater_options_name"

  if ((${#updater_options_ref[@]} == 0)); then
    return 0
  fi

  while IFS= read -r option_name; do
    if [[ -n "${updater_options_ref[$option_name]}" ]]; then
      printf '%s\n%s\n' "-$option_name" "${updater_options_ref[$option_name]}"
    fi
  done < <(printf '%s\n' "${!updater_options_ref[@]}" | sort)
}

bela_updater_options_from_lines() {
  local option_lines="$1"
  local updater_options_name="$2"
  local option_line
  local option_name
  local option_value
  local -n updater_options_ref="$updater_options_name"

  if [[ -z "$option_lines" ]]; then
    return 0
  fi

  while IFS= read -r option_line; do
    option_name="${option_line%%$'\t'*}"
    option_value="${option_line#*$'\t'}"
    updater_options_ref["$option_name"]="$option_value"
  done <<< "$option_lines"
}

bela_updater_options_to_lines() {
  local updater_options_name="$1"
  local option_name
  local -n updater_options_ref="$updater_options_name"

  if ((${#updater_options_ref[@]} == 0)); then
    return 0
  fi

  while IFS= read -r option_name; do
    printf '%s\t%s\n' "$option_name" "${updater_options_ref[$option_name]}"
  done < <(printf '%s\n' "${!updater_options_ref[@]}" | sort)
}

find_project_dirs() {
  local dir="$1"
  local build_command=""
  local updater_option_lines=""
  local -A default_updater_options=()

  if [[ -n "${BELA_PARENT_ELEMENT_PATH:-}" ]]; then
    default_updater_options["parent-element-path"]="$BELA_PARENT_ELEMENT_PATH"
  fi

  updater_option_lines="$(bela_updater_options_to_lines default_updater_options)"

  find_project_dirs_with_config "$dir" "$build_command" "$updater_option_lines"
}

find_project_dirs_with_config() {
  local dir="$1"
  local inherited_build_command="$2"
  local inherited_updater_options="$3"
  local child
  local child_name
  local build_command="$inherited_build_command"
  local updater_option_lines
  local -A effective_updater_options=()

  if bela_config_ignore_projects "$dir"; then
    return 0
  fi

  bela_updater_options_from_lines "$inherited_updater_options" effective_updater_options
  bela_apply_directory_config "$dir" build_command effective_updater_options || return $?
  updater_option_lines="$(bela_updater_options_to_lines effective_updater_options)"

  if detect_project_language "$dir" > /dev/null; then
    BELA_PROJECT_DIRS+=("$dir")
    BELA_PROJECT_BUILD_COMMANDS["$dir"]="$build_command"
    BELA_PROJECT_UPDATER_ARGS["$dir"]="$(bela_updater_args_from_options effective_updater_options)"
    return 0
  fi

  while IFS= read -r child; do
    child_name="$(basename "$child")"
    if should_skip_project_search_dir "$child_name"; then
      continue
    fi

    find_project_dirs_with_config "$child" "$build_command" "$updater_option_lines"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

bela_project_build_command() {
  local project_dir="$1"

  printf '%s\n' "${BELA_PROJECT_BUILD_COMMANDS[$project_dir]:-}"
}

bela_project_updater_args() {
  local project_dir="$1"

  printf '%s\n' "${BELA_PROJECT_UPDATER_ARGS[$project_dir]:-}"
}

bela_project_source_base() {
  local project_dir="$1"
  local repository="${GITHUB_REPOSITORY:-repo}"
  local workspace="${GITHUB_WORKSPACE:-}"
  local workspace_path
  local project_path
  local source

  project_dir="$(cd "$project_dir" && pwd -P)"

  if [[ -z "$workspace" ]]; then
    source="$repository"
  else
    workspace_path="$(cd "$workspace" && pwd -P)"

    if [[ "$project_dir" == "$workspace_path" ]]; then
      source="$repository"
    elif [[ "$project_dir" == "$workspace_path"/* ]]; then
      project_path="${project_dir#"$workspace_path"/}"
      source="$repository/$project_path"
    else
      source="$repository"
    fi
  fi

  echo "$source"
}

bela_project_source() {
  local source
  local branch="${GITHUB_REF_NAME:-}"

  source="$(bela_project_source_base "$1")"
  if [[ -n "$branch" ]]; then
    source+=" ($branch)"
  fi

  echo "$source"
}
