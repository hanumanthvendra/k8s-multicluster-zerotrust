package org.zerotrust

/**
 * Gitleaks (secrets), Semgrep + SonarQube (SAST), Trivy (deps + image).
 */
class SecurityScans implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  SecurityScans(steps) { this.steps = steps }

  void gitleaks() {
    steps.sh 'gitleaks detect --source . --no-banner --redact --config .gitleaks.toml'
  }

  void semgrep() {
    steps.sh 'semgrep scan --config .semgrep.yml --error --metrics=off .'
  }

  /** Upload to SonarQube when the server is up. Does not replace Semgrep. */
  void sonarQube(String host) {
    steps.echo "SonarQube scanner -> ${host}"
    steps.sh """
      set -euo pipefail
      if ! wget -qO- -T 8 '${host}/api/system/status' | grep -q '"status":"UP"'; then
        echo "SonarQube not UP at ${host} — skipping (Semgrep already ran as SAST)"
        exit 0
      fi
      sonar-scanner -Dsonar.host.url='${host}' -Dsonar.qualitygate.wait=false
    """
  }

  void trivyFs() {
    steps.echo 'Trivy filesystem / dependency scan (app/)'
    steps.sh '''
      set -euo pipefail
      trivy fs --timeout 10m --severity CRITICAL --exit-code 1 app
    '''
  }

  void trivyImage(String imageRef) {
    steps.echo "Trivy image scan ${imageRef}"
    steps.sh """
      set -euo pipefail
      trivy image --insecure --timeout 10m --severity CRITICAL --exit-code 1 '${imageRef}'
    """
  }
}
