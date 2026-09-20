import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const fixture = t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bela-node-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const write = (name, contents = '') => {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
    return file;
  };
  return { root, write };
};
