package org.zerotrust

/**
 * GitOps contract: Jenkins is CI. Argo CD is CD. Argo Rollouts is blue/green.
 * After human approval, Jenkins only updates image tag + digest in Git.
 */
class GitOps implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  GitOps(steps) {
    this.steps = steps
  }

  void gate(List clusters) {
    def names = clusters.join(', ')
    steps.echo "GitOps: tag+digest are in Git. Argo CD syncs charts/zerotrust-apps -> ${names}."
    steps.echo 'Argo Rollouts creates Green beside Blue. Jenkins must not kubectl apply / helm upgrade / patch Services.'
  }

  void bumpBackendTagAndPush(String tag, String digest, String repoUrl, String credentialsId) {
    def valuesFile = 'charts/zerotrust-apps/values.yaml'
    steps.withCredentials([steps.usernamePassword(
      credentialsId: credentialsId,
      usernameVariable: 'GIT_USER',
      passwordVariable: 'GIT_TOKEN'
    )]) {
      steps.sh """
        set -euo pipefail
        TAG='${tag}'
        DIGEST='${digest}'
        FILE='${valuesFile}'
        awk -v tag="\$TAG" -v digest="\$DIGEST" '
          \$0 ~ /^backend:/ { b=1 }
          b && \$0 ~ /tag:/ {
            sub(/"[^"]+"/, "\\"" tag "\\"")
          }
          b && \$0 ~ /digest:/ {
            sub(/"[^"]*"/, "\\"" digest "\\"")
            b=0
          }
          { print }
        ' "\$FILE" > "\$FILE.tmp"
        mv "\$FILE.tmp" "\$FILE"
        git status -sb
        git diff -- "\$FILE"
        if git diff --quiet -- "\$FILE"; then
          echo "tag/digest already set — nothing to commit"
          exit 0
        fi
        git add "\$FILE"
        git -c user.email=jenkins@local -c user.name=jenkins \\
          commit -m "chore(gitops): set backend.image tag=\$TAG digest=\$DIGEST"
        git push "https://x-access-token:\${GIT_TOKEN}@github.com/hanumanthvendra/k8s-multicluster-zerotrust.git" HEAD:main
      """
    }
  }
}
