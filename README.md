# BELA Update Action

GitHub Action for updating BELA from a repository without sending source code to BELA.

The action discovers supported projects in GitHub Actions, prepares each project, runs the matching BELA updater Docker image with `--network=none`, and uploads only generated `.bela/bela-update.ecd` files to the BELA API.

## Table of Contents

- [Action](#action)
- [Supported Detection](#supported-detection)
- [Project Discovery](#project-discovery)
- [Repository Configuration](#repository-configuration)
- [Security Model](#security-model)

## Action

Use the [action](https://docs.github.com/en/actions/concepts/workflows-and-actions/about-custom-actions) directly when you need to customize the job or run project-specific steps before the update.

```yaml
name: update-bela
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
        uses: juxhouse/bela-update@2026-07-13-09-40
        env:
          BELA_API_URL: "https://${{ vars.BELA_HOST }}"
          BELA_API_TOKEN: ${{ secrets.BELA_TOKEN }}
          BELA_PARENT_ELEMENT_PATH: ${{ vars.BELA_PARENT_ELEMENT_PATH }}
```

### Action Environment Variables

When using the action directly, configuration is passed through environment variables.

| Name | Required | Description |
| --- | --- | --- |
| `BELA_API_URL` | yes | BELA backend URL. |
| `BELA_API_TOKEN` | yes | BELA API token. |
| `BELA_PARENT_ELEMENT_PATH` | no | Optional default BELA parent element path. `.bela/bela.yml` can override it with `updater-args.parent-element-path`. |


## Supported Detection

The action automatically detects:

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
