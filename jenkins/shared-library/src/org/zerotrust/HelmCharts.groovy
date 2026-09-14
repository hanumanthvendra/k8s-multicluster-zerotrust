package org.zerotrust

/**
 * Helm lint + template for per-cluster value files.
 * CPS-safe: no @NonCPS, all work goes through Pipeline steps.
 */
class HelmCharts implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  HelmCharts(steps) {
    this.steps = steps
  }

  void ensureHelmInstalled() {
    steps.sh '''
      set -euo pipefail
      if command -v helm >/dev/null 2>&1; then
        helm version --short
        exit 0
      fi
      echo "helm not on PATH — installing Helm 3"
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      helm version --short
    '''
  }

  void lintAndTemplate(String chartPath, List valueFiles) {
    if (!chartPath) {
      steps.error('chartPath is required')
    }
    valueFiles.each { String vf ->
      def overlay = "${chartPath}/${vf}"
      def release = vf.replaceAll(/^values-/, '').replaceAll(/\.yaml$/, '')
      steps.echo "helm lint ${chartPath} -f ${overlay}"
      steps.sh "helm lint '${chartPath}' -f '${overlay}'"
      steps.echo "helm template zerotrust-${release} ${chartPath} -f ${overlay}"
      steps.sh "helm template 'zerotrust-${release}' '${chartPath}' -f '${overlay}' >/dev/null"
    }
    steps.echo "Helm lint + template OK for ${valueFiles.size()} overlay(s)"
  }
}
