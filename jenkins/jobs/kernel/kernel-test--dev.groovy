#!groovy
// Runs tests on a Linux kernel git repository.
//
// The `jenkins` user must be in the `docker` user group.
// Requires nodes with labels: `amd64`, `arm64`, `docker`.

script {
    library identifier: "tdd-project@master", retriever: legacySCM(scm)
}

def stagingTokenBootstrap = [:]
boolean cacheFoundBootstrap = false
boolean cacheFoundKernel = false
boolean cacheFoundRootfs = false

pipeline {
    parameters {
        booleanParam(name: 'DOCKER_PURGE',
            defaultValue: false,
            description: 'Remove existing tdd-builder image and rebuild.')

        string(name: 'KERNEL_CONFIG_URL',
            defaultValue: '',
            description: 'URL of an alternate kernel config.')

        string(name: 'KERNEL_GIT_BRANCH',
            defaultValue: 'master',
            description: 'Branch or tag of KERNEL_GIT_URL.')

        string(name: 'KERNEL_GIT_URL',
            defaultValue: 'https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git',
            description: 'URL of a Linux kernel git repository.')

        choice(name: 'NODE_ARCH',
            choices: "amd64\narm64",
            description: 'Jenkins node architecture to build on.')

        choice(name: 'ROOTFS_TYPE',
               choices: "debian\nalpine\nfedora",
               description: 'Root file system type to build.')

        booleanParam(name: 'SYSTEMD_DEBUG',
            defaultValue: false,
            description: 'Run kernel with systemd debug flags.')

        choice(name: 'TARGET_ARCH',
            choices: "arm64\namd64\nppc64le",
            description: 'Target architecture to build for.')

        choice(name: 'TARGET_MACHINE',
               choices: "qemu\ngbt2s18\ngbt2s19\nsaber25\nt88",
               description: 'Target machine to run tests on.')

        choice(name: 'TEST_NAME',
               choices: "sys-info\nhttp-wrk\nkselftest\nltp\nunixbench",
               description: 'Test to run on target machine.')

        string(name: 'PIPELINE_BRANCH',
               defaultValue: 'master',
               description: 'Branch to use for fetching the pipeline jobs')

        // Job debugging parameters.
        choice(name: 'AGENT',
               choices: "master\nlab2\nsaber25\ntdd2\ntdd3",
               description: '[debugging] Which Jenkins agent to use.')

        booleanParam(name: 'USE_BOOTSTRAP_CACHE',
            defaultValue: true,
            description: '[debugging] Use cached rootfs bootstrap image.')

        booleanParam(name: 'USE_ROOTFS_CACHE',
            defaultValue: false,
            description: '[debugging] Use cached rootfs disk image.')

        booleanParam(name: 'USE_KERNEL_CACHE',
            defaultValue: false,
            description: '[debugging] Use cached kernel build.')

    }

    options {
        // Timeout if no node available.
        timeout(time: 90, unit: 'MINUTES')
        //timestamps()
        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '10'))
    }

    environment {
        String buildName = 'build'
        String topBuildDir = "${env.buildName}"
        String scriptsDir = 'scripts'
 
        String bootstrapPrefix="${env.topBuildDir}/${params.TARGET_ARCH}-${params.ROOTFS_TYPE}"
        String bootstrapDir="${env.bootstrapPrefix}.bootstrap"

        String outputPrefix="${env.topBuildDir}/${params.TARGET_ARCH}-${params.ROOTFS_TYPE}-${params.TEST_NAME}"
        String imageDir="${env.outputPrefix}.image"
        String testsDir="${env.outputPrefix}.tests"
        String resultsDir="${env.outputPrefix}.results"

        String kernelSrcDir = sh(
            returnStdout: true,
            script: "set -x; \
echo -n '${env.topBuildDir}/'; \
echo '${params.KERNEL_GIT_URL}' | sed 's|://|-|; s|/|-|g'").trim()
        String kernelBuildDir = "${env.topBuildDir}/${params.TARGET_ARCH}-kernel-build"
        String kernelInstallDir = "${env.topBuildDir}/${params.TARGET_ARCH}-kernel-install"

        String tddStorePath = sh(
            returnStdout: true,
            script: "set -x; \
if [ \${TDD_STORE} ]; then \
    echo -n \${TDD_STORE}; \
else \
    echo -n /run/tdd-store/\${USER}; \
fi")
        String jenkinsCredsPath = "${env.tddStorePath}/jenkins_creds"
        String dockerCredsExtra = "-v ${env.jenkinsCredsPath}/group:/etc/group:ro \
            -v ${env.jenkinsCredsPath}/passwd:/etc/passwd:ro \
            -v ${env.jenkinsCredsPath}/shadow:/etc/shadow:ro \
            -v ${env.jenkinsCredsPath}/sudoers.d:/etc/sudoers.d:ro"
        String dockerTag = sh(
            returnStdout: true,
            script: './docker/builder/build-builder.sh --tag').trim()

        // Job debugging variables.
        String fileStagingDir = 'staging'
        String fileCacheDir = "${env.WORKSPACE}/../${env.JOB_BASE_NAME}--file-cache"
    }

    agent { label "${params.AGENT}" }

    stages {

        stage('setup') {
            steps { /* setup */
                clean_disk_image_build()
                tdd_setup_file_cache()
                tdd_setup_jenkins_creds()
                sh("mkdir -p ${env.resultsDir}")
                //cache_test()
                echo "${STAGE_NAME}: dockerTag        = @${env.dockerTag}@"
                echo "${STAGE_NAME}: dockerCredsExtra = @${env.dockerCredsExtra}@"
            }
        }

        stage('build-builder') {
            environment { /* build-builder */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
            }

            steps { /* build-builder */
                tdd_print_debug_info("${STAGE_NAME}")
                tdd_print_result_header(env.resultFile)

                sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

tag=${env.dockerTag}
docker images \${tag%:*}

if [[ "${params.DOCKER_PURGE}" == 'true' ]]; then
  builder_args+=' --purge'
fi

./docker/builder/build-builder.sh \${builder_args}

""")
            }
            post { /* build-builder */
                always {
                    archiveArtifacts(artifacts: "${env.resultFile}")
                }
                cleanup {
                    echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                }
            }
        }

        stage('parallel-build') {
            failFast false
            parallel { /* parallel-build */

                stage('build-kernel') {
                    environment { /* build-kernel */
                        resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
                    }

                    agent { /* build-kernel */
                        docker {
                            image "${env.dockerTag}"
                            args "--network host ${env.dockerCredsExtra}"
                            reuseNode true
                        }
                    }

                    steps { /* build-kernel */
                        tdd_print_debug_info("${STAGE_NAME}")
                        tdd_print_result_header(env.resultFile)

                        dir(env.kernelSrcDir) {
                            checkout scm: [
                                $class: 'GitSCM',
                                branches: [[name: params.KERNEL_GIT_BRANCH]],
                                 userRemoteConfigs: [[url: params.KERNEL_GIT_URL]],
                            ]
                            sh("git show -q")
                        }

                        script {
                            if (params.USE_KERNEL_CACHE) {
                                cacheFoundKernel = newFileCache.get(
                                    env.fileCacheDir, env.kernelInstallDir)
                                if (cacheFoundKernel) {
                                    currentBuild.result = 'SUCCESS'
                                    echo "${STAGE_NAME}: Using cached files."
                                    return
                                }
                            }

                            sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

rm -rf ${env.kernelBuildDir} ${env.kernelInstallDir}

${env.scriptsDir}/tdd-run.sh \
    --arch=${params.TARGET_ARCH} \
    --build-name=${env.buildName} \
    --linux-branch=${params.KERNEL_GIT_BRANCH} \
    --linux-config=${params.KERNEL_CONFIG_URL} \
    --linux-repo=${params.KERNEL_GIT_URL} \
    --linux-src-dir=${env.kernelSrcDir} \
    --test-machine=${params.TARGET_MACHINE} \
    --rootfs-types=${params.ROOTFS_TYPE} \
    --test-types=${params.TEST_NAME} \
    --build-kernel

rm -rf ${env.kernelBuildDir}
""")
                        }
                    }

                    post { /* build-kernel */
                        always {
                            sh("if [ -f ${env.kernelInstallDir}/boot/config ]; then \
                                    cp -vf ${env.kernelInstallDir}/boot/config ${env.resultsDir}/kernel-config; \
                                else \
                                    echo 'NA' > ${env.resultsDir}/kernel-config; \
                                fi")
                            archiveArtifacts(
                                artifacts: "${env.resultFile}, ${env.resultsDir}/kernel-config")
                        }
                        cleanup {
                            echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                        }
                    }
                }

                stage('build-bootstrap') {
                    environment { /* build-bootstrap */
                        resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
                    }

                    agent { /* build-bootstrap */
                        docker {
                            image "${env.dockerTag}"
                            args "--network host --privileged \
                                ${env.dockerCredsExtra}"
                            reuseNode true
                        }
                    }

                    steps { /* build-bootstrap */
                        tdd_print_debug_info("${STAGE_NAME}")
                        tdd_print_result_header(env.resultFile)

                        script {
                            if (params.USE_BOOTSTRAP_CACHE) {
                                cacheFoundBootstrap = newFileCache.get(
                                    env.fileCacheDir, env.bootstrapDir)
                                if (cacheFoundBootstrap) {
                                    currentBuild.result = 'SUCCESS'
                                    echo "${STAGE_NAME}: Using cached files."
                                    return
                                }
                            }

                            sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

# for debug
id
whoami
#cat /etc/group || :
#ls -l /etc/sudoers || :
#ls -l /etc/sudoers.d || :
#cat /etc/sudoers || :
sudo -S true

${env.scriptsDir}/tdd-run.sh \
    --arch=${params.TARGET_ARCH} \
    --build-name=${env.buildName} \
    --linux-branch=${params.KERNEL_GIT_BRANCH} \
    --linux-config=${params.KERNEL_CONFIG_URL} \
    --linux-repo=${params.KERNEL_GIT_URL} \
    --linux-src-dir=${env.kernelSrcDir} \
    --test-machine=${params.TARGET_MACHINE} \
    --rootfs-types=${params.ROOTFS_TYPE} \
    --test-types=${params.TEST_NAME} \
    --build-bootstrap
""")
                        }
                    }

                    post { /* build-bootstrap */
                        always {
                            archiveArtifacts(artifacts: "${env.resultFile}")
                        }
                        success {
                            script {
                                if (params.USE_BOOTSTRAP_CACHE
                                    && !cacheFoundBootstrap) {
                                    stagingTokenBootstrap = newFileCache.stage(
                                        env.fileStagingDir, env.fileCacheDir,
                                        env.bootstrapDir)
                                }
                            }
                        }
                        cleanup {
                            echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                        }
                    }
                }

            }

            post { /* parallel-build */
                failure {
                    clean_disk_image_build()
                }
                cleanup {
                    echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                }
            }
        }

        stage('cache-bootstrap') {
            when { /* cache-bootstrap */
                expression { return params.USE_BOOTSTRAP_CACHE }
            }
            steps { /* cache-bootstrap */
                tdd_print_debug_info("${STAGE_NAME}")
                script {
                    if (stagingTokenBootstrap.isEmpty()) {
                        echo "${STAGE_NAME}: Bootstrap already cached."
                    } else {
                        newFileCache.commit(stagingTokenBootstrap, '**bootstrap stamp info**')
                    }
                }
            }
        }

        stage('cache-kernel') {
            when { /* cache-kernel */
                expression { return params.USE_KERNEL_CACHE }
            }
            steps { /* cache-kernel */
                tdd_print_debug_info("${STAGE_NAME}")
                script {
                    if (cacheFoundKernel) {
                        echo "${STAGE_NAME}: Kernel already cached."
                    } else {
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.kernelInstallDir, '**kernel stamp info**')
                    }
                }
            }
        }

        stage('build-rootfs') {
            environment { /* build-rootfs */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
            }
            agent { /* build-rootfs */
                docker {
                    image "${env.dockerTag}"
                    args "--network host --privileged ${env.dockerCredsExtra}"
                    reuseNode true
                }
            }

            steps { /* build-rootfs */
                tdd_print_debug_info("${STAGE_NAME}")
                tdd_print_result_header(env.resultFile)
                script {
                    if (params.USE_ROOTFS_CACHE) {
                        if (newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/initrd') == true
                            && newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/manifest') == true
                            && newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/login-key') == true) {
                            cacheFoundRootfs = true
                            echo "${STAGE_NAME}: Using cached files."
                            currentBuild.result = 'SUCCESS'
                            return
                        }
                    }

                    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

${env.scriptsDir}/tdd-run.sh \
    --arch=${params.TARGET_ARCH} \
    --build-name=${env.buildName} \
    --linux-branch=${params.KERNEL_GIT_BRANCH} \
    --linux-config=${params.KERNEL_CONFIG_URL} \
    --linux-repo=${params.KERNEL_GIT_URL} \
    --linux-src-dir=${env.kernelSrcDir} \
    --test-machine=${params.TARGET_MACHINE} \
    --rootfs-types=${params.ROOTFS_TYPE} \
    --test-types=${params.TEST_NAME} \
    --build-rootfs \
    --build-tests
""")
                }
            }

            post { /* build-rootfs */
                always {
                    archiveArtifacts(artifacts: "${env.resultFile}")
                }
                success {
                    archiveArtifacts(artifacts: "${env.imageDir}/manifest")
                }
                failure {
                    clean_disk_image_build()
                    echo "${STAGE_NAME}: ${currentBuild.currentResult}"
                }
                cleanup {
                    echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                }
            }
        }

        stage('cache-rootfs') {
            when { /* cache-rootfs */
                expression { return params.USE_ROOTFS_CACHE }
            }
            steps { /* cache-rootfs */
                tdd_print_debug_info("${STAGE_NAME}")
                script {
                    if (cacheFoundRootfs) {
                        echo "${STAGE_NAME}: Rootfs already cached."
                    } else {
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/initrd', '**initrd stamp info**')
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/login-key', '**login-key stamp info**')
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/manifest', '**manifest stamp info**')
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.testsDir, '**test stamp info**')
                    }
                }
            }
        }

        stage('run-test') {
            when { /* run-test */
                expression { return !(params.TEST_NAME == 'none') }
            }

            environment { /* run-test */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
                outFile = "${env.resultsDir}/${params.TARGET_MACHINE}-console.txt"
                TDD_BMC_CREDS = credentials("${params.TARGET_MACHINE}_bmc_creds")
            }

            agent { /* run-test */
                docker {
                    image "${env.dockerTag}"
                    args "--network host ${env.dockerCredsExtra}"
                    reuseNode true
                }
            }

            steps { /* run-test */
                tdd_print_debug_info("${STAGE_NAME}")
                tdd_print_result_header(env.resultFile)

                script {
                    switch (params.TARGET_MACHINE) {
                    case 'qemu':
                        sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

if [[ ${params.SYSTEMD_DEBUG} ]]; then
    extra_args="--systemd-debug"
fi

${env.scriptsDir}/tdd-run.sh \
    \${extra_args} \
    --arch=${params.TARGET_ARCH} \
    --build-name=${env.buildName} \
    --linux-branch=${params.KERNEL_GIT_BRANCH} \
    --linux-config=${params.KERNEL_CONFIG_URL} \
    --linux-repo=${params.KERNEL_GIT_URL} \
    --linux-src-dir=${env.kernelSrcDir} \
    --test-machine=${params.TARGET_MACHINE} \
    --rootfs-types=${params.ROOTFS_TYPE} \
    --test-types=${params.TEST_NAME} \
    --run-qemu-tests
""")
                        break
                    default:
                        sshagent (credentials: ['tdd-tftp-login-key']) {
                            sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

if [[ ${params.SYSTEMD_DEBUG} ]]; then
    extra_args="--systemd-debug"
fi

${env.scriptsDir}/tdd-run.sh \
    \${extra_args} \
    --arch=${params.TARGET_ARCH} \
    --build-name=${env.buildName} \
    --linux-branch=${params.KERNEL_GIT_BRANCH} \
    --linux-config=${params.KERNEL_CONFIG_URL} \
    --linux-repo=${params.KERNEL_GIT_URL} \
    --linux-src-dir=${env.kernelSrcDir} \
    --test-machine=${params.TARGET_MACHINE} \
    --rootfs-types=${params.ROOTFS_TYPE} \
    --test-types=${params.TEST_NAME} \
    --run-remote-tests
""")
                        }
                        break
                    }
                }
             }

            post { /* run-test */
                always {
                    sh("if [ ! -f ${env.outFile} ]; then \
                            echo 'NA' > ${env.outFile}; \
                        fi")
                    archiveArtifacts(artifacts: "${env.resultFile}, ${env.outFile}")
                }
                success {
                    script {
                            if (readFile("${env.outFile}").contains('reboot: Power down')) {
                                echo "${STAGE_NAME}: FOUND 'reboot' message."
                            } else {
                                echo "${STAGE_NAME}: DID NOT FIND 'reboot' message."
                                currentBuild.result = 'FAILURE'
                            }
                    }
                }
                cleanup {
                    echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                }
            }

        }
    }
}

