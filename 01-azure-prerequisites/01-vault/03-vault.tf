# ============================================================================
# Azure Key Vault for MFT Secrets Management
# ============================================================================

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name != null ? var.key_vault_name : "${var.prefix}-kv"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Network configuration - switchable between public and restricted
  public_network_access_enabled = var.key_vault_public_access_enabled

  # RBAC model (preferred over access policies)
  rbac_authorization_enabled = true

  # Soft delete and purge protection
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_purge_protection_enabled

  tags = var.tags
}
