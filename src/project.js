import fs from 'node:fs';
import path from 'node:path';
import { parseDocument, isMap, isScalar } from 'yaml';

const skippedDirectories = new Set([
  '.git', '.github', '.bela', 'node_modules', 'vendor', 'target', 'build',
  'dist', 'out', 'coverage', '.gradle', '.m2', '.gitlibs',
]);
const allowedKeys = new Set(['ignore-projects', 'build-command', 'updater-args']);

const isFile = (file) => {
  try {
    return fs.statSync(file).isFile();
  } catch (error) {
    if (['ENOENT', 'ENOTDIR'].includes(error.code)) return false;
    throw error;
  }
};

const detectLanguage = (directory) => {
  const has = (...names) => names.some(name => isFile(path.join(directory, name)));
  if (has('deps.edn', 'project.clj')) return 'clojure';
  if (has('package.json')) return 'typescript';
  if (has('pom.xml', 'build.gradle', 'build.gradle.kts', 'gradlew')) return 'java';
  if (fs.readdirSync(directory).some(name => /\.(sln|csproj)$/.test(name) && has(name))) return 'dotnet';
  return null;
};

const readConfig = (directory) => {
  const file = path.join(directory, '.bela', 'bela.yml');
  if (!isFile(file)) return {};
  const invalid = message => {
    throw new Error(`Invalid BELA configuration in ${file}: ${message}`);
  };
  const document = parseDocument(fs.readFileSync(file, 'utf8'));
  if (document.errors.length) invalid(document.errors[0].message);
  const root = document.contents;
  if (!root) return {};
  if (!isMap(root)) invalid('the document must be a mapping.');
  const config = {};
  for (const { key, value } of root.items) {
    if (!isScalar(key) || !allowedKeys.has(key.value)) {
      invalid(`unsupported top-level key: ${String(key)}.`);
    }
    switch (key.value) {
      case 'ignore-projects': {
        if (!isScalar(value) || !/^(true|false)$/i.test(String(value.value))) {
          invalid('ignore-projects must be true or false.');
        }
        config.ignoreProjects = String(value.value).toLowerCase() === 'true';
        break;
      }
      case 'build-command': {
        if (!isScalar(value) || typeof value.value !== 'string' || /[\r\n\0]/.test(value.value)) {
          invalid('build-command must be a single-line string.');
        }
        config.buildCommand = value.value;
        break;
      }
      case 'updater-args': {
        config.updaterOptions = {};
        if (isScalar(value) && value.value === null && value.source === '') break;
        if (!isMap(value) || value.flow) invalid('updater-args must use a nested block mapping.');
        for (const option of value.items) {
          if (!isScalar(option.key) || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(String(option.key.value))) {
            invalid(`invalid updater option name '${String(option.key)}'.`);
          }
          if (!isScalar(option.value) || /[\r\n\0]/.test(String(option.value.value))) {
            invalid(`updater-args.${option.key.value} must be a single-line scalar value.`);
          }
          // Define own properties safely, including names such as "constructor".
          Object.defineProperty(config.updaterOptions, String(option.key.value), {
            value: option.value.value == null ? '' : String(option.value.value),
            enumerable: true, configurable: true, writable: true,
          });
        }
        break;
      }
    }
  }
  return config;
};

const updaterArgv = (options) => {
  return Object.keys(options).sort().flatMap(key => options[key] === '' ? [] : [`-${key}`, options[key]]);
};

const discoverProjects = (root, { parentElementPath } = {}) => {
  const projects = [];
  const pending = [{
    directory: fs.realpathSync(root), buildCommand: '',
    updaterOptions: parentElementPath ? { 'parent-element-path': parentElementPath } : {},
  }];
  // An explicit stack keeps deeply nested repositories off the JavaScript call stack.
  while (pending.length) {
    const inherited = pending.pop();
    const { directory } = inherited;
    const config = readConfig(directory);
    if (config.ignoreProjects) continue;
    const effective = {
      directory,
      buildCommand: config.buildCommand ?? inherited.buildCommand,
      updaterOptions: { ...inherited.updaterOptions, ...config.updaterOptions },
    };
    const language = detectLanguage(directory);
    if (language) {
      projects.push({ ...effective, language, updaterArgs: updaterArgv(effective.updaterOptions) });
      continue;
    }
    const children = fs.readdirSync(directory, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && !skippedDirectories.has(entry.name))
      .map(entry => entry.name).sort().reverse();
    for (const name of children) pending.push({ ...effective, directory: path.join(directory, name) });
  }
  return projects;
};

const sourceBase = (directory, workspace, repository = 'repo') => {
  if (!workspace) return repository;
  const relative = path.relative(fs.realpathSync(workspace), fs.realpathSync(directory));
  if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    return repository;
  }
  return `${repository}/${relative.split(path.sep).join('/')}`;
};

export { isFile, skippedDirectories, detectLanguage, readConfig, updaterArgv, discoverProjects, sourceBase };
