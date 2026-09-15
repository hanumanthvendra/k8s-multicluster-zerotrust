#!/usr/bin/env bash
# GitOps bootstrap on eks-sim (the hub):
#   Jenkins        = CI (scan/build/push; never kubectl-applies apps)
#   Argo CD        = CD (Helm chart from Git -> eks-sim + aks-sim)
#   Argo Rollouts  = blue/green (one controller per cluster)
cd "$(dirname "$0")"; source ./lib.sh
ROOT="$(cd .. && pwd)"

require helm
require kubectl
require curl

register_aks() {
  local ip server ca cert key
  ip="$(node_ip "${C2_NAME}-control-plane")"
  [ -n "$ip" ] || die "could not resolve ${C2_NAME}-control-plane IP"
  server="https://${ip}:6443"
  ca="$(kubectl config view --raw --minify --flatten --context "$C2_CTX" -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  cert="$(kubectl config view --raw --minify --flatten --context "$C2_CTX" -o jsonpath='{.users[0].user.client-certificate-data}')"
  key="$(kubectl config view --raw --minify --flatten --context "$C2_CTX" -o jsonpath='{.users[0].user.client-key-data}')"
  [ -n "$ca" ] && [ -n "$cert" ] && [ -n "$key" ] || die "could not extract kubeconfig client certs for $C2_CTX"

  info "Registering $C2_NAME with Argo CD at $server"
  kubectl --context "$C1_CTX" -n argocd apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-aks-sim
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${C2_NAME}
  server: ${server}
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${ca}",
        "certData": "${cert}",
        "keyData": "${key}"
      }
    }
EOF
  printf '%s\n' "$server"
}

info "Helm repos"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add jenkins https://charts.jenkins.io >/dev/null
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube >/dev/null
helm repo update argo jenkins sonarqube >/dev/null

info "Argo Rollouts on $C1_NAME and $C2_NAME (blue/green; not Jenkins)"
for ctx in "$C1_CTX" "$C2_CTX"; do
  helm upgrade --install argo-rollouts argo/argo-rollouts \
    --kube-context "$ctx" \
    --namespace argo-rollouts --create-namespace \
    -f "$ROOT/gitops/argo-rollouts-values.yaml" \
    --wait --timeout 5m
  ok "Argo Rollouts installed on $ctx"
done

info "Argo CD on $C1_NAME"
helm upgrade --install argocd argo/argo-cd \
  --kube-context "$C1_CTX" \
  --namespace argocd --create-namespace \
  -f "$ROOT/gitops/argocd-values.yaml" \
  --wait --timeout 10m
ok "Argo CD installed"

if [[ "${INSTALL_SONARQUBE:-1}" == "1" ]]; then
  info "SonarQube on $C1_NAME (SAST; Jenkins sonar-scanner). Set INSTALL_SONARQUBE=0 to skip."
  if helm upgrade --install sonarqube sonarqube/sonarqube \
    --kube-context "$C1_CTX" \
    --namespace sonarqube --create-namespace \
    -f "$ROOT/gitops/sonarqube-values.yaml" \
    --wait --timeout 8m; then
    ok "SonarQube installed (NodePort 30090, auth disabled for the lab)"
  else
    warn "SonarQube install failed — Jenkins will skip the SonarQube stage; Semgrep still runs"
  fi
fi

info "Jenkins on $C1_NAME (CI, GitHub source)"
if kubectl --context "$C1_CTX" -n jenkins get pod jenkins-0 >/dev/null 2>&1 && \
   [[ "$(kubectl --context "$C1_CTX" -n jenkins get pod jenkins-0 -o jsonpath='{.status.phase}')" == "Running" ]]; then
  warn "Jenkins already running — skipping helm install"
else
  helm upgrade --install jenkins jenkins/jenkins \
    --kube-context "$C1_CTX" \
    --namespace jenkins --create-namespace \
    -f "$ROOT/gitops/jenkins-values.yaml" \
    --wait --timeout 15m
  ok "Jenkins installed"
fi

AKS_SERVER="$(register_aks)"

info "AppProject + ApplicationSet (repo=$GITOPS_REPO_URL)"
kubectl --context "$C1_CTX" apply -f "$ROOT/gitops/project.yaml"
sed -e "s|__GITOPS_REPO_URL__|${GITOPS_REPO_URL}|g" \
    -e "s|__AKS_SERVER__|${AKS_SERVER}|g" \
    "$ROOT/gitops/applicationset.yaml.tmpl" \
  | kubectl --context "$C1_CTX" apply -f -

info "Waiting for Argo CD Applications to appear"
for _ in $(seq 1 60); do
  if kubectl --context "$C1_CTX" -n argocd get application zerotrust-eks-sim zerotrust-aks-sim >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
kubectl --context "$C1_CTX" -n argocd get application zerotrust-eks-sim zerotrust-aks-sim >/dev/null \
  || die "ApplicationSet did not create zerotrust-eks-sim / zerotrust-aks-sim"

info "Waiting for Helm sync (Synced; Healthy on auto-promote cluster)"
kubectl --context "$C1_CTX" -n argocd wait application/zerotrust-eks-sim \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
kubectl --context "$C1_CTX" -n argocd wait application/zerotrust-eks-sim \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s
ok "zerotrust-eks-sim synced (dev-like auto-promote)"

kubectl --context "$C1_CTX" -n argocd wait application/zerotrust-aks-sim \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
ok "zerotrust-aks-sim synced (staging-like; may pause before Promote)"

HUB_IP="$(node_ip "${C1_NAME}-control-plane")"
ARGO_PW="$(kubectl --context "$C1_CTX" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

info "Triggering Jenkins job zerotrust-gitops (best-effort)"
JENKINS_URL="http://${HUB_IP}:30081"
if curl -sf -u admin:admin123 --max-time 10 "${JENKINS_URL}/login" >/dev/null; then
  CRUMB="$(curl -sf -u admin:admin123 "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" || true)"
  if [ -n "$CRUMB" ]; then
    curl -sf -u admin:admin123 -H "$CRUMB" -X POST "${JENKINS_URL}/job/zerotrust-gitops/build" \
      && ok "Jenkins build queued" \
      || warn "Jenkins job trigger failed (open UI and Run)"
  else
    curl -sf -u admin:admin123 -X POST "${JENKINS_URL}/job/zerotrust-gitops/build" \
      && ok "Jenkins build queued" \
      || warn "Jenkins job trigger failed (open UI and Run)"
  fi
else
  warn "Jenkins UI not reachable at ${JENKINS_URL} yet"
fi

bold "GitOps is live"
echo "  Source of truth:  $GITOPS_REPO_URL  (path charts/zerotrust-apps)"
echo "  CI  Jenkins:      ${JENKINS_URL}   admin / admin123"
echo "  SAST SonarQube:   http://${HUB_IP}:30090  (svc sonarqube-sonarqube; lab auth off)"
echo "  CD  Argo CD:      http://${HUB_IP}:30080   admin / ${ARGO_PW:-<kubectl -n argocd get secret argocd-initial-admin-secret>}"
echo "  Apps:             Argo CD ApplicationSet zerotrust-apps -> ${C1_NAME} + ${C2_NAME}"
echo
bold "Next:  ./scripts/05-test.sh"
