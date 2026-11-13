# Read by the lab scripts (terraform output -raw <name>).
output "subscription_id" { value = var.subscription_id }
output "resource_group_name" { value = azurerm_resource_group.lab.name }
output "cluster_name" { value = azurerm_kubernetes_cluster.lab.name }
output "kubernetes_version" { value = azurerm_kubernetes_cluster.lab.kubernetes_version }
output "acr_name" { value = azurerm_container_registry.lab.name }
output "acr_login_server" { value = azurerm_container_registry.lab.login_server }
output "nodes_nsg_name" { value = azurerm_network_security_group.nodes.name }
output "private_endpoint_subnet_cidr" { value = var.private_endpoint_subnet_cidr }
output "postgres_fqdn" { value = azurerm_postgresql_flexible_server.lab.fqdn }
output "postgres_private_ip" { value = azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address }
output "postgres_admin_login" { value = azurerm_postgresql_flexible_server.lab.administrator_login }
output "postgres_admin_password" {
  value     = random_password.postgres_admin.result
  sensitive = true
}
