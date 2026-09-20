# Node.js migration

Compared against `origin/main` at `179a02c90d1fb9954a0e8d1381185b2c63a9b854`
and the local Babashka implementation on `detected-improvements`.

The action now uses JavaScript ES modules, function expressions and Node.js 24.
Project organization follows `bela-integrations/typescript`: `src/`, `test/`,
`import`/`export`, camelCase and npm scripts. It uses Node's native test runner.
Only YAML parsing requires a runtime library; esbuild packages the published action.

## Compatibility

- Discovery retains Clojure → TypeScript/JavaScript → Java → .NET precedence,
  sorted traversal, skipped dependency/output directories, and stopping at each
  detected project. Directory symlinks are not followed.
- `.bela/bela.yml` inherits build commands and individual updater options down the
  directory tree. Ignored directories prune the whole subtree. The stricter
  YAML validation from the Babashka version is retained; invalid/unknown keys,
  duplicate keys, aliases, inline updater maps and complex option values fail.
- Custom build commands still run through `bash -lc` in the project directory.
  They replace all default preparation, including Java helper/cache creation,
  matching `main`. Node orchestrates the build tools; shell snippets still run
  inside the existing Docker images or as user-provided build commands.
- Default preparation images, commands, Java Gradle metadata and Maven mounts
  follow `main`. Updater execution retains `--network=none --pull=never` and the
  existing language-specific arguments and mounts.
- `BELA_API_URL` is the complete API base URL, including `/api`, as on current
  `main`. Node appends `/ecd-architecture` or `/active-branches-set` directly.
  Upload sends the raw ECD bytes with the existing Authorization header and
  content type. No HTTP redirects are followed.
- Source naming and comma-separated output values are unchanged. GitHub outputs
  use the multiline file format so directory names containing newlines cannot
  introduce extra output keys.
- Branch discovery still fetches/prunes and expands shallow clones, uses
  `origin/HEAD` with event/remote fallbacks, and reports unmerged branches. Results
  are scoped to `origin`; refs from other remotes are excluded. Sync only runs
  after all project uploads succeed.
- Dry run and skip-upload retain their behavior. Logs remain under `.bela/logs`.
  Required API settings are checked before preparing projects. Old generated ECD
  files are removed before analysis so a successful process cannot upload stale data.

## Verification

`npm test` covers discovery/configuration, Docker command contracts, real child
processes, local HTTP requests, orchestration failures, output encoding and branch
sync against a real shallow Git clone. `npm run test:integration` exercises the
CLI with mock Docker commands. CI repeats this against the committed bundle and
invokes the native action in dry-run mode.

The optional real-updater check is `tests/custom-build.sh --docker`; it is separate
from the network-free mock tests and requires a running Docker daemon.
