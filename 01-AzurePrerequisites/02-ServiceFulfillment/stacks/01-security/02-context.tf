terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current Azure AD client configuration
data "azuread_client_config" "current" {}

# Reference to existing parent resource group (from prerequisites)
data "azurerm_resource_group" "parent" {
  name = var.resource_group_name_existing
}

# Create dedicated resource group for security resources
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-security"
  location = var.location
  tags     = var.tags
}