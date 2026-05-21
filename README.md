# BELA Update Action

GitHub Action for updating BELA from a repository without sending source code to BELA.

The action discovers supported projects in GitHub Actions, prepares each project, runs the matching BELA updater Docker image with `--network=none`, and uploads only generated `.bela/bela-update.ecd` files to the BELA API.

## Table of Contents

- [Action](#action)
- [Reusable Workflow](#reusable-workflow)
- [Supported Detection](#supported-detection)
- [Project Discovery](#project-discovery)
- [Security Model](#security-model)

## Action

Use the [action](https://docs.github.com/en/actions/concepts/workflows-and-actions/about-custom-actions) directly when you need to customize the job or run project-specific steps before the update.

```yaml
name: Update BELA

on:
  workflow_dispatch:

jobs:
  bela-update:
    runs-on: ubuntu-latest
    permissions:
      contents: read

    steps:
      - uses: actions/checkout@v4

      - uses: juxhouse/bela-update@v0.1.0
        env:
          BELA_API_URL: ${{ vars.BELA_API_URL }}
          BELA_API_TOKEN: ${{ secrets.BELA_API_TOKEN }}
          BELA_PARENT_ELEMENT_PATH: ${{ vars.BELA_PARENT_ELEMENT_PATH }}
```

### Action Environment Variables

When using the action directly, configuration is passed through environment variables.

| Name | Required | Description |
| --- | --- | --- |
| `BELA_API_URL` | yes | BELA backend URL. |
| `BELA_API_TOKEN` | yes | BELA API token. |
| `BELA_PARENT_ELEMENT_PATH` | no | Optional BELA parent element path. |

## Reusable Workflow

Use the [reusable workflow](https://docs.github.com/en/actions/reference/workflows-and-actions/reusable-workflows) when the default update job is enough for your repository.

```yaml
name: Update BELA

on:
  workflow_dispatch:

jobs:
  bela-update:
    uses: juxhouse/bela-update/.github/workflows/bela-update.yml@v0.1.0
    with:
      bela-api-url: ${{ vars.BELA_API_URL }}
      parent-element-path: ${{ vars.BELA_PARENT_ELEMENT_PATH }}
    secrets:
      BELA_API_TOKEN: ${{ secrets.BELA_API_TOKEN }}
```

### Reusable Workflow Inputs

| Input | Required | Description |
| --- | --- | --- |
| `bela-api-url` | yes | BELA backend URL. |
| `parent-element-path` | no | Optional BELA parent element path. |

### Reusable Workflow Secrets

| Name | Required | Description |
| --- | --- | --- |
| `BELA_API_TOKEN` | yes | BELA API token used to upload the generated ECD file. |

## Supported Detection

The action automatically detects:

| Language | Files |
| --- | --- |
| C# | `*.sln`, `*.csproj` |
| Clojure | `deps.edn`, `project.clj` |
| Java | `pom.xml`, `build.gradle`, `build.gradle.kts`, `gradlew` |
| JavaScript | `package.json` |
| Ruby | `Gemfile` |
| TypeScript | `package.json` |

## Project Discovery

The action starts at the repository root. If it detects a project there, it updates BELA from that project and does not scan deeper.

If the root is not a project, the action scans child directories. When it finds a project in a directory, it updates BELA from that directory and does not scan that directory's children. It still continues scanning sibling directories.

## Security Model

Project preparation may use the network to download dependencies, as normal CI builds do.

The updater execution step runs with:

```sh
docker run --network=none --pull=never ...
```

That means the analysis container receives the prepared workspace but cannot access the network while reading customer code. The only data uploaded to BELA is `.bela/bela-update.ecd`.
