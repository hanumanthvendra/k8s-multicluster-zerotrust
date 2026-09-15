package org.zerotrust

/** Kaniko build + push to the local kind registry (HTTP). Production: ECR. */
class ImageBuild implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  ImageBuild(steps) { this.steps = steps }

  /** Push image:tag and return digest (sha256:...). */
  String kanikoPush(Map args) {
    def registry = args.registry
    def image = args.image
    def tag = args.tag
    def dockerfile = args.dockerfile
    def context = args.context
    def dest = "${registry}/${image}:${tag}"
    def digestFile = '.ci-image-digest'
    steps.echo "Building ${dest}"
    steps.sh """
      set -euo pipefail
      /kaniko/executor \\
        --context="\${PWD}/${context}" \\
        --dockerfile="\${PWD}/${dockerfile}" \\
        --destination='${dest}' \\
        --digest-file="\${PWD}/${digestFile}" \\
        --insecure \\
        --insecure-pull \\
        --skip-tls-verify
    """
    def digest = steps.sh(script: "tr -d '[:space:]' < '${digestFile}'", returnStdout: true).trim()
    steps.echo "Pushed ${dest} digest=${digest}"
    return digest
  }
}
