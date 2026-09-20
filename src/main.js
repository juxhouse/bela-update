import fs from 'node:fs';
import path from 'node:path';
import * as actions from './actions.js';
import * as project from './project.js';
import * as execution from './execution.js';
import * as api from './api.js';
import * as git from './git.js';
import * as logging from './logging.js';

const required = (value, name) => {
  if (!value) throw new Error(`${name} environment variable is required.`);
  return value;
};

const contextFromEnv = (env = process.env) => {
  const root = fs.realpathSync(env.BELA_WORKING_DIRECTORY || '.');
  return {
    root, workspace: env.GITHUB_WORKSPACE || root, repository: env.GITHUB_REPOSITORY || 'repo',
    branch: env.GITHUB_REF_NAME, eventPath: env.GITHUB_EVENT_PATH,
    updaterTag: env.BELA_UPDATER_TAG || 'latest', parentElementPath: env.BELA_PARENT_ELEMENT_PATH,
    dryRun: env.BELA_DRY_RUN === 'true', skipUpload: env.BELA_SKIP_UPLOAD === 'true',
    home: env.HOME, apiUrl: env.BELA_API_URL, apiToken: env.BELA_API_TOKEN,
  };
};

const run = async (context = contextFromEnv(), services = {}) => {
  const { prepare = execution.prepare, runUpdater = execution.runUpdater,
    upload = api.upload, syncActiveBranches = api.syncActiveBranches,
    activeBranches = git.activeBranches, setOutput = actions.setOutput } = services;
  const discovered = project.discoverProjects(context.root, context);
  if (!discovered.length) {
    throw new Error(`Could not detect a supported BELA importer in ${context.root} or its child directories.`);
  }
  const projects = discovered.map(item => {
    const base = project.sourceBase(item.directory, context.workspace, context.repository);
    return { ...item, sourceBase: base, source: context.branch ? `${base} (${context.branch})` : base,
      updaterTag: context.updaterTag, home: context.home };
  });
  const shouldSync = !context.dryRun && !context.skipUpload;
  let branches;
  if (shouldSync) {
    required(context.apiUrl, 'BELA_API_URL');
    required(context.apiToken, 'BELA_API_TOKEN');
    if (process.env.GITHUB_ACTIONS === 'true') actions.command('add-mask', context.apiToken);
    try { branches = await activeBranches(context.workspace, context.eventPath); }
    catch (cause) { throw new Error('Could not determine active Git branches.', { cause }); }
  }
  console.log(`Detected ${projects.length} BELA project(s).`);
  for (const [index, item] of projects.entries()) {
    const logs = path.join(context.root, '.bela', 'logs', `${index + 1}-${logging.slug(item.source)}`);
    logging.groupStart(`Project ${index + 1}/${projects.length}: ${item.source} (${item.language})`);
    try {
      console.log('Directory:', item.directory);
      if (item.buildCommand) console.log('Build command:', item.buildCommand);
      for (const [option, value] of Object.entries(item.updaterOptions)) console.log(`  ${option}: ${value}`);
      if (context.dryRun) {
        console.log('Dry run enabled. Skipping prepare, updater, and upload.');
        continue;
      }
      await logging.runLogged('Prepare dependencies', path.join(logs, 'prepare.log'), output => prepare(item, output));
      const ecd = await logging.runLogged('Run BELA updater', path.join(logs, 'updater.log'), output => runUpdater(item, output));
      if (context.skipUpload) {
        console.log('Generated ECD:', ecd);
        await logging.printLines(ecd, 40);
      } else {
        await logging.runLogged('Upload ECD to BELA', path.join(logs, 'upload.log'), () => upload(context.apiUrl, context.apiToken, ecd));
      }
    } finally { logging.groupEnd(); }
  }
  if (shouldSync) {
    for (const item of projects) {
      await logging.runLogged(`Sync active branches: ${item.sourceBase}`,
        path.join(context.root, '.bela', 'logs', `active-branches-${logging.slug(item.sourceBase)}.log`),
        () => syncActiveBranches(context.apiUrl, context.apiToken, item.sourceBase, branches));
    }
  }
  setOutput('languages', projects.map(item => item.language).join(','));
  setOutput('sources', projects.map(item => item.source).join(','));
  return { projects, activeBranches: branches };
};

const dispatch = async (args, env = process.env) => {
  const command = args[0] || 'run';
  if (!['run', 'prepare', 'updater'].includes(command)) {
    throw Object.assign(new Error(`Unknown command: ${command}`), { exitCode: 2 });
  }
  const context = contextFromEnv(env);
  if (command === 'run') return run(context);
  const item = { directory: context.root, language: required(env.BELA_LANGUAGE, 'BELA_LANGUAGE'),
    updaterTag: context.updaterTag, home: context.home, source: env.BELA_SOURCE };
  if (command === 'prepare') return execution.prepare({ ...item, buildCommand: args[1] || '' });
  return execution.runUpdater({ ...item, source: required(env.BELA_SOURCE, 'BELA_SOURCE'),
    updaterArgs: execution.envUpdaterArgs(env.BELA_UPDATER_ARGS) });
};

export { required, contextFromEnv, run, dispatch };
