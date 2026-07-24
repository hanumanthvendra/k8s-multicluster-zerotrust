#!/usr/bin/env bash
# Installs the Cilium CLI (and checks the rest). Safe to re-run.
cd "$(dirname "$0")"; source ./lib.sh

info "Checking required tooling"
require docker; require kind; require kubectl; require helm
docker info >/dev/null 2>&1 || die "Docker daemon is not running. Start Docker Desktop."
ok "docker / kind / kubectl / helm present"

if ! command -v cilium >/dev/null 2>&1; then
  info "Installing Cilium CLI via Homebrew"
  brew install cilium-cli
fi
ok "cilium CLI: $(cilium version --client | head -1)"

if ! command -v hubble >/dev/null 2>&1; then
  info "Installing Hubble CLI (optional, for traffic observability)"
  brew install hubble || warn "hubble CLI install skipped (not required)"
fi

bold "Prereqs ready. Next:  ./scripts/01-create-clusters.sh"
