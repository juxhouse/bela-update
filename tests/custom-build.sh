#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
cleanup_dir=""

fail() {
  printf 'custom-build: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: tests/custom-build.sh --mock|--docker

  --mock    Validate custom build-command routing with fake docker/curl.
  --docker  Validate real updater contracts with Docker.
EOF
}

cleanup() {
  if [[ -z "$cleanup_dir" ]]; then
    return 0
  fi

  if [[ "${BELA_KEEP_TEST_REPOS:-false}" != "true" ]]; then
    if rm -rf "$cleanup_dir" 2> /dev/null; then
      return 0
    fi

    if command -v docker > /dev/null; then
      docker run --rm --pull=never --network=none \
        -v "$cleanup_dir:/cleanup" \
        --entrypoint /bin/sh \
        juxhouse/bela-updater-clojure:latest \
        -lc 'chmod -R a+rwX /cleanup' > /dev/null 2>&1 || true
      rm -rf "$cleanup_dir" 2> /dev/null || true
    fi

    if [[ -e "$cleanup_dir" ]]; then
      printf 'custom-build: could not remove test repo at %s\n' "$cleanup_dir" >&2
    fi
  else
    printf 'custom-build: kept test repo at %s\n' "$cleanup_dir" >&2
  fi
}

assert_file() {
  local path="$1"

  [[ -f "$path" ]] || fail "expected file to exist: $path"
}

assert_no_file() {
  local path="$1"

  [[ ! -e "$path" ]] || fail "expected file to be absent: $path"
}

assert_file_equals() {
  local path="$1"
  local expected="$2"
  local actual

  assert_file "$path"
  actual="$(< "$path")"
  [[ "$actual" == "$expected" ]] || fail "expected $path to contain '$expected', got '$actual'"
}

assert_file_contains() {
  local path="$1"
  local expected="$2"

  assert_file "$path"
  grep -F -- "$expected" "$path" > /dev/null || fail "expected $path to contain: $expected"
}

assert_file_not_contains() {
  local path="$1"
  local unexpected="$2"

  if [[ -f "$path" ]] && grep -F -- "$unexpected" "$path" > /dev/null; then
    fail "expected $path not to contain: $unexpected"
  fi
}

assert_clean_ecd() {
  local path="$1"
  local source="$2"

  assert_file "$path"
  assert_file_contains "$path" "source $source"
  assert_file_not_contains "$path" "Exception while creating ecd file"
  assert_file_not_contains "$path" "[error]"
  assert_file_not_contains "$path" "[warning]"
}

run_updater() {
  local fixture_dir="$1"
  local language="$2"
  local source="$3"
  local updater_log="$fixture_dir/.bela/updater-output.log"

  if ! env \
    BELA_WORKING_DIRECTORY="$fixture_dir" \
    BELA_LANGUAGE="$language" \
    BELA_SOURCE="$source" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}" updater > "$updater_log" 2>&1; then
    sed -n '1,200p' "$updater_log" >&2 || true
    fail "updater failed for $source"
  fi

  sed -n '1,200p' "$updater_log"
  assert_file_not_contains "$updater_log" "Exception"
  assert_file_not_contains "$updater_log" "Traceback"
}

write_mock_tools() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"

  cat > "$bin_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${BELA_MOCK_DOCKER_LOG:?BELA_MOCK_DOCKER_LOG is required}"
{
  printf 'PWD=%s\n' "$PWD"
  printf 'docker'
  printf ' %q' "$@"
  printf '\n'
} >> "$log"

if [[ "${1:-}" == "pull" ]]; then
  exit 0
fi

if [[ "${1:-}" != "run" ]]; then
  printf 'Unsupported mock docker command: %s\n' "$*" >&2
  exit 1
fi

network_none=false
entrypoint_prepare=false
bela_mount=""
previous=""

for arg in "$@"; do
  if [[ "$arg" == "--network=none" ]]; then
    network_none=true
  fi

  if [[ "$previous" == "entrypoint" ]]; then
    if [[ "$arg" == "/bin/sh" ]]; then
      entrypoint_prepare=true
    fi
    previous=""
    continue
  fi

  if [[ "$previous" == "volume" ]]; then
    case "$arg" in
      *:/.bela|*:/.bela:*)
        bela_mount="${arg%%:/.bela*}"
        ;;
    esac
    previous=""
    continue
  fi

  case "$arg" in
    --entrypoint)
      previous="entrypoint"
      ;;
    -v)
      previous="volume"
      ;;
  esac
