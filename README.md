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
        uses: juxhouse/bela-update@2026-08-23
        env:
          BELA_API_URL: "https://${{ vars.BELA_HOST }}/api"
          BELA_API_TOKEN: ${{ secrets.BELA_API_TOKEN }}
```

On your project's Github page, go to `Settings > Secrets and variables > Actions`

- `BELA_HOST` - Create this in the VARIABLES tab. Example `acme.bela.live`
- `BELA_API_TOKEN` - Create this in the SECRETS tab. You can obtain your token from the BELA app: `BELA > Sources > Use API`

Commit and push that to Github and you're done!

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
