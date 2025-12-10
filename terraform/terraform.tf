terraform {
  required_version = "~> 1.14"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.54"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2" # Use a stable version—check registry for latest
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}
