# Core Azure Configuration
variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names (lowercase letters only)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.prefix))
    error_message = "Prefix must contain only lowercase letters and numbers"
  }
}

# Network Security Group
variable "nsg_name" {
  description = "Name of the Network Security Group"
  type        = string
  default     = null
}

# Virtual Network Configuration
variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet for VMs"
  type        = string
  default     = null
}

# Virtual Machine Scale Set Configuration
variable "vmss_name" {
  description = "Name of the Virtual Machine Scale Set"
  type        = string
  default     = null
}

variable "vmss_image" {
  description = "VM image for the scale set"
  type        = string
  default     = "Canonical:0001-com-ubuntu-confidential-vm-focal:20_04-lts-cvm:latest"
}

variable "vmss_sku" {
  description = "VM SKU for the scale set"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "vmss_instance_count" {
  description = "Initial instance count for VMSS"
  type        = number
  default     = 0
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account (3-24 chars, lowercase letters and numbers only)"
  type        = string
  default     = null
  validation {
    condition     = var.storage_account_name == null || (length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24 && can(regex("^[a-z0-9]+$", var.storage_account_name)))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only"
  }
}

variable "storage_share_name" {
  description = "Name of the file share in the storage account"
  type        = string
  default     = null
}

variable "storage_share_quota" {
  description = "Quota for the file share in GB"
  type        = number
  default     = 1024
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = null
}

# Azure Container Registry Configuration
variable "acr_name" {
  description = "Name of the Azure Container Registry (lowercase letters only)"
  type        = string
  default     = null
  validation {
    condition     = var.acr_name == null || can(regex("^[a-z0-9]+$", var.acr_name))
    error_message = "ACR name must contain only lowercase letters and numbers"
  }
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Purpose = "DevOps"
  }
}

variable "ssh_admin_pub_key" {
  description = "Administrator public key to enable ssh access to linux vms"
  type        = string
  default     = "ssh-ed25519 must-put-somthing-real-here aaa@bbb.com"
}

# Key Vault Network Access
variable "key_vault_allowed_ips" {
  description = "List of IP addresses or CIDR ranges allowed to access the Key Vault"
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for ip in var.key_vault_allowed_ips : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", ip))])
    error_message = "Each IP must be a valid IPv4 address or CIDR range (e.g., '93.41.48.198' or '10.0.0.0/24')"
  }
}

# Azure DevOps Configuration
variable "azdo_org_service_url" {
  description = "Azure DevOps organization service URL (e.g., https://dev.azure.com/yourorg)"
  type        = string
}

variable "azdo_project_name" {
  description = "Name of the Azure DevOps project to create"
  type        = string
}

variable "azdo_project_description" {
  description = "Description of the Azure DevOps project"
  type        = string
  default     = "Service delivery project for MFT on Azure"
}

variable "azdo_project_visibility" {
  description = "Visibility of the Azure DevOps project (private or public)"
  type        = string
  default     = "private"
  validation {
    condition     = contains(["private", "public"], var.azdo_project_visibility)
    error_message = "Project visibility must be either 'private' or 'public'"
  }
}

variable "azdo_agent_pool_name" {
  description = "Name of the Azure DevOps agent pool to create"
  type        = string
}

variable "azdo_pat" {
  description = "Azure DevOps Personal Access Token (PAT) for agent registration"
  type        = string
  sensitive   = true
}

variable "azdo_service_endpoint_name" {
  description = "Name of the Azure RM service endpoint"
  type        = string
  default     = "Azure-ServiceConnection"
}

variable "azdo_service_principal_id" {
  description = "Service Principal (Application) ID for Azure DevOps service connection"
  type        = string
  sensitive   = true
}

variable "azdo_service_principal_key" {
  description = "Service Principal (Application) secret/key for Azure DevOps service connection"
  type        = string
  sensitive   = true
}

variable "azdo_subscription_name" {
  description = "Name of the Azure subscription for the service connection"
  type        = string
}