done

if [[ "$entrypoint_prepare" == true ]]; then
  mkdir -p "$PWD/.bela"
  : > "$PWD/.bela/default-prepare-ran"
  exit 0
fi

if [[ "$network_none" != true ]]; then
  printf 'Updater docker run did not include --network=none.\n' >&2
  exit 1
fi

if [[ -z "$bela_mount" ]]; then
  printf 'Updater docker run did not mount /.bela.\n' >&2
  exit 1
fi

mkdir -p "$bela_mount"
printf 'mock ecd for %s\n' "${BELA_SOURCE:-unknown}" > "$bela_mount/bela-update.ecd"
EOF

  cat > "$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${BELA_MOCK_CURL_LOG:?BELA_MOCK_CURL_LOG is required}"
{
  printf 'curl'
  printf ' %q' "$@"
  printf '\n'
} >> "$log"

printf 'curl should not be called when BELA_SKIP_UPLOAD=true.\n' >&2
exit 1
EOF

  chmod +x "$bin_dir/docker" "$bin_dir/curl"
}

write_package_json() {
  local project_dir="$1"

  cat > "$project_dir/package.json" <<'EOF'
{
  "name": "custom-build-fixture",
  "version": "1.0.0"
}
EOF
}

assert_updater_run_count() {
  local docker_log="$1"
  local expected="$2"
  local actual

  actual="$(grep -c -- '--network=none' "$docker_log" || true)"
  [[ "$actual" == "$expected" ]] || fail "expected $expected offline updater run(s), got $actual"
}

write_local_image_docker_wrapper() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"

  cat > "$bin_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

real_docker="${BELA_REAL_DOCKER:?BELA_REAL_DOCKER is required}"

if [[ "${1:-}" == "pull" && "$#" -eq 2 ]]; then
  if "$real_docker" image inspect "$2" > /dev/null 2>&1; then
    printf 'custom-build: using local Docker image %s\n' "$2" >&2
    exit 0
  fi
fi

exec "$real_docker" "$@"
EOF

  chmod +x "$bin_dir/docker"
}

write_node_prepare_script() {
  local fixture_dir="$1"

  cat > "$fixture_dir/prepare-fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

kind="${1:?fixture kind is required}"

mkdir -p .bela src node_modules/fixture-lib

cat > package.json <<JSON
{
  "name": "custom-build-${kind}-fixture",
  "version": "1.0.0",
  "dependencies": {
    "fixture-lib": "1.2.3"
  }
}
JSON

cat > node_modules/fixture-lib/package.json <<'JSON'
{
  "name": "fixture-lib",
  "version": "1.2.3",
  "main": "index.js",
  "types": "index.d.ts"
}
JSON

cat > node_modules/fixture-lib/index.js <<'JS'
function label(value) {
  return `fixture:${value}`;
}

module.exports = { label };
JS

cat > node_modules/fixture-lib/index.d.ts <<'TS'
export function label(value: string): string;
TS

case "$kind" in
  typescript)
    cat > src/index.ts <<'TS'
import { label } from "fixture-lib";

export function describeService(name: string): string {
  return label(name);
}

describeService("orders");
TS
    ;;
  javascript)
    cat > src/index.js <<'JS'
const { label } = require("fixture-lib");

function describeService(name) {
  return label(name);
}

module.exports = { describeService };
JS
    ;;
  *)
    printf 'Unsupported fixture kind: %s\n' "$kind" >&2
    exit 1
    ;;
esac
EOF

  chmod +x "$fixture_dir/prepare-fixture.sh"
}

