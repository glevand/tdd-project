#!groovy

/*
 * kernelTrigger - Polls git repo for changes, runs kernel-test job.
 *
 *  String cron_spec: Default = '@hourly', See
 *    https://jenkins.io/doc/book/pipeline/syntax/#cron-syntax.
 *  String git_branch: Default = 'master'.
 *  String git_url: Required.
 */

def call(body) {
    def args = [:]
    body.resolveStrategy = Closure.DELEGATE_FIRST
    body.delegate = args
    body()

    args.cron_spec = args.cron_spec ?: '@hourly'
    args.git_branch = args.git_branch ?: 'master'

    print "kernelTrigger: args = ${args}"

    pipeline {
        parameters {
            booleanParam(name: 'FORCE_BUILD',
                defaultValue: false,
                description: 'Force build and test of kernel.')
            string(name: 'PIPELINE_BRANCH',
                defaultValue: 'master',
                description: 'Branch to use for fetching the pipeline jobs')
        }

        options {
            buildDiscarder(logRotator(daysToKeepStr: '2', numToKeepStr: '12'))
        }

        triggers {
            cron(args.cron_spec)
        }

        agent { label "master" }

        stages {
            stage('poll') {
                steps {
                    echo "${STAGE_NAME}: start"

                    copyArtifacts(
                        projectName: "${JOB_NAME}",
                        selector: lastCompleted(),
                        fingerprintArtifacts: true,
                        optional: true,
                    )

                    sh("""#!/bin/bash -ex
export PS4='+\${BASH_SOURCE##*/}:\${LINENO}:'

if [[ -f linux.ref ]]; then
    last="\$(cat linux.ref)"
fi

current=\$(git ls-remote ${args.git_url} ${args.git_branch})

set +x
echo '------'
echo "last    = @\${last}@"
echo "current = @\${current}@"
echo '------'
set -x

if [[ "${params.FORCE_BUILD}" == 'true' \
    || -z "\${last}" || "\${current}" != "\${last}" ]]; then
    echo "${STAGE_NAME}: Need build."
    echo "\${current}" > linux.ref
    echo "yes" > need-build
else
    echo "${STAGE_NAME}: No change."
    echo "no" > need-build
fi
""")
                }
                post { /* poll */
                    success {
                        archiveArtifacts(
                            artifacts: "linux.ref",
                            fingerprint: true
                        )
                    }
                }
            }

            stage ('downstream') {
                when {
                    expression { return readFile('need-build').contains('yes') }
                }
                steps {
                    echo "${STAGE_NAME}: start"

                    build(
                        job: 'kernel-test',
                        parameters: [
                            string(name: 'KERNEL_GIT_BRANCH', value: args.git_branch),
                            string(name: 'KERNEL_GIT_URL', value: args.git_url),
                            booleanParam(name: 'USE_KERNEL_CACHE', value: false),
                            string(name: 'PIPELINE_BRANCH', value: params.PIPELINE_BRANCH)
                        ],
                    )
                }
            }
        }
    }
}
