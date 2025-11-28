resource "azurerm_resource_group" "this" {
  name     = "rg-ssh-terraform-keyservice-test"
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

resource "azurerm_postgresql_flexible_server" "example" {
  # checkov:skip=CKV2_AZURE_57: "Ensure PostgreSQL Flexible Server is configured with private endpoint"
  name                          = "ssh-key-api-database-4597657890"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  version                       = "12"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = "psqladmin"
  administrator_password        = "H@Sh1CoR3!"
  zone                          = "1"

  storage_mb                   = 32768
  storage_tier                 = "P4"
  geo_redundant_backup_enabled = true

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.example]
}

resource "azurerm_key_vault" "example" {
  # checkov:skip=CKV_AZURE_189: "Ensure that Azure Key Vault disables public network access"
  # checkov:skip=CKV_AZURE_109: "Ensure that key vault allows firewall rules settings"
  # checkov:skip=CKV2_AZURE_32: "Ensure private endpoint is configured to key vault"
  name                          = "kv-ssh-keyservice-prod"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = false

  sku_name = "standard"

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
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

resource "azurerm_federated_identity_credential" "api-app" {
  name                = "gh-deployment-api"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.api-app.id
  subject             = "repo:hpc-unibe-ch/ssh-keyservice-api:ref:refs/heads/51-add-support-for-terraform-deployments"
}

resource "azurerm_user_assigned_identity" "web-app" {
  location            = azurerm_resource_group.this.location
  name                = "id-ssh-keyservice-prod-web-app"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "gh_web" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_user_assigned_identity.web-app.principal_id
}

resource "azurerm_federated_identity_credential" "web-app" {
  name                = "gh-deployment-web-app"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.web-app.id
  subject             = "repo:hpc-unibe-ch/ssh-keyservice:ref:refs/heads/main"
}
