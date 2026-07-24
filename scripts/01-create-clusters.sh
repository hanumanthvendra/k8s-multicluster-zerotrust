#!/usr/bin/env bash
# Creates the two kind clusters (eks-sim + aks-sim). Idempotent.
cd "$(dirname "$0")"; source ./lib.sh

create() {
  local name=$1 cfg=$2
  if kind get clusters 2>/dev/null | grep -qx "$name"; then
    warn "cluster '$name' already exists — skipping"
  else
    info "Creating kind cluster: $name"
    kind create cluster --config "$cfg"
  fi
}

create "$C1_NAME" ../kind/cluster1.yaml
create "$C2_NAME" ../kind/cluster2.yaml

info "Nodes will show NotReady until Cilium is installed (no CNI yet) — expected."
kubectl --context "$C1_CTX" get nodes -o wide || true
kubectl --context "$C2_CTX" get nodes -o wide || true

bold "Clusters up. Next:  ./scripts/02-install-cilium.sh"
