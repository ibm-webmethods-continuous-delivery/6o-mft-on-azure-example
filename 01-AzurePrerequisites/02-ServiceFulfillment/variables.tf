# Core Azure Configuration
variable "resource_group_name" {
  description = "Name of the new resource group"
  type        = string
}

variable "resource_group_name_existing" {
  description = "Name of the existing resource group"
  type        = string
}


variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "prefix" {
  description = "Prefix for resource names (lowercase letters and hyphens only)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.prefix))
    error_message = "Prefix must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Purpose = "MFT-ServiceFulfilment"
  }
}

# Network Configuration
variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "public_subnet_1_name" {
  description = "Name of the first public subnet"
  type        = string
  default     = null
}

variable "public_subnet_2_name" {
  description = "Name of the second public subnet"
  type        = string
  default     = null
}

variable "private_subnet_1_name" {
  description = "Name of the first private subnet (for AKS)"
  type        = string
  default     = null
}

variable "private_subnet_2_name" {
  description = "Name of the second private subnet (for PostgreSQL)"
  type        = string
  default     = null
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP addresses or CIDR ranges allowed to access SFTP and management interfaces"
  type        = list(string)
  validation {
    condition     = alltrue([for ip in var.allowed_ip_ranges : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", ip))])
    error_message = "Each IP must be a valid IPv4 address or CIDR range (e.g., '93.41.48.198' or '10.0.0.0/24')"
  }
}

variable "sftp_nsg_name" {
  description = "Name of the Network Security Group for SFTP VMs"
  type        = string
  default     = null
}

variable "aks_nsg_name" {
  description = "Name of the Network Security Group for AKS"
  type        = string
  default     = null
}

# SSH Configuration
variable "ssh_admin_pub_key" {
  description = "Administrator public key to enable SSH access to Linux VMs"
  type        = string
}

# ACR Configuration
variable "acr_name" {
  description = "Name of the existing Azure Container Registry from ServiceDelivery"
  type        = string
}

# ACR Role Assignment Configuration
variable "enable_sftp_vm_acr_role" {
  description = "Enable ACR Pull role assignment for SFTP VMs"
  type        = bool
  default     = false
}


# AGIC Role Assignment Configuration
variable "enable_agic_role_assignments" {
  description = "Enable automatic role assignments for AGIC (requires elevated permissions). If false, role assignments must be done manually."
  type        = bool
  default     = false
}

variable "enable_aks_acr_role" {
  description = "Enable ACR Pull role assignment for AKS cluster"
  type        = bool
  default     = false
}

# SFTP VM Configuration
variable "sftp_lb_name" {
  description = "Name of the Load Balancer for SFTP VMs"
  type        = string
  default     = null
}

variable "sftp_vm_1_name" {
  description = "Name of the first SFTP VM"
  type        = string
  default     = null
}

variable "sftp_vm_2_name" {
  description = "Name of the second SFTP VM"
  type        = string
  default     = null
}

variable "sftp_vm_size" {
  description = "VM size for SFTP VMs"
  type        = string
  default     = "Standard_B2s"
}

# AKS Configuration
variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = null
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS default node pool"
  type        = number
  default     = 2
  validation {
    condition     = var.aks_node_count >= 1 && var.aks_node_count <= 10
    error_message = "AKS node count must be between 1 and 10"
  }
}

variable "aks_node_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

# PostgreSQL Configuration
variable "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  type        = string
  default     = null
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgres_version)
    error_message = "PostgreSQL version must be one of: 11, 12, 13, 14, 15"
  }
}

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
  validation {
    condition     = var.postgres_storage_mb >= 32768 && var.postgres_storage_mb <= 16777216
    error_message = "PostgreSQL storage must be between 32768 MB (32 GB) and 16777216 MB (16 TB)"
  }
}

variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "psqladmin"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_admin_username))
    error_message = "PostgreSQL admin username must start with a letter and contain only letters, numbers, and underscores (max 63 chars)"
  }
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.postgres_admin_password) >= 8
    error_message = "PostgreSQL admin password must be at least 8 characters long"
  }
}

variable "postgres_online_db_name" {
  description = "Name of the PostgreSQL database for online transactions"
  type        = string
  default     = "mft_online"
}

variable "postgres_archive_db_name" {
  description = "Name of the PostgreSQL database for archiving"
  type        = string
  default     = "mft_archive"
}

# Application Gateway Configuration
variable "app_gateway_name" {
  description = "Name of the Application Gateway"
  type        = string
  default     = null
}

variable "app_gateway_sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "Standard_v2"
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.app_gateway_sku_name)
    error_message = "Application Gateway SKU must be either Standard_v2 or WAF_v2"
  }
}

variable "app_gateway_sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "Standard_v2"
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.app_gateway_sku_tier)
    error_message = "Application Gateway tier must be either Standard_v2 or WAF_v2"
  }
}

# Database Configurator Credentials
variable "postgres_dbc_user" {
  description = "Database user for Database Configurator (online database)"
  type        = string
  default     = "mft_app_user"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_dbc_user))
    error_message = "PostgreSQL username must start with a letter and contain only letters, numbers, and underscores (max 63 chars)"
  }
}

variable "postgres_dbc_password" {
  description = "Database password for Database Configurator (online database)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.postgres_dbc_password) >= 8
    error_message = "PostgreSQL password must be at least 8 characters long"
  }
}

variable "postgres_dbc_archive_user" {
  description = "Database user for Database Configurator (archive database)"
  type        = string
  default     = "mft_archive_user"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_dbc_archive_user))
    error_message = "PostgreSQL username must start with a letter and contain only letters, numbers, and underscores (max 63 chars)"
  }
}

variable "postgres_dbc_archive_password" {
  description = "Database password for Database Configurator (archive database)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.postgres_dbc_archive_password) >= 8
    error_message = "PostgreSQL password must be at least 8 characters long"
  }
}

variable "app_gateway_capacity" {
  description = "Capacity (instance count) for Application Gateway"
  type        = number
  default     = 2
  validation {
    condition     = var.app_gateway_capacity >= 1 && var.app_gateway_capacity <= 125
    error_message = "Application Gateway capacity must be between 1 and 125"
  }
}

# Azure Key Vault Configuration
variable "key_vault_public_access_enabled" {
  description = "Enable public network access to Key Vault (true) or use private endpoint (false)"
  type        = bool
  default     = false
}

variable "mft_namespace" {
  description = "Kubernetes namespace for MFT deployment"
  type        = string
  default     = "default"
}

variable "mft_service_account_name" {
  description = "Kubernetes service account name for MFT workload identity"
  type        = string
  default     = "mft-service-account"
}

variable "environment_name" {
  description = "Environment name for hierarchical secret naming (vanilla/dev/test/prod)"
  type        = string
  default     = "vanilla"
  validation {
    condition     = contains(["vanilla", "dev", "test", "prod"], var.environment_name)
    error_message = "Environment must be vanilla, dev, test, or prod"
  }
}

# Certificate Upload Configuration
variable "upload_certificates" {
  description = "Enable automatic upload of certificate files to Key Vault"
  type        = bool
  default     = false
}

variable "certificates_base_path" {
  description = "Relative path from this module to the certificates directory"
  type        = string
  default     = "../../03-TechnologyServices/00-Certificates/data/subjects/az-certs"
}

variable "certificate_password" {
  description = "Password for PKCS12 and JKS keystores (should match TEST_PK_SECRET from cert generation)"
  type        = string
  sensitive   = true
  default     = "ChangeMe123"
}

