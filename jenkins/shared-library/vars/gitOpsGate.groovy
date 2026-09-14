/**
 * Print the CI/CD split (Jenkins validates, Argo CD deploys).
 */
def call(Map args = [:]) {
  def clusters = args.clusters ?: ['eks-sim', 'aks-sim']
  new org.zerotrust.GitOps(this).gate(clusters)
}
