resource "azurerm_resource_group" "this" {
  name     = "rg-ssh-terraform-keyservice-test"
  location = "Switzerland North"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
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

resource "azurerm_service_plan" "sshkeyservice" {
  # checkov:skip=CKV_AZURE_225: "Ensure the App Service Plan is zone redundant"
  # checkov:skip=CKV_AZURE_211: "Ensure App Service plan suitable for production use"
  # checkov:skip=CKV_AZURE_212: "Ensure App Service has a minimum number of instances for failover"
  name                = "asp-sshkeyservice"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "api" {
  # checkov:skip=CKV_AZURE_17: "Ensure the web app has 'Client Certificates (Incoming client certificates)' set"
  # checkov:skip=CKV_AZURE_16: "Ensure that Register with Azure Active Directory is enabled on App Service"
  # checkov:skip=CKV_AZURE_66: "Ensure that App service enables failed request tracing"
  # checkov:skip=CKV_AZURE_63: "Ensure that App service enables HTTP logging"
  # checkov:skip=CKV_AZURE_88: "Ensure that app services use Azure Files"
  # checkov:skip=CKV_AZURE_78: "Ensure FTP deployments are disabled"
  # checkov:skip=CKV_AZURE_213: "Ensure that App Service configures health check"
  name                      = "ssh-keyservice-api-prod"
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  service_plan_id           = azurerm_service_plan.sshkeyservice.id
  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.app.id
  # key_vault_reference_identity_id = azurerm_key_vault.example.id
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  auth_settings {
    enabled = true
  }

  logs {
    detailed_error_messages = true
  }

  site_config {
    # health_check_path = "/healthcheck" # Change to real health check path
    http2_enabled = true
    application_stack {
      python_version = 3.12
    }
  }

  connection_string {
    name  = "test"
    type  = "PostgreSQL"
    value = azurerm_postgresql_flexible_server.example.id
  }
}

# resource "azurerm_linux_web_app" "web" {
#   name                = "ssh-keyservice-web-prod"
#   resource_group_name = azurerm_resource_group.this.name
#   location            = azurerm_resource_group.this.location
#   service_plan_id     = azurerm_service_plan.sshkeyservice.id

#   site_config {}
# }

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

resource "azurerm_user_assigned_identity" "gh-deploy-api" {
  location            = azurerm_resource_group.this.location
  name                = "id-ssh-keyservice-prod-gh-deploy-api"
  resource_group_name = azurerm_resource_group.this.name
}

# The Github Identity used to deploy terraform currently does not have the rights to create role assigments but code would work
# resource "azurerm_role_assignment" "gh_api" {
#   scope                = azurerm_resource_group.this.id
#   role_definition_name = "Website Contributor"
#   principal_id         = azurerm_user_assigned_identity.gh-deploy-api.principal_id
# }

resource "azurerm_user_assigned_identity" "gh-deploy-web" {
  location            = azurerm_resource_group.this.location
  name                = "id-ssh-keyservice-prod-gh-deploy-web"
  resource_group_name = azurerm_resource_group.this.name
}

# The Github Identity used to deploy terraform currently does not have the rights to create role assigments but code would work
# resource "azurerm_role_assignment" "gh_web" {
#   scope                = azurerm_resource_group.this.id
#   role_definition_name = "Website Contributor"
#   principal_id         = azurerm_user_assigned_identity.gh-deploy-web.principal_id
# }
