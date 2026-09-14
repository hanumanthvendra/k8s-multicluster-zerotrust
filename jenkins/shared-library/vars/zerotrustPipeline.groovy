/**
 * Scripted GitOps CI pipeline. Jenkinsfile should be:
 *
 *   @Library('zerotrust') _
 *   zerotrustPipeline()
 */
def call(Map args = [:]) {
  def chartPath = args.chartPath ?: 'charts/zerotrust-apps'
  def clusters = args.clusters ?: ['eks-sim', 'aks-sim']
  def valueFiles = args.valueFiles ?: clusters.collect { "values-${it}.yaml" }

  node {
    timestamps {
      stage('Checkout') {
        checkout scm
      }

      stage('Ensure Helm') {
        ensureHelm()
      }

      stage('Validate Helm charts') {
        helmValidate(chartPath: chartPath, valueFiles: valueFiles)
      }

      stage('GitOps gate') {
        gitOpsGate(clusters: clusters)
      }
    }
  }
}
