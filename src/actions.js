import fs from 'node:fs';
import { randomUUID } from 'node:crypto';

const escapeData = value => String(value).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');

const command = (name, value = '') => console.log(`::${name}::${escapeData(value)}`);

const setOutput = (name, value) => {
  if (!process.env.GITHUB_OUTPUT) return;
  const delimiter = `bela_${randomUUID()}`;
  fs.appendFileSync(process.env.GITHUB_OUTPUT, `${name}<<${delimiter}\n${value}\n${delimiter}\n`);
};

export { command, setOutput };