assert_node_fixture_prepared() {
  local fixture_dir="$1"
  local kind="$2"

  assert_file "$fixture_dir/package.json"
  assert_file "$fixture_dir/node_modules/fixture-lib/package.json"
  assert_file "$fixture_dir/node_modules/fixture-lib/index.js"
  assert_file "$fixture_dir/node_modules/fixture-lib/index.d.ts"
  assert_no_file "$fixture_dir/package-lock.json"
  assert_no_file "$fixture_dir/tsconfig.json"

  case "$kind" in
    typescript)
      assert_file "$fixture_dir/src/index.ts"
      ;;
    javascript)
      assert_file "$fixture_dir/src/index.js"
      ;;
    *)
      fail "unsupported node fixture kind: $kind"
      ;;
  esac
}

run_node_docker_fixture() {
  local tmp_dir="$1"
  local kind="$2"
  local fixture_dir="$tmp_dir/$kind"

  mkdir -p "$fixture_dir"
  write_node_prepare_script "$fixture_dir"

  env \
    BELA_WORKING_DIRECTORY="$fixture_dir" \
    BELA_LANGUAGE=typescript \
    BELA_SOURCE="custom-build/$kind" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}" prepare \
      "./prepare-fixture.sh $kind && rm ./prepare-fixture.sh"

  assert_node_fixture_prepared "$fixture_dir" "$kind"

  run_updater "$fixture_dir" typescript "custom-build/$kind"
  assert_clean_ecd "$fixture_dir/.bela/bela-update.ecd" "custom-build/$kind"
  printf 'custom-build: docker %s fixture passed\n' "$kind"
}

write_java_prepare_script() {
  local fixture_dir="$1"

  cat > "$fixture_dir/prepare-fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .bela src/main/java/com/example target/classes target/dependency

cat > src/main/java/com/example/OrderService.java <<'JAVA'
package com.example;

public class OrderService {
    public String describe(String id) {
        return "order:" + id;
    }
}
JAVA

javac -d target/classes src/main/java/com/example/OrderService.java
: > target/classpath.txt

cat > target/project.properties <<'PROPERTIES'
groupId=com.example
artifactId=custom-build-java-fixture
version=1.0.0
artifactType=gradle
PROPERTIES
EOF

  chmod +x "$fixture_dir/prepare-fixture.sh"
}

assert_java_fixture_prepared() {
  local fixture_dir="$1"

  assert_file "$fixture_dir/src/main/java/com/example/OrderService.java"
  assert_file "$fixture_dir/target/classes/com/example/OrderService.class"
  assert_file "$fixture_dir/target/classpath.txt"
  assert_file "$fixture_dir/target/project.properties"
  assert_file_contains "$fixture_dir/target/project.properties" "artifactType=gradle"
  [[ -d "$fixture_dir/target/dependency" ]] || fail "expected directory to exist: $fixture_dir/target/dependency"
}

run_java_docker_fixture() {
  local tmp_dir="$1"
  local fixture_dir="$tmp_dir/java"

  mkdir -p "$fixture_dir"
  write_java_prepare_script "$fixture_dir"

  env \
    BELA_WORKING_DIRECTORY="$fixture_dir" \
    BELA_LANGUAGE=java \
    BELA_SOURCE="custom-build/java" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}" prepare \
      "./prepare-fixture.sh && rm ./prepare-fixture.sh"

  assert_java_fixture_prepared "$fixture_dir"

  run_updater "$fixture_dir" java "custom-build/java"
  assert_clean_ecd "$fixture_dir/.bela/bela-update.ecd" "custom-build/java"
  printf 'custom-build: docker java fixture passed\n'
}

write_clojure_prepare_script() {
  local fixture_dir="$1"

  cat > "$fixture_dir/prepare-fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .bela .m2/repository src/custom_build

cat > deps.edn <<'EDN'
{:name "custom-build/clojure-fixture"
 :version "1.0.0"
 :paths ["src"]
 :deps {}}
EDN

cat > src/custom_build/clojure_fixture.clj <<'CLJ'
(ns custom-build.clojure-fixture)

(defn describe-service [name]
  (str "service:" name))
CLJ
EOF

  chmod +x "$fixture_dir/prepare-fixture.sh"
}

