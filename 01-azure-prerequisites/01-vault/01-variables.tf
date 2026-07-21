# ============================================================================
# Core Configuration
# ============================================================================

# See CONVENTIONS.md for fundamental variables meaning

variable "prefix" {
  description = "Prefix for resource names (lowercase letters and hyphens only)"
  type        = string
  default     = "vmazex"
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
    Stack   = "01-vault"
  }
}

# When set, the stack uses the existing resource group instead of creating one.
# Leave null to create a new resource group named "${var.prefix}-vault".
variable "resource_group_name" {
  description = "Name of an existing resource group to use. If null, a new resource group named \"<prefix>-vault\" is created."
  type        = string
  default     = null
}

# ============================================================================
# Key Vault Configuration - defaults for ephemerality, not production!
# ============================================================================

# When set, overrides the default Key Vault name "<prefix>-kv".
variable "key_vault_name" {
  description = "Name of the Key Vault. If null, defaults to \"<prefix>-kv\"."
  type        = string
  default     = null
}

variable "key_vault_public_access_enabled" {
  description = "Enable public network access to Key Vault (true) or restrict to selected networks (false)"
  type        = bool
  # false for production systems
  default = true
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  # value up to 90 for production systems
  default = 7
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days"
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault (prevents permanent deletion)"
  type        = bool
  default     = false
}
