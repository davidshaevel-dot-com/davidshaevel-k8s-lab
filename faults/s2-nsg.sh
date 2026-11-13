# An Azure network security group rule blocks the node subnet from the database.
NSG_RULE_NAME=Outbound-Policy-120
fault_supports() { [ "$1" = aks ]; }
fault_describe() { echo "Network security group: rule '$NSG_RULE_NAME' (priority 120) on the node subnet's NSG denies outbound TCP 5432 to the private endpoint subnet."; }
fault_plant() {
  az network nsg rule create --resource-group "$(tf_out resource_group_name)" --nsg-name "$(tf_out nodes_nsg_name)" \
    --name "$NSG_RULE_NAME" --priority 120 --direction Outbound --access Deny --protocol Tcp \
    --source-address-prefixes '*' --source-port-ranges '*' \
    --destination-address-prefixes "$(tf_out private_endpoint_subnet_cidr)" --destination-port-ranges 5432 --output none
}
fault_heal() {
  [ "$(lab_env)" = aks ] || return 0
  az network nsg rule delete --resource-group "$(tf_out resource_group_name)" --nsg-name "$(tf_out nodes_nsg_name)" \
    --name "$NSG_RULE_NAME" --output none 2>/dev/null || true
}
