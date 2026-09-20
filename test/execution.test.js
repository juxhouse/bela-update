import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { prepareCommands, prepare, updaterCommand, runUpdater, envUpdaterArgs } from '../src/execution.js';
import { run } from '../src/process.js';

test('custom builds run on the host in the project directory with BELA context', async t => {
  const { root, write } = fixture(t);
  const script = write('custom build.cjs', "require('node:fs').writeFileSync('result.json', JSON.stringify([process.cwd(), process.env.BELA_LANGUAGE, process.env.BELA_SOURCE]))");
  await prepare({ directory: root, language: 'java', source: 'org/repo (branch)',
    buildCommand: `"${process.execPath}" "${script}"` });
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'result.json'))), [root, 'java', 'org/repo (branch)']);
  assert.equal(fs.existsSync(path.join(root, 'bela.gradle')), false);
  assert.deepEqual(prepareCommands({ buildCommand: '   ' }), [['bash', '-lc', '   ']]);
});

test('custom Maven preparation needs no HOME and does not initialize default caches', async t => {
  const { root, write } = fixture(t);
  write('pom.xml');
  await prepare({ directory: root, language: 'java', buildCommand: 'true' });
  assert.equal(fs.existsSync(path.join(root, '.m2')), false);
});

test('default preparation selects updater/build images, Maven cache and Gradle helper', async t => {
  const { root, write } = fixture(t);
  for (const language of ['clojure', 'typescript', 'dotnet', 'java']) {
    const calls = [];
    await prepare({ directory: root, language, updaterTag: 'test' }, 'inherit', async argv => calls.push(argv));
    const image = language === 'java' ? 'gradle:8.10.2-jdk21' : `juxhouse/bela-updater-${language}:test`;
    assert.deepEqual(calls[0], ['docker', 'pull', image]);
    assert.ok(calls[1].includes(`${root}:/workspace`));
    assert.ok(calls[1].includes('-lc'));
  }
  assert.match(fs.readFileSync(path.join(root, 'bela.gradle'), 'utf8'), /task belaBuild/);
  write('pom.xml');
  const calls = [];
  const home = path.join(root, 'home');
  await prepare({ directory: root, language: 'java', home }, 'inherit', async argv => calls.push(argv));
  assert.ok(fs.statSync(path.join(home, '.m2')).isDirectory());
  assert.deepEqual(calls[0], ['docker', 'pull', 'maven:3.9.6-eclipse-temurin-21']);
  assert.ok(calls[1].includes(`${home}/.m2:/root/.m2`));
  assert.match(calls[1].at(-1), /dependency:build-classpath/);
});

test('updaters run offline with literal arguments and language-specific mounts', t => {
  const { root, write } = fixture(t);
  write('pom.xml');
  for (const language of ['clojure', 'typescript', 'java', 'dotnet']) {
    const argv = updaterCommand({ directory: root, language, source: 'org/repo (feature/x)',
      home: root, updaterArgs: ['-label', 'spaces; $(touch unexpected)'], updaterTag: 'test' });
    for (const arg of ['--network=none', '--pull=never', `${root}:/workspace`, `${root}/.bela:/.bela`,
      'org/repo (feature/x)', 'spaces; $(touch unexpected)']) assert.ok(argv.includes(arg));
    if (language === 'java') assert.ok(argv.includes(`${root}/.m2:/.m2:ro`));
    if (language === 'dotnet') {
      assert.ok(argv.includes('/App/CodeAnalyzer.dll'));
      assert.deepEqual(argv.slice(-4), ['-workspace', '/workspace', '-output', '/.bela/bela-update.ecd']);
    }
  }
});

test('updater rejects stale or missing ECD files, and returns a fresh result', async t => {
  const { root, write } = fixture(t);
  const ecd = write('.bela/bela-update.ecd', 'stale');
  const project = { directory: root, language: 'typescript', source: 'repo' };
  await assert.rejects(runUpdater(project, 'inherit', async () => {}), /Could not find generated ECD/);
  assert.equal(fs.existsSync(ecd), false);
  assert.equal(await runUpdater(project, 'inherit', async argv => {
    if (argv[1] === 'run') write('.bela/bela-update.ecd', 'fresh');
  }), ecd);
  assert.equal(fs.readFileSync(ecd, 'utf8'), 'fresh');
});

test('process arguments are literal, and spawn/process failures propagate', async () => {
  const value = 'value with spaces; $(echo should-not-run)';
  const result = await run([process.execPath, '-e', 'process.stdout.write(process.argv[1])', value], { capture: true });
  assert.equal(result.stdout, value);
  await assert.rejects(run([process.execPath, '-e', 'process.exit(17)']), error => error.exitCode === 17);
  await assert.rejects(run(['bela-command-that-does-not-exist']), { code: 'ENOENT' });
  assert.deepEqual(envUpdaterArgs('-one\r\nvalue with spaces\r\n-two\r\n'), ['-one', 'value with spaces', '-two']);
  assert.deepEqual(envUpdaterArgs('\n\n'), []);
  assert.deepEqual(envUpdaterArgs('   '), ['   ']);
});
