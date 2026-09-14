#!/usr/bin/env bash
# Local OCI registry on the kind Docker network (not Docker Hub).
# Prod equivalent: GHCR / ECR / ACR with OIDC + immutable tags.
# Image name used by Helm + kubelet: 172.18.0.20:5000/zerotrust-backend:<tag>
cd "$(dirname "$0")"; source ./lib.sh

REG_NAME="${REG_NAME:-kind-registry}"
REG_IP="${REG_IP:-172.18.0.20}"
REG_PORT_HOST="${REG_PORT_HOST:-5001}"

info "Local registry ${REG_NAME} at ${REG_IP}:5000 (host localhost:${REG_PORT_HOST})"
if docker inspect "$REG_NAME" >/dev/null 2>&1; then
  warn "registry container already exists"
else
  docker run -d --restart=always --name "$REG_NAME" \
    --network kind --ip "$REG_IP" \
    -p "127.0.0.1:${REG_PORT_HOST}:5000" \
    registry:2
fi

# Kind nodes resolve via containerd hosts.toml (HTTP, insecure).
configure_node() {
  local node=$1
  local dir="/etc/containerd/certs.d/${REG_IP}:5000"
  info "containerd registry mirror on $node"
  docker exec "$node" mkdir -p "$dir"
  cat <<EOF | docker exec -i "$node" cp /dev/stdin "${dir}/hosts.toml"
server = "http://${REG_IP}:5000"
[host."http://${REG_IP}:5000"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
}

for ctx_name in "$C1_NAME" "$C2_NAME"; do
  kind get nodes --name "$ctx_name" | while read -r node; do
    configure_node "$node"
  done
done

# Seed Kaniko base image so CI does not pull from Docker Hub.
if ! curl -sf "http://127.0.0.1:${REG_PORT_HOST}/v2/python/manifests/3.12-alpine" >/dev/null; then
  info "Mirroring python:3.12-alpine into the local registry"
  docker pull python:3.12-alpine
  docker tag python:3.12-alpine "127.0.0.1:${REG_PORT_HOST}/python:3.12-alpine"
  docker push "127.0.0.1:${REG_PORT_HOST}/python:3.12-alpine"
fi

ok "Registry ready: http://${REG_IP}:5000  (Mac: localhost:${REG_PORT_HOST})"
echo "  Push example:  docker tag zerotrust-backend:dev ${REG_IP}:5000/zerotrust-backend:dev && docker push ${REG_IP}:5000/zerotrust-backend:dev"
echo "  Helm image:    ${REG_IP}:5000/zerotrust-backend:<tag>"
