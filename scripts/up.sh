#!/usr/bin/env bash
# make up: create the AKS lab cluster with Terraform and fetch Entra ID credentials.
. "$(dirname "$0")/lib.sh"
need az; need terraform; need kubectl; need kubelogin
[ -f "$TF_DIR/terraform.tfvars" ] || die "copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and fill it in first"
az account show >/dev/null 2>&1 || die "run 'az login' first"
tf init -input=false
tf apply -input=false
info "Fetching credentials (Entra ID; the cluster's local admin account is disabled)"
rg=$(tf_out resource_group_name)
cluster=$(tf_out cluster_name)
az_sub aks get-credentials --resource-group "$rg" --name "$cluster" --context "$AKS_CONTEXT" --overwrite-existing
# Reuse the az CLI sign-in for every kubectl call: no browser prompt per command.
kubelogin convert-kubeconfig --login azurecli --context "$AKS_CONTEXT"
mkdir -p "$LAB_STATE_DIR" && echo aks > "$LAB_STATE_DIR/env"
kubectl config use-context "$AKS_CONTEXT" >/dev/null
# The cluster-admin role assignment can take a few minutes to propagate.
for attempt in $(seq 1 30); do
  out=$(kubectl get nodes 2>&1) && { echo "$out"; exit 0; }
  [ "$attempt" -eq 1 ] && info "kubectl get nodes failed; retrying for up to 5 minutes (RBAC propagation). Error: $out"
  sleep 10
done
die "kubectl still cannot list nodes. Last error: $out
Check: your IP is in api_server_authorized_ip_ranges (curl -4 -s https://ifconfig.me), kubelogin is installed, and the role assignments exist."
