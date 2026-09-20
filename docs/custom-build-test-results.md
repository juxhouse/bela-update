# BELA Custom Build Test Results

Node migration update (2026-09-19): the Node test suite and custom-build mock
integration pass. The standalone bundled action is also checked without installed
dependencies. Real Docker integration could not be rerun because the Docker daemon
is unavailable. The per-language results below describe the historical Bash runs,
not a new validation of the Node implementation against real updater images.

Tested on 2026-08-24 with `tests/custom-build.sh`.

Updated on 2026-08-31: the .NET fixture was changed from `.csproj`-only to solution-based so it matches the current updater, which opens `.sln` files. Static checks and mock mode passed after this adjustment, but Docker mode still needs to be rerun with the Docker daemon available.

## Summary

The custom build validation now has two modes:

```sh
tests/custom-build.sh --mock
tests/custom-build.sh --docker
```

Before the Babashka migration, the original local verification passed:

```sh
bash -n scripts/*.sh scripts/utils/*.sh tests/custom-build.sh
shellcheck -x scripts/*.sh scripts/utils/*.sh tests/custom-build.sh
git diff --check
tests/custom-build.sh --mock
tests/custom-build.sh --docker
```

The Node implementation uses `npm test` plus the same mock and optional
Docker integration modes. These run automatically in `.github/workflows/test.yml`
except for Docker mode, which remains an explicit local integration check.

Docker mode used local updater images when present, so `docker pull` did not need Docker Hub during the test. The updater execution itself still used `docker run --pull=never --network=none`.

## Mock Mode

Purpose: validate action routing without real updater images.

How it was tested:

- Created a temporary repository under `/tmp`.
- Created three detected TypeScript projects:
  - one project with its own `build-command`;
  - one project inheriting `build-command` from the repository root;
  - one project overriding the inherited `build-command`.
- Put fake `docker` and `curl` binaries on `PATH`.
- Ran the BELA orchestrator with `BELA_SKIP_UPLOAD=true`.

Assertions:

- The custom command ran from each detected project directory.
- Parent config inheritance worked.
- Project-local config overrode parent config.
- Default prepare did not run when `build-command` was set.
- The updater phase still ran after custom preparation.
- The updater Docker command included `--network=none`.
- No upload was attempted because upload was skipped. Node's orchestration tests
  verify that both HTTP upload and branch sync are skipped.

Result: pass.

## TypeScript

Source doc: `/home/kauwai/projetos/bela/bela-resources/updaters/Typescript-Other.md`

How it was tested:

- Created a temporary fixture under `/tmp`.
- Ran the preparation entry point with a custom build command.
- The custom command created:
  - `.bela`;
  - `package.json`;
  - `src/index.ts`;
  - `node_modules/fixture-lib/package.json`;
  - `node_modules/fixture-lib/index.js`;
  - `node_modules/fixture-lib/index.d.ts`.
- Deliberately did not create `package-lock.json` or `tsconfig.json`, because this fixture did not test lock-file version reading or custom compiler options.
- Ran the updater entry point offline.

Assertions:

- The documented files existed before updater execution.
- `.bela/bela-update.ecd` existed after updater execution.
- The ECD contained `source custom-build/typescript`.
- The ECD did not contain error or warning markers.
- The updater log did not contain exception traces.

Result: pass.

## JavaScript

Source doc: `/home/kauwai/projetos/bela/bela-resources/updaters/Javascript-Other.md`

How it was tested:

- Used the TypeScript/JavaScript shared contract, because `Javascript-Other.md` points to `Typescript-Other.md`.
- Created a temporary fixture under `/tmp`.
- Ran the preparation entry point with a custom build command.
- The custom command created:
  - `.bela`;
  - `package.json`;
  - `src/index.js`;
  - `node_modules/fixture-lib/package.json`;
  - `node_modules/fixture-lib/index.js`;
  - `node_modules/fixture-lib/index.d.ts`.
- Deliberately did not create `package-lock.json` or `tsconfig.json`.
- Ran the updater entry point offline with the TypeScript updater, matching current project detection behavior.

