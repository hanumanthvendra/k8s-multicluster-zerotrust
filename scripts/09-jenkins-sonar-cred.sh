#!/usr/bin/env bash
# Create Jenkins secret-text credential sonar-token for the SonarQube CI stage.
# Usage:
#   SONAR_TOKEN=squ_... ./scripts/09-jenkins-sonar-cred.sh
#   ./scripts/09-jenkins-sonar-cred.sh          # generate a token as admin/admin
cd "$(dirname "$0")"; source ./lib.sh
require curl

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8089}"
SONAR_URL="${SONAR_URL:-http://127.0.0.1:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASS="${SONAR_ADMIN_PASS:-admin}"

TOKEN="${SONAR_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  curl -sf --max-time 8 "${SONAR_URL}/api/system/status" | grep -q '"status":"UP"' \
    || die "SonarQube not reachable at ${SONAR_URL} (port-forward svc/sonarqube-sonarqube 9000:9000)"
  NAME="jenkins-ci-$(date +%s)"
  RESP="$(curl -sf -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASS}" -X POST \
    "${SONAR_URL}/api/user_tokens/generate?name=${NAME}")" \
    || die "could not generate Sonar token (log in as ${SONAR_ADMIN_USER} and create one)"
  TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<<"$RESP")"
  ok "Generated SonarQube token ${NAME}"
fi

CRUMB_JSON="$(curl -sf -c /tmp/jks-sonar-ck -u admin:admin123 "${JENKINS_URL}/crumbIssuer/api/json")" \
  || die "Jenkins not reachable at ${JENKINS_URL}"
FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumbRequestField"])' <<<"$CRUMB_JSON")"
CRUMB="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])' <<<"$CRUMB_JSON")"

curl -sf -u admin:admin123 -b /tmp/jks-sonar-ck -H "${FIELD}: ${CRUMB}" -X POST \
  "${JENKINS_URL}/credentials/store/system/domain/_/credential/sonar-token/doDelete" >/dev/null 2>&1 || true

CRUMB_JSON="$(curl -sf -c /tmp/jks-sonar-ck -u admin:admin123 "${JENKINS_URL}/crumbIssuer/api/json")"
FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumbRequestField"])' <<<"$CRUMB_JSON")"
CRUMB="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])' <<<"$CRUMB_JSON")"

xml=$(cat <<EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>sonar-token</id>
  <description>SonarQube user token for CI sonar-scanner</description>
  <secret>${TOKEN}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF
)

curl -sf -u admin:admin123 -b /tmp/jks-sonar-ck -H "${FIELD}: ${CRUMB}" \
  -H 'Content-Type: application/xml' \
  --data-binary "$xml" \
  "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
  && ok "Jenkins credential sonar-token created" \
  || die "failed to create sonar-token (Manage Jenkins > Credentials; plugin plain-credentials)"
