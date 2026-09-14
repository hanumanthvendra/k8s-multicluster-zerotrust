package org.zerotrust

/**
 * GitOps contract: Jenkins is CI. Argo CD is CD.
 * Application manifests are never kubectl-applied from this pipeline.
 */
class GitOps implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  GitOps(steps) {
    this.steps = steps
  }

  void gate(List clusters) {
    def names = clusters.join(', ')
    steps.echo "GitOps gate: CI passed. Argo CD syncs charts/zerotrust-apps -> ${names}."
    steps.echo 'Release path: merge to the GitOps branch. Argo CD prune + selfHeal from Git.'
    steps.echo 'This pipeline must not kubectl apply / helm upgrade application workloads.'
  }
}
