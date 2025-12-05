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
  # checkov:skip=CKV_AZURE_222: "Ensure that Azure Web App public network access is disabled"
  # checkov:skip=CKV_AZURE_13: "Ensure App Service Authentication is set on Azure App Service"
  name                      = "ssh-keyservice-api-prod"
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  service_plan_id           = azurerm_service_plan.sshkeyservice.id
  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.app.id
  # key_vault_reference_identity_id = azurerm_key_vault.example.id
  public_network_access_enabled = true

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.api-app.id
    ]
  }

  auth_settings {
    enabled = false
  }

  logs {
    detailed_error_messages = true
  }

  site_config {
    # health_check_path = "/healthcheck" # Change to real health check path
    http2_enabled                     = true
    app_command_line                  = "entrypoint.sh"
    scm_ip_restriction_default_action = true
    application_stack {
      python_version = 3.12
    }

    ip_restriction {
      name       = "unibe-network"
      ip_address = "130.92.0.0/16"
      action     = "Allow"
      priority   = 310
    }

    ip_restriction {
      name                      = "db-network"
      virtual_network_subnet_id = azurerm_subnet.app.id
      action                    = "Allow"
      priority                  = 309
    }

    ip_restriction {
      name                      = "app-network"
      virtual_network_subnet_id = azurerm_subnet.postgres.id
      action                    = "Allow"
      priority                  = 308
    }
  }

  app_settings = {
    AZURE_KEY_VAULT_URL               = azurerm_key_vault.vault-01.vault_uri
    AZURE_POSTGRESQL_CONNECTIONSTRING = local.postgres_connection_string
    AZURE_CLIENT_ID                   = azurerm_user_assigned_identity.api-app.id
  }

  connection_string {
    name  = "pgdb"
    type  = "PostgreSQL"
    value = azurerm_postgresql_flexible_server.postgresql-db-01.id
  }
}
