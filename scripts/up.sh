#!/usr/bin/env bash
# make up: create the AKS lab cluster with Terraform and fetch Entra ID credentials.
. "$(dirname "$0")/lib.sh"
need az; need terraform; need kubectl; need kubelogin
[ -f "$TF_DIR/terraform.tfvars" ] || die "copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and fill it in first"
az account show >/dev/null 2>&1 || die "run 'az login' first"
tf init -input=false
tf apply -input=false
info "Fetching credentials (Entra ID; the cluster's local admin account is disabled)"
az aks get-credentials --resource-group "$(tf_out resource_group_name)" --name "$(tf_out cluster_name)" \
  --context "$AKS_CONTEXT" --overwrite-existing
# Reuse the az CLI sign-in for every kubectl call: no browser prompt per command.
kubelogin convert-kubeconfig --login azurecli --context "$AKS_CONTEXT"
mkdir -p "$LAB_STATE_DIR" && echo aks > "$LAB_STATE_DIR/env"
kubectl config use-context "$AKS_CONTEXT" >/dev/null
kubectl get nodes
