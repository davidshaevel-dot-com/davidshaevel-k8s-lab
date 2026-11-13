resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.nodes_subnet_cidr]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]
  # Enforce NSG rules on private endpoint traffic.
  private_endpoint_network_policies = "Enabled"
}

# Node subnet NSG: Azure's default rules only (VNet and load balancer in,
# everything out). Scenario 2's network security group fault adds a rule here.
resource "azurerm_network_security_group" "nodes" {
  name                = "${var.prefix}-nodes-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

# Private endpoint subnet NSG: only the nodes may reach PostgreSQL.
# (With Azure CNI Overlay, pod traffic leaves the node with the node's IP.)
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${var.prefix}-pe-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "pe_allow_postgres_from_nodes" {
  name                        = "Allow-Postgres-From-Nodes"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = var.nodes_subnet_cidr
  source_port_range           = "*"
  destination_address_prefix  = var.private_endpoint_subnet_cidr
  destination_port_range      = "5432"
}

resource "azurerm_network_security_rule" "pe_deny_other_vnet" {
  name                        = "Deny-Other-VNet-Inbound"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_address_prefix       = "VirtualNetwork"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
