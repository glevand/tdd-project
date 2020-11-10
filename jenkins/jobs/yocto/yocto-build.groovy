#!groovy
// Builds a Yocto distribution from a git repository.
//
// The `jenkins` user must be in the `docker` user group.
// Requires nodes with labels: `amd64`, `arm64`, `docker`.

script {
    library identifier: "tdd-project@master", retriever: legacySCM(scm)
}

def stagingTokenBootstrap = [:]
boolean cacheFoundBootstrap = false
boolean cacheFoundKernel = false
boolean cacheFoundImage = false

pipeline {
    parameters {
        string(name: 'YOCTO_CONFIG_URL',
            defaultValue: '',
            description: 'URL of an alternate conto config.')

        string(name: 'YOCTO_GIT_BRANCH',
            defaultValue: 'master',
            description: 'Branch or tag of YOCTO_GIT_URL.')

        string(name: 'YOCTO_GIT_URL',
            defaultValue: 'https://',
            description: 'URL of a Yocto project git repository.')

        choice(name: 'TARGET_MACHINE',
               choices: "qemu\nx86_64",
               description: '')

        choice(name: 'BUILD_IMAGE_NAME',
               choices: "",
               description: '')

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

        booleanParam(name: 'USE_IMAGE_CACHE',
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
        String topBuildDir = 'build'
        String scriptsDir = 'scripts'
 
        String bootstrapPrefix="${env.topBuildDir}/${params.TARGET_ARCH}-${params.ROOTFS_TYPE}"
        String outputPrefix="${env.bootstrapPrefix}-${params.TEST_NAME}"

        String bootstrapDir="${env.bootstrapPrefix}.bootstrap"
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

        //String qemu_out = "${env.topBuildDir}/qemu-console.txt"
        //String remote_out = "${env.topBuildDir}/${params.TEST_MACHINE}-console.txt"

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
                echo "@${params.TEST_NAME}@"
            }
        }

        stage('build-builder') {
            environment { /* build-builder */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
            }
            steps { /* build-builder */
                echo "${STAGE_NAME}: dockerTag=@${env.dockerTag}@"

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
                            args "--network host \
                                ${env.dockerCredsExtra} \
                            "
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

src_dir="\$(pwd)/${env.kernelSrcDir}"
build_dir="\$(pwd)/${env.kernelBuildDir}"
install_dir="\$(pwd)/${env.kernelInstallDir}"

rm -rf \${build_dir} "\${install_dir}"

${env.scriptsDir}/build-linux-kernel.sh \
    --build-dir=\${build_dir} \
    --install-dir=\${install_dir} \
    ${params.TARGET_ARCH} \${src_dir} defconfig

if [[ -n "${params.KERNEL_CONFIG_URL}" ]]; then
    curl --silent --show-error --location ${params.KERNEL_CONFIG_URL} \
        > \${build_dir}/.config
else
    ${env.scriptsDir}/set-config-opts.sh \
        --verbose \
        ${env.scriptsDir}/tx2-fixup.spec \${build_dir}/.config
fi

${env.scriptsDir}/build-linux-kernel.sh \
    --build-dir=\${build_dir} \
    --install-dir=\${install_dir} \
    ${params.TARGET_ARCH} \${src_dir} fresh

cp -vf \${install_dir}/boot/config \${install_dir}/boot/kernel-config
rm -rf \${build_dir}
""")
                        }
                    }

                    post { /* build-kernel */
                        success {
                            archiveArtifacts(
                                artifacts: "${env.resultFile}, ${env.kernelInstallDir}/boot/kernel-config",
                                fingerprint: true)
                        }
                        cleanup {
                            echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                        }
                    }
                }

                stage('bootstrap-disk-image') {
                    environment { /* bootstrap-disk-image */
                        resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
                    }

                    agent { /* bootstrap-disk-image */
                        docker {
                            image "${env.dockerTag}"
                            args "--network host \
                                --privileged \
                                ${env.dockerCredsExtra} \
                            "
                            reuseNode true
                        }
                    }

                    steps { /* bootstrap-disk-image */
                        tdd_print_debug_info("${STAGE_NAME}")
                        tdd_print_result_header(env.resultFile)

                        echo "${STAGE_NAME}: params.USE_BOOTSTRAP_CACHE=${params.USE_BOOTSTRAP_CACHE}"

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

                            echo "${STAGE_NAME}: dockerCredsExtra = @${env.dockerCredsExtra}@"

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

${env.scriptsDir}/build-rootfs.sh \
    --arch=${params.TARGET_ARCH} \
    --output-dir=${env.bootstrapDir} \
    --rootfs-type=${params.ROOTFS_TYPE} \
    --bootstrap \
    --verbose
""")
                        }
                    }

                    post { /* bootstrap-disk-image */
                        success {
                            script {
                                if (params.USE_BOOTSTRAP_CACHE
                                    && !cacheFoundBootstrap) {
                                    stagingTokenBootstrap = newFileCache.stage(
                                        env.fileStagingDir, env.fileCacheDir,
                                        env.bootstrapDir)
                                }
                            }
                            archiveArtifacts(
                                artifacts: "${env.resultFile}",
                                fingerprint: true)
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

        stage('build-disk-image') {
            environment { /* build-disk-image */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
            }
            agent { /* build-disk-image */
                docker {
                    image "${env.dockerTag}"
                            args "--network host \
                                --privileged \
                                ${env.dockerCredsExtra} \
                            "
                    reuseNode true
                }
            }

            steps { /* build-disk-image */
                tdd_print_debug_info("${STAGE_NAME}")
                tdd_print_result_header(env.resultFile)
                script {
                    if (params.USE_IMAGE_CACHE) {
                        if (newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/initrd') == true
                            && newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/manifest') == true
                            && newFileCache.get(env.fileCacheDir,
                            env.imageDir + '/login-key') == true) {
                            cacheFoundImage = true
                            echo "${STAGE_NAME}: Using cached files."
                            currentBuild.result = 'SUCCESS'
                            return
                        }
                    }

                    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

if [[ "${params.TEST_NAME}" != 'none' ]]; then
    source ${env.scriptsDir}/test-plugin/${params.TEST_NAME}.sh
    test_name="${params.TEST_NAME}"
    extra_packages+="\$(test_packages_\${test_name//-/_} ${params.ROOTFS_TYPE})"
fi

modules_dir="\$(find ${env.kernelInstallDir}/lib/modules/* -maxdepth 0 -type d)"

${env.scriptsDir}/build-rootfs.sh \
    --arch=${params.TARGET_ARCH} \
    --output-dir=${env.imageDir} \
    --rootfs-type=${params.ROOTFS_TYPE} \
    --bootstrap-src=${env.bootstrapDir} \
    --kernel-modules=\${modules_dir} \
    --extra-packages="\${extra_packages}" \
    --rootfs-setup \
    --make-image \
    --verbose

    test_setup_\${test_name//-/_} ${params.ROOTFS_TYPE} ${env.imageDir}/rootfs
""")
                }
            }

            post { /* build-disk-image */
                success {
                    archiveArtifacts(
                        artifacts: "${env.resultFile}, ${env.rootfs_prefix}.manifest",
                        fingerprint: true)
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

        stage('cache-image') {
            when { /* cache-image */
                expression { return params.USE_IMAGE_CACHE }
            }
            steps { /* cache-image */
                tdd_print_debug_info("${STAGE_NAME}")
                script {
                    if (cacheFoundImage) {
                        echo "${STAGE_NAME}: Image already cached."
                    } else {
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/initrd', '**initrd stamp info**')
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/login-key', '**login-key stamp info**')
                        newFileCache.put(env.fileStagingDir, env.fileCacheDir,
                            env.imageDir + '/manifest', '**manifest stamp info**')
                    }
                }
            }
        }

        stage('build-test') {
            when { /* build-test */
                expression { return (params.TEST_NAME != 'none' && !params.USE_IMAGE_CACHE) }
            }

            environment { /* build-test */
                resultFile = "${env.resultsDir}/${STAGE_NAME}-result.txt"
            }

            agent { /* build-test */
                docker {
                    image "${env.dockerTag}"
                    args "--network host \
                        ${env.dockerCredsExtra} \
                    "
                    reuseNode true
                }
            }

            steps { /* build-test */
                tdd_print_debug_info("${STAGE_NAME}")
                tdd_print_result_header(env.resultFile)

                sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

source ${env.scriptsDir}/test-plugin/${params.TEST_NAME}.sh

test_name="${params.TEST_NAME}"
test_build_\${test_name//-/_} ${env.testsDir} "${env.imageDir}/rootfs" ${env.kernelSrcDir}

""")
            }

            post { /* run-test */
                cleanup {
                    echo "${STAGE_NAME}: cleanup: ${currentBuild.currentResult} -> ${currentBuild.result}"
                    archiveArtifacts(
                        artifacts: "${env.resultFile}",
                        fingerprint: true)
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
                    args "--network host \
                        ${env.dockerCredsExtra} \
                    "
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

bash -x ${env.scriptsDir}/run-kernel-qemu-tests.sh \
    --kernel=${env.kernelInstallDir}/boot/Image \
    --initrd=${env.imageDir}/initrd \
    --ssh-login-key=${env.imageDir}/login-key \
    --test-name=${params.TEST_NAME} \
    --tests-dir=${env.testsDir} \
    --out-file=${env.outFile} \
    --result-file=${env.resultFile} \
    --arch=${params.TARGET_ARCH} \
    \${extra_args} \
    --verbose
""")
                        break
                    default:
                        sshagent (credentials: ['tdd-tftp-login-key']) {
                            sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

if [[ ${params.SYSTEMD_DEBUG} ]]; then
    extra_args="--systemd-debug"
fi

bash -x ${env.scriptsDir}/run-kernel-remote-tests.sh \
    --kernel=${env.kernelInstallDir}/boot/Image \
    --initrd=${env.imageDir}/initrd \
    --ssh-login-key=${env.imageDir}/login-key \
    --test-name=${params.TEST_NAME} \
    --tests-dir=${env.testsDir} \
    --out-file=${env.outFile} \
    --result-file=${env.resultFile} \
    --test-machine=${params.TARGET_MACHINE} \
    \${extra_args} \
    --verbose
""")
                        }
                        break
                    }
                }
             }

            post { /* run-test */
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
                    archiveArtifacts(
                        artifacts: "${env.resultFile}, ${env.outFile}",
                        fingerprint: true)
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
