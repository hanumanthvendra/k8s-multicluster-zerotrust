#!/usr/bin/env bash
# Shared config + helpers. Sourced by every script.
set -euo pipefail

# ---- Cluster identity -------------------------------------------------------
# Two kind clusters standing in for EKS and AKS. IDs and CIDRs MUST be unique
# per cluster for Cluster Mesh to work.
export C1_NAME="eks-sim"   ; export C1_ID=1 ; export C1_POD_CIDR="10.1.0.0/16"
export C2_NAME="aks-sim"   ; export C2_ID=2 ; export C2_POD_CIDR="10.2.0.0/16"

export C1_CTX="kind-${C1_NAME}"
export C2_CTX="kind-${C2_NAME}"

# Pin Cilium for reproducibility. Override with:  CILIUM_VERSION=1.17.x ./script
export CILIUM_VERSION="${CILIUM_VERSION:-1.19.6}"

# Docker network shared by all kind nodes (nodes are mutually routable here,
# which is what lets Cluster Mesh and the egress demo work locally).
export KIND_NET="kind"

# Git source of truth for Argo CD + Jenkins (override if you fork).
export GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/hanumanthvendra/k8s-multicluster-zerotrust.git}"

# ---- Pretty logging ---------------------------------------------------------
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✔ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31mx %s\033[0m\n" "$*" >&2; exit 1; }

# IP of a kind node's container on the shared docker network (used as the
# in-cluster API server address for kube-proxy replacement).
node_ip() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
