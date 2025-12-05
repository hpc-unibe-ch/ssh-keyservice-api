resource "azurerm_resource_group" "this" {
  name     = "rg-ssh-keyservice-api"
  location = "Switzerland North"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "exampleVnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.example.id
  resource_group_name   = azurerm_resource_group.this.name
  depends_on            = [azurerm_subnet.postgres]
}

resource "azurerm_postgresql_flexible_server" "postgresql-db-01" {
  # checkov:skip=CKV2_AZURE_57: "Ensure PostgreSQL Flexible Server is configured with private endpoint"
  name                          = "ssh-key-api-database-4597657890"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  version                       = "12"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = azurerm_key_vault_secret.postgresql_admin_login.value
  administrator_password        = azurerm_key_vault_secret.postgresql_admin_password.value
  # administrator_login    = "pgadmin"
  # administrator_password = "jbc124asd"
  zone = "1"

  storage_mb                   = 32768
  storage_tier                 = "P4"
  geo_redundant_backup_enabled = true

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.example]
}

resource "azurerm_postgresql_flexible_server_database" "ssh-key-api-dev-database" {
  name      = "ssh-key-api-dev-database"
  server_id = azurerm_postgresql_flexible_server.postgresql-db-01.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  depends_on = [azurerm_postgresql_flexible_server.postgresql-db-01]
}

resource "azurerm_user_assigned_identity" "api-app" {
  location            = azurerm_resource_group.this.location
  name                = "id-ssh-keyservice-prod-api-app"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "gh_api" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_user_assigned_identity.api-app.principal_id
}

resource "azurerm_role_assignment" "api-keyvault" {
  scope                = azurerm_key_vault.vault-01.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api-app.principal_id
}

resource "azurerm_federated_identity_credential" "api-app" {
  name                = "gh-deployment-api"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.api-app.id
  subject             = "repo:hpc-unibe-ch/ssh-keyservice-api:environment:Production"
}
