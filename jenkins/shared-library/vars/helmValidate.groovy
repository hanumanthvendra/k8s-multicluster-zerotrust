/**
 * Lint and template a Helm chart against per-cluster value files.
 *
 * helmValidate(chartPath: 'charts/zerotrust-apps', valueFiles: ['values-eks-sim.yaml'])
 */
def call(Map args = [:]) {
  def chartPath = args.chartPath ?: 'charts/zerotrust-apps'
  def valueFiles = args.valueFiles ?: ['values.yaml']
  new org.zerotrust.HelmCharts(this).lintAndTemplate(chartPath, valueFiles)
}
