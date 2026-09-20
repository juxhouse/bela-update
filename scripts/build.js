import fs from 'node:fs';
import { build } from 'esbuild';

const main = async () => {
  const result = await build({
    entryPoints: ['src/index.js'], bundle: true, platform: 'node', target: 'node24',
    format: 'cjs', outfile: 'dist/index.cjs', write: false, legalComments: 'eof',
    banner: { js: `/*! Bundled dependency: yaml\n${fs.readFileSync('node_modules/yaml/LICENSE', 'utf8')}*/` },
  });
  const bundle = result.outputFiles[0].contents;
  if (process.argv.includes('--check')) {
    if (!fs.existsSync('dist/index.cjs') || !fs.readFileSync('dist/index.cjs').equals(Buffer.from(bundle))) {
      throw new Error('dist/index.cjs is out of date. Run npm run build and commit dist/index.cjs.');
    }
  } else {
    fs.mkdirSync('dist', { recursive: true });
    fs.writeFileSync('dist/index.cjs', bundle);
  }
};

main().catch(error => { console.error(error.message); process.exitCode = 1; });
