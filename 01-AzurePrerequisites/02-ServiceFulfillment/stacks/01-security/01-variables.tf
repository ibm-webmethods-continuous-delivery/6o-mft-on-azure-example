# ============================================================================
# Core Configuration
# ============================================================================

# Prefix helps us keep together all stacks of a project
# must be short and a combination of lower case letters
# first letter identify the type of environment:
# d - development
# v - vanilla (our default in the example)
# e - pre-production
# p - production
# t - test
# the rest of the letters must be as unique as possible in the global landscape, e.g. akfjs
# example prefix: vakfjs, vplexh

variable "prefix" {
  description = "Prefix for resource names (lowercase letters and hyphens only)"
  type        = string
  validation {
    condition     = can(regex("^[a-z]+$", var.prefix))
    error_message = "Prefix must contain only lowercase letters"
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Purpose = "MFT-Security"
    Stack   = "01-security"
  }
}

variable "resource_group_name_existing" {
  description = "Name of the existing parent resource group (from prerequisites)"
  type        = string
}

# ============================================================================
# Key Vault Configuration
# ============================================================================

variable "key_vault_public_access_enabled" {
  description = "Enable public network access to Key Vault (true) or use private endpoint (false)"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 90
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days"
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault (prevents permanent deletion)"
  type        = bool
  default     = true
}

# ============================================================================
# Workload Identity Configuration
# ============================================================================

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster (required for federated credentials)"
  type        = string
}

variable "mft_namespace" {
  description = "Kubernetes namespace for MFT deployment"
  type        = string
  default     = "mft"
}

variable "mft_service_account_name" {
  description = "Kubernetes service account name for MFT workload identity"
  type        = string
  default     = "mft-service-account"
}

# ============================================================================
# Secret Management Configuration
# ============================================================================

variable "environment_name" {
  description = "Environment name for hierarchical secret naming (vanilla/dev/test/prod)"
  type        = string
  default     = "vanilla"
  validation {
    condition     = contains(["vanilla", "dev", "test", "prod"], var.environment_name)
    error_message = "Environment must be vanilla, dev, test, or prod"
  }
}

variable "secret_expiration_date" {
  description = "Fixed expiration date for Key Vault secrets (RFC3339 format). Set once and don't change to avoid drift."
  type        = string
  default     = null
  validation {
    condition     = var.secret_expiration_date == null || can(timeadd(var.secret_expiration_date, "0s"))
    error_message = "Expiration date must be in RFC3339 format (e.g., '2030-12-31T23:59:59Z') or null"
  }
}

# ============================================================================
# Database Credentials (for Key Vault secrets)
# ============================================================================

variable "postgres_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  type        = string
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

variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "psqladmin"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "postgres_dbc_user" {
  description = "Database user for Database Configurator (online database)"
  type        = string
  default     = "mft_app_user"
}

variable "postgres_dbc_password" {
  description = "Database password for Database Configurator (online database)"
  type        = string
  sensitive   = true
}

variable "postgres_dbc_archive_user" {
  description = "Database user for Database Configurator (archive database)"
  type        = string
  default     = "mft_archive_user"
}

variable "postgres_dbc_archive_password" {
  description = "Database password for Database Configurator (archive database)"
  type        = string
  sensitive   = true
}

# ============================================================================
# Certificate Upload Configuration
# ============================================================================

variable "upload_certificates" {
  description = "Enable automatic upload of certificate files to Key Vault"
  type        = bool
  default     = false
}

variable "certificates_base_path" {
  description = "Relative path from this module to the certificates directory"
  type        = string
  default     = "../../../../03-TechnologyServices/00-Certificates/data/subjects/az-certs"
}

variable "certificate_password" {
  description = "Password for PKCS12 and JKS keystores (should match TEST_PK_SECRET from cert generation)"
  type        = string
  sensitive   = true
  default     = "ChangeMe123"
}

# ============================================================================
# AGIC Service Principal Configuration
# ============================================================================

variable "enable_agic_role_assignments" {
  description = "Enable automatic role assignments for AGIC (requires elevated permissions). If false, role assignments must be done manually."
  type        = bool
  default     = false
}

variable "app_gateway_id" {
  description = "ID of the Application Gateway (required for AGIC role assignments)"
  type        = string
  default     = ""
}

variable "app_gateway_subnet_id" {
  description = "ID of the Application Gateway subnet (required for AGIC role assignments)"
  type        = string
  default     = ""
}

# ============================================================================
# Network Configuration (for private endpoints)
# ============================================================================

variable "vnet_id" {
  description = "ID of the Virtual Network (required for private endpoints)"
  type        = string
  default     = ""
}

variable "private_subnet_id" {
  description = "ID of the private subnet for Key Vault private endpoint"
  type        = string
  default     = ""
}