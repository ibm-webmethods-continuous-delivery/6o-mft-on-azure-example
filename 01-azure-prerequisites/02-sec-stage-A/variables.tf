# Core Azure Configuration
variable "prefix" {
  description = "Prefix for resource names (lowercase letters only, e.g., 'vmazex')"
  type        = string
  default     = "vmazex"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{3,9}$", var.prefix))
    error_message = "Prefix must start with a lowercase letter, contain only lowercase letters and numbers, and be 4-10 characters long"
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

# Resource Group Names
variable "delivery_rg_suffix" {
  description = "Suffix for the Service Delivery resource group name"
  type        = string
  default     = "s-delivery"
}

variable "fulfillment_rg_suffix" {
  description = "Suffix for the Service Fulfillment resource group name"
  type        = string
  default     = "s-fulfillment"
}

# Infrastructure Team Service Principal
variable "infra_sp_name_suffix" {
  description = "Suffix for the infrastructure team service principal name"
  type        = string
  default     = "infra-sp"
}

variable "infra_sp_description" {
  description = "Description for the infrastructure team service principal"
  type        = string
  default     = "Service Principal for infrastructure team to provision Azure resources"
}

# Azure DevOps Service Principal
variable "create_azdo_sp" {
  description = "Whether to create the Azure DevOps service principal for Stage C service delivery setup"
  type        = bool
  default     = true
}

variable "azdo_sp_name_suffix" {
  description = "Suffix for the Azure DevOps service principal name"
  type        = string
  default     = "azdo-sp"
}

variable "azdo_sp_description" {
  description = "Description for the Azure DevOps service principal"
  type        = string
  default     = "Service Principal for Azure DevOps service delivery provisioning"
}

# MFT Workload Identity
variable "create_mft_identity" {
  description = "Whether to create the MFT workload user-assigned managed identity"
  type        = bool
  default     = true
}

variable "mft_identity_suffix" {
  description = "Suffix for the MFT workload identity name"
  type        = string
  default     = "mft-identity"
}

# AGIC Workload Identity
variable "create_agic_identity" {
  description = "Whether to create the AGIC workload user-assigned managed identity"
  type        = bool
  default     = true
}

variable "agic_identity_suffix" {
  description = "Suffix for the AGIC workload identity name"
  type        = string
  default     = "agic-identity"
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    ManagedBy = "SecurityTeam"
    Stage     = "Prerequisites"
  }
}


# Key Vault Access (for Stage B infrastructure team)
variable "key_vault_resource_group_name" {
  description = "Resource group name containing the Key Vault (from 01-vault/). Infrastructure SP needs Reader access to this RG."
  type        = string
  default     = null
}
