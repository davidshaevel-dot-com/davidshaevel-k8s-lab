resource "random_password" "postgres_admin" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "azurerm_postgresql_flexible_server" "lab" {
  name                          = "${var.prefix}-pg-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = var.postgres_location
  version                       = var.postgres_version
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  administrator_login           = "labadmin"
  administrator_password        = random_password.postgres_admin.result
  public_network_access_enabled = false
  tags                          = var.tags

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-pg-dns-link"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.lab.id
  registration_enabled  = false
  tags                  = var.tags
}

# The endpoint lives in the lab VNet (East US); the server may be in another
# region (see var.postgres_location).
resource "azurerm_private_endpoint" "postgres" {
  name                = "${var.prefix}-pg-pe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.prefix}-pg-psc"
    private_connection_resource_id = azurerm_postgresql_flexible_server.lab.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "postgres"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}
