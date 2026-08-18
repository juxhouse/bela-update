# `.bela` Directory Configuration

The action uses `.bela` for BELA-specific repository metadata and generated output. A repository, subdirectory, or project directory can include a `.bela/bela.yml` file to control how projects in that directory tree are discovered and prepared.

The supported config format is a small top-level YAML subset:

```yaml
ignore-projects: true
build-command: "./scripts/build-for-bela.sh --profile legacy-ci"
updater-args:
  parent-element-path: "billing-service"
  ignore-test-code: true
```

## Inheritance

Configuration is applied from the action working directory down to each detected project. Values defined closer to the project override values from parent directories.

For example:

```text
repo/
  .bela/bela.yml
  services/
    .bela/bela.yml
    billing/
      pom.xml
```

The `billing` project receives config from `repo/.bela/bela.yml`, then `repo/services/.bela/bela.yml`. When both files configure the same behavior, the value from `services` wins.

## Keys

### `ignore-projects`

When set to `true`, the action ignores every project in the same directory and its descendants.

```yaml
ignore-projects: true
```

This is useful for examples, archived code, generated fixtures, or projects that should not be sent to BELA.

### `build-command`

Sets the build or preparation command for all projects in the directory tree.

```yaml
build-command: "./scripts/build-for-bela.sh --profile legacy-ci"
```

This value overrides any value inherited from parent directories. The command runs from the detected project directory inside the same container environment that the language default uses.

When `build-command` is set, it replaces the language default preparation command. The command must leave the project in the state expected by the updater.

### `updater-args`

Configures options used when updating a detected project, such as where to place imported elements or whether test code should be included.

```yaml
updater-args:
  parent-element-path: "billing-service"
  ignore-test-code: true
```

Common options:

| Name | Description |
| --- | --- |
| `parent-element-path` | Places imported elements under the given BELA parent element path. |
| `ignore-test-code` | Excludes test code when supported by the updater. |

