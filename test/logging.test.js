import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { runLogged, printLines } from '../src/logging.js';
import { setOutput } from '../src/actions.js';

test('logged failures retain process details and propagate the original exit code', async t => {
  const { root } = fixture(t);
  const file = path.join(root, 'logs', 'failure.log');
  await assert.rejects(runLogged('Expected failure', file, output => {
    fs.writeSync(output, 'detail line\n');
    throw Object.assign(new Error('expected failure'), { exitCode: 17 });
  }), error => error.exitCode === 17);
  assert.equal(fs.readFileSync(file, 'utf8'), 'detail line\nexpected failure\n');
  const lines = [];
  await printLines(file, 1, { tail: true, write: line => lines.push(line) });
  assert.deepEqual(lines, ['expected failure']);
});

test('GitHub output values preserve newlines without creating additional output keys', t => {
  const { write } = fixture(t);
  const file = write('output');
  const previous = process.env.GITHUB_OUTPUT;
  process.env.GITHUB_OUTPUT = file;
  t.after(() => {
    if (previous === undefined) delete process.env.GITHUB_OUTPUT;
    else process.env.GITHUB_OUTPUT = previous;
  });
  const value = 'org/repo/a\nsurprise=value (branch)';
  setOutput('sources', value);
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const delimiter = lines[0].slice('sources<<'.length);
  assert.equal(lines[0], `sources<<${delimiter}`);
  assert.equal(lines.slice(1, -2).join('\n'), value);
  assert.equal(lines.at(-2), delimiter);
});
