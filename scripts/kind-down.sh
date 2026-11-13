#!/usr/bin/env bash
# make kind-down: delete the local kind cluster.
. "$(dirname "$0")/lib.sh"
need kind
kind delete cluster --name "$KIND_CLUSTER_NAME"
if [ "$(cat "$LAB_STATE_DIR/env" 2>/dev/null)" = kind ]; then rm -f "$LAB_STATE_DIR/env"; fi
rm -rf "$LAB_STATE_DIR/overlay"
state_clear
