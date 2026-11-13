#!/usr/bin/env bash
# make kind-up: create the local kind cluster (idempotent).
. "$(dirname "$0")/lib.sh"
need docker; need kind; need kubectl
docker info >/dev/null 2>&1 || die "Docker is not running; start Docker Desktop first"
if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER_NAME"; then
  info "kind cluster $KIND_CLUSTER_NAME already exists"
else
  info "Creating kind cluster $KIND_CLUSTER_NAME"
  kind create cluster --name "$KIND_CLUSTER_NAME" --config "$LAB_ROOT/kind/cluster.yaml" --wait 120s
fi
mkdir -p "$LAB_STATE_DIR" && echo kind > "$LAB_STATE_DIR/env"
kubectl config use-context "$KIND_CONTEXT" >/dev/null
kubectl get nodes
