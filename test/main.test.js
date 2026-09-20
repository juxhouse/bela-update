import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { run, contextFromEnv, dispatch } from '../src/main.js';

const contextFor = root => ({ root, workspace: root, repository: 'org/repo', branch: 'feature/x',
  apiUrl: 'https://bela.example/api', apiToken: 'token', updaterTag: 'test' });

const servicesFor = (root, calls, outputs) => ({
  activeBranches: async () => { calls.push('branches'); return ['feature/x']; },
  prepare: async item => { calls.push(`prepare:${item.sourceBase}`); },
  runUpdater: async item => {
    calls.push(`updater:${item.sourceBase}`);
    const file = path.join(root, '.bela', 'generated.ecd');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'fresh ecd\n');
    return file;
  },
  upload: async () => { calls.push('upload'); },
  syncActiveBranches: async (url, token, source, branches) => { calls.push(['sync', source, branches]); },
  setOutput: (name, value) => { outputs[name] = value; },
});

test('dry run writes compatible output values without Git, Docker or HTTP', async t => {
  const { root, write } = fixture(t);
  write('package.json');
  const calls = [], outputs = {};
  await run({ ...contextFor(root), dryRun: true, apiUrl: undefined, apiToken: undefined }, servicesFor(root, calls, outputs));
  assert.deepEqual(calls, []);
  assert.deepEqual(outputs, { languages: 'typescript', sources: 'org/repo (feature/x)' });
  assert.equal(fs.existsSync(path.join(root, '.bela')), false);
});

test('skip-upload prepares and generates ECD without Git or HTTP', async t => {
  const { root, write } = fixture(t);
  write('package.json');
  const calls = [], outputs = {};
  await run({ ...contextFor(root), skipUpload: true }, servicesFor(root, calls, outputs));
  assert.deepEqual(calls, ['prepare:org/repo', 'updater:org/repo']);
});

test('all projects upload before branch sync and produce ordered outputs', async t => {
  const { root, write } = fixture(t);
  write('a/package.json');
  write('b/pom.xml');
  const calls = [], outputs = {};
  await run(contextFor(root), servicesFor(root, calls, outputs));
  assert.deepEqual(calls, ['branches', 'prepare:org/repo/a', 'updater:org/repo/a', 'upload',
    'prepare:org/repo/b', 'updater:org/repo/b', 'upload',
    ['sync', 'org/repo/a', ['feature/x']], ['sync', 'org/repo/b', ['feature/x']]]);
  assert.deepEqual(outputs, { languages: 'typescript,java',
    sources: 'org/repo/a (feature/x),org/repo/b (feature/x)' });
});

test('prepare, updater, upload or sync failure prevents success outputs', async t => {
  for (const stage of ['prepare', 'runUpdater', 'upload', 'syncActiveBranches']) {
    const { root, write } = fixture(t);
    write('package.json');
    const calls = [], outputs = {};
    const services = servicesFor(root, calls, outputs);
    services[stage] = async () => { throw new Error(`failure in ${stage}`); };
    await assert.rejects(run(contextFor(root), services), new RegExp(`failure in ${stage}`));
    assert.deepEqual(outputs, {});
    if (stage !== 'syncActiveBranches') assert.equal(calls.some(call => Array.isArray(call) && call[0] === 'sync'), false);
  }
});

test('missing configuration and Git failures stop before preparation', async t => {
  const { root, write } = fixture(t);
  const calls = [], outputs = {};
  const services = servicesFor(root, calls, outputs);
  await assert.rejects(run(contextFor(root), services), /Could not detect/);
  write('package.json');
  await assert.rejects(run({ ...contextFor(root), apiToken: '' }, services), /BELA_API_TOKEN/);
  await assert.rejects(run(contextFor(root), { ...services, activeBranches: async () => { throw new Error('Git failed'); } }), /Could not determine active Git branches/);
  assert.deepEqual(calls, []);
});

test('environment parsing preserves flags and CLI errors have an exit code', async t => {
  const { root } = fixture(t);
  const context = contextFromEnv({ BELA_WORKING_DIRECTORY: root, BELA_DRY_RUN: 'true', BELA_SKIP_UPLOAD: 'false', BELA_UPDATER_TAG: '' });
  assert.equal(context.workspace, root);
  assert.equal(context.updaterTag, 'latest');
  assert.equal(context.dryRun, true);
  assert.equal(context.skipUpload, false);
  await assert.rejects(dispatch(['unknown']), error => error.exitCode === 2);
  await assert.rejects(dispatch(['prepare'], { BELA_WORKING_DIRECTORY: root }), /BELA_LANGUAGE/);
});
