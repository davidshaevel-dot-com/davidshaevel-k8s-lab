data "azurerm_client_config" "current" {}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = var.prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Break-glass access path: API server reachable only from the listed IPs,
  # sign-in through Entra ID with Azure RBAC, no local admin account.
  local_account_disabled = true
  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_size
    node_count                   = var.system_node_count
    vnet_subnet_id               = azurerm_subnet.nodes.id
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = var.tags

  # Scenario 1 upgrades the cluster by hand; a later `make up` (for example to
  # update the authorized IP) must not try to downgrade it.
  lifecycle {
    ignore_changes = [kubernetes_version, default_node_pool[0].orchestrator_version]
  }

  depends_on = [azurerm_subnet_network_security_group_association.nodes]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.lab.id
  mode                  = "User"
  vm_size               = var.user_node_size
  vnet_subnet_id        = azurerm_subnet.nodes.id
  orchestrator_version  = var.kubernetes_version
  auto_scaling_enabled  = true
  min_count             = var.user_node_min
  max_count             = var.user_node_max
  upgrade_settings {
    max_surge = "1"
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [orchestrator_version]
  }
}

# The cluster identity manages networking in the bring-your-own subnet.
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.lab.identity[0].principal_id
}

# Whoever runs terraform apply gets cluster admin through Azure RBAC, and the
# right to download the (Entra ID) kubeconfig.
resource "azurerm_role_assignment" "operator_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "operator_cluster_user" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_container_registry" "lab" {
  name                = "${replace(var.prefix, "-", "")}${random_string.suffix.result}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}