void tdd_setup_jenkins_creds() {
    sh("""#!/bin/bash -ex
export PS4='+ [tdd_setup_jenkins_creds] \${BASH_SOURCE##*/}:\${LINENO}: '

sudo rm -rf ${env.jenkinsCredsPath}
sudo mkdir -p ${env.jenkinsCredsPath}
sudo chown \$(id --user --real --name): ${env.jenkinsCredsPath}/
sudo cp -avf /etc/group ${env.jenkinsCredsPath}/
sudo cp -avf /etc/passwd ${env.jenkinsCredsPath}/
sudo cp -avf /etc/shadow  ${env.jenkinsCredsPath}/
sudo cp -avf /etc/sudoers.d ${env.jenkinsCredsPath}/
""")
}

void tdd_print_debug_info(String stage_name) {
    sh("""#!/bin/bash -ex
echo 'In ${stage_name}:'
whoami
id
""")
}

void tdd_print_result_header(String resultFile) {
    sh("""#!/bin/bash -ex

echo "node=${NODE_NAME}" > ${resultFile}
echo "--------" >> ${resultFile}
echo "printenv" >> ${resultFile}
echo "--------" >> ${resultFile}
printenv | sort >> ${resultFile}
echo "--------" >> ${resultFile}
""")
}

void clean_disk_image_build() {
    echo "cleaning disk-image"
    sh("sudo rm -rf ${env.topBuildDir}/*.rootfs ${env.topBuildDir}/*.bootstrap")
}

