#!/usr/bin/env bash
# Removes everything this demo created.
cd "$(dirname "$0")"; source ./lib.sh

info "Removing external partner container"
docker rm -f partner >/dev/null 2>&1 || true
docker rm -f kind-registry >/dev/null 2>&1 || true

info "Deleting kind clusters"
kind delete cluster --name "$C1_NAME" || true
kind delete cluster --name "$C2_NAME" || true

ok "Teardown complete."
