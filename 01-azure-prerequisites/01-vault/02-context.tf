terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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

# ============================================================================
# Resource Group — created only when var.resource_group_name is null
# ============================================================================

resource "azurerm_resource_group" "main" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = "${var.prefix}-vault"
  location = var.location
  tags     = var.tags
}

# Resolve the effective resource group name and location for downstream resources
locals {
  rg_name     = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.main[0].name
  rg_location = var.resource_group_name != null ? var.location : azurerm_resource_group.main[0].location
}
