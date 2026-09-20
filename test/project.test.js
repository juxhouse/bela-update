import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { detectLanguage, discoverProjects, readConfig, sourceBase, skippedDirectories } from '../src/project.js';

test('detects every supported marker and preserves language precedence', t => {
  const { root, write } = fixture(t);
  for (const [marker, language] of [
    ['a.sln', 'dotnet'], ['a.csproj', 'dotnet'], ['pom.xml', 'java'],
    ['build.gradle', 'java'], ['build.gradle.kts', 'java'], ['gradlew', 'java'],
    ['package.json', 'typescript'], ['deps.edn', 'clojure'], ['project.clj', 'clojure'],
  ]) {
    const file = write(`markers/${marker}`);
    assert.equal(detectLanguage(path.dirname(file)), language);
    fs.unlinkSync(file);
    write(`precedence/${marker}`);
    assert.equal(detectLanguage(path.join(root, 'precedence')), language);
  }
});

test('discovery is sorted, skips generated trees and symlinks, and stops at a project', t => {
  const { root, write } = fixture(t);
  write('b/pom.xml');
  write('a project/package.json');
  write('a project/nested/deps.edn');
  for (const skip of skippedDirectories) write(`${skip}/nested/package.json`);
  fs.symlinkSync(root, path.join(root, 'cycle'));
  fs.symlinkSync(path.join(root, 'b'), path.join(root, 'alias'));
  assert.deepEqual(discoverProjects(root).map(p => path.basename(p.directory)), ['a project', 'b']);
  write('package.json');
  assert.equal(discoverProjects(root).length, 1);
  assert.equal(discoverProjects(root)[0].directory, root);
});

test('inherits configuration, overrides individual options, ignores subtrees and isolates siblings', t => {
  const { root, write } = fixture(t);
  write('.bela/bela.yml', 'build-command: root build\nupdater-args:\n  alpha: root\n  empty:\n');
  write('services/.bela/bela.yml', 'build-command: parent build\nupdater-args:\n  alpha: parent\n  beta: true\n');
  write('services/a/package.json');
  write('services/b/package.json');
  write('services/b/.bela/bela.yml', 'build-command: ""\nupdater-args:\n  alpha: ""\n  beta: false\n  parent-element-path: "billing # service" # comment\n');
  write('z/package.json');
  write('ignored/.bela/bela.yml', 'ignore-projects: true\n');
  write('ignored/nested/package.json');
  const [a, b, z] = discoverProjects(root, { parentElementPath: 'default' });
  assert.equal(a.buildCommand, 'parent build');
  assert.deepEqual(a.updaterArgs, ['-alpha', 'parent', '-beta', 'true', '-parent-element-path', 'default']);
  assert.equal(b.buildCommand, '');
  assert.deepEqual(b.updaterArgs, ['-beta', 'false', '-parent-element-path', 'billing # service']);
  assert.equal(z.buildCommand, 'root build');
  assert.deepEqual(z.updaterArgs, ['-alpha', 'root', '-parent-element-path', 'default']);
});

test('rejects invalid YAML and unsupported configuration with file context', t => {
  const { root, write } = fixture(t);
  for (const content of [
    'unknown: value', '- a\n- list', 'build-command: [echo, no]', 'build-command: 123',
    'build-command: |\n  echo one\n  echo two\n', 'ignore-projects: sometimes',
    'updater-args: inline', 'updater-args: {option: value}',
    '"updater-args": {option: value}', 'updater-args:\n  bad option: value',
    'updater-args:\n  multiline: |\n    one\n    two\n',
    'updater-args:\n  nested:\n    key: value', 'build-command: a\nbuild-command: b',
    'updater-args:\n  alias: &a hello\n  another: *a',
    'updater-args:\n  bad: "\\0"', 'build-command: [',
  ]) {
    write('.bela/bela.yml', content);
    assert.throws(() => readConfig(root), /Invalid BELA configuration.*bela.yml/s, content);
  }
});

test('empty configs and scalar options retain supported semantics', t => {
  const { root, write } = fixture(t);
  assert.deepEqual(readConfig(root), {});
  write('.bela/bela.yml', '# just a comment\n');
  assert.deepEqual(readConfig(root), {});
  write('.bela/bela.yml', 'ignore-projects: "TRUE"\nupdater-args:\n');
  assert.deepEqual(readConfig(root), { ignoreProjects: true, updaterOptions: {} });
  write('.bela/bela.yml', 'updater-args:\n  zero: 0\n  flag: false\n  blank:\n  space: "   "\n  constructor: safe\n');
  write('package.json');
  assert.deepEqual(discoverProjects(root)[0].updaterArgs, ['-constructor', 'safe', '-flag', 'false', '-space', '   ', '-zero', '0']);
});

test('source names use canonical workspace-relative paths', t => {
  const { root, write } = fixture(t);
  write('workspace/path with spaces/package.json');
  write('workspace-other/package.json');
  const workspace = path.join(root, 'workspace');
  fs.symlinkSync(workspace, path.join(root, 'linked'));
  assert.equal(sourceBase(path.join(workspace, 'path with spaces'), path.join(root, 'linked'), 'org/repo'), 'org/repo/path with spaces');
  assert.equal(sourceBase(workspace, workspace, 'org/repo'), 'org/repo');
  assert.equal(sourceBase(path.join(root, 'workspace-other'), workspace, 'org/repo'), 'org/repo');
});
