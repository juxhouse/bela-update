import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { run } from '../src/process.js';

test('published bundle runs independently without node_modules and writes action outputs', async t => {
  const { root, write } = fixture(t);
  const bundle = path.join(root, 'action.cjs');
  fs.copyFileSync(new URL('../dist/index.cjs', import.meta.url), bundle);
  const workspace = path.join(root, 'workspace');
  write('workspace/.bela/bela.yml', 'updater-args:\n  parent-element-path: "test parent"\n');
  write('workspace/a/package.json');
  write('workspace/b/pom.xml');
  const output = write('outputs');
  const { stdout } = await run([process.execPath, bundle], {
    cwd: workspace, capture: true,
    env: { ...process.env, BELA_WORKING_DIRECTORY: workspace, BELA_DRY_RUN: 'true',
      BELA_PARENT_ELEMENT_PATH: '', GITHUB_WORKSPACE: workspace,
      GITHUB_REPOSITORY: 'org/repo', GITHUB_REF_NAME: 'feature/x', GITHUB_OUTPUT: output },
  });
  assert.match(stdout, /parent-element-path: test parent/);
  const outputs = Object.fromEntries([...fs.readFileSync(output, 'utf8')
    .matchAll(/(\w+)<<(bela_[^\n]+)\n([^]*?)\n\2\n/g)].map(match => [match[1], match[3]]));
  assert.deepEqual(outputs, { languages: 'typescript,java', sources: 'org/repo/a (feature/x),org/repo/b (feature/x)' });
  await assert.rejects(run([process.execPath, bundle, 'invalid'], { cwd: root, capture: true }), error => error.exitCode === 2);
});
