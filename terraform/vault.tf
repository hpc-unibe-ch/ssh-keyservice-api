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
# import {
#   id = "https://kv-ssh-keyservice-api.vault.azure.net/secrets/postgresql-admin-login/4f510f64fc3e40358f9030fc98090d54"
#   to = azurerm_key_vault_secret.postgresql_admin_login
# }

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "postgresql_admin_password" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "postgresql-admin-password"
  value        = random_password.postgresql_admin.result
  key_vault_id = azurerm_key_vault.vault-01.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}
# import {
#   id = "https://kv-ssh-keyservice-api.vault.azure.net/secrets/postgresql-admin-password/cd0cdef77c66422783a4c2bdc05d22ec"
#   to = azurerm_key_vault_secret.postgresql_admin_password
# }

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
# import {
#   id = "https://kv-ssh-keyservice-api.vault.azure.net/secrets/TENANT-ID/f7d870cf26e6424082b770db485d4066"
#   to = azurerm_key_vault_secret.tennant_id
# }

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "valid_api_keys" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "VALID-API-KEYS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    "sk_live_abc123xyz456",
    "sk_live_def789ghi012",
    "sk_test_jkl345mno678"
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}
# import {
#   id = "https://kv-ssh-keyservice-api.vault.azure.net/secrets/VALID-API-KEYS/27a0b170294849869f08869f4854fcf1"
#   to = azurerm_key_vault_secret.valid_api_keys
# }

# tfsec:ignore:AVD-AZU-0017
resource "azurerm_key_vault_secret" "trusted_cors_origins" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets"
  name         = "TRUSTED-CORS-ORIGINS"
  key_vault_id = azurerm_key_vault.vault-01.id
  value = join(",", [
    "https://ondemand.hpc.unibe.ch",
    "https://app.example.com"
  ])
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.api-keyvault]
}
# import {
#   id = "https://kv-ssh-keyservice-api.vault.azure.net/secrets/TRUSTED-CORS-ORIGINS/3ba73b6298114c26b9e5e94b713ce74a"
#   to = azurerm_key_vault_secret.trusted_cors_origins
# }
