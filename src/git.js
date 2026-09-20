import fs from 'node:fs';
import { run } from './process.js';

const eventDefaultBranch = (eventPath) => {
  try {
    const branch = JSON.parse(fs.readFileSync(eventPath, 'utf8')).repository?.default_branch;
    return typeof branch === 'string' && branch ? branch : null;
  } catch {
    return null;
  }
};

const originMainBranch = async (directory, eventPath, execute = run) => {
  const git = (...args) => execute(['git', '-C', directory, ...args], { capture: true });
  const head = async () => {
    try {
      return (await git('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')).stdout.trim();
    } catch { return null; }
  };
  const symbolic = await head();
  if (symbolic) return symbolic;
  const branch = eventDefaultBranch(eventPath);
  if (branch) {
    try {
      await git('show-ref', '--verify', '--quiet', `refs/remotes/origin/${branch}`);
      return `origin/${branch}`;
    } catch { /* Try the remote's advertised HEAD next. */ }
  }
  try { await git('remote', 'set-head', 'origin', '--auto'); } catch { /* Checked below. */ }
  const remoteHead = await head();
  if (remoteHead) return remoteHead;
  throw new Error('Could not determine the main branch from origin/HEAD or the GitHub event.');
};

const activeBranches = async (directory, eventPath, execute = run) => {
  const git = (...args) => ['git', '-C', directory, ...args];
  const shallow = (await execute(git('rev-parse', '--is-shallow-repository'), { capture: true })).stdout.trim() === 'true';
  await execute(git('fetch', 'origin', '+refs/heads/*:refs/remotes/origin/*', '--prune', '--filter=blob:none',
    ...(shallow ? ['--unshallow'] : [])));
  const main = await originMainBranch(directory, eventPath, execute);
  const { stdout } = await execute(git('for-each-ref', '--format=%(refname:strip=3)', `--no-merged=${main}`, 'refs/remotes/origin/'), { capture: true });
  return stdout.split(/\r?\n/).map(line => line.trim()).filter(branch => branch && branch !== 'HEAD');
};

export { eventDefaultBranch, originMainBranch, activeBranches };
