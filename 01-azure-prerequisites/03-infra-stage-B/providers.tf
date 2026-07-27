terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Azure Provider
# Authentication via service principal from Stage A
# Set these environment variables before running terraform:
#   export ARM_CLIENT_ID="<infra-sp-client-id>"
#   export ARM_CLIENT_SECRET="<infra-sp-client-secret>"
#   export ARM_TENANT_ID="<tenant-id>"
#   export ARM_SUBSCRIPTION_ID="<subscription-id>"
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
