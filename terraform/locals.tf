locals {
  postgres_connection_string = "dbname=${azurerm_postgresql_flexible_server_database.ssh-key-api-dev-database.name} host=${azurerm_postgresql_flexible_server.postgresql-db-01.fqdn} port=5432 sslmode=require user=${azurerm_key_vault_secret.postgresql_admin_login.value} password=${azurerm_key_vault_secret.postgresql_admin_password.value}"
}

locals {
  db_name = "ssh-key-api-database-${random_string.suffix.result}"
}