assert_clojure_fixture_prepared() {
  local fixture_dir="$1"

  assert_file "$fixture_dir/deps.edn"
  assert_file "$fixture_dir/src/custom_build/clojure_fixture.clj"
  [[ -d "$fixture_dir/.m2/repository" ]] || fail "expected directory to exist: $fixture_dir/.m2/repository"
  [[ ! -e "$fixture_dir/.gitlibs" ]] || fail "expected .gitlibs to be absent for a fixture without git dependencies"
}

run_clojure_docker_fixture() {
  local tmp_dir="$1"
  local fixture_dir="$tmp_dir/clojure"

  mkdir -p "$fixture_dir"
  write_clojure_prepare_script "$fixture_dir"

  env \
    BELA_WORKING_DIRECTORY="$fixture_dir" \
    BELA_LANGUAGE=clojure \
    BELA_SOURCE="custom-build/clojure" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}" prepare \
      "./prepare-fixture.sh && rm ./prepare-fixture.sh"

  assert_clojure_fixture_prepared "$fixture_dir"

  run_updater "$fixture_dir" clojure "custom-build/clojure"
  assert_clean_ecd "$fixture_dir/.bela/bela-update.ecd" "custom-build/clojure"
  printf 'custom-build: docker clojure fixture passed\n'
}

write_dotnet_prepare_script() {
  local fixture_dir="$1"

  cat > "$fixture_dir/prepare-fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .bela/dependencies

cat > CustomBuildDotnetFixture.sln <<'SLN'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CustomBuildDotnetFixture", "CustomBuildDotnetFixture.csproj", "{2DF7DD81-09A0-4AF7-B2BA-34857E79E9A7}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{2DF7DD81-09A0-4AF7-B2BA-34857E79E9A7}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{2DF7DD81-09A0-4AF7-B2BA-34857E79E9A7}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{2DF7DD81-09A0-4AF7-B2BA-34857E79E9A7}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{2DF7DD81-09A0-4AF7-B2BA-34857E79E9A7}.Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
EndGlobal
SLN

cat > CustomBuildDotnetFixture.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
XML

cat > OrderService.cs <<'CS'
namespace CustomBuild.DotnetFixture;

public sealed class OrderService
{
    public string Describe(string id)
    {
        return $"order:{id}";
    }
}
CS

dotnet restore CustomBuildDotnetFixture.sln --packages ./.bela/dependencies
EOF

  chmod +x "$fixture_dir/prepare-fixture.sh"
}

assert_dotnet_fixture_prepared() {
  local fixture_dir="$1"

  assert_file "$fixture_dir/CustomBuildDotnetFixture.sln"
  assert_file "$fixture_dir/CustomBuildDotnetFixture.csproj"
  assert_file "$fixture_dir/OrderService.cs"
  assert_file "$fixture_dir/obj/project.assets.json"
  [[ -d "$fixture_dir/.bela/dependencies" ]] || fail "expected directory to exist: $fixture_dir/.bela/dependencies"
}

run_dotnet_docker_fixture() {
  local tmp_dir="$1"
  local fixture_dir="$tmp_dir/dotnet"

  mkdir -p "$fixture_dir"
  write_dotnet_prepare_script "$fixture_dir"

  env \
    BELA_WORKING_DIRECTORY="$fixture_dir" \
    BELA_LANGUAGE=dotnet \
    BELA_SOURCE="custom-build/dotnet" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}" prepare \
      "./prepare-fixture.sh && rm ./prepare-fixture.sh"

  assert_dotnet_fixture_prepared "$fixture_dir"

  run_updater "$fixture_dir" dotnet "custom-build/dotnet"
  assert_clean_ecd "$fixture_dir/.bela/bela-update.ecd" "custom-build/dotnet"
  assert_file_contains "$fixture_dir/.bela/bela-update.ecd" "/assembly/CustomBuildDotnetFixture [assembly]"
  assert_file_contains "$fixture_dir/.bela/bela-update.ecd" "OrderService [class]"
  printf 'custom-build: docker dotnet fixture passed\n'
}

