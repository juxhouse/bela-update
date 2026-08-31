# BELA Update Action

This is the easiest way to keep BELA in sync with your repo if it uses a **standard build**.

> [!IMPORTANT]
> If your project has a non-standard build, this action might NOT work. Use the [BELA Docker App](https://github.com/juxhouse/bela-resources/blob/main/CodeSynchronization.md) directly instead.

## Create the Action

Create an action called `.github/workflows/bela-update.yml` in your repo.

```yaml
name: bela-update
on:
  push:
  workflow_dispatch:  # Allows manual execution.

jobs:
  update-bela-arch:
    runs-on: ubuntu-latest
    permissions:
      contents: read

    steps:
      - uses: actions/checkout@v4

      - id: bela
        uses: juxhouse/bela-update@2026-08-23
        env:
          BELA_API_URL: "https://${{ vars.BELA_HOST }}"
          BELA_API_TOKEN: ${{ secrets.BELA_TOKEN }}
          # Optional parent element path:
          BELA_PARENT_ELEMENT_PATH: ${{ vars.BELA_PARENT_ELEMENT_PATH }}
```

### Secrets and Environment Variables

On your project's Github page, go to `Settings > Secrets and variables > Actions`

On the Secrets tab, create a secret for:



| Name | Description |
| --- | --- |
| `BELA_API_URL` | BELA backend URL. |
| `BELA_API_TOKEN` | BELA API token. |
| `BELA_PARENT_ELEMENT_PATH` | Optional. Parent element path. |


## Supported Languages

The action automatically detects projects in these languages:

| Language | Files |
| --- | --- |
| C# | `*.sln`, `*.csproj` |
| Clojure | `deps.edn`, `project.clj` |
| Java | `pom.xml`, `build.gradle`, `build.gradle.kts`, `gradlew` |
| JavaScript | `package.json` |
| TypeScript | `package.json` |

## Project Discovery

The action starts at the repository root. If it detects a project there, it updates BELA from that project and does not scan deeper.

If the root is not a project, the action scans child directories. When it finds a project in a directory, it updates BELA from that directory and does not scan that directory's children. It still continues scanning sibling directories.

## Branch Sources

On each push, the action includes the GitHub branch in the source name using the format `source-name (branch-name)`. After all detected projects are uploaded successfully, it fetches and prunes the repository's remote branches and sends the branches that are not merged into `origin/HEAD` to BELA. BELA uses that list to remove branch sources for deleted or merged branches.

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

## Security Model

Project preparation may use the network to download dependencies, as normal CI builds do.

The updater execution step runs with:

```sh
docker run --network=none --pull=never ...
```

That means the analysis container receives the prepared workspace but cannot access the network while reading customer code. The only data uploaded to BELA is `.bela/bela-update.ecd`.
