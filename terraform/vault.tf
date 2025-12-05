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

  # network_acls {
  #   bypass         = "AzureServices"
  #   default_action = "Deny"
  #   ip_rules = [
  #     "130.92.8.0/24",
  #     "4.226.22.100" # LBE IP of Azure Firewall
  #   ]
  # }
}

resource "random_password" "postgresql_admin" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
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
resource "azurerm_key_vault_secret" "APP_CLIENT_ID" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "APP_CLIENT_ID"
  value        = azurerm_linux_web_app.api.id
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "TENANT_ID" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "APP_CLIENT_ID"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "VALID_API_KEYS" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "VALID_API_KEYS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    "sk_live_abc123xyz456",
    "sk_live_def789ghi012",
    "sk_test_jkl345mno678"
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "TRUSTED_CORS_ORIGINS" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "TRUSTED_CORS_ORIGINS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    "https://ondemand.hpc.unibe.ch",
    "https://app.example.com"
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}
