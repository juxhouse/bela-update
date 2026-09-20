import { openAsBlob } from 'node:fs';
import { isFile } from './project.js';

const post = async (apiUrl, token, endpoint, body, contentType) => {
  const response = await fetch(`${apiUrl.replace(/\/+$/, '')}/${endpoint}`, {
    method: 'POST',
    headers: { Authorization: token, 'Content-Type': contentType },
    body,
    redirect: 'error',
    signal: AbortSignal.timeout(300_000),
  });
  // Neither endpoint returns data needed by the action.
  await response.body?.cancel();
  if (!response.ok) throw new Error(`BELA API request failed with HTTP status ${response.status}.`);
};

const upload = async (apiUrl, token, ecdFile) => {
  if (!isFile(ecdFile)) throw new Error(`Could not find generated ECD file at ${ecdFile}`);
  await post(apiUrl, token, 'ecd-architecture', await openAsBlob(ecdFile), 'application/x-www-form-urlencoded');
};

const syncActiveBranches = async (apiUrl, token, source, branches) => {
  await post(apiUrl, token, 'active-branches-set', JSON.stringify({ source, activeBranches: branches }), 'application/json');
};

export { upload, syncActiveBranches };