void tdd_setup_file_cache() {
    sh("""#!/bin/bash -ex
mkdir -p ${env.fileCacheDir}
""")
}

void cache_test() {
    script {
        sh("""#!/bin/bash -ex
mkdir -p ${env.topBuildDir}/c-test
echo "aaa" > ${env.topBuildDir}/c-test/aaa
echo "bbb" > ${env.topBuildDir}/c-test/bbb
""")
        def token = newFileCache.stage(
            env.fileStagingDir, env.fileCacheDir,
            "${env.topBuildDir}/c-test")

        if (!token.isEmpty()) {
            newFileCache.commit(token, "TEST Commit 1")
        } else {
            echo "c-test not staged 1."
        }

        token = newFileCache.stage(
            env.fileStagingDir, env.fileCacheDir,
            "${env.topBuildDir}/c-test")

        if (!token.isEmpty()) {
            newFileCache.commit(token, "TEST Commit 2")
        } else {
            echo "c-test not staged 2."
        }

        sh("""#!/bin/bash -ex
mkdir -p ${env.topBuildDir}/c-test
echo "ccc" > ${env.topBuildDir}/c-test/ccc
""")

        newFileCache.put(
            env.fileStagingDir, env.fileCacheDir,
            "${env.topBuildDir}/c-test", "TEST Put 3")

        newFileCache.get(env.fileCacheDir,
            "${env.topBuildDir}/c-test",
            "${env.topBuildDir}/c-test-out")

        sh("""#!/bin/bash -ex
find "${env.topBuildDir}/c-test-out"
""")

        newFileCache.get(env.fileCacheDir,
            "${env.topBuildDir}/c-test")
    }
}
