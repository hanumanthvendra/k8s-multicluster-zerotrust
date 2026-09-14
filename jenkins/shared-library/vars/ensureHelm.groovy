/**
 * Install Helm 3 on the agent if it is missing.
 */
def call() {
  new org.zerotrust.HelmCharts(this).ensureHelmInstalled()
}
