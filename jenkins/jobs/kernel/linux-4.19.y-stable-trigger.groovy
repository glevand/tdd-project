#!groovy
// Polls linux kernel repo for changes, builds kernel, runs tests.

script {
    library identifier: 'tdd@master', retriever: legacySCM(scm)
}

kernelTrigger {
    git_url = 'https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
    git_branch = 'linux-4.19.y'
    cron_spec = 'H H/6 * * *' // Every 6 Hrs.
}
