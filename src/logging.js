import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { command } from './actions.js';

const groupStart = (title) => {
  if (process.env.GITHUB_ACTIONS === 'true') command('group', title);
  else console.log(`\n==> ${title}`);
};

const groupEnd = () => {
  if (process.env.GITHUB_ACTIONS === 'true') command('endgroup');
};

const slug = (value) => {
  return value.replace(/[^A-Za-z0-9._-]/g, '-').replace(/^-+|-+$/g, '') || 'project';
};

const printLines = async (file, count, { tail = false, write = console.log } = {}) => {
  if (count === 0) return;
  const stream = fs.createReadStream(file, { encoding: 'utf8' });
  const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
  const buffer = [];
  let index = 0;
  try {
    for await (const line of lines) {
      if (tail) buffer[index % count] = line;
      else write(line);
      index++;
      if (!tail && index >= count) break;
    }
    if (tail) {
      const start = index >= count ? index % count : 0;
      for (let i = 0; i < buffer.length; i++) write(buffer[(start + i) % buffer.length]);
    }
  } finally {
    lines.close();
    stream.destroy();
  }
};

const runLogged = async (title, file, operation) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  groupStart(title);
  console.log('Writing detailed logs to', file);
  const output = fs.openSync(file, 'w');
  try {
    const result = await operation(output);
    console.log('Completed:', title);
    return result;
  } catch (error) {
    fs.writeSync(output, `${error.message}\n`);
    console.error('Failed:', title);
    const configured = process.env.BELA_LOG_TAIL_LINES || '200';
    const count = /^-?\d+$/.test(configured) && Number.isSafeInteger(Number(configured))
      ? Math.abs(Number(configured)) : 200;
    await printLines(file, count, { tail: true, write: console.error });
    throw error;
  } finally {
    fs.closeSync(output);
    groupEnd();
  }
};

export { groupStart, groupEnd, slug, printLines, runLogged };
