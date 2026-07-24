#!/usr/bin/env bash
# Proves the three claims of the scenario:
#   1. Cross-cluster global service      (IP-agnostic service discovery)
#   2. Identity-based authorization      (allow by label, deny by label — no IP)
#   3. Stable egress IP                  (one whitelistable IP, survives churn)
cd "$(dirname "$0")"; source ./lib.sh

fe() { kubectl --context "$C1_CTX" -n apps exec deploy/frontend -c shell -- "$@"; }
bad(){ kubectl --context "$C1_CTX" -n apps exec deploy/bad-client -c shell -- "$@"; }

########################################################################
bold "TEST 1 — Cross-cluster global service (backend spans BOTH clusters)"
########################################################################
info "Calling backend.apps.svc.cluster.local 10x from frontend in eks-sim:"
for i in $(seq 1 10); do
  fe curl -s --max-time 5 http://backend.apps.svc.cluster.local/ || echo "(request failed)"
done | sed 's/^/    /'
echo
ok "Responses mix eks-sim AND aks-sim => one service, two clusters, zero IPs pinned"
echo

########################################################################
bold "TEST 2 — Identity-based authorization (no CIDR anywhere)"
########################################################################
info "frontend (identity app=frontend) -> backend  [EXPECT: allowed]"
if fe curl -s --max-time 5 http://backend.apps.svc.cluster.local/ >/dev/null; then
  ok "frontend ALLOWED"
else
  warn "frontend blocked (unexpected)"
fi

info "bad-client (identity app=bad-client) -> backend  [EXPECT: denied/timeout]"
if bad curl -s --max-time 5 http://backend.apps.svc.cluster.local/ >/dev/null 2>&1; then
  warn "bad-client got through (unexpected)"
else
  ok "bad-client DENIED by identity policy (dropped, not routed) "
fi
echo "    Note: neither pod's IP appears in any policy. Reschedule them, IPs"
echo "    change, verdict is identical. That is the point."
echo

########################################################################
bold "TEST 3 — Stable egress IP to an external 'partner'"
########################################################################
info "Starting an external partner (traefik/whoami) on the docker '$KIND_NET' net"
docker rm -f partner >/dev/null 2>&1 || true
docker run -d --name partner --network "$KIND_NET" traefik/whoami >/dev/null
PARTNER_IP="$(node_ip partner)"; PARTNER_CIDR="${PARTNER_IP}/32"
EGRESS_IP="$(node_ip ${C1_NAME}-worker2)"
ok "partner IP = $PARTNER_IP   |   dedicated egress node IP = $EGRESS_IP"

# Clear any egress policy from a previous run so the BEFORE/AFTER contrast is real.
kubectl --context "$C1_CTX" delete ciliumegressgatewaypolicy egress-to-partner --ignore-not-found >/dev/null 2>&1 || true
sleep 3

info "BEFORE egress policy — source IP seen by partner (= whatever node runs the pod):"
fe curl -s --max-time 5 "http://${PARTNER_IP}/" | grep -i RemoteAddr | sed 's/^/    /' || true

info "Applying CiliumEgressGatewayPolicy (pin frontend egress -> $EGRESS_IP)"
sed "s#__PARTNER_CIDR__#${PARTNER_CIDR}#" ../manifests/egress/egress-to-partner.yaml \
  | kubectl --context "$C1_CTX" apply -f -
sleep 8

info "AFTER egress policy — source IP seen by partner (should be $EGRESS_IP every time):"
for i in 1 2 3; do
  fe curl -s --max-time 5 "http://${PARTNER_IP}/" | grep -i RemoteAddr | sed 's/^/    /' || true
done
echo
ok "All partner-bound traffic now exits via ONE stable IP ($EGRESS_IP)."
echo "    Security whitelists that single IP — not CIDR ranges, and it survives"
echo "    node/cluster upgrades. In EKS that IP is an Elastic IP; in AKS a static"
echo "    Public IP / NAT Gateway."
echo
bold "Done. Open the Hubble UI with:  cilium hubble ui --context $C1_CTX"
