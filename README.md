# BELA Update Action

This is the easiest way to keep BELA in sync with your Github repo if it uses a **standard build**.

> [!IMPORTANT]
> If your project has a non-standard build, this action might NOT work. Use the [BELA Docker App](https://github.com/juxhouse/bela-resources/blob/main/CodeSynchronization.md) directly instead.

## Create the Action

You just need to create an action called `.github/workflows/bela-update.yml` in your repo.

```yaml
name: bela-update
on:
  push:
  workflow_dispatch:  # Allows manual execution.

jobs:
  update-bela-arch:
    runs-on: ubuntu-latest
    permissions:
      contents: read  # Ensures the action cannot write to your repo

    steps:
      - uses: actions/checkout@v4

      - id: bela
        uses: juxhouse/bela-update@v1
        env:
          BELA_API_URL: "https://${{ vars.BELA_HOST }}/api"
          BELA_API_TOKEN: ${{ secrets.BELA_API_TOKEN }}
```

On your project's Github page, go to `Settings > Secrets and variables > Actions`

- `BELA_HOST` - Create this in the VARIABLES tab. Example `acme.bela.live`
- `BELA_API_TOKEN` - Create this in the SECRETS tab. You can obtain your token from the BELA app: `BELA > Sources > Use API`

Commit and push that to Github and you're done!

### Action Environment Variables

| Name | Required | Description |
| --- | --- | --- |
| `BELA_API_URL` | yes | BELA API base URL, including `/api`, e.g. `https://acme.bela.live/api`. |
| `BELA_API_TOKEN` | yes | BELA API token. |
| `BELA_PARENT_ELEMENT_PATH` | no | Optional default BELA parent element path. `.bela/bela.yml` can override it with `updater-args.parent-element-path`. |
| `BELA_WORKING_DIRECTORY` | no | Directory where discovery starts. Defaults to the current directory. |
| `BELA_UPDATER_TAG` | no | Docker updater tag. Defaults to `latest`. |
| `BELA_DRY_RUN` | no | Set to `true` to discover projects and write outputs without preparing, analysing or uploading. |
| `BELA_SKIP_UPLOAD` | no | Set to `true` to generate and preview ECD files without uploading or synchronizing branches. |
| `BELA_LOG_TAIL_LINES` | no | Number of log lines printed after a failed step. Defaults to `200`. |

The action runs with GitHub's Node.js 24 runtime. Use a Linux runner with Git,
Bash and Docker available, such as `ubuntu-latest`. Callers do not need to install
Node.js, npm dependencies, Babashka, `curl` or `jq` for the action.

The `languages` and `sources` outputs contain comma-separated values in project
discovery order. JavaScript and TypeScript both use the `typescript` updater.

## Supported Languages

The action automatically detects projects in these languages:

| Language | Files |
| --- | --- |
| C# | `*.sln`, `*.csproj` |
| Clojure | `deps.edn`, `project.clj` |
| Java | `pom.xml`, `build.gradle`, `build.gradle.kts`, `gradlew` |
| JavaScript | `package.json` |
| TypeScript | `package.json` |

## How it Works

The action searches the folders in your repo for projects. When it detects a project, it does not scan deeper into its subfolders.

If the root is not a project, the action scans child directories. When it finds a project in a directory, it updates BELA from that directory and does not scan that directory's children. It still continues scanning sibling directories.

## Branch Sources

On each push, the action includes the GitHub branch in the source name using the format `source-name (branch-name)`. Before processing projects, it fetches and prunes the repository's remote branches. After all detected projects are uploaded successfully, it sends the branches that are not merged into `origin/HEAD` to BELA. BELA uses that list to remove branch sources for deleted or merged branches.

The action uses `origin/HEAD` or the repository's default branch from the GitHub event to identify the main branch. Branch cleanup is skipped when `BELA_DRY_RUN=true` or `BELA_SKIP_UPLOAD=true`.

## Repository Configuration

Any directory can define BELA configuration in `.bela/bela.yml`. The action applies configuration from the repository root down to each detected project, with the closest config taking precedence.

```yaml
ignore-projects: true
build-command: "./scripts/build-for-bela.sh --profile legacy-ci"
updater-args:
  parent-element-path: "billing-service"
  ignore-test-code: true
```

> [!IMPORTANT]
> `updater-args` must use options supported by the updater for the detected project. See the [BELA updater docs](https://github.com/juxhouse/bela-resources/tree/main/updaters) for options available by updater.

See [`.bela` directory configuration](docs/bela-directory.md) for the supported keys and inheritance rules.

## Parent Element Path
You can add an extra env var to the action, like this:

`BELA_PARENT_ELEMENT_PATH: path/to/the/parent/element`

## Security Model

Project preparation may use the network to download dependencies, as normal CI builds do.

The updater execution step runs with:

```sh
docker run --network=none --pull=never ...
```

That means the analysis container receives the prepared workspace but cannot access the network while reading customer code. The only data uploaded to BELA is `.bela/bela-update.ecd`.

## Development

Use Node.js 24 and npm:

```sh
npm ci
npm test
npm run test:integration
npm run build
npm run check:dist
```

Source files use ES modules and function expressions (`const name = (...) =>`).
`yaml` is the only runtime dependency; filesystem access, child processes, HTTP,
GitHub outputs and tests use Node built-ins. `esbuild` is a development dependency
used to bundle the action, including YAML parsing, into `dist/index.cjs`.
Commit the generated bundle with source changes so callers can run the action
without installing packages. CI checks that the bundle matches its sources.

| Module | Responsibility |
| --- | --- |
| `src/project.js` | Language detection, configuration inheritance and project discovery. |
| `src/execution.js` | Preparation commands and offline Docker updater execution. |
| `src/git.js` | Default branch detection and active branch discovery. |
| `src/api.js` | ECD upload and active branch synchronization. |
| `src/main.js` | Orchestration and CLI commands. |
| `src/process.js`, `src/logging.js`, `src/actions.js` | Processes, logs and GitHub workflow commands. |

To inspect a repository locally:

```sh
BELA_WORKING_DIRECTORY=/path/to/repository BELA_DRY_RUN=true npm start
```

`node src/index.js prepare 'your build command'` and `node src/index.js updater`
can also run individual stages. Both require `BELA_LANGUAGE`; the updater also
requires `BELA_SOURCE`. `BELA_UPDATER_ARGS` accepts one argument per line for the
standalone updater command.

`tests/custom-build.sh --docker` is an optional integration check against real
updaters. It requires a running Docker daemon, Java (`javac`) and the .NET SDK on
the host. See [migration notes](docs/node-migration.md) for compatibility decisions.
