import http from 'node:http';
import { once } from 'node:events';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './helpers.js';
import { upload, syncActiveBranches } from '../src/api.js';

test('HTTP requests preserve the API base path, authorization, ECD bytes and JSON body', async t => {
  const { write } = fixture(t);
  const requests = [];
  const server = http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    requests.push({ url: request.url, headers: request.headers, body: Buffer.concat(chunks) });
    response.writeHead(204).end();
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/api/`;
  const contents = Buffer.from('source org/repo\nUnicode: ação\n&raw=1\0');
  await upload(url, 'test-token', write('output.ecd', contents));
  await syncActiveBranches(url, 'test-token', 'org/repo/service', ['feature/a', 'branch "quoted"']);
  assert.equal(requests[0].url, '/api/ecd-architecture');
  assert.equal(requests[0].headers.authorization, 'test-token');
  assert.equal(requests[0].headers['content-type'], 'application/x-www-form-urlencoded');
  assert.deepEqual(requests[0].body, contents);
  assert.equal(requests[1].url, '/api/active-branches-set');
  assert.equal(requests[1].headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(requests[1].body), {
    source: 'org/repo/service', activeBranches: ['feature/a', 'branch "quoted"'],
  });
});

test('failed HTTP responses fail the action and redirects are not followed', async t => {
  let status = 500;
  let calls = 0;
  const server = http.createServer((request, response) => {
    calls++;
    request.resume();
    response.writeHead(status, { Location: '/unexpected' }).end('failure');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}`;
  await assert.rejects(syncActiveBranches(url, 'token', 'repo', []), /HTTP status 500/);
  status = 302;
  await assert.rejects(syncActiveBranches(url, 'token', 'repo', []));
  assert.equal(calls, 2);
});
