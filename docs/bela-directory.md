# `.bela` Directory Configuration

The action uses `.bela` for BELA-specific repository metadata and generated output. A repository, subdirectory, or project directory can include a `.bela/bela.yml` file to control how projects in that directory tree are discovered and prepared.

The supported config format is a small top-level YAML subset:

```yaml
ignore-projects: true
parent-element-path: "billing-service"
build-command: "./scripts/build-for-bela.sh --profile legacy-ci"
```

Nested YAML objects and multiline values are not supported.

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

The `billing` project receives config from `repo/.bela/bela.yml`, then `repo/services/.bela/bela.yml`. If both files set `parent-element-path` or `build-command`, the value from `services` wins.

## Keys

### `ignore-projects`

When set to `true`, the action ignores every project in the same directory and its descendants.

```yaml
ignore-projects: true
```

This is useful for examples, archived code, generated fixtures, or projects that should not be sent to BELA.

### `parent-element-path`

Sets the BELA parent element path for all projects in the directory tree.

```yaml
parent-element-path: "billing-service"
```

This value overrides `BELA_PARENT_ELEMENT_PATH` and any value inherited from parent directories.

### `build-command`

Sets the build or preparation command for all projects in the directory tree.

```yaml
build-command: "./scripts/build-for-bela.sh --profile legacy-ci"
```

This value overrides any value inherited from parent directories. The command runs from the detected project directory inside the same container environment that the language default uses.

When `build-command` is set, it replaces the language default preparation command. The command must leave the project in the state expected by the updater.
