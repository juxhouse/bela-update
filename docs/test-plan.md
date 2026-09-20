# BELA Custom Build Validation Plan

This plan validates only the custom build path. The normal action flow has already been smoke-tested in another repository and generated the expected number of ECD files, so this document intentionally ignores broad action coverage.

The goal is to prove that:

- `build-command` behaves the way `docs/bela-directory.md` says it behaves;
- the `*-Other.md` updater docs in `bela-resources/updaters` describe enough prepared files for the updater to analyse a project offline;
- the action connects those two contracts correctly.

## Out Of Scope

Do not spend time on:

- validating project count discovery beyond the minimum needed to reach a custom-build project;
- upload behavior;
- active branch sync;
- `GITHUB_OUTPUT` formatting;
- default language preparation behavior when `build-command` is not set;
- CI wiring.

Those can be tested later if needed. They are not the point of this pass.

## Contracts To Validate

### Action Contract

`docs/bela-directory.md` currently says:

- `build-command` is configured in `.bela/bela.yml`;
- configuration is applied from the action working directory down to detected projects;
- values closer to the project override parent values;
- `build-command` runs directly on the runner from the detected project directory;
- `build-command` replaces the language default preparation command;
- the command must leave the project in the state expected by the updater.

The scripts should match that contract:

- `src/project.js` resolves the effective build command for each detected project;
- `src/main.js` passes that command to `src/execution.js`;
- `src/execution.js` runs `bash -lc "$build_command"` inside `BELA_WORKING_DIRECTORY`;
- when a custom command exists, default Docker preparation is skipped;
- updater execution runs afterward with `--network=none`.

### Updater Documentation Contract

Use these docs as the source of truth:

- `/home/kauwai/projetos/bela/bela-resources/updaters/Java-Other.md`
- `/home/kauwai/projetos/bela/bela-resources/updaters/Typescript-Other.md`
- `/home/kauwai/projetos/bela/bela-resources/updaters/Javascript-Other.md`
- `/home/kauwai/projetos/bela/bela-resources/updaters/Clojure-Other.md`
- `/home/kauwai/projetos/bela/bela-resources/updaters/.NET-Other.md`

Each language fixture should prepare only what its `*-Other.md` file says is required. If the real updater cannot analyse that prepared fixture offline, then either the action behavior, the fixture, or the documentation is wrong.

## Test Shape

Create a focused script:

```text
tests/custom-build.sh
```

The script should support two modes:

```sh
tests/custom-build.sh --mock
tests/custom-build.sh --docker
```

Use temporary repositories under `/tmp`. Do not commit generated dependency folders such as `node_modules`, `.m2`, `.gitlibs`, `target`, `.bela/dependencies`, or NuGet package directories.

## Mock Mode

Mock mode validates action routing without real updater images.

It should:

- create one small detected project with `.bela/bela.yml` defining `build-command`;
- make the custom command write marker files such as `.bela/custom-build-ran`;
- put mock `docker` and `curl` commands on a temporary `PATH`;
- run the Node orchestrator with `BELA_SKIP_UPLOAD=true`;
- make the mock updater create `.bela/bela-update.ecd`;
- assert that the custom command ran from the detected project directory;
- assert that default preparation did not run;
- assert that the updater phase still ran after custom preparation;
- assert that updater Docker execution used `--network=none`.

Mock mode should also include the smallest possible config inheritance check because the docs currently describe inheritance:

- parent `.bela/bela.yml` with `build-command`;
- child detected project inheriting that command;
- child `.bela/bela.yml` overriding the parent command.

Do not test unrelated discovery edge cases here.

## Docker Mode

Docker mode validates that the custom build docs describe real updater contracts.

For each supported updater-doc contract, create a temporary fixture project, run a custom build command that prepares exactly the documented files, then run the normal updater step offline.

The core flow should be:

```sh
BELA_WORKING_DIRECTORY="$fixture"
BELA_LANGUAGE="$language"
BELA_SOURCE="$source"
node src/index.js prepare "$custom_build_command"
node src/index.js updater
test -f "$fixture/.bela/bela-update.ecd"
```

The important assertion is not just that an ECD exists. The fixture must be intentionally prepared according to the matching `*-Other.md` doc, so a passing updater run proves the doc and action contract agree.

## Language Fixtures

### Java

Validate the Java custom-build doc with one Maven-shaped fixture and one non-Maven fixture if practical.

The custom command should create:

- `.bela`;
- `src/main/java`;
- `target/classes`;
- `target/classpath.txt`;
- dependency JARs through either `$HOME/.m2` for Maven projects or `target/dependency` for non-Maven projects;
- `target/project.properties` for non-Maven projects, with `artifactType` and `artifactId`, plus `groupId` when `artifactType=maven`.

The updater should run offline and produce `.bela/bela-update.ecd`.

### TypeScript And JavaScript

`Javascript-Other.md` points to `Typescript-Other.md`, so test one TypeScript fixture and one JavaScript fixture against the same documented contract.

The custom command should create:

- `.bela`;
- `package.json`;
- source files;
- `node_modules` with the packages imported by the source files;
- `package-lock.json` only when the fixture is testing lock-file version reading;
- `tsconfig.json` only for the TypeScript fixture when compiler options are needed;
- any generated files imported by the source.

Do not treat a lock file as a replacement for `node_modules`. The docs say `node_modules` must exist for offline module resolution.

### Clojure

The custom command should create:

- `.bela`;
- `deps.edn` or `project.clj`;
- source files under `src`;
- `.m2/repository`;
- `.gitlibs/libs` only when the fixture uses git dependencies.

The test should not claim `.gitlibs` is always required. It is required only for projects with git dependencies.

### .NET

The custom command should create:

- `.bela`;
- `.sln` plus the `.csproj` files it references;
- source files referenced by those project files;
- `.bela/dependencies` for .NET Core projects;
- restored package directories inside the workspace for .NET Framework projects, if a .NET Framework fixture is included.

Start with .NET Core unless there is a clear reason to add a .NET Framework fixture. Use a solution-based fixture because the current .NET updater opens solution files.

## Acceptance Criteria

The first useful pass is done when these commands pass locally:

```sh
npm test
shellcheck -x tests/custom-build.sh
bash -n tests/custom-build.sh
git diff --check
tests/custom-build.sh --mock
tests/custom-build.sh --docker
```

If `--docker` requires updater images that are not already present, it may pull them. The updater execution itself must still run offline with `--network=none`.

## Agent Handoff

Start with `tests/custom-build.sh --mock`. Keep it narrow:

- prove custom `build-command` runs;
- prove default preparation is skipped;
- prove parent and project-level `build-command` behavior matches `docs/bela-directory.md`;
- prove the updater step still runs offline afterward.

After that, implement `--docker` one language at a time. For each language, read the matching `*-Other.md` doc first, build the smallest fixture that satisfies that doc, and run the updater offline.

Do not add broad action smoke tests in this pass. This is a custom-build/docs-contract validation task.
