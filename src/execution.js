import fs from 'node:fs';
import path from 'node:path';
import { run } from './process.js';
import { isFile } from './project.js';
import gradleHelper from './gradle.js';

const mavenImage = 'maven:3.9.6-eclipse-temurin-21';
const gradleImage = 'gradle:8.10.2-jdk21';
const preparationScripts = {
  clojure: 'mkdir -p /workspace/.bela /workspace/.m2 /workspace/.gitlibs && if [ -f project.clj ]; then lein deps; else clojure -A:test:dev -P && clojure -A:test:dev -Spath; fi && { [ ! -d /root/.m2 ] || cp -R /root/.m2/. /workspace/.m2/; } && { [ ! -d /root/.gitlibs ] || cp -R /root/.gitlibs/. /workspace/.gitlibs/; }',
  typescript: 'mkdir -p /workspace/.bela && if [ -f package-lock.json ]; then npm ci; elif [ -f npm-shrinkwrap.json ]; then npm ci; else npm install; fi',
  dotnet: 'mkdir -p /workspace/.bela/dependencies && dotnet restore --packages /workspace/.bela/dependencies',
};

const updaterImage = (language, tag = 'latest') => {
  if (!['clojure', 'typescript', 'java', 'dotnet'].includes(language)) {
    throw new Error(`Unsupported BELA language: ${language}`);
  }
  return `juxhouse/bela-updater-${language}:${tag}`;
};

const mavenDirectory = (project) => {
  if (project.m2Directory) return project.m2Directory;
  if (!project.home) throw new Error('HOME is required to locate the default Maven .m2 directory.');
  return path.join(project.home, '.m2');
};

const withMavenCache = (project) => {
  if (project.language !== 'java' || !isFile(path.join(project.directory, 'pom.xml'))) return project;
  const directory = mavenDirectory(project);
  fs.mkdirSync(directory, { recursive: true });
  return { ...project, m2Directory: fs.realpathSync(directory) };
};

const prepareCommands = (project) => {
  const { directory, language, buildCommand, updaterTag } = project;
  if (buildCommand) return [['bash', '-lc', buildCommand]];
  const workspace = ['-v', `${directory}:/workspace`, '-w', '/workspace'];
  if (language === 'java') {
    if (isFile(path.join(directory, 'pom.xml'))) {
      return [
        ['docker', 'pull', mavenImage],
        ['docker', 'run', '--rm', '-v', `${mavenDirectory(project)}:/root/.m2`, ...workspace, mavenImage, '/bin/sh', '-lc',
          'mkdir -p /workspace/.bela /workspace/target && mvn -B clean install && mvn -B dependency:build-classpath -Dmdep.outputFile=target/classpath.txt'],
      ];
    }
    return [
      ['docker', 'pull', gradleImage],
      ['docker', 'run', '--rm', ...workspace, gradleImage, '/bin/sh', '-lc',
        'mkdir -p /workspace/.bela /workspace/target && if [ -f ./gradlew ]; then chmod +x ./gradlew && ./gradlew clean build && ./gradlew belaBuild --init-script bela.gradle; else gradle clean build && gradle belaBuild --init-script bela.gradle; fi'],
    ];
  }
  const image = updaterImage(language, updaterTag);
  return [
    ['docker', 'pull', image],
    ['docker', 'run', '--rm', ...workspace, '--entrypoint', '/bin/sh', image, '-lc', preparationScripts[language]],
  ];
};

const processOptions = (project, output) => {
  return {
    cwd: project.directory, output,
    env: { ...process.env, BELA_WORKING_DIRECTORY: project.directory, BELA_LANGUAGE: project.language,
      BELA_SOURCE: project.source || '', BELA_UPDATER_ARGS: (project.updaterArgs || []).join('\n') },
  };
};

const prepare = async (project, output = 'inherit', execute = run) => {
  fs.mkdirSync(path.join(project.directory, '.bela'), { recursive: true });
  // Custom builds own all preparation, including Java's generated files and caches.
  if (!project.buildCommand) {
    project = withMavenCache(project);
    if (project.language === 'java' && !isFile(path.join(project.directory, 'pom.xml'))) {
      fs.writeFileSync(path.join(project.directory, 'bela.gradle'), gradleHelper);
    }
  }
  for (const argv of prepareCommands(project)) await execute(argv, processOptions(project, output));
};

const updaterCommand = (project) => {
  const { directory, language, source, updaterArgs = [], updaterTag } = project;
  const image = updaterImage(language, updaterTag);
  const command = ['docker', 'run', '--rm', '--pull=never', '--network=none',
    '-v', `${directory}:/workspace`, '-v', `${path.join(directory, '.bela')}:/.bela`];
  if (language === 'dotnet') {
    return [...command, '--entrypoint', 'dotnet', image, '/App/CodeAnalyzer.dll', '-source', source,
      ...updaterArgs, '-workspace', '/workspace', '-output', '/.bela/bela-update.ecd'];
  }
  if (language === 'java' && isFile(path.join(directory, 'pom.xml'))) {
    command.push('-v', `${mavenDirectory(project)}:/.m2:ro`);
  }
  return [...command, image, '-source', source, ...updaterArgs];
};

const runUpdater = async (project, output = 'inherit', execute = run) => {
  fs.mkdirSync(path.join(project.directory, '.bela'), { recursive: true });
  project = withMavenCache(project);
  const options = processOptions(project, output);
  await execute(['docker', 'pull', updaterImage(project.language, project.updaterTag)], options);
  const ecd = path.join(project.directory, '.bela', 'bela-update.ecd');
  // A successful process must produce a new ECD, never upload a previous run's file.
  fs.rmSync(ecd, { force: true });
  await execute(updaterCommand(project), options);
  if (!isFile(ecd)) throw new Error(`Could not find generated ECD file at ${ecd}`);
  return ecd;
};

const envUpdaterArgs = (value) => {
  const lines = (value || '').split(/\r?\n/);
  while (lines.at(-1) === '') lines.pop();
  return lines;
};

export { mavenImage, gradleImage, prepareCommands, updaterImage, updaterCommand, prepare, runUpdater, envUpdaterArgs };
