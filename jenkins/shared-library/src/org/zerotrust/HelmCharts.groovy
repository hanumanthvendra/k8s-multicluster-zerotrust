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
      export HELM_INSTALL_DIR="${HELM_INSTALL_DIR:-$HOME/bin}"
      mkdir -p "$HELM_INSTALL_DIR"
      export PATH="$HELM_INSTALL_DIR:$HOME/.local/bin:$PATH"
      if command -v helm >/dev/null 2>&1; then
        helm version --short
        exit 0
      fi
      echo "helm not on PATH — installing Helm 3 to $HELM_INSTALL_DIR (no sudo)"
      os="$(uname -s | tr '[:upper:]' '[:lower:]')"
      machine="$(uname -m)"
      case "$machine" in
        aarch64|arm64) helm_arch=arm64 ;;
        x86_64|amd64) helm_arch=amd64 ;;
        *) echo "unsupported arch: $machine" >&2; exit 1 ;;
      esac
      helm_ver="${HELM_VERSION:-v3.16.4}"
      tmp="$(mktemp -d)"
      curl -fsSL "https://get.helm.sh/helm-${helm_ver}-${os}-${helm_arch}.tar.gz" -o "$tmp/helm.tgz"
      tar -xzf "$tmp/helm.tgz" -C "$tmp"
      install -m 0755 "$tmp/${os}-${helm_arch}/helm" "$HELM_INSTALL_DIR/helm"
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
      steps.sh """
        set -euo pipefail
        export PATH="\$HOME/bin:\$HOME/.local/bin:\$PATH"
        helm lint '${chartPath}' -f '${overlay}'
      """
      steps.echo "helm template zerotrust-${release} ${chartPath} -f ${overlay}"
      steps.sh """
        set -euo pipefail
        export PATH="\$HOME/bin:\$HOME/.local/bin:\$PATH"
        helm template 'zerotrust-${release}' '${chartPath}' -f '${overlay}' >/dev/null
      """
    }
    steps.echo "Helm lint + template OK for ${valueFiles.size()} overlay(s)"
  }
}
