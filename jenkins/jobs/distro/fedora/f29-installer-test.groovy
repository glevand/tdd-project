#!groovy
// Test install of Fedora.


script {
    library identifier: "tdd-project@master", retriever: legacySCM(scm)
}

String test_machine = 'gbt2s19'

pipeline {
    parameters {
        booleanParam(name: 'DOCKER_PURGE',
            defaultValue: false,
            description: 'Remove existing tdd builder image and rebuild.')
        string(name: 'FEDORA_KICKSTART_URL',
            defaultValue: '',
            description: 'URL of an alternate Anaconda kickstart file.')
        booleanParam(name: 'FORCE', 
            defaultValue: false,
            description: 'Force tests to run.')
        string(name: 'FEDORA_INITRD_URL',
            //defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/os/images/pxeboot/initrd.img',
            defaultValue: 'https://download.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/os/images/pxeboot/initrd.img',
            description: 'URL of Fedora Anaconda initrd.')
        //string(name: 'FEDORA_ISO_URL', // TODO: Add iso support.
        //    defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/iso/Fedora-Server-netinst-aarch64-29-???.iso',
        //    description: 'URL of Fedora Anaconda CD-ROM iso.')
        string(name: 'FEDORA_KERNEL_URL',
            //defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/os/images/pxeboot/vmlinuz',
            defaultValue: 'https://download.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/os/images/pxeboot/vmlinuz',
            description: 'URL of Fedora Anaconda kernel.')
        booleanParam(name: 'RUN_QEMU_TESTS',
            defaultValue: true,
            description: 'Run kernel tests in QEMU emulator.')
        booleanParam(name: 'RUN_REMOTE_TESTS',
            defaultValue: false,
            description: 'Run kernel tests on remote test machine.')
        choice(name: 'TARGET_ARCH',
            choices: "arm64\namd64\nppc64le",
            description: 'Target architecture to build for.')
        string(name: 'PIPELINE_BRANCH',
               defaultValue: 'master',
               description: 'Branch to use for fetching the pipeline jobs')
    }

    options {
        // Timeout if no node available.
        timeout(time: 90, unit: 'MINUTES')
        //timestamps()
        buildDiscarder(logRotator(daysToKeepStr: '10', numToKeepStr: '5'))
    }

    environment {
        String tddStorePath = sh(
            returnStdout: true,
            script: "set -x; \
if [ \${TDD_STORE} ]; then \
    echo -n \${TDD_STORE}; \
else \
    echo -n /run/tdd-store/\${USER}; \
fi")
        jenkinsCredsPath = "${env.tddStorePath}/jenkins_creds"
        String dockerCredsExtra = "-v ${env.jenkinsCredsPath}/group:/etc/group:ro \
        -v ${env.jenkinsCredsPath}/passwd:/etc/passwd:ro \
        -v ${env.jenkinsCredsPath}/shadow:/etc/shadow:ro \
        -v ${env.jenkinsCredsPath}/sudoers.d:/etc/sudoers.d:ro"
        String dockerSshExtra = sh(
            returnStdout: true,
            script: "set -x; \
if [ \${TDD_JENKINS} ]; then \
    echo -n ' '; \
else \
    user=\$(id --user --real --name); \
    echo -n '-v /home/\${user}/.ssh:/home/\${user}/.ssh'; \
fi")
        String dockerTag = sh(
            returnStdout: true,
            script: './docker/builder/build-builder.sh --tag').trim()
        String qemu_out = "qemu-console.txt"
        String remote_out = test_machine + "-console.txt"
        String tftp_initrd = 'tdd-initrd'
        String tftp_kickstart = 'tdd-kickstart'
        String tftp_kernel = 'tdd-kernel'
    }

    agent {
        //label "${params.NODE_ARCH} && docker"
        label 'master'
    }

    stages {

        stage('setup') {
            steps { /* setup */
                tdd_setup_jenkins_creds()
            }
        }

        stage('parallel-setup') {
            failFast false
            parallel { /* parallel-setup */

                stage('download-files') {
                    steps { /* download-files */
                        tdd_print_debug_info("start")

                        copyArtifacts(
                            projectName: "${JOB_NAME}",
                            selector: lastCompleted(),
                            fingerprintArtifacts: true,
                            optional: true,
                        )

                        sh("""#!/bin/bash
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '
set -ex

rm -f ${env.tftp_initrd} ${env.tftp_kickstart} ${env.tftp_kernel}

if [[ -n "${params.FEDORA_KICKSTART_URL}" ]]; then
    curl --silent --show-error --location ${params.FEDORA_KICKSTART_URL} > ${env.tftp_kickstart}
else
    cp jenkins/jobs/distro/fedora/f29-qemu.ks ${env.tftp_kickstart}
fi
curl --silent --show-error --location ${params.FEDORA_INITRD_URL} > ${env.tftp_initrd}
curl --silent --show-error --location ${params.FEDORA_KERNEL_URL} > ${env.tftp_kernel}

if [[ -f md5sum.txt ]]; then
    last="\$(cat md5sum.txt)"
fi

current=\$(md5sum ${env.tftp_initrd} ${env.tftp_kernel})

set +x
echo '------'
echo "last    = \n\${last}"
echo "current = \n\${current}"
ls -l ${env.tftp_initrd} ${env.tftp_kernel}
echo '------'
set -x

if [[ "${params.FORCE}" == 'true' || -z "\${last}" \
    || "\${current}" != "\${last}" ]]; then
    echo "${STAGE_NAME}: Need test."
    echo "\${current}" > md5sum.txt
    echo "yes" > need-test
else
    echo "${STAGE_NAME}: No change."
    echo "no" > need-test
fi
""")
                }
                post { /* download-files */
                    success {
                        archiveArtifacts(
                            artifacts: "md5sum.txt",
                            fingerprint: true
                        )
                    }
                    cleanup {
                        echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                    }
                }
            }

            stage('build-builder') {
                steps { /* build-builder */
                        tdd_print_debug_info("start")
                        tdd_print_result_header()

                    echo "${STAGE_NAME}: dockerTag=@${env.dockerTag}@"

                    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

tag=${env.dockerTag}
docker images \${tag%:*}

[[ "${params.DOCKER_PURGE}" != 'true' ]] || build_args=' --purge'

./docker/builder/build-builder.sh \${build_args}

""")
                }
                post { /* build-builder */
                    cleanup {
                        echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                    }
                }
            }
        }
    }

    stage('parallel-test') {
            failFast false
            parallel { /* parallel-test */

                stage('remote-tests') {

                    when {
                        expression { return params.RUN_REMOTE_TESTS == true \
                            && readFile('need-test').contains('yes')  }
                    }

                    stages { /* remote-tests */

                        stage('upload-files') {
                            steps {
                                echo "${STAGE_NAME}: start"
                                tdd_upload_tftp_files('tdd-tftp-login-key',
                                    env.tftp_server, env.tftp_root,
                                    env.tftp_initrd + ' ' + env.tftp_kernel + ' '
                                        + env.tftp_kickstart)
                            }
                        }

                        stage('run-remote-tests') {

                            agent { /* run-remote-tests */
                                docker {
                                    image "${env.dockerTag}"
                                    args "--network host \
                                        ${env.dockerCredsExtra} \
                                        ${env.dockerSshExtra} \
                                    "
                                    reuseNode true
                                }
                            }

                            environment { /* run-remote-tests */
                                TDD_BMC_CREDS = credentials("${test_machine}_bmc_creds")
                            }

                            options { /* run-remote-tests */
                                timeout(time: 90, unit: 'MINUTES')
                            }

                            steps { /* run-remote-tests */
                                echo "${STAGE_NAME}: start"
                                tdd_print_debug_info("${STAGE_NAME}")
                                tdd_print_result_header()

                                script {
                                    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

echo "--------"
printenv | sort
echo "--------"

echo "${STAGE_NAME}: TODO"
""")
                                    currentBuild.result = 'FAILURE' // FIXME.
                                }
                            }

                            post { /* run-remote-tests */
                                cleanup {
                                    archiveArtifacts(
                                        artifacts: "${STAGE_NAME}-result.txt, ${env.remote_out}",
                                        fingerprint: true)
                                    echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                                }
                            }
                        }
                    }
                }

                stage('run-qemu-tests') {
                    when {
                        expression { return params.RUN_QEMU_TESTS == true \
                            && readFile('need-test').contains('yes')  }
                    }

                    agent { /* run-qemu-tests */
                        docker {
                            image "${env.dockerTag}"
                            args "--network host \
                                ${env.dockerCredsExtra} \
                                ${env.dockerSshExtra} \
                            "
                            reuseNode true
                        }
                    }

                    options { /* run-qemu-tests */
                        timeout(time: 90, unit: 'MINUTES')
                    }

                    steps { /* run-qemu-tests */
                        tdd_print_debug_info("start")
                        tdd_print_result_header()

                        sh("""#!/bin/bash
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '
set -ex

rm -f ${env.qemu_out}
touch ${env.qemu_out}

rm -f fedora.hda
qemu-img create -f qcow2 fedora.hda 20G

rm -f test-login-key
ssh-keygen -q -f test-login-key -N ''

scripts/run-fedora-qemu-tests.sh  \
    --arch=${params.TARGET_ARCH} \
    --initrd=${env.tftp_initrd} \
    --kernel=${env.tftp_kernel} \
    --kickstart=${env.tftp_kickstart} \
    --out-file=${env.qemu_out} \
    --hda=fedora.hda \
    --ssh-key=test-login-key \
    --verbose

""")
                    }

                    post { /* run-qemu-tests */
                        success {
                            script {
                                    if (readFile("${env.qemu_out}").contains('reboot: Power down')) {
                                        echo "${STAGE_NAME}: FOUND 'reboot' message."
                                    } else {
                                        echo "${STAGE_NAME}: DID NOT FIND 'reboot' message."
                                        currentBuild.result = 'FAILURE'
                                    }
                            }
                        }
                        cleanup {
                            archiveArtifacts(
                                artifacts: "${STAGE_NAME}-result.txt, ${env.qemu_out}",
                                fingerprint: true)
                            echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                        }
                    }
                }
            }
        }
    }
}

void tdd_setup_jenkins_creds() {
    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

sudo mkdir -p ${env.jenkinsCredsPath}
sudo chown \$(id --user --real --name): ${env.jenkinsCredsPath}/
sudo cp -avf /etc/group /etc/passwd /etc/shadow /etc/sudoers.d ${env.jenkinsCredsPath}/
""")
}

void tdd_print_debug_info(String info) {
    sh("""#!/bin/bash -ex
echo '${STAGE_NAME}: ${info}'
whoami
id
sudo true
""")
}

void tdd_print_result_header() {
    sh("""#!/bin/bash -ex

echo "node=${NODE_NAME}" > ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
echo "printenv" >> ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
printenv | sort >> ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
""")
}


void tdd_upload_tftp_files(String keyId, String server, String root, String files) {
    echo 'upload_tftp_files: key   = @' + keyId + '@'
    echo 'upload_tftp_files: root  = @' + root + '@'
    echo 'upload_tftp_files: files = @' + files + '@'

    sshagent (credentials: [keyId]) {
        sh("""#!/bin/bash -ex

ssh ${server} ls -lh ${root}
for f in "${files}"; do
    scp \${f} ${server}:${root}/\${f}
done
ssh ${server} ls -lh ${root}
""")
    }
}
