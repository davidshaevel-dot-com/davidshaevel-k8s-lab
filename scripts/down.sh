#!/usr/bin/env bash
# make down: destroy the AKS lab cluster and everything Terraform created with it.
. "$(dirname "$0")/lib.sh"
need terraform
tf destroy -input=false
kubectl config delete-context "$AKS_CONTEXT" >/dev/null 2>&1 || true
if [ "$(cat "$LAB_STATE_DIR/env" 2>/dev/null)" = aks ]; then rm -f "$LAB_STATE_DIR/env"; fi
rm -rf "$LAB_STATE_DIR/overlay"
state_clear
