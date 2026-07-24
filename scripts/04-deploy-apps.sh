#!/usr/bin/env bash
# Deploys backend into BOTH clusters (global service), clients into eks-sim,
# and the identity-based authorization policy into both clusters.
cd "$(dirname "$0")"; source ./lib.sh
M=../manifests

info "Namespaces"
kubectl --context "$C1_CTX" apply -f "$M/apps/namespace.yaml"
kubectl --context "$C2_CTX" apply -f "$M/apps/namespace.yaml"

info "backend -> eks-sim (global service) and aks-sim (global service)"
kubectl --context "$C1_CTX" apply -f "$M/apps/backend-eks.yaml"
kubectl --context "$C2_CTX" apply -f "$M/apps/backend-aks.yaml"

info "clients (frontend + bad-client) -> eks-sim"
kubectl --context "$C1_CTX" apply -f "$M/apps/clients.yaml"

info "identity-based authorization policy -> both clusters"
kubectl --context "$C1_CTX" apply -f "$M/policies/backend-allow-frontend.yaml"
kubectl --context "$C2_CTX" apply -f "$M/policies/backend-allow-frontend.yaml"

info "Waiting for rollouts"
kubectl --context "$C1_CTX" -n apps rollout status deploy/backend --timeout=120s
kubectl --context "$C2_CTX" -n apps rollout status deploy/backend --timeout=120s
kubectl --context "$C1_CTX" -n apps rollout status deploy/frontend --timeout=120s
kubectl --context "$C1_CTX" -n apps rollout status deploy/bad-client --timeout=120s
ok "All workloads running"

bold "Deployed. Next:  ./scripts/05-test.sh"
