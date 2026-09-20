import { spawn } from 'node:child_process';

const run = (argv, { cwd, env = process.env, output = 'inherit', capture = false } = {}) => {
  return new Promise((resolve, reject) => {
    const child = spawn(argv[0], argv.slice(1), {
      cwd, env, shell: false,
      stdio: ['ignore', capture ? 'pipe' : output, capture ? 'pipe' : output],
    });
    let stdout = '';
    let stderr = '';
    if (capture) {
      child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
      child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    }
    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(Object.assign(new Error(`Command ${argv[0]} failed ${signal ? `with signal ${signal}` : `with exit code ${code}`}.`), {
        exitCode: code || 1, stdout, stderr,
      }));
    });
  });
};

export { run };