run_mock_mode() {
  local tmp_dir
  local repo
  local mock_bin
  local docker_log
  local curl_log
  local direct_project
  local inherited_project
  local overridden_project

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bela-custom-build.XXXXXX")"
  cleanup_dir="$tmp_dir"
  repo="$tmp_dir/repo"
  mock_bin="$tmp_dir/bin"
  docker_log="$tmp_dir/docker.log"
  curl_log="$tmp_dir/curl.log"
  direct_project="$repo/direct"
  inherited_project="$repo/inherited"
  overridden_project="$repo/overridden"

  trap cleanup EXIT

  mkdir -p \
    "$repo/.bela" \
    "$direct_project/.bela" \
    "$inherited_project" \
    "$overridden_project/.bela"

  write_mock_tools "$mock_bin"
  write_package_json "$direct_project"
  write_package_json "$inherited_project"
  write_package_json "$overridden_project"

  cat > "$repo/.bela/bela.yml" <<'EOF'
build-command: pwd > .bela/inherited-build-pwd && printf 'inherited\n' > .bela/inherited-build-ran
EOF

  cat > "$direct_project/.bela/bela.yml" <<'EOF'
build-command: pwd > .bela/direct-build-pwd && printf 'direct\n' > .bela/direct-build-ran
EOF

  cat > "$overridden_project/.bela/bela.yml" <<'EOF'
build-command: pwd > .bela/override-build-pwd && printf 'override\n' > .bela/override-build-ran
EOF

  env \
    PATH="$mock_bin:$PATH" \
    BELA_MOCK_DOCKER_LOG="$docker_log" \
    BELA_MOCK_CURL_LOG="$curl_log" \
    BELA_SKIP_UPLOAD=true \
    BELA_LOG_TAIL_LINES=80 \
    BELA_WORKING_DIRECTORY="$repo" \
    GITHUB_WORKSPACE="$repo" \
    GITHUB_REPOSITORY="example/custom-build-test" \
    node "${BELA_ACTION_ENTRYPOINT:-$repo_dir/src/index.js}"

  assert_file_equals "$direct_project/.bela/direct-build-pwd" "$direct_project"
  assert_file_contains "$direct_project/.bela/direct-build-ran" "direct"
  assert_no_file "$direct_project/.bela/inherited-build-ran"
  assert_file "$direct_project/.bela/bela-update.ecd"

  assert_file_equals "$inherited_project/.bela/inherited-build-pwd" "$inherited_project"
  assert_file_contains "$inherited_project/.bela/inherited-build-ran" "inherited"
  assert_file "$inherited_project/.bela/bela-update.ecd"

  assert_file_equals "$overridden_project/.bela/override-build-pwd" "$overridden_project"
  assert_file_contains "$overridden_project/.bela/override-build-ran" "override"
  assert_no_file "$overridden_project/.bela/inherited-build-ran"
  assert_file "$overridden_project/.bela/bela-update.ecd"

  assert_no_file "$direct_project/.bela/default-prepare-ran"
  assert_no_file "$inherited_project/.bela/default-prepare-ran"
  assert_no_file "$overridden_project/.bela/default-prepare-ran"
  assert_file_not_contains "$docker_log" "--entrypoint"
  assert_updater_run_count "$docker_log" 3

  if [[ -s "$curl_log" ]]; then
    fail "curl was called even though BELA_SKIP_UPLOAD=true"
  fi

  printf 'custom-build: mock mode passed\n'
}

run_docker_mode() {
  local tmp_dir
  local real_docker
  local bin_dir

  command -v docker > /dev/null || fail "docker is required for --docker mode"
  real_docker="$(command -v docker)"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bela-custom-build-docker.XXXXXX")"
  cleanup_dir="$tmp_dir"
  bin_dir="$tmp_dir/bin"
  trap cleanup EXIT
  write_local_image_docker_wrapper "$bin_dir"

  export BELA_REAL_DOCKER="$real_docker"
  export PATH="$bin_dir:$PATH"

  run_node_docker_fixture "$tmp_dir" typescript
  run_node_docker_fixture "$tmp_dir" javascript
  run_java_docker_fixture "$tmp_dir"
  run_clojure_docker_fixture "$tmp_dir"
  run_dotnet_docker_fixture "$tmp_dir"

  printf 'custom-build: docker mode passed\n'
}

case "${1:-}" in
  --mock)
    run_mock_mode
    ;;
  --docker)
    run_docker_mode
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
