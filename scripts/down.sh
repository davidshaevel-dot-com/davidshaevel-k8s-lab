#!/usr/bin/env bash
# make down: destroy the AKS lab cluster and everything Terraform created with it.
. "$(dirname "$0")/lib.sh"
need terraform

# Remove the app before the destroy. Deleting the user node pool drains its nodes, and a
# drain evicts pods: the web PodDisruptionBudget (minAvailable 1) refuses to evict the
# last web pod when there is no other node for it, and the pool delete fails after an
# hour. Deleting the namespace removes the pods outright, budget and all. Always the AKS
# context by name, never lab_context, so a kind cluster is never touched. This step
# never fails the teardown: on any problem it warns and carries on.
remove_app() {
  local reason
  if ! kubectl config get-contexts "$AKS_CONTEXT" >/dev/null 2>&1; then
    reason="no $AKS_CONTEXT context in your kubeconfig"
  else
    info "Removing the $LAB_NS namespace from $AKS_CONTEXT so the node pool can drain"
    kubectl --context "$AKS_CONTEXT" delete namespace "$LAB_NS" --ignore-not-found \
      --wait=true --timeout=180s --request-timeout=20s >/dev/null 2>&1 && return 0
    reason="kubectl delete namespace $LAB_NS failed or timed out"
  fi
  echo "warning: could not remove the $LAB_NS namespace before the destroy ($reason); continuing. If the user node pool delete then fails on a disruption budget, see \"make down stops at the node pool\" in the README." >&2
}
remove_app
tf destroy -input=false
kubectl config delete-context "$AKS_CONTEXT" >/dev/null 2>&1 || true
if [ "$(cat "$LAB_STATE_DIR/env" 2>/dev/null)" = aks ]; then rm -f "$LAB_STATE_DIR/env"; fi
rm -rf "$LAB_STATE_DIR/overlay"
state_clear
