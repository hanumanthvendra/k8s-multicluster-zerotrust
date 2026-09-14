#!/usr/bin/env bash
# Create Jenkins credential github-push (GitHub PAT) so the Approve stage can git push.
# Usage: GITHUB_TOKEN=ghp_... ./scripts/08-jenkins-github-cred.sh
# PAT needs repo contents:write on hanumanthvendra/k8s-multicluster-zerotrust.
cd "$(dirname "$0")"; source ./lib.sh
require curl

TOKEN="${GITHUB_TOKEN:-}"
USER="${GITHUB_USER:-hanumanthvendra}"
JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8089}"
[ -n "$TOKEN" ] || die "set GITHUB_TOKEN to a GitHub PAT (repo write)"

CRUMB_JSON="$(curl -sf -c /tmp/jks-ck -u admin:admin123 "${JENKINS_URL}/crumbIssuer/api/json")" \
  || die "Jenkins not reachable at ${JENKINS_URL} (start port-forward)"
FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumbRequestField"])' <<<"$CRUMB_JSON")"
CRUMB="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])' <<<"$CRUMB_JSON")"

# Idempotent: delete then create
curl -sf -u admin:admin123 -b /tmp/jks-ck -H "${FIELD}: ${CRUMB}" -X POST \
  "${JENKINS_URL}/credentials/store/system/domain/_/credential/github-push/doDelete" >/dev/null 2>&1 || true

CRUMB_JSON="$(curl -sf -c /tmp/jks-ck -u admin:admin123 "${JENKINS_URL}/crumbIssuer/api/json")"
FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumbRequestField"])' <<<"$CRUMB_JSON")"
CRUMB="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])' <<<"$CRUMB_JSON")"

xml=$(cat <<EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>github-push</id>
  <description>GitHub PAT for GitOps tag bump after Approve</description>
  <username>${USER}</username>
  <password>${TOKEN}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
)

curl -sf -u admin:admin123 -b /tmp/jks-ck -H "${FIELD}: ${CRUMB}" \
  -H 'Content-Type: application/xml' \
  --data-binary "$xml" \
  "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
  && ok "Jenkins credential github-push created" \
  || die "failed to create github-push (open Jenkins > Credentials)"
