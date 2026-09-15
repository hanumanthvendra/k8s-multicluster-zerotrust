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

  /**
   * sonar-scanner-cli with a Jenkins secret-text credential (sonar-token).
   * skipJreProvisioning: the image already has Java; auto-JRE download is flaky in kind.
   */
  void sonarQube(String host, String credentialsId) {
    steps.echo "SonarQube scanner -> ${host}"
    steps.withCredentials([steps.string(credentialsId: credentialsId, variable: 'SONAR_TOKEN')]) {
      steps.sh """
        set -euo pipefail
        sonar-scanner \\
          -Dsonar.host.url='${host}' \\
          -Dsonar.token="\$SONAR_TOKEN" \\
          -Dsonar.scanner.skipJreProvisioning=true \\
          -Dsonar.qualitygate.wait=false
      """
    }
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
