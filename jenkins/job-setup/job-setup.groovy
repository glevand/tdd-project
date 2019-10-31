/*
 * Create TDD CI jobs on a Jenkins server.
 *
 * This entire script can be pasted directly into the text box found at
 * ${JENKINS_URL}/script to populate the server with jobs
 *
 * Note that settings such as user permissions and secret credentials
 * are not handled by this script.
 */

final String REPO_URL = 'https://github.com/glevand/tdd-project.git'
final String REPO_JOB_PATH = 'jenkins/jobs'
final String REPO_BRANCH = 'dev'
final String BASE_FOLDER = 'tdd-dev'
\
/*
 * Create a new folder project under the given parent model.
 */
Actionable createFolder(String name,
                        ModifiableTopLevelItemGroup parent = Jenkins.instance,
                        String description = '') {
    parent.createProjectFromXML(name, new ByteArrayInputStream("""\
<?xml version="1.0" encoding="UTF-8"?>
<com.cloudbees.hudson.plugins.folder.Folder plugin="cloudbees-folder">
  <description>${description}</description>
  <healthMetrics>
    <com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
      <nonRecursive>true</nonRecursive>
    </com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
  </healthMetrics>
</com.cloudbees.hudson.plugins.folder.Folder>
""".bytes))
}

/*
 * Create a new pipeline project under the given parent model.
 *
 * This XML template assumes all jobs will pull the Groovy source from
 * the repository and that the source has a properties step to overwrite
 * the initial parameter definitions.
 */
Job createPipeline(String name,
                   ModifiableTopLevelItemGroup parent = Jenkins.instance,
                   String description = '',
                   String repo = REPO_URL,
                   String branch = '${PIPELINE_BRANCH}',
                   String script = 'Jenkinsfile',
                   String defaultPipelineBranch = REPO_BRANCH) {
    parent.createProjectFromXML(name, new ByteArrayInputStream("""\
<?xml version="1.0" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <description>${description}</description>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>PIPELINE_BRANCH</name>
          <description>Branch to use for fetching the Jenkins pipeline jobs.</description>
          <defaultValue>${defaultPipelineBranch}</defaultValue>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>${repo}</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/${branch}</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <extensions>
        <hudson.plugins.git.extensions.impl.CleanBeforeCheckout/>
      </extensions>
    </scm>
    <scriptPath>${script}</scriptPath>
  </definition>
</flow-definition>
""".bytes))
}

/* Create a temporary directory for cloning the pipeline repository.  */
def proc = ['/bin/mktemp', '--directory'].execute()
proc.waitFor()
if (proc.exitValue() != 0)
    throw new Exception('Could not create a temporary directory')
final String REPO_PATH = proc.text.trim()

/* Fetch all the Groovy pipeline scripts.  */
proc = ['/usr/bin/git', 'clone', "--branch=${REPO_BRANCH}", '--depth=1', REPO_URL, REPO_PATH].execute()
proc.waitFor()
if (proc.exitValue() != 0)
    throw new Exception("Could not clone ${REPO_URL} into ${REPO_PATH}")

def f_base = createFolder(BASE_FOLDER)
def f_kernel = createFolder('kernel', f_base)
def f_distro = createFolder('distro', f_base)
def f_fedora = createFolder('fedora', f_distro)

def jobs = [
    1: [name: 'kernel-test',
        description: 'Runs tests on a Linux kernel git repository.',
        script: '/kernel/kernel-test.groovy',
        folder: f_kernel],
    2: [name: 'linux-mainline-trigger',
        description: 'Polls linux mainline for changes.  Builds kernel and runs a boot test in QEMU.',
        script: '/kernel/linux-mainline-trigger.groovy',
        folder: f_kernel],
    3: [name: 'linux-next-trigger',
        description: 'Polls linux-next for changes.  Builds kernel and runs a boot test in QEMU.',
        script: '/kernel/linux-next-trigger.groovy',
        folder: f_kernel],
    4: [name: 'linux-4.19.y-stable-trigger',
        description: 'Polls linux-stable for changes.  Builds kernel and runs a boot test in QEMU.',
        script: '/kernel/linux-4.19.y-stable-trigger.groovy',
        folder: f_kernel],
    5: [name: 'linux-4.20.y-stable-trigger',
        description: 'Polls linux-stable for changes.  Builds kernel and runs a boot test in QEMU.',
        script: '/kernel/linux-4.20.y-stable-trigger.groovy',
        folder: f_kernel],
    6: [name: 'f29-installer-test',
        description: 'Test of latest Fedora 29 pxeboot installer.',
        script: '/distro/fedora/f29-installer-test.groovy',
        folder: f_fedora],
]

jobs.each { entry ->
    println "Creating pipeline job $entry.value.name: $entry.value.description"

    createPipeline(entry.value.name,
        entry.value.folder,
        entry.value.description,
        REPO_URL,
        '${PIPELINE_BRANCH}',
        REPO_JOB_PATH + entry.value.script,
        REPO_BRANCH)
}

/* Clean up the temporary repository.  */
proc = ['/bin/rm', '--force', '--recursive', REPO_PATH].execute()
proc.waitFor()
if (proc.exitValue() != 0)
    throw new Exception("Could not remove ${REPO_PATH}")

println 'Jenkins jobs were successfully created.'
