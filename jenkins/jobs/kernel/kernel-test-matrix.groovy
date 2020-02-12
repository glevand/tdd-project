#!groovy
// Runs tests on a Linux kernel git repository.

properties([
    buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '5')),

    parameters([
    booleanParam(name: 'KERNEL_DEBUG',
        defaultValue: false,
        description: 'Run kernel with debug flags.'),
    string(name: 'KERNEL_GIT_BRANCH',
        defaultValue: 'master',
        description: 'Repository branch of KERNEL_GIT_URL.'),
    string(name: 'KERNEL_GIT_URL',
        defaultValue: 'https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git',
        description: 'URL of a Linux kernel git repository.'),
    string(name: 'NODE_ARCH_LIST',
        //defaultValue: 'amd64', // FIXME: For test only!!!
        defaultValue: 'amd64 arm64',
        description: 'List of Jenkins node architectures to build on.'),
    string(name: 'TARGET_ARCH_LIST',
        defaultValue: 'arm64', // FIXME: Need to setup amd64.
        description: 'List of target architectures to build for.'),
    booleanParam(name: 'USE_IMAGE_CACHE',
        defaultValue: false,
        description: 'Use cached disk image.'),
    booleanParam(name: 'USE_KERNEL_CACHE',
        defaultValue: false,
        description: 'Use cached kernel image.')
    string(name: 'PIPELINE_BRANCH',
            defaultValue: 'master',
            description: 'Branch to use for fetching the pipeline jobs')
    ])
])

def map_entry = { Boolean _kernel_debug, String _kernel_git_branch,
    String _kernel_git_url, String _node_arch, String _target_arch,
    Boolean _use_image_cache, Boolean _use_kernel_cache
    ->
    Boolean kernel_debug = _kernel_debug
    String kernel_git_branch = _kernel_git_branch
    String kernel_git_url = _kernel_git_url
    String node_arch = _node_arch
    String target_arch = _target_arch
    Boolean use_image_cache = _use_image_cache
    Boolean use_kernel_cache = _use_kernel_cache

    echo "${JOB_BASE_NAME}: Scheduleing ${node_arch}-${target_arch}"

    // Timeout if no node_arch node is available.
    timeout(time: 45, unit: 'MINUTES') {
        build(job: 'kernel-test',
            parameters: [
                booleanParam(name: 'KERNEL_DEBUG', value: kernel_debug),
                string(name: 'KERNEL_GIT_BRANCH', value: kernel_git_branch),
                string(name: 'KERNEL_GIT_URL', value: kernel_git_url),
                string(name: 'NODE_ARCH', value: node_arch),
                string(name: 'TARGET_ARCH', value: target_arch),
                booleanParam(name: 'USE_IMAGE_CACHE', value: use_image_cache),
                booleanParam(name: 'USE_KERNEL_CACHE', value: use_kernel_cache)
                string(name: 'PIPELINE_BRANCH', value: params.PIPELINE_BRANCH)
            ]
        )
    }
}

def build_map = [:]
build_map.failFast = false

for (node_arch in params.NODE_ARCH_LIST.split()) {
    for (target_arch in params.TARGET_ARCH_LIST.split()) {
        build_map[node_arch] = map_entry.curry(
            params.KERNEL_DEBUG,
            params.KERNEL_GIT_BRANCH,
            params.KERNEL_GIT_URL,
            node_arch, target_arch,
            params.USE_CHEATER_CACHE)
        }
}

stage('Downstream') {
    parallel build_map
}
