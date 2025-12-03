locals {
  postgres_connection_string = "postgresql://${azurerm_postgresql_flexible_server.postgresql-db-01.administrator_login}:${azurerm_postgresql_flexible_server.postgresql-db-01.administrator_password}@${azurerm_postgresql_flexible_server.postgresql-db-01.fqdn}:5432/${azurerm_postgresql_flexible_server.postgresql-db-01.name}?sslmode=require"
}
