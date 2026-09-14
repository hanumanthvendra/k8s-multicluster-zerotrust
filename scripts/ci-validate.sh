#!/usr/bin/env bash
# CI contract: Helm charts must render. Used by Jenkins and `make gitops-lint`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/zerotrust-apps"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }

helm lint "$CHART" -f "$CHART/values-eks-sim.yaml"
helm lint "$CHART" -f "$CHART/values-aks-sim.yaml"
helm template zerotrust-eks "$CHART" -f "$CHART/values-eks-sim.yaml" >/dev/null
helm template zerotrust-aks "$CHART" -f "$CHART/values-aks-sim.yaml" >/dev/null
echo "Helm lint + template OK"
