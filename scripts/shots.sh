#!/usr/bin/env bash
# Screenshot helper. Each subcommand prints ONE clean, titled block to screenshot.
# Save every screenshot into  linkedin/screenshots/  with the suggested name.
#
#   ./scripts/shots.sh 1     cross-cluster global service   -> 01-global-service.png
#   ./scripts/shots.sh 2     identity allow / deny          -> 02-identity-authz.png
#   ./scripts/shots.sh 3     stable egress IP before/after  -> 03-stable-egress.png
#   ./scripts/shots.sh 4     mesh + wireguard status        -> 04-mesh-status.png
#   ./scripts/shots.sh 5     the identity-scoping gotcha    -> 05-identity-scoping.png
#   ./scripts/shots.sh traffic   generate traffic while the Hubble UI is open
cd "$(dirname "$0")"; source ./lib.sh

hr(){ printf '\033[1;36m%s\033[0m\n' "────────────────────────────────────────────────────────────"; }
title(){ hr; printf '\033[1m  %s\033[0m\n' "$*"; hr; }
fe(){ kubectl --context "$C1_CTX" -n apps exec deploy/frontend -c shell -- "$@"; }
bad(){ kubectl --context "$C1_CTX" -n apps exec deploy/bad-client -c shell -- "$@"; }

case "${1:-}" in
1)
  title "One global service across EKS + AKS  —  discovery by identity, not IP"
  echo "frontend (in eks-sim)  ->  curl backend.apps.svc.cluster.local  x10"
  echo
  for i in $(seq 1 10); do fe curl -s --max-time 5 http://backend.apps.svc.cluster.local/; done \
    | sed 's/^/   /'
  echo
  echo "→ Same service name. Two clusters. Load-balanced. Zero IPs pinned."
  ;;
2)
  title "Identity-based authorization  —  no IP or CIDR anywhere in the policy"
  echo "Policy: app=frontend (from eks-sim) may call app=backend :8080"
  echo
  printf '   frontend   (app=frontend)   -> backend : '
  fe curl -s --max-time 5 http://backend.apps.svc.cluster.local/ >/dev/null 2>&1 \
    && echo "ALLOWED ✅" || echo "blocked"
  printf '   bad-client (app=bad-client) -> backend : '
  bad curl -s --max-time 5 http://backend.apps.svc.cluster.local/ >/dev/null 2>&1 \
    && echo "got through" || echo "DENIED / DROPPED ⛔"
  echo
  echo "→ Verdict follows IDENTITY. Reschedule the pods, IPs change, result is identical."
  ;;
3)
  title "Stable egress IP  —  whitelist ONE address, not CIDR ranges"
  docker rm -f partner >/dev/null 2>&1 || true
  docker run -d --name partner --network "$KIND_NET" traefik/whoami >/dev/null
  P=$(node_ip partner); EG=$(node_ip ${C1_NAME}-worker2)
  kubectl --context "$C1_CTX" delete ciliumegressgatewaypolicy egress-to-partner --ignore-not-found >/dev/null 2>&1
  sleep 3
  echo "partner=$P   dedicated egress node=$EG"
  echo
  echo "BEFORE  (no egress policy) — source IP the partner sees:"
  fe curl -s --max-time 5 "http://${P}/" | grep -i RemoteAddr | sed 's/^/   /'
  sed "s#__PARTNER_CIDR__#${P}/32#" ../manifests/egress/egress-to-partner.yaml \
    | kubectl --context "$C1_CTX" apply -f - >/dev/null
  sleep 8
  echo
  echo "AFTER  (egress gateway pinned to $EG) — source IP, three requests:"
  for i in 1 2 3; do fe curl -s --max-time 5 "http://${P}/" | grep -i RemoteAddr | sed 's/^/   /'; done
  echo
  echo "→ In EKS that IP is an Elastic IP; in AKS a static Public IP / NAT Gateway."
  ;;
4)
  title "Cluster Mesh connected + WireGuard encryption in transit"
  cilium clustermesh status --context "$C1_CTX" 2>/dev/null \
    | grep -iE "remote cluster|nodes are connected|Cluster Connections|aks-sim:" | sed 's/^/   /'
  echo
  kubectl --context "$C1_CTX" -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg status 2>/dev/null | grep -iE "KubeProxyReplacement|Routing|Encryption|ClusterMesh" | sed 's/^/   /'
  ;;
5)
  title "The gotcha: cross-cluster identity is default-deny (opt in per cluster)"
  echo "The policy's app=frontend selector, as resolved on aks-sim — note Cilium"
  echo "appended the source-cluster label. Cross-cluster trust is explicit:"
  echo
  kubectl --context "$C2_CTX" -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg policy selectors list 2>/dev/null | sed 's/^/   /'
  echo
  echo "→ A local rule can never silently authorize a look-alike identity from"
  echo "  another cluster. That is zero-trust working as intended."
  ;;
traffic)
  title "Generating cross-cluster + partner traffic (Ctrl-C to stop)"
  echo "Leave this running while the Hubble UI is open so the map stays live."
  docker inspect partner >/dev/null 2>&1 || docker run -d --name partner --network "$KIND_NET" traefik/whoami >/dev/null
  P=$(node_ip partner)
  while true; do
    fe curl -s --max-time 3 http://backend.apps.svc.cluster.local/ >/dev/null 2>&1 || true
    bad curl -s --max-time 2 http://backend.apps.svc.cluster.local/ >/dev/null 2>&1 || true
    fe curl -s --max-time 3 "http://${P}/" >/dev/null 2>&1 || true
    sleep 1
  done
  ;;
*)
  echo "usage: ./scripts/shots.sh {1|2|3|4|5|traffic}"; exit 1;;
esac
