package org.zerotrust

/**
 * GitOps contract: Jenkins is CI. Argo CD is CD.
 * After human approval, Jenkins only updates the image tag in Git.
 */
class GitOps implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  GitOps(steps) {
    this.steps = steps
  }

  void gate(List clusters) {
    def names = clusters.join(', ')
    steps.echo "GitOps: tag is in Git. Argo CD syncs charts/zerotrust-apps -> ${names}."
    steps.echo 'This pipeline must not kubectl apply / helm upgrade application workloads.'
  }

  void bumpBackendTagAndPush(String tag, String repoUrl, String credentialsId) {
    def valuesFile = 'charts/zerotrust-apps/values.yaml'
    steps.withCredentials([steps.usernamePassword(
      credentialsId: credentialsId,
      usernameVariable: 'GIT_USER',
      passwordVariable: 'GIT_TOKEN'
    )]) {
      steps.sh """
        set -euo pipefail
        TAG='${tag}'
        FILE='${valuesFile}'
        awk -v tag="\$TAG" '
          \$0 ~ /^backend:/ { b=1 }
          b && \$0 ~ /tag:/ {
            sub(/"[^"]+"/, "\\"" tag "\\"")
            b=0
          }
          { print }
        ' "\$FILE" > "\$FILE.tmp"
        mv "\$FILE.tmp" "\$FILE"
        git status -sb
        git diff -- "\$FILE"
        if git diff --quiet -- "\$FILE"; then
          echo "tag already \$TAG — nothing to commit"
          exit 0
        fi
        git add "\$FILE"
        git -c user.email=jenkins@local -c user.name=jenkins \\
          commit -m "chore(gitops): set backend.image.tag to \$TAG [skip ci]"
        git push "https://x-access-token:\${GIT_TOKEN}@github.com/hanumanthvendra/k8s-multicluster-zerotrust.git" HEAD:main
      """
    }
  }
}
