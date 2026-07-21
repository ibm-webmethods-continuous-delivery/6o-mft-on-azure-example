# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the resource group (created or existing)"
  value       = local.rg_name
}

output "resource_group_id" {
  description = "ID of the resource group (created or existing)"
  value       = var.resource_group_name == null ? azurerm_resource_group.main[0].id : null
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = local.rg_location
}

# ============================================================================
# Azure Key Vault Outputs
# ============================================================================

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# ============================================================================
# Azure Context Outputs
# ============================================================================

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}
