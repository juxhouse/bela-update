import { command } from './actions.js';
import { dispatch } from './main.js';

dispatch(process.argv.slice(2)).catch(error => {
  if (process.env.GITHUB_ACTIONS === 'true') command('error', error.message);
  else console.error(error.message);
  process.exitCode = error.exitCode || 1;
});
