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

resource "random_password" "postgresql_admin" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

resource "azurerm_key_vault_secret" "postgresql_admin_login" {
  name            = "postgresql-admin-login"
  value           = "psqladmin"
  key_vault_id    = azurerm_key_vault.vault-01.id
  expiration_date = "2030-12-30T20:00:00Z"
  content_type    = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

resource "azurerm_key_vault_secret" "postgresql_admin_password" {
  name            = "postgresql-admin-password"
  value           = random_password.postgresql_admin.result
  key_vault_id    = azurerm_key_vault.vault-01.id
  expiration_date = "2030-12-30T20:00:00Z"
  content_type    = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

resource "azurerm_key_vault" "vault-01" {
  # checkov:skip=CKV_AZURE_189: "Ensure that Azure Key Vault disables public network access"
  # checkov:skip=CKV_AZURE_109: "Ensure that key vault allows firewall rules settings"
  # checkov:skip=CKV2_AZURE_32: "Ensure private endpoint is configured to key vault"
  name                        = "kv-ssh-keyservice-api"
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  rbac_authorization_enabled  = true

  sku_name = "standard"

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    # ip_rules = [
    #   "130.92.8.0/24",
    #   "4.226.22.100" # LBE IP of Azure Firewall
    # ]
  }
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