Assertions:

- The documented files existed before updater execution.
- `.bela/bela-update.ecd` existed after updater execution.
- The ECD contained `source custom-build/javascript`.
- The ECD did not contain error or warning markers.
- The updater log did not contain exception traces.

Result: pass.

## Java

Source doc: `/home/kauwai/projetos/bela/bela-resources/updaters/Java-Other.md`

How it was tested:

- Created a non-Maven temporary fixture under `/tmp`.
- Ran the preparation entry point with a custom build command.
- The custom command created:
  - `.bela`;
  - `src/main/java/com/example/OrderService.java`;
  - `target/classes/com/example/OrderService.class`, compiled with `javac`;
  - `target/classpath.txt`;
  - `target/dependency`;
  - `target/project.properties`.
- Ran the updater entry point offline.

Assertions:

- The documented files existed before updater execution.
- `.bela/bela-update.ecd` existed after updater execution.
- The ECD contained `source custom-build/java`.
- The ECD did not contain error or warning markers.
- The updater log did not contain exception traces.

Result: pass.

Note: the Java updater now requires `artifactType` and `artifactId` in `target/project.properties`. If `artifactType=maven`, `groupId` is also required. When `groupId` is present the ECD project path is Maven-style; when it is absent the path is `artifactType/artifactId`. Missing `version` defaults to `0.0.0`.

## Clojure

Source doc: `/home/kauwai/projetos/bela/bela-resources/updaters/Clojure-Other.md`

How it was tested:

- Created a temporary fixture under `/tmp`.
- Ran the preparation entry point with a custom build command.
- The custom command created:
  - `.bela`;
  - `deps.edn`;
  - `src/custom_build/clojure_fixture.clj`;
  - `.m2/repository`.
- Deliberately did not create `.gitlibs`, because the fixture has no git dependencies and the doc says `.gitlibs/libs` is required only when the project uses git dependencies.
- Ran the updater entry point offline.

Assertions:

- The documented files existed before updater execution.
- `.gitlibs` was absent for this no-git-dependency fixture.
- `.bela/bela-update.ecd` existed after updater execution.
- The ECD contained `source custom-build/clojure`.
- The ECD did not contain error or warning markers.
- The updater log did not contain exception traces.

Result: pass.

Note: the Clojure updater prints nonfatal `ls` and `cp` messages for missing `.gitlibs` even when the fixture has no git dependencies. The ECD was clean and the updater completed successfully.

## .NET

Source doc: `/home/kauwai/projetos/bela/bela-resources/updaters/.NET-Other.md`

How it was tested:

- Created a solution-based .NET Core temporary fixture under `/tmp`.
- Ran the preparation entry point with a custom build command.
- The custom command created:
  - `.bela/dependencies`;
  - `CustomBuildDotnetFixture.sln`;
  - `CustomBuildDotnetFixture.csproj`;
  - `OrderService.cs`;
  - `obj/project.assets.json` via `dotnet restore CustomBuildDotnetFixture.sln --packages ./.bela/dependencies`.
- Targeted `net9.0` because the runner and updater image both had .NET 9 available.
- Ran the updater entry point offline.

Assertions:

- The documented files existed before updater execution.
- `.bela/bela-update.ecd` existed after updater execution.
- The ECD contained `source custom-build/dotnet`.
- The ECD contained `/assembly/CustomBuildDotnetFixture [assembly]`.
- The ECD contained `OrderService [class]`.
- The ECD did not contain error or warning markers.
- The updater log did not contain exception traces.

Result after 2026-08-31 fixture adjustment: pending Docker rerun.

## Remaining Gaps

- Java Maven-shaped fixture was not added. The passing Java fixture covers the non-Maven `target/project.properties` path.
- .NET Framework fixture was not added. The passing .NET fixture covers solution-based .NET Core, as planned.
- The original run excluded CI wiring; the Node migration adds unit, mock,
  bundle consistency and native-action dry-run checks in CI.
