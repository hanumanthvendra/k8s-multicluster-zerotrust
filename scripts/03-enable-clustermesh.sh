#!/usr/bin/env bash
# Wires the two clusters into a single mesh and mutually authenticates them.
# After this, a Service annotated as "global" is discoverable and load-balanced
# ACROSS both clusters — by identity, not by IP.
cd "$(dirname "$0")"; source ./lib.sh

info "Enabling Cluster Mesh apiserver on both clusters (NodePort — works on kind)"
cilium clustermesh enable --context "$C1_CTX" --service-type NodePort
cilium clustermesh enable --context "$C2_CTX" --service-type NodePort

info "Waiting for clustermesh apiservers"
cilium clustermesh status --context "$C1_CTX" --wait
cilium clustermesh status --context "$C2_CTX" --wait

info "Connecting $C1_NAME <-> $C2_NAME (exchanges certs, no shared secrets by hand)"
# --allow-mismatching-ca: each cluster was provisioned with its OWN Cilium CA,
# which is exactly what you get with independently-created EKS and AKS clusters.
# This bundles the remote CA into the trust store instead of requiring a single
# shared CA. (Alternative for greenfield: install both clusters from one shared
# CA up front — see README "Sharing a CA".)
cilium clustermesh connect --context "$C1_CTX" --destination-context "$C2_CTX" \
  --allow-mismatching-ca

info "Waiting for the mesh to converge"
cilium clustermesh status --context "$C1_CTX" --wait
cilium clustermesh status --context "$C2_CTX" --wait
ok "Cluster Mesh established"

bold "Mesh up. Next:  ./scripts/04-deploy-apps.sh"
