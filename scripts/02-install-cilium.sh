#!/usr/bin/env bash
# Installs Cilium on both clusters with the features this scenario needs:
#   - kube-proxy replacement (eBPF)      -> prerequisite for egress gateway
#   - WireGuard transparent encryption   -> encrypts pod traffic, incl. cross-cluster
#   - egress gateway                     -> stable egress IP that survives upgrades
#   - Hubble + UI                        -> live traffic maps for screenshots
#   - cluster-pool IPAM w/ unique CIDR   -> required for Cluster Mesh
cd "$(dirname "$0")"; source ./lib.sh

install_cilium() {
  local ctx=$1 name=$2 id=$3 pod_cidr=$4 cp_node=$5
  local api_ip; api_ip="$(node_ip "$cp_node")"
  [ -n "$api_ip" ] || die "could not resolve API server IP for $cp_node"

  info "Installing Cilium on $name (id=$id, podCIDR=$pod_cidr, apiServer=$api_ip:6443)"
  cilium install --context "$ctx" --version "$CILIUM_VERSION" \
    --set cluster.name="$name" \
    --set cluster.id="$id" \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="$pod_cidr" \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="$api_ip" \
    --set k8sServicePort=6443 \
    --set encryption.enabled=true \
    --set encryption.type=wireguard \
    --set egressGateway.enabled=true \
    --set bpf.masquerade=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  info "Waiting for Cilium to be ready on $name"
  cilium status --context "$ctx" --wait
  ok "Cilium ready on $name"
}

install_cilium "$C1_CTX" "$C1_NAME" "$C1_ID" "$C1_POD_CIDR" "${C1_NAME}-control-plane"
install_cilium "$C2_CTX" "$C2_NAME" "$C2_ID" "$C2_POD_CIDR" "${C2_NAME}-control-plane"

# Label one worker in eks-sim as the dedicated egress gateway node.
info "Labelling egress-gateway node in $C1_NAME"
kubectl --context "$C1_CTX" label node "${C1_NAME}-worker2" egress-node=true --overwrite
ok "egress-node=true on ${C1_NAME}-worker2"

bold "Cilium installed on both clusters. Next:  ./scripts/03-enable-clustermesh.sh"
