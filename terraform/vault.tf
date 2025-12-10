# tfsec:ignore:AVD-AZU-0013
resource "azurerm_key_vault" "vault-01" {
  # checkov:skip=CKV_AZURE_189: "Ensure that Azure Key Vault disables public network access"
  # checkov:skip=CKV_AZURE_109: "Ensure that key vault allows firewall rules settings"
  # checkov:skip=CKV2_AZURE_32: "Ensure private endpoint is configured to key vault"
  name                          = "kv-ssh-keyservice-api"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  rbac_authorization_enabled    = true
  public_network_access_enabled = true

  sku_name = "standard"
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "postgresql_admin_login" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "postgresql-admin-login"
  value        = "psqladmin"
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "postgresql_admin_password" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "postgresql-admin-password"
  value        = random_password.postgresql_admin.result
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "app_client_id" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "APP-CLIENT-ID"
  value        = azurerm_linux_web_app.api.id
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "tennant_id" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "TENANT-ID"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "valid_api_keys" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "VALID-API-KEYS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    random_password.api_key.result
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "trusted_cors_origins" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "TRUSTED-CORS-ORIGINS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    "https://ondemand.hpc.unibe.ch"
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

resource "random_password" "postgresql_admin" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

resource "random_password" "api_key" {
  length  = 64
  special = false
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}
