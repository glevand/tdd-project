#!groovy
// Polls linux kernel repo for changes, builds kernel, runs tests.

script {
    library identifier: 'tdd@master', retriever: legacySCM(scm)
}

kernelTrigger {
    git_url = 'https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git'
    git_branch = 'master'
    cron_spec = '@hourly'
}
