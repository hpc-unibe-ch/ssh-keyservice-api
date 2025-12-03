locals {
  postgres_connection_string = "postgresql://${azurerm_postgresql_flexible_server.example.administrator_login}:${azurerm_postgresql_flexible_server.example.administrator_password}@${azurerm_postgresql_flexible_server.example.fqdn}:5432/${azurerm_postgresql_flexible_server.example.name}?sslmode=require"
}
