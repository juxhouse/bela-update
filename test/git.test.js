import path from 'node:path';
import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { activeBranches, originMainBranch } from '../src/git.js';
import { run } from '../src/process.js';

test('active branches fetch all refs, prune and unshallow when necessary', async () => {
  for (const shallow of [true, false]) {
    const calls = [];
    const execute = async argv => {
      calls.push(argv);
      if (argv.includes('rev-parse')) return { stdout: `${shallow}\n` };
      if (argv.includes('symbolic-ref')) return { stdout: 'origin/trunk\n' };
      return { stdout: 'feature/a\nfeature/b\n' };
    };
    assert.deepEqual(await activeBranches('/repo', undefined, execute), ['feature/a', 'feature/b']);
    const fetch = calls.find(argv => argv.includes('fetch'));
    assert.ok(fetch.includes('+refs/heads/*:refs/remotes/origin/*'));
    assert.ok(fetch.includes('--prune'));
    assert.equal(fetch.includes('--unshallow'), shallow);
  }
});

test('default branch falls back to the event, then remote HEAD, and otherwise fails', async t => {
  const { write } = fixture(t);
  const event = write('event.json', JSON.stringify({ repository: { default_branch: 'trunk' } }));
  assert.equal(await originMainBranch('/repo', event, async argv => {
    if (argv.includes('symbolic-ref')) throw new Error('missing');
    assert.equal(argv.at(-1), 'refs/remotes/origin/trunk');
    return { stdout: '' };
  }), 'origin/trunk');
  let attempts = 0;
  assert.equal(await originMainBranch('/repo', undefined, async argv => {
    if (argv.includes('symbolic-ref') && attempts++ === 0) throw new Error('missing');
    return { stdout: 'origin/main\n' };
  }), 'origin/main');
  await assert.rejects(originMainBranch('/repo', undefined, async () => { throw new Error('missing'); }), /Could not determine/);
});

test('real shallow clone excludes merged, deleted and other-remote branches', async t => {
  const { root } = fixture(t);
  const origin = path.join(root, 'origin');
  const clone = path.join(root, 'clone');
  const git = (...args) => run(['git', ...args], { capture: true });
  await git('init', '-b', 'trunk', origin);
  await git('-C', origin, 'config', 'user.name', 'BELA Test');
  await git('-C', origin, 'config', 'user.email', 'bela-test@example.invalid');
  await git('-C', origin, 'commit', '--allow-empty', '-m', 'base');
  await git('-C', origin, 'branch', 'merged');
  await git('-C', origin, 'checkout', '-b', 'feature/active');
  await git('-C', origin, 'commit', '--allow-empty', '-m', 'feature');
  await git('-C', origin, 'branch', 'deleted');
  await git('-C', origin, 'checkout', 'trunk');
  await git('clone', '--depth=1', `file://${origin}`, clone);
  const feature = (await git('-C', origin, 'rev-parse', 'feature/active')).stdout.trim();
  await git('-C', clone, 'fetch', 'origin', '+refs/heads/*:refs/remotes/origin/*');
  await git('-C', clone, 'update-ref', 'refs/remotes/other/not-ours', feature);
  await git('-C', origin, 'branch', '-D', 'deleted');
  assert.deepEqual(await activeBranches(clone), ['feature/active']);
  assert.equal((await git('-C', clone, 'rev-parse', '--is-shallow-repository')).stdout.trim(), 'false');
  await assert.rejects(git('-C', clone, 'show-ref', '--verify', 'refs/remotes/origin/deleted'));
  // A checkout with no symbolic origin/HEAD can still use GitHub's event metadata.
  await git('-C', clone, 'symbolic-ref', '--delete', 'refs/remotes/origin/HEAD');
  const event = path.join(root, 'event.json');
  fs.writeFileSync(event, JSON.stringify({ repository: { default_branch: 'trunk' } }));
  assert.deepEqual(await activeBranches(clone, event), ['feature/active']);
});
