#!/usr/bin/env bash
set -euo pipefail

working_directory="${BELA_WORKING_DIRECTORY:-.}"
language="${BELA_LANGUAGE:?BELA_LANGUAGE is required. Run detect-language.sh first.}"
updater_tag="${BELA_UPDATER_TAG:-latest}"

cd "$working_directory"
mkdir -p .bela

updater_image="juxhouse/bela-updater-${language}:${updater_tag}"

run_prepare_in_updater_image() {
  local script="$1"
  shift

  docker pull "$updater_image"
  docker run --rm \
    "$@" \
    -v "$PWD:/workspace" \
    -w /workspace \
    --entrypoint /bin/sh \
    "$updater_image" \
    -lc "$script"
}

case "$language" in
  clojure)
    run_prepare_in_updater_image \
      'mkdir -p /workspace/.bela /workspace/.m2 /workspace/.gitlibs && if [ -f project.clj ]; then lein deps; else clojure -A:test:dev -P && clojure -A:test:dev -Spath; fi && [ ! -d /root/.m2 ] || cp -R /root/.m2/. /workspace/.m2/ && [ ! -d /root/.gitlibs ] || cp -R /root/.gitlibs/. /workspace/.gitlibs/'
    ;;

  typescript)
    run_prepare_in_updater_image \
      'mkdir -p /workspace/.bela && if [ -f package-lock.json ]; then npm ci; elif [ -f npm-shrinkwrap.json ]; then npm ci; else npm install; fi'
    ;;

  ruby)
    run_prepare_in_updater_image \
      'mkdir -p /workspace/.bela/external_gems && gem install bundler --no-document && bundle config set --local path /workspace/.bela/external_gems && bundle install'
    ;;

  dotnet)
    run_prepare_in_updater_image \
      'mkdir -p /workspace/.bela/dependencies && dotnet restore --packages /workspace/.bela/dependencies'
    ;;

  java)
    # The Java updater image is runtime-only: it contains Temurin plus the
    # updater jar, but no Maven, Gradle, or JDK build tools. Prepare Java
    # projects with build-tool images, then run the updater offline later.
    if [[ -f pom.xml ]]; then
      mkdir -p .m2
      docker pull maven:3.9.6-eclipse-temurin-21
      docker run --rm \
        -v "$PWD/.m2:/.m2" \
        -v "$PWD:/workspace" \
        -w /workspace \
        maven:3.9.6-eclipse-temurin-21 \
        /bin/sh -lc 'mkdir -p /workspace/.bela /.m2 /workspace/target && mvn -B -Dmaven.repo.local=/.m2/repository clean install && mvn -B -Dmaven.repo.local=/.m2/repository dependency:build-classpath -Dmdep.outputFile=target/classpath.txt'
    else
      docker pull gradle:8.10.2-jdk21
      cat > bela.gradle <<'EOF'
allprojects {
    afterEvaluate {
        tasks.named('compileJava').configure {
            destinationDir = file("$projectDir/target/classes")
        }

        task copyDependencies(type: Copy) {
            dependsOn compileJava
            from configurations.runtimeClasspath
            into file("$projectDir/target/dependency")
        }

        task writeClasspath {
            dependsOn compileJava
            doLast {
                def classpathFile = file("$projectDir/target/classpath.txt")
                classpathFile.withWriter('UTF-8') { writer ->
                    configurations.runtimeClasspath.each {
                        writer.writeLine it.name
                    }
                }
            }
        }

        task writeProjectProperties {
            dependsOn compileJava
            doLast {
                def propertiesFile = file("$projectDir/target/project.properties")
                def artifactId = project.hasProperty('archivesBaseName') ? project.archivesBaseName : project.name

                propertiesFile.withWriter('UTF-8') { writer ->
                    writer.writeLine "artifactType=${project.hasProperty('group') && project.group ? 'maven' : 'gradle'}"
                    writer.writeLine "groupId=${project.group ?: 'unspecified'}"
                    writer.writeLine "artifactId=${artifactId}"
                    writer.writeLine "version=${project.version ?: 'unspecified'}"
                }
            }
        }

        task createNeededDirs {
            file("$projectDir/target").mkdirs()
            file(".bela").mkdirs()
        }

        task belaBuild {
            dependsOn createNeededDirs
            dependsOn compileJava
            dependsOn copyDependencies
            dependsOn writeClasspath
            dependsOn writeProjectProperties
        }
    }
}
EOF
      docker run --rm \
        -v "$PWD:/workspace" \
        -w /workspace \
        gradle:8.10.2-jdk21 \
        /bin/sh -lc 'mkdir -p /workspace/.bela /workspace/target && if [ -f ./gradlew ]; then chmod +x ./gradlew && ./gradlew clean build && ./gradlew belaBuild --init-script bela.gradle; else gradle clean build && gradle belaBuild --init-script bela.gradle; fi'
    fi
    ;;

  *)
    echo "Unsupported BELA language: $language" >&2
    exit 1
    ;;
esac
