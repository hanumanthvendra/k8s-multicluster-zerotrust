package org.zerotrust

/** Kaniko build + push to the local kind registry (HTTP). */
class ImageBuild implements Serializable {
  private static final long serialVersionUID = 1L
  def steps

  ImageBuild(steps) { this.steps = steps }

  void kanikoPush(Map args) {
    def registry = args.registry
    def image = args.image
    def tag = args.tag
    def dockerfile = args.dockerfile
    def context = args.context
    def dest = "${registry}/${image}:${tag}"
    steps.echo "Building ${dest}"
    steps.sh """
      set -euo pipefail
      /kaniko/executor \\
        --context="\${PWD}/${context}" \\
        --dockerfile="\${PWD}/${dockerfile}" \\
        --destination='${dest}' \\
        --insecure \\
        --insecure-pull \\
        --skip-tls-verify
    """
  }
}
