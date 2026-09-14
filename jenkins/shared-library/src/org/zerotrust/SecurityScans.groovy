package org.zerotrust

/** Gitleaks (secrets) + Semgrep (SAST). */
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
}
