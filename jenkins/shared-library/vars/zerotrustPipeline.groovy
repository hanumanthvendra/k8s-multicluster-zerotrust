/**
 * Scripted CI. After the image is in the registry, a human Approve step
 * commits backend.image.tag to Git. Argo CD deploys from that commit.
 *
 * GitOps tag-bump commits use subject prefix chore(gitops): so poll-SCM does not rebuild.
 */
def call(Map args = [:]) {
  def chartPath = args.chartPath ?: 'charts/zerotrust-apps'
  def clusters = args.clusters ?: ['eks-sim', 'aks-sim']
  def valueFiles = args.valueFiles ?: clusters.collect { "values-${it}.yaml" }
  def registry = args.registry ?: '172.18.0.20:5000'
  def imageName = args.imageName ?: 'zerotrust-backend'
  def dockerfile = args.dockerfile ?: 'app/backend/Dockerfile'
  def dockerContext = args.dockerContext ?: 'app/backend'
  def gitCreds = args.gitCredentialsId ?: 'github-push'
  def repoUrl = args.repoUrl ?: 'https://github.com/hanumanthvendra/k8s-multicluster-zerotrust.git'
  def label = "zt-ci-${UUID.randomUUID().toString().take(8)}"

  def gitSha = 'dev'
  def skipCi = false

  def podYaml = """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  securityContext:
    fsGroup: 1000
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:3309.v27b_9314fd1a_4-3-jdk21
    - name: gitleaks
      image: zricethezav/gitleaks:v8.24.3
      command: ["sleep", "infinity"]
    - name: semgrep
      image: semgrep/semgrep:1.110.0
      command: ["sleep", "infinity"]
    - name: helm
      image: alpine/helm:3.16.4
      command: ["sleep", "infinity"]
    - name: python
      image: python:3.12-alpine
      command: ["sleep", "infinity"]
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: ["sleep", "infinity"]
"""

  podTemplate(label: label, yaml: podYaml) {
    node(label) {
      timestamps {
        stage('Checkout') {
          checkout scm
          gitSha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          def lastSubject = sh(script: 'git log -1 --pretty=%s', returnStdout: true).trim()
          echo "git=${gitSha} subject=${lastSubject}"
          if (lastSubject.startsWith('chore(gitops):')) {
            skipCi = true
            echo 'Skipping CI — this commit is a GitOps image-tag bump.'
          }
        }

        if (!skipCi) {
          stage('Security') {
            parallel(
              Secrets: {
                container('gitleaks') {
                  new org.zerotrust.SecurityScans(this).gitleaks()
                }
              },
              SAST: {
                container('semgrep') {
                  new org.zerotrust.SecurityScans(this).semgrep()
                }
              }
            )
          }

          stage('Build') {
            parallel(
              Helm: {
                container('helm') {
                  helmValidate(chartPath: chartPath, valueFiles: valueFiles)
                }
              },
              Compile: {
                container('python') {
                  sh 'python -m py_compile app/backend/server.py'
                }
              }
            )
          }

          stage('Image') {
            container('kaniko') {
              new org.zerotrust.ImageBuild(this).kanikoPush(
                registry: registry,
                image: imageName,
                tag: gitSha,
                dockerfile: dockerfile,
                context: dockerContext
              )
              echo "Pushed ${registry}/${imageName}:${gitSha}"
            }
          }
        }
      }
    }
  }

  if (skipCi) {
    return
  }

  // Agent pod is gone. Wait for a human so we do not hold Kaniko/Semgrep nodes.
  stage('Approve GitOps') {
    timeout(time: 24, unit: 'HOURS') {
      input message: "Deploy ${registry}/${imageName}:${gitSha} via Argo CD? This will commit the tag to GitHub main.", ok: 'Approve'
    }
  }

  node {
    timestamps {
      stage('Update image tag in Git') {
        checkout scm
        new org.zerotrust.GitOps(this).bumpBackendTagAndPush(gitSha, repoUrl, gitCreds)
        gitOpsGate(clusters: clusters)
      }
    }
  }
}
